package telemetry

import (
	"github.com/gin-gonic/gin"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	TotalNodes = prometheus.NewGauge(prometheus.GaugeOpts{
		Name: "gbnt_total_nodes",
		Help: "Current number of nodes registered in the cluster.",
	})
	TotalTasks = prometheus.NewGauge(prometheus.GaugeOpts{
		Name: "gbnt_total_tasks",
		Help: "Current number of tasks scheduled in the cluster.",
	})
)

func init() {
	// Register custom metrics with the global prometheus registry
	prometheus.MustRegister(TotalNodes)
	prometheus.MustRegister(TotalTasks)
}

// MetricsHandler returns a gin.HandlerFunc for Prometheus scraping
func MetricsHandler() gin.HandlerFunc {
	h := promhttp.Handler()
	return func(c *gin.Context) {
		h.ServeHTTP(c.Writer, c.Request)
	}
}
