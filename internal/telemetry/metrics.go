package telemetry

import (
	"log"
	"net/http"

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

// StartMetricsServer starts a dedicated HTTP server for Prometheus scraping on port 4001.
func StartMetricsServer() {
	mux := http.NewServeMux()
	mux.Handle("/metrics", promhttp.Handler())

	log.Println("Starting Gubernator Telemetry/Prometheus on :4001")
	if err := http.ListenAndServe(":4001", mux); err != nil {
		log.Fatalf("Failed to start telemetry server: %v", err)
	}
}
