package web

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/mario-ezquerro/gubernator/internal/caddy"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

func caddyWAFConfigHandler(c *gin.Context) {
	cfg, err := caddy.GetWAFConfig()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, cfg)
}

func caddyWAFUpdateConfigHandler(c *gin.Context) {
	var req db.ManagedWAFConfig
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid WAF configuration payload: " + err.Error()})
		return
	}

	updated, err := caddy.UpdateWAFConfig(req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update WAF configuration: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"message": "WAF configuration updated and Caddyfile regenerated",
		"config":  updated,
	})
}

func caddyWAFRoutesHandler(c *gin.Context) {
	routes, err := caddy.ListRouteWAFs()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"routes": routes})
}

type wafRouteToggleReq struct {
	Host    string `json:"host"`
	Enabled *bool  `json:"enabled"`
	Mode    string `json:"mode"`
}

func caddyWAFRouteToggleHandler(c *gin.Context) {
	var req wafRouteToggleReq
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

func caddyWAFRouteDeleteHandler(c *gin.Context) {
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

func caddyWAFEventsHandler(c *gin.Context) {
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

func caddyWAFStatsHandler(c *gin.Context) {
	stats, err := caddy.GetWAFStats()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, stats)
}

type wafIPActionReq struct {
	IP     string `json:"ip"`
	Reason string `json:"reason"`
}

func caddyWAFIPBlockHandler(c *gin.Context) {
	var req wafIPActionReq
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

func caddyWAFIPUnblockHandler(c *gin.Context) {
	var req wafIPActionReq
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

type wafSimulateReq struct {
	Host   string `json:"host"`
	Vector string `json:"vector"`
}

func caddyWAFSimulateTestHandler(c *gin.Context) {
	var req wafSimulateReq
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
