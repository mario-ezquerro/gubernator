package api

import (
	"encoding/json"
	"io"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/ebpf"
)

// @Summary Get eBPF kernel network telemetry and probe stats
// @Description Returns kernel eBPF capabilities, active probes, flow rate, throughput, and packet statistics
// @Tags ebpf
// @Produce json
// @Success 200 {object} ebpf.EBPFStats
// @Router /v1/ebpf/stats [get]
func EBPFStatsHandler(c *gin.Context) {
	eng := ebpf.GetEngine()
	stats := eng.Probe.GetStats()
	c.JSON(http.StatusOK, stats)
}

// @Summary Get recent eBPF captured network flows
// @Description Returns recent captured L4/L7 network flows with filtering by protocol, status, query, and limit
// @Tags ebpf
// @Produce json
// @Param limit query int false "Maximum number of flows to return (default 50)"
// @Param protocol query string false "Protocol filter (e.g. HTTP, gRPC, DNS, TCP, REDIS, POSTGRES)"
// @Param status query string false "Status filter (healthy, warning, error, or ERRORS)"
// @Param q query string false "Search query matching source, dest, method, or path"
// @Success 200 {array} ebpf.Flow
// @Router /v1/ebpf/flows [get]
func EBPFFlowsHandler(c *gin.Context) {
	limitStr := c.DefaultQuery("limit", "50")
	limit, _ := strconv.Atoi(limitStr)
	if limit <= 0 {
		limit = 50
	}
	proto := c.Query("protocol")
	status := c.Query("status")
	query := c.Query("q")

	eng := ebpf.GetEngine()
	flows := eng.Probe.GetRecentFlows(limit, proto, status, query)
	if flows == nil {
		flows = []ebpf.Flow{}
	}
	c.JSON(http.StatusOK, flows)
}

// @Summary Get live eBPF service mesh topology graph
// @Description Returns interconnected topology graph with service nodes and active communication edges
// @Tags ebpf
// @Produce json
// @Success 200 {object} ebpf.EBPFTopology
// @Router /v1/ebpf/topology [get]
func EBPFTopologyHandler(c *gin.Context) {
	eng := ebpf.GetEngine()
	topo := eng.Probe.BuildTopology()
	c.JSON(http.StatusOK, topo)
}

// @Summary Trigger on-demand eBPF traffic simulation
// @Description Injects traffic flows (burst, normal, errors) for testing and UI live visualization
// @Tags ebpf
// @Accept json
// @Produce json
// @Param profile body ebpf.SimulationProfile true "Simulation Profile configuration"
// @Success 200 {object} map[string]string
// @Router /v1/ebpf/simulate [post]
func EBPFSimulateHandler(c *gin.Context) {
	var profile ebpf.SimulationProfile
	if err := c.ShouldBindJSON(&profile); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid simulation payload: " + err.Error()})
		return
	}

	eng := ebpf.GetEngine()
	eng.SimulateTraffic(profile)
	c.JSON(http.StatusOK, gin.H{"status": "Simulation triggered successfully", "pattern": profile.Pattern})
}

// @Summary Stream live eBPF network flows via Server-Sent Events (SSE)
// @Description Real-time stream of captured network packets and flows
// @Tags ebpf
// @Produce text/event-stream
// @Router /v1/ebpf/stream [get]
func EBPFStreamHandler(c *gin.Context) {
	c.Writer.Header().Set("Content-Type", "text/event-stream")
	c.Writer.Header().Set("Cache-Control", "no-cache")
	c.Writer.Header().Set("Connection", "keep-alive")
	c.Writer.Header().Set("Transfer-Encoding", "chunked")

	eng := ebpf.GetEngine()
	ch := eng.Probe.Subscribe()
	defer eng.Probe.Unsubscribe(ch)

	c.Stream(func(w io.Writer) bool {
		select {
		case <-c.Request.Context().Done():
			return false
		case flow, ok := <-ch:
			if !ok {
				return false
			}
			data, err := json.Marshal(flow)
			if err == nil {
				c.SSEvent("flow", string(data))
			}
			return true
		}
	})
}
