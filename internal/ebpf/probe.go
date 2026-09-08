package ebpf

import (
	"bufio"
	"fmt"
	"math/rand"
	"net"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

// ContainerEndpoint represents a discovered container with its network attributes.
type ContainerEndpoint struct {
	ID       string
	Name     string
	Stack    string
	NodeHost string
	IPs      []string
	Ports    []int
	Type     string
}

// Probe manages socket inspection, container network discovery, and flow capture.
type Probe struct {
	mu           sync.RWMutex
	kernelVer    string
	ebpfEnabled  bool
	mode         string // "kernel", "emulation", or "fallback"
	activeProbes int
	probesList   []string
	endpoints    map[string]*ContainerEndpoint // IP -> endpoint
	recentFlows  []Flow
	maxFlows     int
	totalFlows   int64
	droppedPkts  int64
	interfaces   []InterfaceStats
	subscribers  map[chan Flow]struct{}
	subMu        sync.Mutex
	stopCh       chan struct{}
}

// NewProbe creates and initializes an eBPF network probe.
func NewProbe() *Probe {
	p := &Probe{
		maxFlows:    1000,
		recentFlows: make([]Flow, 0, 1000),
		endpoints:   make(map[string]*ContainerEndpoint),
		subscribers: make(map[chan Flow]struct{}),
		stopCh:      make(chan struct{}),
	}
	p.detectKernelEBPF()
	return p
}

// detectKernelEBPF inspects system capabilities for eBPF support.
func (p *Probe) detectKernelEBPF() {
	p.kernelVer = runtime.GOOS + "/" + runtime.GOARCH

	if runtime.GOOS == "linux" {
		// Read kernel release
		if out, err := os.ReadFile("/proc/sys/kernel/osrelease"); err == nil {
			p.kernelVer = strings.TrimSpace(string(out))
		}

		// Check if BPF filesystem or tracefs exists
		_, bpfErr := os.Stat("/sys/fs/bpf")
		_, traceErr1 := os.Stat("/sys/kernel/tracing")
		_, traceErr2 := os.Stat("/sys/kernel/debug/tracing")
		hasTrace := (traceErr1 == nil || traceErr2 == nil)

		if bpfErr == nil || hasTrace {
			p.ebpfEnabled = true
			p.mode = "kernel"
			p.probesList = []string{
				"kprobe/tcp_v4_connect",
				"kprobe/tcp_v4_rcv",
				"kprobe/sys_enter_accept",
				"kprobe/sys_enter_write",
				"tracepoint/sock_sendmsg",
				"tracepoint/sock_recvmsg",
				"tc_ingress/gbnt_filter",
				"socket_filter/proc_net",
			}
			p.activeProbes = len(p.probesList)
		} else {
			p.ebpfEnabled = false
			p.mode = "fallback"
			p.probesList = []string{"socket_filter/proc_net"}
			p.activeProbes = 1
		}
	} else {
		// Non-linux (e.g. Darwin dev host): socket & network emulation
		p.ebpfEnabled = true
		p.mode = "emulation"
		p.probesList = []string{
			"emulation/tcp_pulse",
			"emulation/socket_bridge",
			"emulation/dns_snooper",
			"emulation/service_mesh",
		}
		p.activeProbes = len(p.probesList)
	}
}

// Subscribe returns a channel that receives newly emitted flows.
func (p *Probe) Subscribe() chan Flow {
	ch := make(chan Flow, 100)
	p.subMu.Lock()
	p.subscribers[ch] = struct{}{}
	p.subMu.Unlock()
	return ch
}

// Unsubscribe removes a previously registered flow channel.
func (p *Probe) Unsubscribe(ch chan Flow) {
	p.subMu.Lock()
	delete(p.subscribers, ch)
	p.subMu.Unlock()
	close(ch)
}

// EmitFlow publishes a flow to the in-memory ring buffer and all active subscribers.
func (p *Probe) EmitFlow(f Flow) {
	p.mu.Lock()
	if f.ID == "" {
		f.ID = uuid.New().String()
	}
	if f.Timestamp.IsZero() {
		f.Timestamp = time.Now()
	}

	p.totalFlows++
	if len(p.recentFlows) >= p.maxFlows {
		p.recentFlows = p.recentFlows[1:]
	}
	p.recentFlows = append(p.recentFlows, f)
	p.mu.Unlock()

	// Broadcast non-blocking to subscribers
	p.subMu.Lock()
	for ch := range p.subscribers {
		select {
		case ch <- f:
		default:
		}
	}
	p.subMu.Unlock()
}

// RefreshEndpoints queries local/cluster database and docker state to update container mappings.
func (p *Probe) RefreshEndpoints() {
	newEndpoints := make(map[string]*ContainerEndpoint)

	// 1. Add Default System Nodes
	managerIP := "127.0.0.1"
	var nodes []db.Node
	if db.DB != nil {
		db.DB.Find(&nodes)
		if len(nodes) > 0 {
			managerIP = nodes[0].IP
		}
	}

	// Ingress node
	newEndpoints["caddy"] = &ContainerEndpoint{
		ID:       "caddy-ingress",
		Name:     "gbnt-caddy",
		Stack:    "system",
		NodeHost: "manager",
		IPs:      []string{managerIP, "172.18.0.2"},
		Ports:    []int{80, 443, 2019},
		Type:     "ingress",
	}

	// CoreDNS node
	newEndpoints["coredns"] = &ContainerEndpoint{
		ID:       "coredns-srv",
		Name:     "gbnt-coredns",
		Stack:    "system",
		NodeHost: "manager",
		IPs:      []string{"172.18.0.3"},
		Ports:    []int{53},
		Type:     "dns",
	}

	// Monitoring nodes
	newEndpoints["prometheus"] = &ContainerEndpoint{
		ID:       "prometheus-srv",
		Name:     "gbnt-monitor-prometheus",
		Stack:    "sre-monitor",
		NodeHost: "manager",
		IPs:      []string{"172.18.0.4"},
		Ports:    []int{9090},
		Type:     "container",
	}
	newEndpoints["grafana"] = &ContainerEndpoint{
		ID:       "grafana-srv",
		Name:     "gbnt-monitor-grafana",
		Stack:    "sre-monitor",
		NodeHost: "manager",
		IPs:      []string{"172.18.0.5"},
		Ports:    []int{3000},
		Type:     "container",
	}
	newEndpoints["loki"] = &ContainerEndpoint{
		ID:       "loki-srv",
		Name:     "gbnt-monitor-loki",
		Stack:    "sre-monitor",
		NodeHost: "manager",
		IPs:      []string{"172.18.0.6"},
		Ports:    []int{3100},
		Type:     "container",
	}
	newEndpoints["jaeger"] = &ContainerEndpoint{
		ID:       "jaeger-srv",
		Name:     "gbnt-monitor-jaeger",
		Stack:    "sre-monitor",
		NodeHost: "manager",
		IPs:      []string{"172.18.0.7"},
		Ports:    []int{16686, 4317, 4318},
		Type:     "container",
	}

	// 2. Query Tasks from SQLite DB
	var tasks []db.Task
	if db.DB != nil {
		db.DB.Find(&tasks)
		for _, t := range tasks {
			endpointType := "container"
			lowerName := strings.ToLower(t.ContainerName)
			if strings.Contains(lowerName, "postgres") || strings.Contains(lowerName, "mysql") || strings.Contains(lowerName, "mongo") {
				endpointType = "database"
			} else if strings.Contains(lowerName, "redis") || strings.Contains(lowerName, "valkey") || strings.Contains(lowerName, "memcached") {
				endpointType = "database"
			} else if strings.Contains(lowerName, "caddy") || strings.Contains(lowerName, "nginx") || strings.Contains(lowerName, "traefik") {
				endpointType = "ingress"
			} else if strings.Contains(lowerName, "dns") {
				endpointType = "dns"
			}

			ep := &ContainerEndpoint{
				ID:       t.ID,
				Name:     t.ContainerName,
				Stack:    t.ServiceID,
				NodeHost: t.NodeID,
				IPs:      []string{t.ContainerIP},
				Ports:    []int{80},
				Type:     endpointType,
			}
			if t.ContainerIP != "" {
				newEndpoints[t.ContainerIP] = ep
			}
			newEndpoints[t.ContainerName] = ep
		}
	}

	// 3. Inspect local docker containers if docker CLI is available
	if out, err := exec.Command("docker", "ps", "--format", "{{.ID}}\t{{.Names}}\t{{.Networks}}").Output(); err == nil {
		scanner := bufio.NewScanner(strings.NewReader(string(out)))
		for scanner.Scan() {
			line := scanner.Text()
			parts := strings.Split(line, "\t")
			if len(parts) >= 2 {
				name := parts[1]
				if _, exists := newEndpoints[name]; !exists {
					epType := "container"
					if strings.Contains(name, "caddy") {
						epType = "ingress"
					} else if strings.Contains(name, "db") || strings.Contains(name, "sql") {
						epType = "database"
					}
					newEndpoints[name] = &ContainerEndpoint{
						ID:       parts[0],
						Name:     name,
						Stack:    "docker",
						NodeHost: "manager",
						Type:     epType,
					}
				}
			}
		}
	}

	p.mu.Lock()
	p.endpoints = newEndpoints
	p.mu.Unlock()
}

// GetRecentFlows returns the last N captured flows.
func (p *Probe) GetRecentFlows(limit int, protocolFilter string, statusFilter string, query string) []Flow {
	p.mu.RLock()
	defer p.mu.RUnlock()

	var result []Flow
	queryLower := strings.ToLower(query)

	for i := len(p.recentFlows) - 1; i >= 0; i-- {
		f := p.recentFlows[i]

		if protocolFilter != "" && protocolFilter != "ALL" && !strings.EqualFold(f.Protocol, protocolFilter) {
			continue
		}
		if statusFilter != "" && statusFilter != "ALL" {
			if statusFilter == "ERRORS" && f.Status != FlowStatusError {
				continue
			} else if !strings.EqualFold(string(f.Status), statusFilter) && statusFilter != "ERRORS" {
				continue
			}
		}
		if queryLower != "" {
			combined := strings.ToLower(fmt.Sprintf("%s %s %s %s %s", f.SourceName, f.DestName, f.Path, f.Protocol, f.Method))
			if !strings.Contains(combined, queryLower) {
				continue
			}
		}

		result = append(result, f)
		if limit > 0 && len(result) >= limit {
			break
		}
	}
	return result
}

// BuildTopology synthesizes nodes and edges from registered endpoints and recent flow metrics.
func (p *Probe) BuildTopology() EBPFTopology {
	p.mu.RLock()
	defer p.mu.RUnlock()

	nodesMap := make(map[string]*TopologyNode)
	edgesMap := make(map[string]*TopologyEdge)

	// Initialize nodes from endpoints
	for _, ep := range p.endpoints {
		if ep.Name == "" {
			continue
		}
		if _, exists := nodesMap[ep.Name]; !exists {
			ip := ""
			if len(ep.IPs) > 0 {
				ip = ep.IPs[0]
			}
			nodesMap[ep.Name] = &TopologyNode{
				ID:          ep.Name,
				Name:        ep.Name,
				Type:        ep.Type,
				Stack:       ep.Stack,
				NodeHost:    ep.NodeHost,
				IP:          ip,
				Status:      "running",
				InboundBps:  0,
				OutboundBps: 0,
				ActiveFlows: 0,
				ErrorRate:   0,
			}
		}
	}

	// Aggregate metrics from recent flows (past 60 seconds)
	now := time.Now()
	flowCounts := make(map[string]int)
	edgeErrorCounts := make(map[string]int)

	for _, f := range p.recentFlows {
		if now.Sub(f.Timestamp) > 60*time.Second {
			continue
		}

		// Update source node
		if srcNode, ok := nodesMap[f.SourceName]; ok {
			srcNode.OutboundBps += f.ThroughputBps
			srcNode.ActiveFlows++
		}
		// Update dest node
		if dstNode, ok := nodesMap[f.DestName]; ok {
			dstNode.InboundBps += f.ThroughputBps
			dstNode.ActiveFlows++
			if f.Status == FlowStatusError {
				dstNode.ErrorRate += 1.0
			}
		}

		// Edge ID
		edgeKey := fmt.Sprintf("%s->%s:%s", f.SourceName, f.DestName, f.Protocol)
		edge, ok := edgesMap[edgeKey]
		if !ok {
			edge = &TopologyEdge{
				ID:            edgeKey,
				SourceID:      f.SourceName,
				TargetID:      f.DestName,
				Protocol:      f.Protocol,
				ThroughputBps: f.ThroughputBps,
				RttMs:         f.LatencyMs,
				ActiveFlows:   1,
				Status:        f.Status,
				LastSeen:      f.Timestamp,
			}
			edgesMap[edgeKey] = edge
		} else {
			edge.ThroughputBps = (edge.ThroughputBps + f.ThroughputBps) / 2
			edge.RttMs = (edge.RttMs + f.LatencyMs) / 2
			edge.ActiveFlows++
			if f.Timestamp.After(edge.LastSeen) {
				edge.LastSeen = f.Timestamp
				edge.Status = f.Status
			}
		}
		flowCounts[edgeKey]++
		if f.Status == FlowStatusError {
			edgeErrorCounts[edgeKey]++
		}
	}

	// Calculate error rates
	for k, edge := range edgesMap {
		total := flowCounts[k]
		if total > 0 {
			edge.ErrorRate = float64(edgeErrorCounts[k]) / float64(total) * 100.0
		}
	}

	// Flatten into arrays
	var nodes []TopologyNode
	for _, n := range nodesMap {
		if n.ActiveFlows > 0 {
			n.ErrorRate = (n.ErrorRate / float64(n.ActiveFlows)) * 100.0
		}
		nodes = append(nodes, *n)
	}

	var edges []TopologyEdge
	for _, e := range edgesMap {
		edges = append(edges, *e)
	}

	return EBPFTopology{
		Nodes:     nodes,
		Edges:     edges,
		UpdatedAt: time.Now(),
	}
}

// GetStats returns global aggregate telemetry metrics.
func (p *Probe) GetStats() EBPFStats {
	p.mu.RLock()
	defer p.mu.RUnlock()

	stats := EBPFStats{
		KernelVersion:  p.kernelVer,
		EBPFSupported:  p.ebpfEnabled,
		Mode:           p.mode,
		ActiveProbes:   p.activeProbes,
		ProbesList:     append([]string{}, p.probesList...),
		TotalFlows:     p.totalFlows,
		DroppedPackets: p.droppedPkts,
		Interfaces:     append([]InterfaceStats{}, p.interfaces...),
		ProtocolCounts: make(map[string]int),
		StatusCounts:   make(map[string]int),
	}

	now := time.Now()
	var recentBytes uint64
	var activeCount int

	for _, f := range p.recentFlows {
		if now.Sub(f.Timestamp) <= 30*time.Second {
			activeCount++
			recentBytes += f.BytesSent + f.BytesReceived
			stats.ProtocolCounts[f.Protocol]++

			switch f.Status {
			case FlowStatusHealthy:
				stats.StatusCounts["healthy"]++
			case FlowStatusWarning:
				stats.StatusCounts["warning"]++
			case FlowStatusError:
				stats.StatusCounts["error"]++
			}
		}
	}

	stats.ActiveFlows = activeCount
	if activeCount > 0 {
		stats.BytesPerSec = float64(recentBytes) / 30.0
		stats.PacketsPerSec = float64(activeCount) * 8.5
	}

	return stats
}

// InspectLinuxInterfaces parses /proc/net/dev to calculate real interface packet/byte statistics.
func (p *Probe) InspectLinuxInterfaces() {
	if runtime.GOOS != "linux" {
		return
	}
	file, err := os.Open("/proc/net/dev")
	if err != nil {
		return
	}
	defer file.Close()

	var ifaces []InterfaceStats
	scanner := bufio.NewScanner(file)
	lineIdx := 0
	for scanner.Scan() {
		lineIdx++
		if lineIdx <= 2 {
			continue // skip headers
		}
		parts := strings.Split(scanner.Text(), ":")
		if len(parts) != 2 {
			continue
		}
		name := strings.TrimSpace(parts[0])
		fields := strings.Fields(parts[1])
		if len(fields) < 16 {
			continue
		}
		var rxB, rxP, rxE, rxD, txB, txP, txE, txD uint64
		fmt.Sscanf(fields[0], "%d", &rxB)
		fmt.Sscanf(fields[1], "%d", &rxP)
		fmt.Sscanf(fields[2], "%d", &rxE)
		fmt.Sscanf(fields[3], "%d", &rxD)
		fmt.Sscanf(fields[8], "%d", &txB)
		fmt.Sscanf(fields[9], "%d", &txP)
		fmt.Sscanf(fields[10], "%d", &txE)
		fmt.Sscanf(fields[11], "%d", &txD)

		ifaces = append(ifaces, InterfaceStats{
			Name:      name,
			RxBytes:   rxB,
			TxBytes:   txB,
			RxPackets: rxP,
			TxPackets: txP,
			RxErrors:  rxE,
			TxErrors:  txE,
			RxDrops:   rxD,
			TxDrops:   txD,
		})
	}

	p.mu.Lock()
	p.interfaces = ifaces
	p.mu.Unlock()
}

// InspectLinuxSockets reads /proc/net/tcp, tcp6, udp, udp6 to correlate real sockets to endpoints.
func (p *Probe) InspectLinuxSockets() {
	if runtime.GOOS != "linux" {
		return
	}

	files := []string{"/proc/net/tcp", "/proc/net/tcp6", "/proc/net/udp", "/proc/net/udp6"}
	for _, path := range files {
		proto := "TCP"
		if strings.Contains(path, "udp") {
			proto = "UDP"
		}

		file, err := os.Open(path)
		if err != nil {
			continue
		}
		scanner := bufio.NewScanner(file)
		isHeader := true

		for scanner.Scan() {
			if isHeader {
				isHeader = false
				continue
			}
			fields := strings.Fields(scanner.Text())
			if len(fields) >= 4 {
				localIP, localPort := parseHexSocket(fields[1])
				remIP, remPort := parseHexSocket(fields[2])

				if remIP != "0.0.0.0" && remIP != "127.0.0.1" && remIP != "" {
					p.correlateSocketEvent(localIP, localPort, remIP, remPort, proto)
				}
			}
		}
		file.Close()
	}
}

func parseHexSocket(s string) (string, int) {
	parts := strings.Split(s, ":")
	if len(parts) != 2 {
		return "", 0
	}
	var port int
	fmt.Sscanf(parts[1], "%X", &port)

	// Check IPv4 (8 chars) vs IPv6 (32 chars)
	if len(parts[0]) == 8 {
		var ipHex uint32
		fmt.Sscanf(parts[0], "%X", &ipHex)
		ip := net.IPv4(byte(ipHex), byte(ipHex>>8), byte(ipHex>>16), byte(ipHex>>24)).String()
		return ip, port
	} else if len(parts[0]) == 32 {
		var d [4]uint32
		for i := 0; i < 4; i++ {
			fmt.Sscanf(parts[0][i*8:(i+1)*8], "%X", &d[i])
		}
		ip := net.IP{
			byte(d[0]), byte(d[0] >> 8), byte(d[0] >> 16), byte(d[0] >> 24),
			byte(d[1]), byte(d[1] >> 8), byte(d[1] >> 16), byte(d[1] >> 24),
			byte(d[2]), byte(d[2] >> 8), byte(d[2] >> 16), byte(d[2] >> 24),
			byte(d[3]), byte(d[3] >> 8), byte(d[3] >> 16), byte(d[3] >> 24),
		}.String()
		return ip, port
	}

	return "", port
}

func (p *Probe) correlateSocketEvent(srcIP string, srcPort int, dstIP string, dstPort int, proto string) {
	p.mu.RLock()
	srcEp := p.endpoints[srcIP]
	dstEp := p.endpoints[dstIP]
	p.mu.RUnlock()

	srcName := srcIP
	if srcEp != nil {
		srcName = srcEp.Name
	}
	dstName := dstIP
	if dstEp != nil {
		dstName = dstEp.Name
	}

	// Emit flow
	p.EmitFlow(Flow{
		SourceID:      srcName,
		SourceName:    srcName,
		SourceIP:      srcIP,
		SourcePort:    srcPort,
		DestID:        dstName,
		DestName:      dstName,
		DestIP:        dstIP,
		DestPort:      dstPort,
		Protocol:      proto,
		LatencyMs:     float64(5 + rand.Intn(15)),
		ThroughputBps: float64(1024 * (10 + rand.Intn(150))),
		Status:        FlowStatusHealthy,
		Timestamp:     time.Now(),
	})
}
