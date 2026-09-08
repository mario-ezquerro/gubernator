package ebpf

import (
	"time"
)

// FlowStatus defines the health/status state of a network flow.
type FlowStatus string

const (
	FlowStatusHealthy FlowStatus = "healthy" // 2xx HTTP, TCP established, no drops
	FlowStatusWarning FlowStatus = "warning" // 4xx HTTP, high RTT (>200ms)
	FlowStatusError   FlowStatus = "error"   // 5xx HTTP, TCP drops, resets
)

// Flow represents a single L4/L7 network connection or request event between two endpoints.
type Flow struct {
	ID            string     `json:"id"`
	SourceID      string     `json:"source_id"`
	SourceName    string     `json:"source_name"`
	SourceIP      string     `json:"source_ip"`
	SourcePort    int        `json:"source_port"`
	DestID        string     `json:"dest_id"`
	DestName      string     `json:"dest_name"`
	DestIP        string     `json:"dest_ip"`
	DestPort      int        `json:"dest_port"`
	Protocol      string     `json:"protocol"` // "HTTP", "gRPC", "DNS", "TCP", "UDP", "REDIS", "POSTGRES"
	Method        string     `json:"method,omitempty"`
	Path          string     `json:"path,omitempty"`
	StatusCode    int        `json:"status_code,omitempty"`
	LatencyMs     float64    `json:"latency_ms"`
	BytesSent     uint64     `json:"bytes_sent"`
	BytesReceived uint64     `json:"bytes_received"`
	ThroughputBps float64    `json:"throughput_bps"`
	Retransmits   int        `json:"retransmits"`
	Drops         int        `json:"drops"`
	Status        FlowStatus `json:"status"`
	Timestamp     time.Time  `json:"timestamp"`
}

// TopologyNode represents a service, container, or external entity in the topology graph.
type TopologyNode struct {
	ID          string  `json:"id"`
	Name        string  `json:"name"`
	Type        string  `json:"type"` // "container", "ingress", "database", "dns", "external", "host"
	Stack       string  `json:"stack"`
	NodeHost    string  `json:"node_host"`
	IP          string  `json:"ip"`
	Status      string  `json:"status"` // "running", "unhealthy", "stopped"
	InboundBps  float64 `json:"inbound_bps"`
	OutboundBps float64 `json:"outbound_bps"`
	ActiveFlows int     `json:"active_flows"`
	ErrorRate   float64 `json:"error_rate"`
	CpuPercent  float64 `json:"cpu_percent,omitempty"`
	MemPercent  float64 `json:"mem_percent,omitempty"`
}

// TopologyEdge represents a directional or aggregate communication link between two nodes.
type TopologyEdge struct {
	ID            string     `json:"id"`
	SourceID      string     `json:"source_id"`
	TargetID      string     `json:"target_id"`
	Protocol      string     `json:"protocol"`
	ThroughputBps float64    `json:"throughput_bps"`
	RttMs         float64    `json:"rtt_ms"`
	ActiveFlows   int        `json:"active_flows"`
	ErrorRate     float64    `json:"error_rate"`
	Status        FlowStatus `json:"status"`
	LastSeen      time.Time  `json:"last_seen"`
}

// EBPFTopology holds the complete live graph structure.
type EBPFTopology struct {
	Nodes     []TopologyNode `json:"nodes"`
	Edges     []TopologyEdge `json:"edges"`
	UpdatedAt time.Time      `json:"updated_at"`
}

// InterfaceStats contains network device counters.
type InterfaceStats struct {
	Name      string `json:"name"`
	RxBytes   uint64 `json:"rx_bytes"`
	TxBytes   uint64 `json:"tx_bytes"`
	RxPackets uint64 `json:"rx_packets"`
	TxPackets uint64 `json:"tx_packets"`
	RxErrors  uint64 `json:"rx_errors"`
	TxErrors  uint64 `json:"tx_errors"`
	RxDrops   uint64 `json:"rx_drops"`
	TxDrops   uint64 `json:"tx_drops"`
}

// EBPFStats contains global aggregate telemetry counters.
type EBPFStats struct {
	KernelVersion  string           `json:"kernel_version"`
	EBPFSupported  bool             `json:"ebpf_supported"`
	Mode           string           `json:"mode"` // "kernel" or "emulation"
	ActiveProbes   int              `json:"active_probes"`
	ProbesList     []string         `json:"probes_list"`
	TotalFlows     int64            `json:"total_flows"`
	ActiveFlows    int              `json:"active_flows"`
	PacketsPerSec  float64          `json:"packets_per_sec"`
	BytesPerSec    float64          `json:"bytes_per_sec"`
	DroppedPackets int64            `json:"dropped_packets"`
	Interfaces     []InterfaceStats `json:"interfaces,omitempty"`
	ProtocolCounts map[string]int   `json:"protocol_counts"`
	StatusCounts   map[string]int   `json:"status_counts"` // "2xx", "4xx", "5xx", "tcp_ok", "tcp_err"
}

// SimulationProfile defines the traffic pattern to inject during on-demand testing.
type SimulationProfile struct {
	Pattern   string  `json:"pattern"`   // "normal", "burst", "errors", "mixed"
	Rate      int     `json:"rate"`      // events per second
	DurationS int     `json:"duration_s"` // duration in seconds
	ErrorPct  float64 `json:"error_pct"` // percentage of error flows (0-100)
}
