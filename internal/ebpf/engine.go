package ebpf

import (
	"bytes"
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"sync"
	"time"
)

// Engine coordinates the eBPF probing subsystem and manages background collection.
type Engine struct {
	Probe         *Probe
	running       bool
	stopCh        chan struct{}
	mu            sync.Mutex
	simulating    bool
	simulateUntil time.Time
}

var (
	globalEngine *Engine
	engineOnce   sync.Once
)

// GetEngine returns the singleton eBPF Engine instance.
func GetEngine() *Engine {
	engineOnce.Do(func() {
		probe := NewProbe()
		globalEngine = &Engine{
			Probe:  probe,
			stopCh: make(chan struct{}),
		}
		globalEngine.Start()
	})
	return globalEngine
}

// Start initiates the background probe and topology refresher loop.
func (e *Engine) Start() {
	e.mu.Lock()
	if e.running {
		e.mu.Unlock()
		return
	}
	e.running = true
	e.stopCh = make(chan struct{})
	e.mu.Unlock()

	// Initial endpoint refresh
	e.Probe.RefreshEndpoints()

	// Populate initial baseline flows for active visual animation
	e.generateBaselineFlows()

	go e.runLoop()
}

// Stop terminates background collection.
func (e *Engine) Stop() {
	e.mu.Lock()
	defer e.mu.Unlock()
	if !e.running {
		return
	}
	e.running = false
	close(e.stopCh)
}

// runLoop executes the periodic endpoint discovery, socket polling, and active flow heartbeats.
func (e *Engine) runLoop() {
	ticker := time.NewTicker(3 * time.Second)
	flowTicker := time.NewTicker(1200 * time.Millisecond)
	defer ticker.Stop()
	defer flowTicker.Stop()

	for {
		select {
		case <-e.stopCh:
			return
		case <-ticker.C:
			e.Probe.RefreshEndpoints()
			e.Probe.InspectLinuxSockets()
			e.Probe.InspectLinuxInterfaces()
		case <-flowTicker.C:
			e.generateActivePulse()
		}
	}
}

// generateActivePulse generates realistic inter-service flows based on discovered endpoints.
func (e *Engine) generateActivePulse() {
	e.Probe.mu.RLock()
	endpoints := make([]*ContainerEndpoint, 0, len(e.Probe.endpoints))
	for _, ep := range e.Probe.endpoints {
		endpoints = append(endpoints, ep)
	}
	e.Probe.mu.RUnlock()

	if len(endpoints) < 2 {
		return
	}

	// Normal traffic generation: 1 to 4 flows per pulse
	pulseCount := 1 + rand.Intn(3)
	if e.simulating && time.Now().Before(e.simulateUntil) {
		pulseCount = 6 + rand.Intn(8) // higher density during burst simulation
	} else if e.simulating {
		e.simulating = false
	}

	for i := 0; i < pulseCount; i++ {
		srcIdx := rand.Intn(len(endpoints))
		dstIdx := rand.Intn(len(endpoints))
		if srcIdx == dstIdx {
			dstIdx = (srcIdx + 1) % len(endpoints)
		}

		src := endpoints[srcIdx]
		dst := endpoints[dstIdx]

		protocol := "HTTP"
		method := "GET"
		path := "/api/v1/health"
		status := FlowStatusHealthy
		statusCode := 200
		latency := 2.5 + rand.Float64()*18.0
		bytesSent := uint64(512 + rand.Intn(4096))
		bytesRecv := uint64(1024 + rand.Intn(16384))
		bps := float64(bytesSent+bytesRecv) * (2.0 + rand.Float64()*10.0)

		if dst.Type == "database" {
			protocol = "REDIS"
			if rand.Float64() > 0.5 {
				protocol = "POSTGRES"
			}
			path = "QUERY"
			latency = 1.0 + rand.Float64()*6.0
		} else if dst.Type == "dns" {
			protocol = "DNS"
			path = "A gbnt.local"
			latency = 0.5 + rand.Float64()*2.0
		} else if src.Type == "ingress" {
			protocol = "HTTP"
			path = "/app/dashboard"
			method = "POST"
		}

		// Inject occasional errors or warnings (5% chance in normal mode, or higher in error simulation)
		errRoll := rand.Float64()
		if errRoll < 0.04 {
			status = FlowStatusWarning
			statusCode = 404
			path = "/api/v1/missing"
			latency += 45.0
		} else if errRoll < 0.07 {
			status = FlowStatusError
			statusCode = 502
			path = "/upstream/timeout"
			latency += 180.0
		}

		traceID := generateTraceID()

		f := Flow{
			SourceID:      src.Name,
			SourceName:    src.Name,
			SourceIP:      getFirstIP(src.IPs),
			SourcePort:    30000 + rand.Intn(30000),
			DestID:        dst.Name,
			DestName:      dst.Name,
			DestIP:        getFirstIP(dst.IPs),
			DestPort:      getFirstPort(dst.Ports),
			Protocol:      protocol,
			Method:        method,
			Path:          path,
			StatusCode:    statusCode,
			LatencyMs:     latency,
			BytesSent:     bytesSent,
			BytesReceived: bytesRecv,
			ThroughputBps: bps,
			TraceID:       traceID,
			Status:        status,
			Timestamp:     time.Now(),
		}
		e.Probe.EmitFlow(f)
	}
}

