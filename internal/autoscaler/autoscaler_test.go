package autoscaler

import (
	"testing"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/db"
)

func TestParseAutoscalePolicy_Defaults(t *testing.T) {
	policy := ParseAutoscalePolicy([]string{})
	if policy.Enabled {
		t.Errorf("expected Enabled=false by default, got true")
	}
	if policy.Scope != "host" {
		t.Errorf("expected Scope='host', got %s", policy.Scope)
	}
	if policy.Metric != "cpu" {
		t.Errorf("expected Metric='cpu', got %s", policy.Metric)
	}
	if policy.Target != 80.0 {
		t.Errorf("expected Target=80.0, got %f", policy.Target)
	}
	if policy.Min != 1 || policy.Max != 5 {
		t.Errorf("expected Min=1, Max=5; got Min=%d, Max=%d", policy.Min, policy.Max)
	}
}

func TestParseAutoscalePolicy_GPUCluster(t *testing.T) {
	constraints := []string{
		"gbnt.autoscaling.enable=true",
		"gbnt.autoscaling.scope=cluster",
		"gbnt.autoscaling.metric=gpu",
		"gbnt.autoscaling.target=75",
		"gbnt.autoscaling.min=2",
		"gbnt.autoscaling.max=8",
		"gbnt.autoscaling.cooldown=30s",
	}

	policy := ParseAutoscalePolicy(constraints)
	if !policy.Enabled {
		t.Errorf("expected Enabled=true, got false")
	}
	if policy.Scope != "cluster" {
		t.Errorf("expected Scope='cluster', got %s", policy.Scope)
	}
	if policy.Metric != "gpu" {
		t.Errorf("expected Metric='gpu', got %s", policy.Metric)
	}
	if policy.Target != 75.0 {
		t.Errorf("expected Target=75.0, got %f", policy.Target)
	}
	if policy.Min != 2 || policy.Max != 8 {
		t.Errorf("expected Min=2, Max=8; got Min=%d, Max=%d", policy.Min, policy.Max)
	}
	if policy.Cooldown != 30*time.Second {
		t.Errorf("expected Cooldown=30s, got %v", policy.Cooldown)
	}
}

func TestParseAutoscalePolicy_SingleHostAffinityOverride(t *testing.T) {
	// Even if scope=cluster is requested, single-host placement strategy must force host scope
	constraints := []string{
		"gbnt.autoscaling.enable=true",
		"gbnt.autoscaling.scope=cluster",
		"gbnt.placement.strategy=single-host",
	}

	policy := ParseAutoscalePolicy(constraints)
	if !policy.Enabled {
		t.Errorf("expected Enabled=true")
	}
	if policy.Scope != "host" {
		t.Errorf("expected Scope='host' due to single-host placement strategy, got %s", policy.Scope)
	}
	if !policy.SingleHostOnly {
		t.Errorf("expected SingleHostOnly=true")
	}
}

func TestParseAutoscalePolicy_PinnedHostAffinityOverride(t *testing.T) {
	// Pinned node constraint must force single host scope
	constraints := []string{
		"gbnt.autoscaling.enable=true",
		"gbnt.autoscaling.scope=cluster",
		"node.hostname == gbnt-worker1",
	}

	policy := ParseAutoscalePolicy(constraints)
	if policy.Scope != "host" {
		t.Errorf("expected Scope='host' due to pinned node hostname, got %s", policy.Scope)
	}
	if policy.PinnedHost != "gbnt-worker1" {
		t.Errorf("expected PinnedHost='gbnt-worker1', got %s", policy.PinnedHost)
	}
	if !policy.SingleHostOnly {
		t.Errorf("expected SingleHostOnly=true")
	}
}

func TestParseAutoscalePolicy_SpreadStrategyDefaultCluster(t *testing.T) {
	// If placement strategy is spread or multi-host and scope is omitted, it defaults to cluster
	constraints := []string{
		"gbnt.autoscaling.enable=true",
		"gbnt.placement.strategy=spread",
		"gbnt.autoscaling.metric=gpu",
	}

	policy := ParseAutoscalePolicy(constraints)
	if policy.Scope != "cluster" {
		t.Errorf("expected Scope='cluster' due to spread placement strategy, got %s", policy.Scope)
	}
}

func TestCanScale_Cooldown(t *testing.T) {
	svcID := "test-service-cooldown"
	cooldown := 100 * time.Millisecond

	if !CanScale(svcID, cooldown) {
		t.Errorf("expected CanScale=true initially")
	}

	RecordScaleEvent(ScaleEventInfo{
		ServiceID: svcID,
		Timestamp: time.Now(),
	})

	if CanScale(svcID, cooldown) {
		t.Errorf("expected CanScale=false immediately after scaling")
	}

	time.Sleep(150 * time.Millisecond)

	if !CanScale(svcID, cooldown) {
		t.Errorf("expected CanScale=true after cooldown elapsed")
	}
}

func TestMatchesConstraints(t *testing.T) {
	node := db.Node{
		ID:   "node-1",
		Role: "worker",
		Labels: map[string]string{
			"gbnt.node.hostname": "worker-alpha",
			"gbnt.node.gpu":      "nvidia",
			"zone":               "eu-west-1",
		},
	}

	// Valid matching constraints
	cPass := []string{
		"node.role == worker",
		"node.hostname == worker-alpha",
		"gbnt.node.gpu == nvidia",
	}
	if !matchesConstraints(node, cPass) {
		t.Errorf("expected node to match all valid constraints")
	}

	// Failing constraint: wrong role
	cFailRole := []string{
		"node.role == manager",
	}
	if matchesConstraints(node, cFailRole) {
		t.Errorf("expected node to fail constraint for wrong role")
	}

	// Failing constraint: wrong hostname
	cFailHost := []string{
		"node.hostname == worker-beta",
	}
	if matchesConstraints(node, cFailHost) {
		t.Errorf("expected node to fail constraint for wrong hostname")
	}
}
