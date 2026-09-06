package docker

import (
	"testing"

	"github.com/mario-ezquerro/gubernator/internal/db"
)

func TestBuiltinDaemonPresets(t *testing.T) {
	presets := BuiltinDaemonPresets()
	if len(presets) < 4 {
		t.Fatalf("expected at least 4 presets, got %d", len(presets))
	}

	prod, ok := presets["production"]
	if !ok {
		t.Fatal("missing 'production' preset")
	}
	if prod["log-driver"] != "json-file" {
		t.Errorf("expected log-driver 'json-file', got %v", prod["log-driver"])
	}
	if prod["live-restore"] != true {
		t.Errorf("expected live-restore true, got %v", prod["live-restore"])
	}

	gpu, ok := presets["gpu"]
	if !ok {
		t.Fatal("missing 'gpu' preset")
	}
	if gpu["default-runtime"] != "nvidia" {
		t.Errorf("expected default-runtime 'nvidia', got %v", gpu["default-runtime"])
	}

	sre, ok := presets["sre"]
	if !ok {
		t.Fatal("missing 'sre' preset")
	}
	if sre["metrics-addr"] != "0.0.0.0:9323" {
		t.Errorf("expected metrics-addr '0.0.0.0:9323', got %v", sre["metrics-addr"])
	}
}

func TestValidateDaemonJSON(t *testing.T) {
	// Valid JSON
	validJSON := `{
		"log-driver": "json-file",
		"log-opts": {"max-size": "20m", "max-file": "3"},
		"live-restore": true
	}`
	parsed, err := ValidateDaemonJSON(validJSON)
	if err != nil {
		t.Fatalf("unexpected error on valid JSON: %v", err)
	}
	if parsed["log-driver"] != "json-file" {
		t.Errorf("expected log-driver json-file, got %v", parsed["log-driver"])
	}

	// Invalid JSON syntax
	invalidJSON := `{"log-driver": "json-file",`
	_, err = ValidateDaemonJSON(invalidJSON)
	if err == nil {
		t.Fatal("expected error on invalid JSON, got nil")
	}

	// Invalid relative data-root
	badDataRoot := `{"data-root": "relative/path"}`
	_, err = ValidateDaemonJSON(badDataRoot)
	if err == nil {
		t.Fatal("expected error on relative data-root, got nil")
	}
}

func TestNodeHasGPU(t *testing.T) {
	nodeWithoutGPU := db.Node{
		ID:     "worker-1",
		Labels: map[string]string{"gbnt.node.role": "worker"},
	}
	if NodeHasGPU(nodeWithoutGPU) {
		t.Errorf("expected false for node without GPU labels")
	}

	nodeWithNvidiaLabel := db.Node{
		ID:     "worker-gpu",
		Labels: map[string]string{"gbnt.node.gpu": "nvidia"},
	}
	if !NodeHasGPU(nodeWithNvidiaLabel) {
		t.Errorf("expected true for node with gbnt.node.gpu=nvidia")
	}

	nodeWithGenericGPU := db.Node{
		ID:     "worker-ai",
		Labels: map[string]string{"gpu": "true"},
	}
	if !NodeHasGPU(nodeWithGenericGPU) {
		t.Errorf("expected true for node with gpu=true")
	}
}
