package api

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/docker"
)

// DockerDaemonGetHandler retrieves the status and configuration of /etc/docker/daemon.json across nodes.
func DockerDaemonGetHandler(c *gin.Context) {
	scope := c.DefaultQuery("scope", "all")
	node := c.DefaultQuery("node", "")
	statuses, err := docker.GetClusterDockerDaemonStatus(scope, node)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"scope":   scope,
		"node":    node,
		"hosts":   statuses,
		"presets": docker.BuiltinDaemonPresets(),
	})
}

// DockerDaemonSaveHandler saves and applies /etc/docker/daemon.json on target cluster nodes.
func DockerDaemonSaveHandler(c *gin.Context) {
	var req struct {
		TargetScope string `json:"target_scope"`
		NodeID      string `json:"node_id"`
		RawJSON     string `json:"raw_json"`
		Action      string `json:"action"`
		Backup      *bool  `json:"backup"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.TargetScope == "" {
		req.TargetScope = "all"
	}
	backup := true
	if req.Backup != nil {
		backup = *req.Backup
	}

	results, err := docker.SaveAndApplyDockerDaemonConfig(req.TargetScope, req.NodeID, req.RawJSON, req.Action, backup)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Docker daemon configuration processed",
		"results": results,
		"action":  req.Action,
		"scope":   req.TargetScope,
	})
}