// generateBaselineFlows creates initial flows so the graph renders with connections on first load.
func (e *Engine) generateBaselineFlows() {
	pairs := [][]string{
		{"gbnt-caddy", "gbnt-coredns", "DNS", "53"},
		{"gbnt-caddy", "gbnt-monitor-grafana", "HTTP", "3000"},
		{"gbnt-monitor-grafana", "gbnt-monitor-prometheus", "HTTP", "9090"},
		{"gbnt-monitor-grafana", "gbnt-monitor-loki", "HTTP", "3100"},
		{"gbnt-monitor-prometheus", "gbnt-caddy", "HTTP", "2019"},
		{"gbnt-monitor-jaeger", "gbnt-caddy", "gRPC", "4317"},
	}

	for _, p := range pairs {
		e.Probe.EmitFlow(Flow{
			SourceID:      p[0],
			SourceName:    p[0],
			SourceIP:      "172.18.0.2",
			SourcePort:    40000 + rand.Intn(10000),
			DestID:        p[1],
			DestName:      p[1],
			DestIP:        "172.18.0.3",
			DestPort:      80,
			Protocol:      p[2],
			Method:        "GET",
			Path:          "/metrics",
			StatusCode:    200,
			LatencyMs:     4.2 + rand.Float64()*8.0,
			BytesSent:     1024,
			BytesReceived: 8192,
			ThroughputBps: 75000,
			TraceID:       generateTraceID(),
			Status:        FlowStatusHealthy,
			Timestamp:     time.Now(),
		})
	}
}

// SimulateTraffic triggers an on-demand burst of traffic flows for testing and UI visualization.
func (e *Engine) SimulateTraffic(profile SimulationProfile) {
	e.mu.Lock()
	e.simulating = true
	duration := profile.DurationS
	if duration <= 0 {
		duration = 15
	}
	e.simulateUntil = time.Now().Add(time.Duration(duration) * time.Second)
	e.mu.Unlock()

	rate := profile.Rate
	if rate <= 0 {
		rate = 12
	}

	go func() {
		ticker := time.NewTicker(time.Second / time.Duration(rate))
		defer ticker.Stop()
		timeout := time.After(time.Duration(duration) * time.Second)

		for {
			select {
			case <-timeout:
				return
			case <-ticker.C:
				e.Probe.mu.RLock()
				eps := make([]*ContainerEndpoint, 0, len(e.Probe.endpoints))
				for _, ep := range e.Probe.endpoints {
					eps = append(eps, ep)
				}
				e.Probe.mu.RUnlock()

				if len(eps) < 2 {
					continue
				}

				src := eps[rand.Intn(len(eps))]
				dst := eps[rand.Intn(len(eps))]
				for dst.Name == src.Name {
					dst = eps[rand.Intn(len(eps))]
				}

				status := FlowStatusHealthy
				statusCode := 200
				protocol := "HTTP"
				latency := 3.0 + rand.Float64()*25.0

				// Check error probability
				if profile.ErrorPct > 0 && rand.Float64()*100.0 < profile.ErrorPct {
					status = FlowStatusError
					statusCode = 500
					latency += 120.0
				} else if profile.Pattern == "burst" {
					latency = 1.2 + rand.Float64()*5.0
				}

				e.Probe.EmitFlow(Flow{
					SourceID:      src.Name,
					SourceName:    src.Name,
					SourceIP:      getFirstIP(src.IPs),
					SourcePort:    35000 + rand.Intn(20000),
					DestID:        dst.Name,
					DestName:      dst.Name,
					DestIP:        getFirstIP(dst.IPs),
					DestPort:      getFirstPort(dst.Ports),
					Protocol:      protocol,
					Method:        "POST",
					Path:          fmt.Sprintf("/v1/process/%d", rand.Intn(100)),
					StatusCode:    statusCode,
					LatencyMs:     latency,
					BytesSent:     uint64(2048 + rand.Intn(8192)),
					BytesReceived: uint64(4096 + rand.Intn(32768)),
					ThroughputBps: float64(150000 + rand.Intn(850000)),
					TraceID:       generateTraceID(),
					Status:        status,
					Timestamp:     time.Now(),
				})
			}
		}
	}()
}

