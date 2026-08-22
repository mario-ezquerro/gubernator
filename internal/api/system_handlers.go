package api

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/telemetry"
)

// SystemAdoptionHandler returns public GitHub adoption stats, release downloads and local cluster metrics.
func SystemAdoptionHandler(c *gin.Context) {
	force := c.Query("force") == "true"
	stats := telemetry.GetAdoptionStats(force)
	c.JSON(http.StatusOK, stats)
}
