package api

import (
	"log/slog"
	"net/http"
	"os/exec"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/aqueducts"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/mario-ezquerro/gubernator/internal/monitor"
)

// @Summary Inspect Node
// @Description Fetch full details of a specific node
// @Tags nodes
// @Produce json
// @Param id path string true "Node ID"
// @Success 200 {object} db.Node
// @Router /v1/node/{id} [get]
func NodeInspectHandler(c *gin.Context) {
	id := c.Param("id")
	var node db.Node
	if err := db.DB.First(&node, "id = ?", id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Node not found"})
		return
	}
	c.JSON(http.StatusOK, node)
}

type NodeRoleRequest struct {
	Role string `json:"role" binding:"required"` // "worker" or "manager"
}

// @Summary Promote/Demote Node
// @Description Change the role of a node
// @Tags nodes
// @Accept json
// @Produce json
// @Param id path string true "Node ID"
// @Param request body NodeRoleRequest true "Role Update"
// @Success 200 {object} map[string]string
// @Router /v1/node/{id}/role [post]
func NodeRoleHandler(c *gin.Context) {
	id := c.Param("id")
	var req NodeRoleRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Role != "worker" && req.Role != "manager" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid role"})
		return
	}

	res := db.DB.Model(&db.Node{}).Where("id = ?", id).Update("role", req.Role)
	if res.Error != nil || res.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "Node not found"})
		return
	}

	// Trigger Prometheus targets reload
	if err := monitor.UpdatePrometheusConfig(); err != nil {
		slog.Warn("failed to update Prometheus config on node role change", "err", err)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Node role updated"})
}

type NodeAvailabilityRequest struct {
	Availability string `json:"availability" binding:"required"` // "active", "pause", "drain"
}

// @Summary Update Node Availability
// @Description Pause or drain a node
// @Tags nodes
// @Accept json
// @Produce json
// @Param id path string true "Node ID"
// @Param request body NodeAvailabilityRequest true "Availability Update"
// @Success 200 {object} map[string]string
// @Router /v1/node/{id}/availability [post]
func NodeAvailabilityHandler(c *gin.Context) {
	id := c.Param("id")
	var req NodeAvailabilityRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Availability != "active" && req.Availability != "pause" && req.Availability != "drain" && req.Availability != "maintenance" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid availability"})
		return
	}

	// Update status logic
	status := "active"
	if req.Availability != "active" {
		status = req.Availability
	}

	res := db.DB.Model(&db.Node{}).Where("id = ?", id).Update("status", status)
	if res.Error != nil || res.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "Node not found"})
		return
	}

	// Trigger node task draining if status is drain or maintenance
	if status == "drain" || status == "maintenance" {
		go drainNodeTasks(id)
	}

	// Trigger Prometheus targets reload
	if err := monitor.UpdatePrometheusConfig(); err != nil {
		slog.Warn("failed to update Prometheus config on node availability change", "err", err)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Node availability updated"})
}

// @Summary Leave Legion
// @Description Mark node as left
// @Tags nodes
// @Produce json
// @Param id path string true "Node ID"
// @Success 200 {object} map[string]string
// @Router /v1/node/{id}/leave [post]
func NodeLeaveHandler(c *gin.Context) {
	id := c.Param("id")
	res := db.DB.Model(&db.Node{}).Where("id = ?", id).Update("status", "left")
	if res.Error != nil || res.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "Node not found"})
		return
	}

	// Trigger Prometheus targets reload
	if err := monitor.UpdatePrometheusConfig(); err != nil {
		slog.Warn("failed to update Prometheus config on node leave", "err", err)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Node marked as left"})
}

type NodeLabelsRequest struct {
	Labels map[string]string `json:"labels" binding:"required"`
}

// @Summary Update Node Labels
// @Description Add, update, or remove node labels
// @Tags nodes
// @Accept json
// @Produce json
// @Param id path string true "Node ID"
// @Param request body NodeLabelsRequest true "Labels Update"
// @Success 200 {object} map[string]string
// @Router /v1/node/{id}/labels [post]
func NodeLabelsHandler(c *gin.Context) {
	id := c.Param("id")
	var req NodeLabelsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := db.UpdateNodeLabels(id, req.Labels); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Trigger Prometheus targets reload
	if err := monitor.UpdatePrometheusConfig(); err != nil {
		slog.Warn("failed to update Prometheus config on node labels change", "err", err)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Node labels updated"})
}

func drainNodeTasks(nodeID string) {
	var tasks []db.Task
	if err := db.DB.Where("node_id = ? AND status != ?", nodeID, "dead").Find(&tasks).Error; err != nil {
		return
	}

	for _, task := range tasks {
		var svc db.Service
		if err := db.DB.First(&svc, "id = ?", task.ServiceID).Error; err != nil {
			continue
		}

		// Filter out core system and monitoring stacks
		if svc.StackID == "core-gbnt-stack" || svc.StackID == "sre-monitor-stack" ||
			strings.Contains(strings.ToLower(svc.StackID), "core-gbnt") ||
			strings.Contains(strings.ToLower(svc.StackID), "monitor") {
			continue
		}

		slog.Info("Draining task from node", "task_id", task.ID, "node_id", nodeID, "service_id", svc.ID)

		// 1. Stop local container if it was running on the manager node itself
		if task.NodeID == "node-local-manager" && task.ContainerName != "" {
			exec.Command("docker", "stop", task.ContainerName).Run()
			exec.Command("docker", "rm", "-f", task.ContainerName).Run()
		}

		// 2. Mark the task as dead in DB (the worker agent will clean up its local container)
		db.DB.Model(&task).Updates(map[string]interface{}{
			"status":       "dead",
			"container_ip": "",
		})

		// 3. Reschedule a new replica (will be placed on another ACTIVE node)
		scheduleService(&svc, "")
	}

	// Regenerate configurations
	go aqueducts.GenerateHostsFile()
	go aqueducts.GenerateCaddyfile()
}

