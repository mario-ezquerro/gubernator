package aqueducts

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/glebarez/sqlite"
	"github.com/mario-ezquerro/gubernator/internal/coredns"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"gorm.io/gorm"
)

func TestSanitizeDNSLabel(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"CORE-GBNT", "core-gbnt"},
		{"CORE-GBNT (worker-1)", "core-gbnt-worker-1"},
		{"[SRE] Monitor (Manager)", "sre-monitor-manager"},
		{"node-local-manager", "node-local-manager"},
		{"gbnt_worker_1", "gbnt-worker-1"},
		{"  service.name/123:foo  ", "service-name-123-foo"},
		{"---hello---world---", "hello-world"},
		{"NormalName123", "normalname123"},
	}

	for _, tc := range tests {
		got := SanitizeDNSLabel(tc.input)
		if got != tc.expected {
			t.Errorf("SanitizeDNSLabel(%q) = %q; want %q", tc.input, got, tc.expected)
		}
	}
}

func TestIsSystemStack(t *testing.T) {
	if !isSystemStack("core-gbnt-stack", "CORE-GBNT") {
		t.Errorf("expected core-gbnt-stack to be recognized as system stack")
	}
	if !isSystemStack("core-stack-node-1", "CORE-GBNT (node-1)") {
		t.Errorf("expected worker core-stack to be recognized as system stack")
	}
	if !isSystemStack("sre-monitor-stack", "[SRE] Monitor (Manager)") {
		t.Errorf("expected sre-monitor-stack to be recognized as system stack")
	}
	if isSystemStack("wp-stack", "wordpress") {
		t.Errorf("expected wordpress stack to NOT be recognized as system stack")
	}
}

func TestGenerateHostsFile_MultiNode_CleanMinimal(t *testing.T) {
	testDB, err := gorm.Open(sqlite.Open("file::memory:?cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to connect database: %v", err)
	}
	db.DB = testDB

	_ = testDB.AutoMigrate(&db.Node{}, &db.Stack{}, &db.Service{}, &db.Task{}, &db.CustomDNSRecord{})

	tmpDir, err := os.MkdirTemp("", "gbnt-dns-test-*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	origHome := os.Getenv("HOME")
	os.Setenv("HOME", tmpDir)
	defer os.Setenv("HOME", origHome)

	_ = os.MkdirAll(coredns.CoreDNSDir(), 0755)

	now := time.Now()

	// 1. Manager Node
	testDB.Create(&db.Node{
		ID:     "node-local-manager",
		IP:     "192.168.1.100",
		Role:   "manager",
		Status: "active",
	})

	// 2. Worker Node
	testDB.Create(&db.Node{
		ID:     "node-gbnt-worker1",
		IP:     "192.168.1.101",
		Role:   "worker",
		Status: "active",
	})

	// 3. Stacks
	testDB.Create(&db.Stack{
		ID:        "core-gbnt-stack",
		Name:      "CORE-GBNT",
		CreatedAt: now,
		UpdatedAt: now,
	})
	testDB.Create(&db.Stack{
		ID:        "core-stack-node-gbnt-worker1",
		Name:      "CORE-GBNT (node-gbnt-worker1)",
		CreatedAt: now,
		UpdatedAt: now,
	})
	testDB.Create(&db.Stack{
		ID:        "sre-monitor-stack",
		Name:      "[SRE] Monitor (Manager)",
		CreatedAt: now,
		UpdatedAt: now,
	})
	testDB.Create(&db.Stack{
		ID:        "wp-stack",
		Name:      "wordpress",
		CreatedAt: now,
		UpdatedAt: now,
	})

	// 4. Services
	testDB.Create(&db.Service{ID: "core-svc-caddy", StackID: "core-gbnt-stack", Name: "caddy"})
	testDB.Create(&db.Service{ID: "core-svc-worker-caddy", StackID: "core-stack-node-gbnt-worker1", Name: "caddy"})
	testDB.Create(&db.Service{ID: "sre-svc-loki", StackID: "sre-monitor-stack", Name: "loki"})
	testDB.Create(&db.Service{ID: "svc-wp-app", StackID: "wp-stack", Name: "app"})

	// 5. Tasks
	testDB.Create(&db.Task{
		ID:          "core-task-caddy",
		ServiceID:   "core-svc-caddy",
		NodeID:      "node-local-manager",
		Status:      "running",
		ContainerIP: "172.18.0.2",
	})
	testDB.Create(&db.Task{
		ID:          "core-task-worker-caddy",
		ServiceID:   "core-svc-worker-caddy",
		NodeID:      "node-gbnt-worker1",
		Status:      "running",
		ContainerIP: "172.18.0.3",
	})
	testDB.Create(&db.Task{
		ID:          "sre-task-loki",
		ServiceID:   "sre-svc-loki",
		NodeID:      "node-local-manager",
		Status:      "running",
		ContainerIP: "172.18.0.4",
	})
	testDB.Create(&db.Task{
		ID:          "task-wp-1",
		ServiceID:   "svc-wp-app",
		NodeID:      "node-gbnt-worker1",
		Status:      "running",
		ContainerIP: "172.18.0.5",
	})

	// Run GenerateHostsFile
	GenerateHostsFile()

	hostsFile := filepath.Join(coredns.CoreDNSDir(), "gubernator.hosts")
	contentBytes, err := os.ReadFile(hostsFile)
	if err != nil {
		t.Fatalf("failed to read generated hosts file: %v", err)
	}

	content := string(contentBytes)
	lines := strings.Split(content, "\n")

	t.Logf("Generated gubernator.hosts:\n%s", content)

	// Verify manager caddy entries
	if !strings.Contains(content, "172.18.0.2\tmanager.caddy.gbnt.local") || !strings.Contains(content, "172.18.0.2\tmanager.caddy.gbnt") {
		t.Errorf("missing manager caddy entry")
	}

	// Verify worker caddy entries
	if !strings.Contains(content, "192.168.1.101\tnode-gbnt-worker1.caddy.gbnt.local") || !strings.Contains(content, "192.168.1.101\tnode-gbnt-worker1.caddy.gbnt") {
		t.Errorf("missing node-gbnt-worker1 caddy entry")
	}

	// Verify manager loki entries
	if !strings.Contains(content, "172.18.0.4\tmanager.loki.gbnt.local") || !strings.Contains(content, "172.18.0.4\tmanager.loki.gbnt") {
		t.Errorf("missing manager loki entry")
	}

	// Verify user app stack-scoped entries
	if !strings.Contains(content, "192.168.1.101\tapp.wordpress.gbnt.local") || !strings.Contains(content, "192.168.1.101\tapp.wordpress.gbnt") {
		t.Errorf("missing user stack-scoped domain app.wordpress.gbnt.local")
	}

	// CRITICAL TEST: Verify that generic "caddy.gbnt.local" or "loki.gbnt.local" are NOT present to prevent collisions
	for _, l := range lines {
		fields := strings.Fields(l)
		if len(fields) >= 2 {
			domain := fields[1]
			if domain == "caddy.gbnt.local" || domain == "caddy.gbnt" {
				t.Errorf("forbidden generic entry found: %q (causes duplicate IP conflicts across nodes)", domain)
			}
			if domain == "loki.gbnt.local" || domain == "loki.gbnt" {
				t.Errorf("forbidden generic entry found: %q", domain)
			}
			if strings.ContainsAny(domain, " ()[]_") {
				t.Errorf("invalid character in domain %q", domain)
			}
		}
	}
}
