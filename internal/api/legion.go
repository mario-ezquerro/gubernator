package api

import (
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/mario-ezquerro/gubernator/internal/monitor"
)

// JoinRequest represents the payload for joining the cluster
type JoinRequest struct {
	ID     string            `json:"id" binding:"required"`
	IP     string            `json:"ip" binding:"required"`
	Token  string            `json:"token" binding:"required"`
	Labels map[string]string `json:"labels"`
}

// @Summary Join the cluster
// @Description Register a new worker node in the Gubernator cluster using a Join Token
// @Tags legion
// @Accept json
// @Produce json
// @Param request body JoinRequest true "Join Request"
// @Success 200 {object} map[string]string
// @Failure 401 {object} map[string]string
// @Router /v1/node/join [post]
func NodeJoinHandler(c *gin.Context) {
	var req JoinRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Verify Token
	var config db.ClusterConfig
	if err := db.DB.First(&config, "id = ?", "global").Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Could not verify token"})
		return
	}

	if config.JoinToken != req.Token {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid join token"})
		return
	}

	// Register or Update Node
	node := db.Node{
		ID:     req.ID,
		IP:     req.IP,
		Role:   "worker",
		Status: "active",
		Labels: req.Labels,
	}

	if err := db.DB.Save(&node).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to register node"})
		return
	}

	// Regenerate and reload Prometheus configurations with the new worker target
	if err := monitor.UpdatePrometheusConfig(); err != nil {
		log.Printf("Warning: failed to update Prometheus config on node join: %v", err)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Successfully joined the cluster"})
}

// HeartbeatRequest represents the payload for node heartbeats
type HeartbeatRequest struct {
	ID string `json:"id" binding:"required"`
}

// @Summary Node Heartbeat
// @Description Nodes call this to let the manager know they are alive
// @Tags legion
// @Accept json
// @Produce json
// @Param request body HeartbeatRequest true "Heartbeat Request"
// @Success 200 {object} map[string]string
// @Router /v1/node/heartbeat [post]
func NodeHeartbeatHandler(c *gin.Context) {
	var req HeartbeatRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	result := db.DB.Model(&db.Node{}).Where("id = ?", req.ID).Updates(map[string]interface{}{
		"status":     "active",
		"updated_at": time.Now(),
	})

	if result.Error != nil || result.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "Node not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Heartbeat received"})
}

// @Summary Get Cluster Join Token
// @Description Retrieve the current global join token (requires local access)
// @Tags legion
// @Produce json
// @Success 200 {object} map[string]string
// @Router /v1/cluster/token [get]
func ClusterTokenHandler(c *gin.Context) {
	// In a real scenario, this should be protected.
	// We'll restrict it to localhost for basic security.
	if c.ClientIP() != "127.0.0.1" && c.ClientIP() != "::1" {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied. Can only read token from localhost."})
		return
	}

	var config db.ClusterConfig
	if err := db.DB.First(&config, "id = ?", "global").Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Token not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"token": config.JoinToken})
}

// ClusterInfoHandler returns all bootstrap information (tokens + ready commands).
// Only accessible from localhost to protect sensitive credentials.
//
// @Summary Get Cluster Bootstrap Info
// @Description Returns join token, API token, and ready-to-use CLI commands. Localhost only.
// @Tags legion
// @Produce json
// @Success 200 {object} map[string]string
// @Router /v1/cluster/info [get]
func ClusterInfoHandler(c *gin.Context) {
	if c.ClientIP() != "127.0.0.1" && c.ClientIP() != "::1" {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied. Can only read bootstrap info from localhost."})
		return
	}

	var config db.ClusterConfig
	if err := db.DB.First(&config, "id = ?", "global").Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Config not found"})
		return
	}

	// Try to determine the manager's outbound IP
	managerIP := "localhost"
	if ip := c.Request.Host; ip != "" {
		managerIP = "localhost"
	}

	c.JSON(http.StatusOK, gin.H{
		"join_token":      config.JoinToken,
		"api_token":       config.APIToken,
		"manager_ip_hint": managerIP,
		"join_command":    "gbnt legion join --token " + config.JoinToken + " --manager <MANAGER-IP>:4000",
		"config_command":  "gbnt config add-context myserver --server http://<MANAGER-IP>:4000 --token " + config.APIToken,
	})
}

