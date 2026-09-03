package api

import (
	"fmt"
	"net/http"
	"os"
	"os/exec"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/aqueducts"
	"github.com/mario-ezquerro/gubernator/internal/caddy"
	"github.com/mario-ezquerro/gubernator/internal/coredns"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/mario-ezquerro/gubernator/internal/docker"
	"github.com/mario-ezquerro/gubernator/internal/monitor"
)

// @Summary List Stacks
// @Description List all deployed stacks
// @Tags stacks
// @Produce json
// @Success 200 {array} db.Stack
// @Router /v1/stack/ls [get]
func StackListHandler(c *gin.Context) {
	var stacks []db.Stack
	if err := db.DB.Find(&stacks).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch stacks"})
		return
	}
	for i := range stacks {
		if stacks[i].NodeID == "" {
			var firstTask db.Task
			if err := db.DB.Joins("JOIN services ON services.id = tasks.service_id").
				Where("services.stack_id = ? AND tasks.node_id != '' AND tasks.node_id != 'none'", stacks[i].ID).
				First(&firstTask).Error; err == nil && firstTask.NodeID != "" {
				stacks[i].NodeID = firstTask.NodeID
				db.DB.Model(&stacks[i]).Update("node_id", firstTask.NodeID)
			}
		}
	}
	c.JSON(http.StatusOK, stacks)
}

// @Summary List Stack Services
// @Description List services belonging to a stack
// @Tags stacks
// @Produce json
// @Param id path string true "Stack ID"
// @Success 200 {array} db.Service
// @Router /v1/stack/{id}/services [get]
func StackServicesHandler(c *gin.Context) {
	id := c.Param("id")
	var services []db.Service
	if err := db.DB.Where("stack_id = ?", id).Find(&services).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch services"})
		return
	}
	c.JSON(http.StatusOK, services)
}

// @Summary Remove Stack
// @Description Delete a stack, stop its containers, and remove all related records
// @Tags stacks
// @Produce json
// @Param id path string true "Stack ID"
// @Success 200 {object} map[string]string
// @Router /v1/stack/{id} [delete]
func StackRmHandler(c *gin.Context) {
	id := c.Param("id")

	// Special handling for SRE Monitor stack
	if id == monitor.SREStackID {
		// Stop and remove all monitoring containers (Docker)
		monitor.StopAll()
		// Update tasks status to "dead" and clear container IP in DB, keeping stack and services
		var services []db.Service
		db.DB.Where("stack_id = ?", id).Find(&services)
		for _, svc := range services {
			db.DB.Model(&db.Task{}).Where("service_id = ?", svc.ID).Updates(map[string]interface{}{
				"status":       "dead",
				"container_ip": "",
			})
		}
		c.JSON(http.StatusOK, gin.H{"message": "Monitor containers stopped and marked as dead"})
		return
	}

	// Special handling for Core stack (CoreDNS + Caddy + Gubernator)
	if id == coredns.CoreStackID {
		// Restart the core containers but do not delete them from database or stop/remove them permanently
		var services []db.Service
		db.DB.Where("stack_id = ?", id).Find(&services)
		for _, svc := range services {
			var tasks []db.Task
			db.DB.Where("service_id = ?", svc.ID).Find(&tasks)
			for _, task := range tasks {
				if task.ContainerName != "" {
					go func(name string) {
						exec.Command("docker", "restart", name).Run()
					}(task.ContainerName)
				}
			}
		}
		c.JSON(http.StatusOK, gin.H{"message": "Core containers restarted"})
		return
	}

	// Stop all running containers for this stack first
	StopStackContainers(id)

	// Delete tasks related to this stack's services
	var services []db.Service
	db.DB.Where("stack_id = ?", id).Find(&services)
	for _, svc := range services {
		db.DB.Where("service_id = ?", svc.ID).Delete(&db.Task{})
	}

	// Delete services
	db.DB.Where("stack_id = ?", id).Delete(&db.Service{})

	// Delete stack
	if res := db.DB.Where("id = ?", id).Delete(&db.Stack{}); res.Error != nil || res.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "Stack not found"})
		return
	}

	// Trigger generation of DNS and Ingress now that the stack and its tasks are deleted
	aqueducts.GenerateAllAsync()

	c.JSON(http.StatusOK, gin.H{"message": "Stack removed and containers stopped"})
}

