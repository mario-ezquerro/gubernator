package examples

import (
	"os"
	"path/filepath"
	"testing"
	"gopkg.in/yaml.v3"
)

func TestGetAllPOCExamples(t *testing.T) {
	exs := GetAllPOCExamples()
	if len(exs) == 0 {
		t.Fatalf("expected at least 1 POC example, got 0")
	}

	foundMap := make(map[string]bool)
	for _, ex := range exs {
		foundMap[ex.ID] = true
		if ex.Name == "" {
			t.Errorf("example '%s' has empty Name", ex.ID)
		}
		if ex.Description == "" {
			t.Errorf("example '%s' has empty Description", ex.ID)
		}
		if ex.ComposeRaw == "" {
			t.Errorf("example '%s' has empty ComposeRaw", ex.ID)
		}

		// Ensure ComposeRaw is valid YAML
		var parsed map[string]interface{}
		if err := yaml.Unmarshal([]byte(ex.ComposeRaw), &parsed); err != nil {
			t.Errorf("example '%s' has invalid YAML: %v", ex.ID, err)
		}
	}

	expectedIDs := []string{
		"hello-loadbalancer",
		"wordpress-mysql",
		"public-https",
		"sloth-slo",
		"n8n-workflow",
		"jaeger-tracing",
		"jupyter-datascience",
		"sre-observability",
	}

	for _, id := range expectedIDs {
		if !foundMap[id] {
			t.Errorf("expected POC example with id '%s' not found", id)
		}
	}
}

func TestExportExamplesToDisk(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "gbnt-examples-test-*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	if err := ExportExamplesToDisk(tempDir); err != nil {
		t.Fatalf("ExportExamplesToDisk failed: %v", err)
	}

	// Verify README.md exists
	readmePath := filepath.Join(tempDir, "README.md")
	if _, err := os.Stat(readmePath); os.IsNotExist(err) {
		t.Errorf("expected README.md in exported directory")
	}

	// Verify at least one yaml exists
	files, err := ListServerStackFiles(tempDir)
	if err != nil {
		t.Fatalf("ListServerStackFiles failed: %v", err)
	}
	if len(files) == 0 {
		t.Errorf("expected exported yaml files in temp dir, got 0")
	}
}

func TestReadServerStackFile(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "gbnt-server-test-*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	yamlContent := `services:
  testapp:
    image: alpine:latest
    command: echo hello
    deploy:
      replicas: 1
      placement:
        constraints:
          - stack.name == test-stack
`
	filePath := filepath.Join(tempDir, "test.yml")
	if err := os.WriteFile(filePath, []byte(yamlContent), 0644); err != nil {
		t.Fatalf("failed to write test file: %v", err)
	}

	res, err := ReadServerStackFile(filePath)
	if err != nil {
		t.Fatalf("ReadServerStackFile failed: %v", err)
	}

	if res.InferredName != "test-stack" {
		t.Errorf("expected inferred name 'test-stack', got '%s'", res.InferredName)
	}
	if len(res.Services) != 1 || res.Services[0] != "testapp" {
		t.Errorf("expected service 'testapp', got %v", res.Services)
	}
}
