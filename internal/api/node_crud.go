package api

import (
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"

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

	if req.Availability != "active" && req.Availability != "pause" && req.Availability != "drain" && req.Availability != "maintenance" && req.Availability != "no_schedule" {
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

	// Trigger node task draining if status is drain, maintenance, pause or no_schedule
	if status == "drain" || status == "maintenance" || status == "pause" || status == "no_schedule" {
		go drainNodeTasks(id)
	}

	// Trigger Prometheus targets reload
	if err := monitor.UpdatePrometheusConfig(); err != nil {
		slog.Warn("failed to update Prometheus config on node availability change", "err", err)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Node availability updated"})
}

// @Summary Reboot Node
// @Description Drain tasks and initiate host reboot
// @Tags nodes
// @Produce json
// @Param id path string true "Node ID"
// @Success 200 {object} map[string]string
// @Router /v1/node/{id}/reboot [post]
func NodeRebootHandler(c *gin.Context) {
	id := c.Param("id")

	var node db.Node
	if err := db.DB.First(&node, "id = ?", id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Node not found"})
		return
	}

	// 1. Mark status as maintenance and evacuate tasks
	db.DB.Model(&node).Update("status", "maintenance")
	go drainNodeTasks(id)

	// 2. Trigger reboot asynchronously
	go func() {
		time.Sleep(1 * time.Second)
		slog.Info("node reboot initiated", "id", id)
		exec.Command("sudo", "reboot").Run()
	}()

	c.JSON(http.StatusOK, gin.H{"message": "Node reboot initiated"})
}

func isSystemStack(stackID string) bool {
	s := strings.ToLower(stackID)
	return strings.HasPrefix(s, "core-stack-") ||
		strings.HasPrefix(s, "sre-stack-") ||
		s == "core-gbnt-stack" ||
		s == "sre-monitor-stack" ||
		strings.Contains(s, "core-gbnt") ||
		strings.Contains(s, "sre-monitor") ||
		strings.Contains(s, "monitor")
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

	var node db.Node
	if err := db.DB.First(&node, "id = ?", id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Node not found"})
		return
	}

	// Drain all user tasks (reschedules non-system tasks to other nodes)
	drainNodeTasks(id)

	// Purge ALL tasks associated with this node from the DB,
	// including core-gbnt and sre-monitor tasks that were skipped by the drain.
	db.DB.Where("node_id = ?", id).Delete(&db.Task{})

	// Purge node-specific stacks and services (CORE and SRE)
	coreStackID := "core-stack-" + id
	sreStackID := "sre-stack-" + id

	var workerStacks []db.Stack
	db.DB.Where("id = ? OR id = ? OR id LIKE ?", coreStackID, sreStackID, "%"+id).Find(&workerStacks)
	for _, st := range workerStacks {
		db.DB.Where("stack_id = ?", st.ID).Delete(&db.Service{})
		db.DB.Where("id = ?", st.ID).Delete(&db.Stack{})
	}

	db.DB.Where("stack_id = ? OR stack_id = ?", coreStackID, sreStackID).Delete(&db.Service{})
	db.DB.Where("id = ? OR id = ?", coreStackID, sreStackID).Delete(&db.Stack{})

	// Delete the node entirely so it disappears from the UI
	res := db.DB.Model(&db.Node{}).Where("id = ?", id).Delete(nil)
	if res.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete node"})
		return
	}

	// Trigger Prometheus targets reload
	if err := monitor.UpdatePrometheusConfig(); err != nil {
		slog.Warn("failed to update Prometheus config on node leave", "err", err)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Node drained and removed from cluster"})
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
		if isSystemStack(svc.StackID) {
			continue
		}

		slog.Info("Draining task from node", "task_id", task.ID, "node_id", nodeID, "service_id", svc.ID)

		// 1. Stop container on the drained host
		containerName := task.ContainerName
		if containerName == "" {
			containerName = "gbnt-" + task.ID
		}
		if task.NodeID == "node-local-manager" {
			exec.Command("docker", "stop", containerName).Run()
			exec.Command("docker", "rm", "-f", containerName).Run()
		} else {
			var targetNode db.Node
			if err := db.DB.First(&targetNode, "id = ? OR ip = ?", task.NodeID, task.NodeID).Error; err == nil && targetNode.IP != "" {
				sshArgs := []string{"-o", "UserKnownHostsFile=/dev/null", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=5"}
				keyCandidates := []string{
					"/root/.ssh/id_ed25519", "/root/.ssh/id_rsa",
					"/data/id_ed25519", "/data/id_rsa",
					"/data/ssh/id_ed25519", "/data/ssh/id_rsa",
				}
				for _, k := range keyCandidates {
					if _, err := os.Stat(k); err == nil {
						sshArgs = append(sshArgs, "-i", k)
						break
					}
				}
				stopCmd := fmt.Sprintf("sudo docker rm -f %s 2>/dev/null || true", containerName)
				stopSSHArgs := append(append([]string{}, sshArgs...), fmt.Sprintf("ubuntu@%s", targetNode.IP), stopCmd)
				_ = exec.Command("ssh", stopSSHArgs...).Run()
			}
		}

		// 2. Mark the task as dead in DB
		db.DB.Model(&task).Updates(map[string]interface{}{
			"status":       "dead",
			"container_ip": "",
		})

		// 3. If draining manager, relax any obsolete "node.role == manager" constraint so it can migrate to workers
		var drainingNode db.Node
		if err := db.DB.First(&drainingNode, "id = ?", nodeID).Error; err == nil && strings.ToLower(drainingNode.Role) == "manager" {
			cleanConstraints := make([]string, 0, len(svc.Constraints))
			for _, c := range svc.Constraints {
				trimmed := strings.TrimSpace(c)
				if trimmed != "node.role == manager" && trimmed != "node.role==manager" && trimmed != "gbnt.node.role == manager" && trimmed != "gbnt.node.role==manager" {
					cleanConstraints = append(cleanConstraints, c)
				}
			}
			if len(cleanConstraints) != len(svc.Constraints) {
				svc.Constraints = cleanConstraints
				db.DB.Model(&svc).Update("constraints", svc.Constraints)
			}
		}

		// 4. Reschedule a new replica (will be placed on another ACTIVE node)
		scheduleService(&svc, "")
	}

	// Regenerate configurations
	go aqueducts.GenerateHostsFile()
	go aqueducts.GenerateCaddyfile()
}

