package api

import (
	"net/http"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/coredns"
)

// @Summary Get CoreDNS Configuration
// @Description Returns the raw text of the Corefile
// @Tags CoreDNS
// @Produce plain
// @Success 200 {string} string "CoreDNS configuration content"
// @Router /v1/coredns/config [get]
func GetCoreDNSConfig(c *gin.Context) {
	content, err := os.ReadFile(coredns.CorefilePath())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read CoreDNS config: " + err.Error()})
		return
	}
	c.String(http.StatusOK, string(content))
}

type UpdateConfigRequest struct {
	Config string `json:"config"`
}

// @Summary Update CoreDNS Configuration
// @Description Overwrites the Corefile and restarts the CoreDNS container
// @Tags CoreDNS
// @Accept json
// @Produce json
// @Param body body UpdateConfigRequest true "New configuration"
// @Success 200 {object} map[string]string
// @Router /v1/coredns/config [put]
func UpdateCoreDNSConfig(c *gin.Context) {
	var req UpdateConfigRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body"})
		return
	}

	if req.Config == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Config cannot be empty"})
		return
	}

	// Write the new config
	if err := os.WriteFile(coredns.CorefilePath(), []byte(req.Config), 0644); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save CoreDNS config: " + err.Error()})
		return
	}

	// Restart CoreDNS to pick up the new Corefile
	if err := coredns.Restart(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Config saved but failed to restart CoreDNS: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "CoreDNS configuration updated successfully"})
}
