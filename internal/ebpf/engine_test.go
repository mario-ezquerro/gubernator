package ebpf

import (
	"testing"
	"time"
)

func TestEBPFProbeAndTopology(t *testing.T) {
	probe := NewProbe()
	probe.RefreshEndpoints()

	// Emit test flows
	flow1 := Flow{
		SourceID:      "gbnt-caddy",
		SourceName:    "gbnt-caddy",
		SourceIP:      "172.18.0.2",
		DestID:        "gbnt-monitor-grafana",
		DestName:      "gbnt-monitor-grafana",
		DestIP:        "172.18.0.5",
		Protocol:      "HTTP",
		StatusCode:    200,
		LatencyMs:     5.2,
		ThroughputBps: 50000,
		Status:        FlowStatusHealthy,
		Timestamp:     time.Now(),
	}
	probe.EmitFlow(flow1)

	flow2 := Flow{
		SourceID:      "gbnt-caddy",
		SourceName:    "gbnt-caddy",
		SourceIP:      "172.18.0.2",
		DestID:        "gbnt-coredns",
		DestName:      "gbnt-coredns",
		DestIP:        "172.18.0.3",
		Protocol:      "DNS",
		StatusCode:    200,
		LatencyMs:     1.1,
		ThroughputBps: 15000,
		Status:        FlowStatusHealthy,
		Timestamp:     time.Now(),
	}
	probe.EmitFlow(flow2)

	// Verify recent flows
	flows := probe.GetRecentFlows(10, "", "", "")
	if len(flows) < 2 {
		t.Fatalf("expected at least 2 flows, got %d", len(flows))
	}

	// Verify protocol filter
	dnsFlows := probe.GetRecentFlows(10, "DNS", "", "")
	if len(dnsFlows) != 1 {
		t.Fatalf("expected 1 DNS flow, got %d", len(dnsFlows))
	}
	if dnsFlows[0].Protocol != "DNS" {
		t.Fatalf("expected DNS protocol, got %s", dnsFlows[0].Protocol)
	}

	// Verify topology synthesis
	topo := probe.BuildTopology()
	if len(topo.Nodes) == 0 {
		t.Fatalf("expected topology nodes, got 0")
	}
	if len(topo.Edges) < 2 {
		t.Fatalf("expected at least 2 edges, got %d", len(topo.Edges))
	}

	// Verify stats
	stats := probe.GetStats()
	if stats.ActiveFlows < 2 {
		t.Fatalf("expected active flows >= 2, got %d", stats.ActiveFlows)
	}
}

func TestEBPFSimulation(t *testing.T) {
	eng := GetEngine()
	if eng == nil {
		t.Fatalf("expected non-nil engine")
	}

	// Run brief simulation
	eng.SimulateTraffic(SimulationProfile{
		Pattern:   "burst",
		Rate:      10,
		DurationS: 1,
		ErrorPct:  10,
	})

	time.Sleep(200 * time.Millisecond)
	flows := eng.Probe.GetRecentFlows(5, "", "", "")
	if len(flows) == 0 {
		t.Fatalf("expected captured flows after simulation")
	}
}
