package api

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
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
		log.Printf("Warning: failed to update Prometheus config on node role change: %v", err)
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

	if req.Availability != "active" && req.Availability != "pause" && req.Availability != "drain" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid availability"})
		return
	}

	// Update status logic (if drain, we might want to kill tasks, but for MVP we just mark it)
	status := "active"
	if req.Availability != "active" {
		status = req.Availability
	}

	res := db.DB.Model(&db.Node{}).Where("id = ?", id).Update("status", status)
	if res.Error != nil || res.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "Node not found"})
		return
	}

	// Trigger Prometheus targets reload
	if err := monitor.UpdatePrometheusConfig(); err != nil {
		log.Printf("Warning: failed to update Prometheus config on node availability change: %v", err)
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
		log.Printf("Warning: failed to update Prometheus config on node leave: %v", err)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Node marked as left"})
}