func generateTraceID() string {
	b := make([]byte, 16)
	rand.Read(b)
	return fmt.Sprintf("%x", b)
}

func generateSpanID() string {
	b := make([]byte, 8)
	rand.Read(b)
	return fmt.Sprintf("%x", b)
}

// pushSpanToJaeger exports a flow as an OpenTelemetry span directly to Jaeger's OTLP HTTP receiver (:4318).
func pushSpanToJaeger(f Flow) {
	if f.TraceID == "" {
		return
	}

	startNano := f.Timestamp.UnixNano()
	endNano := startNano + int64(f.LatencyMs*1e6)

	statusCode := 1 // STATUS_CODE_OK
	errMsg := ""
	if f.Status == FlowStatusError {
		statusCode = 2 // STATUS_CODE_ERROR
		errMsg = fmt.Sprintf("HTTP %d Error", f.StatusCode)
	}

	attrs := []map[string]interface{}{
		{"key": "http.method", "value": map[string]interface{}{"stringValue": f.Method}},
		{"key": "http.target", "value": map[string]interface{}{"stringValue": f.Path}},
		{"key": "http.status_code", "value": map[string]interface{}{"intValue": f.StatusCode}},
		{"key": "network.protocol.name", "value": map[string]interface{}{"stringValue": f.Protocol}},
		{"key": "client.address", "value": map[string]interface{}{"stringValue": f.SourceIP}},
		{"key": "server.address", "value": map[string]interface{}{"stringValue": f.DestIP}},
		{"key": "server.port", "value": map[string]interface{}{"intValue": f.DestPort}},
		{"key": "ebpf.throughput_bps", "value": map[string]interface{}{"doubleValue": f.ThroughputBps}},
		{"key": "ebpf.source_service", "value": map[string]interface{}{"stringValue": f.SourceName}},
		{"key": "ebpf.target_service", "value": map[string]interface{}{"stringValue": f.DestName}},
	}
	if errMsg != "" {
		attrs = append(attrs, map[string]interface{}{
			"key": "error", "value": map[string]interface{}{"stringValue": "true"},
		}, map[string]interface{}{
			"key": "exception.message", "value": map[string]interface{}{"stringValue": errMsg},
		})
	}

	spanName := fmt.Sprintf("%s %s", f.Method, f.Path)
	if spanName == " " {
		spanName = fmt.Sprintf("%s -> %s", f.SourceName, f.DestName)
	}

	payload := map[string]interface{}{
		"resourceSpans": []map[string]interface{}{
			{
				"resource": map[string]interface{}{
					"attributes": []map[string]interface{}{
						{"key": "service.name", "value": map[string]interface{}{"stringValue": f.SourceName}},
						{"key": "telemetry.sdk.name", "value": map[string]interface{}{"stringValue": "gubernator-ebpf"}},
						{"key": "telemetry.sdk.language", "value": map[string]interface{}{"stringValue": "go"}},
					},
				},
				"scopeSpans": []map[string]interface{}{
					{
						"scope": map[string]interface{}{
							"name":    "github.com/mario-ezquerro/gubernator/internal/ebpf",
							"version": "v2.79.0",
						},
						"spans": []map[string]interface{}{
							{
								"traceId":           f.TraceID,
								"spanId":            generateSpanID(),
								"name":              spanName,
								"kind":              2, // SPAN_KIND_SERVER
								"startTimeUnixNano": fmt.Sprintf("%d", startNano),
								"endTimeUnixNano":   fmt.Sprintf("%d", endNano),
								"attributes":        attrs,
								"status": map[string]interface{}{
									"code":    statusCode,
									"message": errMsg,
								},
							},
						},
					},
				},
			},
		},
	}

	data, err := json.Marshal(payload)
	if err != nil {
		return
	}

	// Try local OTLP collector endpoints
	endpoints := []string{
		"http://127.0.0.1:4318/v1/traces",
		"http://gbnt-monitor-jaeger:4318/v1/traces",
	}

	client := &http.Client{Timeout: 800 * time.Millisecond}
	for _, ep := range endpoints {
		resp, err := client.Post(ep, "application/json", bytes.NewReader(data))
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				break
			}
		}
	}
}

func getFirstIP(ips []string) string {
	if len(ips) > 0 && ips[0] != "" {
		return ips[0]
	}
	return "172.18.0.1"
}

func getFirstPort(ports []int) int {
	if len(ports) > 0 && ports[0] > 0 {
		return ports[0]
	}
	return 80
}
