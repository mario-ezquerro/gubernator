package api

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/monitor"
)

// @Summary Get Weave Scope Network Topology Status
// @Description Get current running status and URL of Weave Scope network topology superpower
// @Tags monitor
// @Produce json
// @Success 200 {object} monitor.ScopeStatusResponse
// @Router /v1/monitor/scope/status [get]
func ScopeStatusHandler(c *gin.Context) {
	hostIP := c.Request.Host
	if hostIP == "" {
		hostIP = "localhost"
	}
	// Strip port if present in Host header
	if idx := len(hostIP) - 1; idx >= 0 {
		for i, r := range hostIP {
			if r == ':' {
				hostIP = hostIP[:i]
				break
			}
		}
	}

	status := monitor.GetScopeStatus(hostIP)
	c.JSON(http.StatusOK, status)
}

// @Summary Enable Weave Scope Network Topology
// @Description Deploy and start the Weave Scope container for interactive container network topology
// @Tags monitor
// @Produce json
// @Success 200 {object} monitor.ScopeStatusResponse
// @Failure 500 {object} Response
// @Router /v1/monitor/scope/enable [post]
func ScopeEnableHandler(c *gin.Context) {
	if err := monitor.EnableScope(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	ScopeStatusHandler(c)
}

// @Summary Disable Weave Scope Network Topology
// @Description Stop and remove the Weave Scope container
// @Tags monitor
// @Produce json
// @Success 200 {object} monitor.ScopeStatusResponse
// @Failure 500 {object} gin.H
// @Router /v1/monitor/scope/disable [post]
func ScopeDisableHandler(c *gin.Context) {
	if err := monitor.DisableScope(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	ScopeStatusHandler(c)
}
