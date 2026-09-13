package api

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/caddy"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

func CaddyWAFGetConfigHandler(c *gin.Context) {
	cfg, err := caddy.GetWAFConfig()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, cfg)
}

func CaddyWAFUpdateConfigHandler(c *gin.Context) {
	var req db.ManagedWAFConfig
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid WAF configuration payload: " + err.Error()})
		return
	}

	updated, err := caddy.UpdateWAFConfig(req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update WAF config: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"message": "WAF configuration updated successfully",
		"config":  updated,
	})
}

func CaddyWAFListRoutesHandler(c *gin.Context) {
	routes, err := caddy.ListRouteWAFs()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"routes": routes})
}

type wafRouteToggleRequest struct {
	Host    string `json:"host"`
	Enabled *bool  `json:"enabled"`
	Mode    string `json:"mode"`
}

func CaddyWAFRouteToggleHandler(c *gin.Context) {
	var req wafRouteToggleRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid route toggle payload: " + err.Error()})
		return
	}
	if strings.TrimSpace(req.Host) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Host is required"})
		return
	}

	enabled := true
	if req.Enabled != nil {
		enabled = *req.Enabled
	}
	mode := strings.ToLower(strings.TrimSpace(req.Mode))
	if mode == "" {
		mode = "enforce"
	}

	route, err := caddy.SetRouteWAF(req.Host, enabled, mode, "manual")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update route WAF: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Route WAF updated successfully",
		"route":   route,
	})
}

func CaddyWAFRouteDeleteHandler(c *gin.Context) {
	host := c.Param("host")
	if strings.TrimSpace(host) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Host parameter is required"})
		return
	}

	if err := caddy.DeleteRouteWAF(host); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"message": "Route WAF override cleared, restored to cluster defaults",
		"host":    host,
	})
}

func CaddyWAFListEventsHandler(c *gin.Context) {
	limitStr := c.DefaultQuery("limit", "50")
	limit, _ := strconv.Atoi(limitStr)
	attackType := c.Query("type")
	host := c.Query("host")

	events, err := caddy.ListWAFEvents(limit, attackType, host)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"events": events})
}

func CaddyWAFGetStatsHandler(c *gin.Context) {
	stats, err := caddy.GetWAFStats()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, stats)
}

type wafIPRequest struct {
	IP     string `json:"ip"`
	Reason string `json:"reason"`
}

func CaddyWAFIPBlockHandler(c *gin.Context) {
	var req wafIPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid IP block payload: " + err.Error()})
		return
	}
	if strings.TrimSpace(req.IP) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "IP is required"})
		return
	}

	if err := caddy.BlockIP(req.IP, req.Reason); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to block IP: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"message": "IP added to Threat Shield blacklist",
		"ip":      req.IP,
	})
}

func CaddyWAFIPUnblockHandler(c *gin.Context) {
	var req wafIPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid IP unblock payload: " + err.Error()})
		return
	}
	if strings.TrimSpace(req.IP) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "IP is required"})
		return
	}

	if err := caddy.UnblockIP(req.IP); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to unblock IP: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"message": "IP removed from Threat Shield blacklist",
		"ip":      req.IP,
	})
}

type wafSimulateRequest struct {
	Host   string `json:"host"`
	Vector string `json:"vector"`
}

func CaddyWAFSimulateTestHandler(c *gin.Context) {
	var req wafSimulateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid simulation payload: " + err.Error()})
		return
	}

	evt, err := caddy.SimulateThreat(req.Host, req.Vector)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Simulation failed: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"message": "Security threat simulated and evaluated by Threat Shield engine",
		"event":   evt,
	})
}
