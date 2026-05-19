package api

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/db"
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

	c.JSON(http.StatusOK, gin.H{"message": "Stack removed and containers stopped"})
}
