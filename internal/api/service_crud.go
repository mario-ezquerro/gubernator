package api

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

// @Summary List Services
// @Description List all services
// @Tags services
// @Produce json
// @Success 200 {array} db.Service
// @Router /v1/service/ls [get]
func ServiceListHandler(c *gin.Context) {
	var services []db.Service
	if err := db.DB.Find(&services).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch services"})
		return
	}
	c.JSON(http.StatusOK, services)
}

// @Summary List Service Tasks
// @Description List tasks belonging to a service
// @Tags services
// @Produce json
// @Param id path string true "Service ID"
// @Success 200 {array} db.Task
// @Router /v1/service/{id}/tasks [get]
func ServiceTasksHandler(c *gin.Context) {
	id := c.Param("id")
	var tasks []db.Task
	if err := db.DB.Where("service_id = ?", id).Find(&tasks).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch tasks"})
		return
	}
	c.JSON(http.StatusOK, tasks)
}

// @Summary Remove Service
// @Description Delete a service and its tasks
// @Tags services
// @Produce json
// @Param id path string true "Service ID"
// @Success 200 {object} map[string]string
// @Router /v1/service/{id} [delete]
func ServiceRmHandler(c *gin.Context) {
	id := c.Param("id")

	// Delete tasks
	db.DB.Where("service_id = ?", id).Delete(&db.Task{})

	// Delete service
	if res := db.DB.Where("id = ?", id).Delete(&db.Service{}); res.Error != nil || res.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "Service not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Service removed"})
}

type ScaleRequest struct {
	Replicas int `json:"replicas" binding:"required"`
}

// @Summary Scale Service
// @Description Update the replicas of a service
// @Tags services
// @Accept json
// @Produce json
// @Param id path string true "Service ID"
// @Param request body ScaleRequest true "Replicas Update"
// @Success 200 {object} map[string]string
// @Router /v1/service/{id}/scale [post]
func ServiceScaleHandler(c *gin.Context) {
	id := c.Param("id")
	var req ScaleRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var svc db.Service
	if err := db.DB.First(&svc, "id = ?", id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Service not found"})
		return
	}

	// Update the service model
	db.DB.Model(&svc).Update("desired_replicas", req.Replicas)

	// Note: Fully scaling up/down involves modifying task objects. For MVP, we just update the target replicas.
	// The scheduler or a reconciler loop should ideally pick this up to spin up/down containers.
	// For now, we update the DB state.

	c.JSON(http.StatusOK, gin.H{"message": "Service scaled to " + strconv.Itoa(req.Replicas)})
}
