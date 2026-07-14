package api

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/aqueducts"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

// TaskResponse represents the payload sent back to a worker
type TaskResponse struct {
	Tasks []TaskWithImage `json:"tasks"`
}

type TaskWithImage struct {
	Task        db.Task  `json:"task"`
	Image       string   `json:"image"`
	Ports       []string `json:"ports"`
	Env         []string `json:"env"`
	Volumes     []string `json:"volumes"`
	Command     string   `json:"command"`
	Constraints []string `json:"constraints"`
}

// @Summary Get assigned tasks for a node
// @Description Fetches active tasks for the worker to execute and proxy
// @Tags tasks
// @Produce json
// @Param node_id path string true "Node ID"
// @Success 200 {object} TaskResponse
// @Router /v1/node/tasks/{node_id} [get]
func NodeTasksHandler(c *gin.Context) {
	nodeID := c.Param("node_id")

	var tasks []db.Task
	if err := db.DB.Where("node_id = ? AND status != ?", nodeID, "dead").Find(&tasks).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch tasks"})
		return
	}

	var response []TaskWithImage
	for _, t := range tasks {
		var svc db.Service
		db.DB.First(&svc, "id = ?", t.ServiceID)
		response = append(response, TaskWithImage{
			Task:        t,
			Image:       svc.Image,
			Ports:       svc.Ports,
			Env:         svc.Env,
			Volumes:     svc.Volumes,
			Command:     svc.Command,
			Constraints: svc.Constraints,
		})
	}

	c.JSON(http.StatusOK, TaskResponse{Tasks: response})
}

type TaskStatusRequest struct {
	Status      string `json:"status" binding:"required"`
	ContainerIP string `json:"container_ip"`
}

// @Summary Update task status
// @Description Worker reports back whether the task is running or failed
// @Tags tasks
// @Accept json
// @Produce json
// @Param task_id path string true "Task ID"
// @Param request body TaskStatusRequest true "Status Update"
// @Success 200 {object} map[string]string
// @Router /v1/node/tasks/{task_id}/status [post]
func UpdateTaskStatusHandler(c *gin.Context) {
	taskID := c.Param("task_id")

	var req TaskStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	updates := map[string]interface{}{
		"status": req.Status,
	}
	if req.ContainerIP != "" {
		updates["container_ip"] = req.ContainerIP
	}

	res := db.DB.Model(&db.Task{}).Where("id = ?", taskID).Updates(updates)
	if res.Error != nil || res.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "Task not found"})
		return
	}

	// Trigger CoreDNS & Caddy update
	aqueducts.GenerateAllAsync()

	c.JSON(http.StatusOK, gin.H{"message": "Status updated"})
}

// @Summary List all tasks
// @Description Get a list of all tasks
// @Tags tasks
// @Produce json
// @Success 200 {array} db.Task
// @Router /v1/task/ls [get]
func TaskListHandler(c *gin.Context) {
	var tasks []db.Task
	if err := db.DB.Find(&tasks).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch tasks"})
		return
	}
	c.JSON(http.StatusOK, tasks)
}

// @Summary Remove a task
// @Description Delete a task by ID
// @Tags tasks
// @Produce json
// @Param id path string true "Task ID"
// @Success 200 {object} map[string]string
// @Router /v1/task/{id} [delete]
func TaskRmHandler(c *gin.Context) {
	id := c.Param("id")
	res := db.DB.Where("id = ?", id).Delete(&db.Task{})
	if res.Error != nil || res.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "Task not found"})
		return
	}

	aqueducts.GenerateAllAsync()

	c.JSON(http.StatusOK, gin.H{"message": "Task removed"})
}
