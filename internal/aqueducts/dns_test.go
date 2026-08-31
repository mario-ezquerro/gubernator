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

func TestGetNodeSlugs(t *testing.T) {
	// Manager
	mgrSlugs := GetNodeSlugs("node-local-manager", nil)
	if !contains(mgrSlugs, "manager") || !contains(mgrSlugs, "node-local-manager") {
		t.Errorf("GetNodeSlugs(node-local-manager) = %v; expected manager and node-local-manager", mgrSlugs)
	}

	// Worker with prefix
	workerSlugs := GetNodeSlugs("gbnt-worker-1", map[string]string{
		"hostname": "prod-node-01",
	})
	if !contains(workerSlugs, "gbnt-worker-1") || !contains(workerSlugs, "worker-1") || !contains(workerSlugs, "prod-node-01") {
		t.Errorf("GetNodeSlugs(gbnt-worker-1) = %v; expected gbnt-worker-1, worker-1, prod-node-01", workerSlugs)
	}

	// Worker node- prefix
	nodeWorkerSlugs := GetNodeSlugs("node-worker-2", nil)
	if !contains(nodeWorkerSlugs, "node-worker-2") || !contains(nodeWorkerSlugs, "worker-2") {
		t.Errorf("GetNodeSlugs(node-worker-2) = %v; expected node-worker-2 and worker-2", nodeWorkerSlugs)
	}
}

func TestGetStackSlugs(t *testing.T) {
	coreWorkerSlugs := GetStackSlugs("CORE-GBNT (worker-1)")
	if !contains(coreWorkerSlugs, "core-gbnt-worker-1") || !contains(coreWorkerSlugs, "core-gbnt") {
		t.Errorf("GetStackSlugs(CORE-GBNT (worker-1)) = %v; expected core-gbnt-worker-1 and core-gbnt", coreWorkerSlugs)
	}

	wpSlugs := GetStackSlugs("wordpress-prod")
	if !contains(wpSlugs, "wordpress-prod") {
		t.Errorf("GetStackSlugs(wordpress-prod) = %v; expected wordpress-prod", wpSlugs)
	}
}

func TestGenerateHostsFile_MultiNode(t *testing.T) {
	// Setup in-memory sqlite DB
	testDB, err := gorm.Open(sqlite.Open("file::memory:?cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to connect database: %v", err)
	}
	db.DB = testDB

	_ = testDB.AutoMigrate(&db.Node{}, &db.Stack{}, &db.Service{}, &db.Task{}, &db.CustomDNSRecord{})

	// Temporary directory for CoreDNS config
	tmpDir, err := os.MkdirTemp("", "gbnt-dns-test-*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	// Set HOME so CoreDNSDir uses our temp dir
	origHome := os.Getenv("HOME")
	os.Setenv("HOME", tmpDir)
	defer os.Setenv("HOME", origHome)

	_ = os.MkdirAll(coredns.CoreDNSDir(), 0755)

	now := time.Now()

	// Insert Manager Node
	testDB.Create(&db.Node{
		ID:     "node-local-manager",
		IP:     "192.168.1.100",
		Role:   "manager",
		Status: "active",
	})

	// Insert Worker Node
	testDB.Create(&db.Node{
		ID:     "gbnt-worker-1",
		IP:     "192.168.1.101",
		Role:   "worker",
		Status: "active",
	})

	// Insert Stacks
	testDB.Create(&db.Stack{
		ID:        "core-gbnt-stack",
		Name:      "CORE-GBNT",
		CreatedAt: now,
		UpdatedAt: now,
	})
	testDB.Create(&db.Stack{
		ID:        "core-stack-gbnt-worker-1",
		Name:      "CORE-GBNT (gbnt-worker-1)",
		CreatedAt: now,
		UpdatedAt: now,
	})
	testDB.Create(&db.Stack{
		ID:        "wp-stack",
		Name:      "wordpress",
		CreatedAt: now,
		UpdatedAt: now,
	})

	// Insert Services
	testDB.Create(&db.Service{
		ID:      "core-svc-caddy",
		StackID: "core-gbnt-stack",
		Name:    "caddy",
	})
	testDB.Create(&db.Service{
		ID:      "core-svc-gbnt-worker-1-caddy",
		StackID: "core-stack-gbnt-worker-1",
		Name:    "caddy",
	})
	testDB.Create(&db.Service{
		ID:      "svc-wp-app",
		StackID: "wp-stack",
		Name:    "app",
	})

	// Insert Tasks
	testDB.Create(&db.Task{
		ID:          "core-task-caddy",
		ServiceID:   "core-svc-caddy",
		NodeID:      "node-local-manager",
		Status:      "running",
		ContainerIP: "172.18.0.2",
	})
	testDB.Create(&db.Task{
		ID:          "core-task-gbnt-worker-1-caddy",
		ServiceID:   "core-svc-gbnt-worker-1-caddy",
		NodeID:      "gbnt-worker-1",
		Status:      "running",
		ContainerIP: "172.18.0.3",
	})
	testDB.Create(&db.Task{
		ID:          "task-wp-1",
		ServiceID:   "svc-wp-app",
		NodeID:      "gbnt-worker-1",
		Status:      "running",
		ContainerIP: "172.18.0.4",
	})

	// Insert Custom DNS record
	testDB.Create(&db.CustomDNSRecord{
		ID:         "cust-1",
		Domain:     "custom-db.gbnt",
		IP:         "10.0.0.50",
		RecordType: "A",
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

	// Validate node-specific caddy records
	expectedSubstrings := []string{
		"172.18.0.2\tmanager.caddy.gbnt",
		"172.18.0.2\tmanager.caddy.gbnt.local",
		"192.168.1.101\tworker-1.caddy.gbnt",
		"192.168.1.101\tworker-1.caddy.gbnt.local",
		"192.168.1.101\tgbnt-worker-1.caddy.gbnt",
		"192.168.1.101\tworker-1.app.gbnt",
		"192.168.1.101\tworker-1.app.wordpress.gbnt",
		"10.0.0.50\tcustom-db.gbnt",
	}

	for _, exp := range expectedSubstrings {
		if !strings.Contains(content, exp) {
			t.Errorf("hosts file missing expected entry %q\nFull Content:\n%s", exp, content)
		}
	}

	// Verify no illegal characters exist in any domain name
	for _, l := range lines {
		l = strings.TrimSpace(l)
		if l == "" || strings.HasPrefix(l, "#") {
			continue
		}
		fields := strings.Fields(l)
		if len(fields) < 2 {
			continue
		}
		domain := fields[1]
		if strings.ContainsAny(domain, " ()[]_") {
			t.Errorf("invalid character found in domain: %q in line %q", domain, l)
		}
	}
}

func contains(slice []string, val string) bool {
	for _, s := range slice {
		if s == val {
			return true
		}
	}
	return false
}