// @Summary Stop Stack
// @Description Stop all running containers in a stack without deleting it
// @Tags stacks
// @Produce json
// @Param id path string true "Stack ID"
// @Success 200 {object} map[string]string
// @Router /v1/stack/{id}/stop [post]
func StackStopHandler(c *gin.Context) {
	id := c.Param("id")

	var stack db.Stack
	if err := db.DB.First(&stack, "id = ?", id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Stack not found"})
		return
	}

	// 1. Special handling for SRE Monitor stack
	if id == monitor.SREStackID {
		monitor.StopAll()
		var services []db.Service
		db.DB.Where("stack_id = ?", id).Find(&services)
		for _, svc := range services {
			db.DB.Model(&db.Task{}).Where("service_id = ?", svc.ID).Updates(map[string]interface{}{
				"status":       "stopped",
				"container_ip": "",
			})
		}
		c.JSON(http.StatusOK, gin.H{"status": "stopped", "message": "Monitor containers stopped"})
		return
	}

	// 2. Special handling for Core stack (CoreDNS + Caddy)
	if id == coredns.CoreStackID {
		coredns.Stop()
		caddy.Stop()
		var services []db.Service
		db.DB.Where("stack_id = ?", id).Find(&services)
		for _, svc := range services {
			db.DB.Model(&db.Task{}).Where("service_id = ?", svc.ID).Updates(map[string]interface{}{
				"status":       "stopped",
				"container_ip": "",
			})
		}
		c.JSON(http.StatusOK, gin.H{"status": "stopped", "message": "Core containers stopped"})
		return
	}

	// 3. User deployed stacks: strictly enforce desired replicas
	var services []db.Service
	db.DB.Where("stack_id = ?", id).Find(&services)
	stoppedCount := 0
	for _, svc := range services {
		desired := svc.DesiredReplicas
		if desired <= 0 {
			desired = 1
		}
		var tasks []db.Task
		db.DB.Where("service_id = ?", svc.ID).Order("created_at desc").Find(&tasks)
		for i, task := range tasks {
			if i < desired {
				_ = StopTaskOnNode(task)
				db.DB.Model(&db.Task{}).Where("id = ?", task.ID).Updates(map[string]interface{}{
					"status":       "stopped",
					"container_ip": "",
				})
				stoppedCount++
			} else {
				cName := task.ContainerName
				if cName == "" {
					cName = "gbnt-" + task.ID
				}
				_ = docker.RemoveContainerOnNode(task.NodeID, cName)
				db.DB.Delete(&task)
			}
		}
	}

	aqueducts.GenerateAllAsync()
	c.JSON(http.StatusOK, gin.H{"status": "stopped", "stack_id": id, "stopped_containers": stoppedCount})
}

// @Summary Start Stack
// @Description Start all containers in a stopped stack
// @Tags stacks
// @Produce json
// @Param id path string true "Stack ID"
// @Success 200 {object} map[string]string
// @Router /v1/stack/{id}/start [post]
func StackStartHandler(c *gin.Context) {
	id := c.Param("id")

	var stack db.Stack
	if err := db.DB.First(&stack, "id = ?", id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Stack not found"})
		return
	}

	// 1. Special handling for SRE Monitor stack
	if id == monitor.SREStackID {
		_ = monitor.EnsureNetwork()
		_ = monitor.WriteConfigs(nil)
		_ = monitor.DeployManagerStack(os.Getenv("GBNT_WEB_USER"), os.Getenv("GBNT_WEB_PASSWORD"))
		_ = monitor.RegisterInDB(db.DB)
		aqueducts.GenerateAllAsync()
		c.JSON(http.StatusOK, gin.H{"status": "started", "message": "Monitor stack started"})
		return
	}

	// 2. Special handling for Core stack
	if id == coredns.CoreStackID {
		_ = coredns.EnsureNetwork()
		_ = coredns.EnsureRunning()
		_ = caddy.EnsureRunning()
		_ = coredns.RegisterInDB(db.DB)
		aqueducts.GenerateAllAsync()
		c.JSON(http.StatusOK, gin.H{"status": "started", "message": "Core stack started"})
		return
	}

	// 3. User deployed stacks
	if stack.RawComposeFile != "" {
		if _, err := DeployStackRaw(stack.Name, stack.RawComposeFile, ""); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to start stack: %v", err)})
			return
		}
	}

	aqueducts.GenerateAllAsync()
	c.JSON(http.StatusOK, gin.H{"status": "started", "stack_id": id})
}

// @Summary Reconcile Stack
// @Description Reconcile a stack against desired replicas, repairing degraded services and purging dead/stale containers
// @Tags stacks
// @Produce json
// @Param id path string true "Stack ID or Name"
// @Success 200 {object} map[string]interface{}
// @Router /v1/stack/{id}/reconcile [post]
func StackReconcileHandler(c *gin.Context) {
	id := c.Param("id")
	pruned, rescheduled, err := ReconcileSingleStack(id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"status":                 "ok",
		"stack_id":               id,
		"pruned_containers":      pruned,
		"rescheduled_containers": rescheduled,
		"message":                fmt.Sprintf("Stack %s reconciled. Purged %d stale containers, rescheduled %d.", id, pruned, rescheduled),
	})
}

// @Summary Prune Tasks
// @Description Prune all dead, duplicate, and orphan containers across the cluster
// @Tags tasks
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Router /v1/tasks/prune [post]
func TasksPruneHandler(c *gin.Context) {
	pruned, rescheduled := ReconcileClusterServices()
	c.JSON(http.StatusOK, gin.H{
		"status":                 "ok",
		"pruned_containers":      pruned,
		"rescheduled_containers": rescheduled,
		"message":                fmt.Sprintf("Cluster reconciliation complete. Purged %d stale containers, rescheduled %d.", pruned, rescheduled),
	})
}
