package web

import (
	"testing"
)

func TestApplyAutoscaleToConstraints(t *testing.T) {
	// 1. Enabling autoscale with custom values
	existing := []string{"node.role==worker", "gbnt.autoscaling.enable=false"}
	req := autoscaleConfigRequest{
		Enabled:  true,
		Metric:   "gpu",
		Scope:    "cluster",
		Target:   75.0,
		Min:      2,
		Max:      8,
		Cooldown: "45s",
	}

	res := applyAutoscaleToConstraints(existing, req)
	expectedContains := []string{
		"node.role==worker",
		"gbnt.autoscaling.enable=true",
		"gbnt.autoscaling.metric=gpu",
		"gbnt.autoscaling.scope=cluster",
		"gbnt.autoscaling.target=75",
		"gbnt.autoscaling.min=2",
		"gbnt.autoscaling.max=8",
		"gbnt.autoscaling.cooldown=45s",
	}

	if len(res) != len(expectedContains) {
		t.Fatalf("expected %d constraints, got %d: %v", len(expectedContains), len(res), res)
	}

	for _, exp := range expectedContains {
		found := false
		for _, r := range res {
			if r == exp {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("expected constraint %q not found in %v", exp, res)
		}
	}

	// 2. Disabling autoscale cleans up previous keys and appends enable=false
	disableReq := autoscaleConfigRequest{Enabled: false}
	resDisabled := applyAutoscaleToConstraints(res, disableReq)
	if len(resDisabled) != 2 {
		t.Fatalf("expected 2 constraints after disable, got %d: %v", len(resDisabled), resDisabled)
	}
	if resDisabled[0] != "node.role==worker" || resDisabled[1] != "gbnt.autoscaling.enable=false" {
		t.Errorf("unexpected disabled constraints: %v", resDisabled)
	}
}
