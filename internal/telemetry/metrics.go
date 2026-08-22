package telemetry

import (
	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/storage"

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

// glusterCollector implements prometheus.Collector for live GlusterFS metrics.
type glusterCollector struct {
	healthScoreDesc   *prometheus.Desc
	daemonRunningDesc *prometheus.Desc
	peersTotalDesc    *prometheus.Desc
	peersConnDesc     *prometheus.Desc
	volsTotalDesc     *prometheus.Desc
	volStatusDesc     *prometheus.Desc
	volCapacityDesc   *prometheus.Desc
	volBricksTotDesc  *prometheus.Desc
	volBricksOnDesc   *prometheus.Desc
	volPendingHeal    *prometheus.Desc
	volSplitBrainDesc *prometheus.Desc
}

func newGlusterCollector() *glusterCollector {
	return &glusterCollector{
		healthScoreDesc: prometheus.NewDesc(
			"gbnt_gluster_health_score",
			"Overall cluster storage health score (0-100).",
			nil, nil,
		),
		daemonRunningDesc: prometheus.NewDesc(
			"gbnt_gluster_daemon_running",
			"Whether glusterd daemon is currently running (1 = active, 0 = inactive).",
			nil, nil,
		),
		peersTotalDesc: prometheus.NewDesc(
			"gbnt_gluster_peers_total",
			"Total number of peers configured in the trusted storage pool.",
			nil, nil,
		),
		peersConnDesc: prometheus.NewDesc(
			"gbnt_gluster_peers_connected",
			"Number of trusted storage pool peers currently connected and online.",
			nil, nil,
		),
		volsTotalDesc: prometheus.NewDesc(
			"gbnt_gluster_volumes_total",
			"Total number of GlusterFS distributed and replicated volumes.",
			nil, nil,
		),
		volStatusDesc: prometheus.NewDesc(
			"gbnt_gluster_volume_status",
			"Status of the volume (1 = Started/Online, 0 = Stopped/Offline).",
			[]string{"volume", "type", "replica_count"}, nil,
		),
		volCapacityDesc: prometheus.NewDesc(
			"gbnt_gluster_volume_capacity_bytes",
			"Volume storage capacity in bytes.",
			[]string{"volume", "kind"}, nil,
		),
		volBricksTotDesc: prometheus.NewDesc(
			"gbnt_gluster_volume_bricks_total",
			"Total bricks allocated to this volume.",
			[]string{"volume"}, nil,
		),
		volBricksOnDesc: prometheus.NewDesc(
			"gbnt_gluster_volume_bricks_online",
			"Online bricks currently serving I/O for this volume.",
			[]string{"volume"}, nil,
		),
		volPendingHeal: prometheus.NewDesc(
			"gbnt_gluster_volume_pending_heals",
			"Number of files pending self-heal synchronization.",
			[]string{"volume"}, nil,
		),
		volSplitBrainDesc: prometheus.NewDesc(
			"gbnt_gluster_volume_split_brain",
			"Whether the volume is experiencing split-brain condition (1 = split-brain, 0 = healthy).",
			[]string{"volume"}, nil,
		),
	}
}

func (c *glusterCollector) Describe(ch chan<- *prometheus.Desc) {
	ch <- c.healthScoreDesc
	ch <- c.daemonRunningDesc
	ch <- c.peersTotalDesc
	ch <- c.peersConnDesc
	ch <- c.volsTotalDesc
	ch <- c.volStatusDesc
	ch <- c.volCapacityDesc
	ch <- c.volBricksTotDesc
	ch <- c.volBricksOnDesc
	ch <- c.volPendingHeal
	ch <- c.volSplitBrainDesc
}

func (c *glusterCollector) Collect(ch chan<- prometheus.Metric) {
	diag, err := storage.GetGlusterDiagnostics()
	if err != nil || diag == nil {
		return
	}
	daemonVal := 0.0
	if diag.DaemonRunning {
		daemonVal = 1.0
	}

	ch <- prometheus.MustNewConstMetric(c.healthScoreDesc, prometheus.GaugeValue, float64(diag.HealthScore))
	ch <- prometheus.MustNewConstMetric(c.daemonRunningDesc, prometheus.GaugeValue, daemonVal)
	ch <- prometheus.MustNewConstMetric(c.peersTotalDesc, prometheus.GaugeValue, float64(diag.PeersCount))

	connectedCount := 0
	for _, p := range diag.Peers {
		if p.Connected {
			connectedCount++
		}
	}
	ch <- prometheus.MustNewConstMetric(c.peersConnDesc, prometheus.GaugeValue, float64(connectedCount))
	ch <- prometheus.MustNewConstMetric(c.volsTotalDesc, prometheus.GaugeValue, float64(diag.VolumesCount))

	volumes, err := storage.GetGlusterVolumes()
	if err != nil {
		return
	}
	for _, v := range volumes {
		statusVal := 0.0
		if v.Status == "Started" {
			statusVal = 1.0
		}
		ch <- prometheus.MustNewConstMetric(
			c.volStatusDesc, prometheus.GaugeValue, statusVal,
			v.Name, v.Type, string(rune('0'+v.ReplicaCount)),
		)
		ch <- prometheus.MustNewConstMetric(c.volCapacityDesc, prometheus.GaugeValue, float64(v.CapacityTotal), v.Name, "total")
		ch <- prometheus.MustNewConstMetric(c.volCapacityDesc, prometheus.GaugeValue, float64(v.CapacityUsed), v.Name, "used")
		ch <- prometheus.MustNewConstMetric(c.volCapacityDesc, prometheus.GaugeValue, float64(v.CapacityFree), v.Name, "free")
		ch <- prometheus.MustNewConstMetric(c.volBricksTotDesc, prometheus.GaugeValue, float64(v.NumBricks), v.Name)

		onlineBricks := 0
		for _, b := range v.Bricks {
			if b.Online {
				onlineBricks++
			}
		}
		ch <- prometheus.MustNewConstMetric(c.volBricksOnDesc, prometheus.GaugeValue, float64(onlineBricks), v.Name)
		ch <- prometheus.MustNewConstMetric(c.volPendingHeal, prometheus.GaugeValue, float64(v.PendingHeals), v.Name)

		splitVal := 0.0
		if heal, err := storage.GetGlusterHealReport(v.Name); err == nil && heal.InSplitBrain {
			splitVal = 1.0
		}
		ch <- prometheus.MustNewConstMetric(c.volSplitBrainDesc, prometheus.GaugeValue, splitVal, v.Name)
	}
}

func init() {
	// Register custom metrics with the global prometheus registry
	prometheus.MustRegister(TotalNodes)
	prometheus.MustRegister(TotalTasks)
	prometheus.MustRegister(newGlusterCollector())
}

// MetricsHandler returns a gin.HandlerFunc for Prometheus scraping
func MetricsHandler() gin.HandlerFunc {
	h := promhttp.Handler()
	return func(c *gin.Context) {
		h.ServeHTTP(c.Writer, c.Request)
	}
}
