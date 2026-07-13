package api

import (
	"net/http"
	"os/exec"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/aqueducts"
	"github.com/mario-ezquerro/gubernator/internal/coredns"
	"github.com/mario-ezquerro/gubernator/internal/db"
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
