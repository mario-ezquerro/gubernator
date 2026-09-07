package aqueducts

import (
	"fmt"
	"os"
	"strings"
	"sync"
	"testing"

	"github.com/mario-ezquerro/gubernator/internal/caddy"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

var caddyTestMutex sync.Mutex

func TestGenerateCaddyfile_MultiUpstreamLoadBalancing(t *testing.T) {
	caddyTestMutex.Lock()
	defer caddyTestMutex.Unlock()

	dsn := fmt.Sprintf("file:%s?mode=memory&cache=private", t.Name())
	if err := db.Init(dsn); err != nil {
		t.Fatalf("db.Init failed: %v", err)
	}

	caddyDir := caddy.CaddyDir()
	if err := os.MkdirAll(caddyDir, 0755); err != nil {
		t.Fatalf("failed to create caddy directory: %v", err)
	}

	// Clean tables
	db.DB.Where("1 = 1").Delete(&db.Node{})
	db.DB.Where("1 = 1").Delete(&db.Task{})
	db.DB.Where("1 = 1").Delete(&db.Service{})
	db.DB.Where("1 = 1").Delete(&db.Stack{})

	// Seed nodes: 2 workers
	w1 := db.Node{ID: "worker-1", IP: "192.168.252.101", Role: "worker", Status: "active"}
	w2 := db.Node{ID: "worker-2", IP: "192.168.252.102", Role: "worker", Status: "active"}
	db.DB.Create(&w1)
	db.DB.Create(&w2)

	// Seed service with Caddy load balancing and health check
	svc := db.Service{
		ID:              "svc-multi-web",
		StackID:         "stack-lb",
		Name:            "web",
		Image:           "nginx:alpine",
		DesiredReplicas: 2,
		Ports:           []string{"8080:80"},
		Constraints: []string{
			"ingress.host=lb-app.gbnt.local",
			"gbnt.caddy.lb=least_conn",
			"gbnt.caddy.health_uri=/healthz",
			"gbnt.caddy.health_interval=3s",
			"gbnt.caddy.health_timeout=1s",
		},
	}
	db.DB.Create(&svc)

	// Seed 2 running tasks across the 2 workers
	t1 := db.Task{
		ID:        "task-w1",
		ServiceID: svc.ID,
		NodeID:    w1.ID,
		Status:    "running",
	}
	t2 := db.Task{
		ID:        "task-w2",
		ServiceID: svc.ID,
		NodeID:    w2.ID,
		Status:    "running",
	}
	db.DB.Create(&t1)
	db.DB.Create(&t2)

	// Generate Caddyfile
	GenerateCaddyfile()

	caddyfilePath := caddy.CaddyfilePath()
	contentBytes, err := os.ReadFile(caddyfilePath)
	if err != nil {
		t.Fatalf("failed to read generated Caddyfile: %v", err)
	}
	content := string(contentBytes)

	t.Logf("Generated Caddyfile:\n%s", content)

	// Verify host header
	if !strings.Contains(content, "lb-app.gbnt.local") {
		t.Errorf("Caddyfile missing host lb-app.gbnt.local")
	}

	// Verify both upstreams are present on the reverse_proxy line
	if !strings.Contains(content, "192.168.252.101:8080") {
		t.Errorf("Caddyfile missing upstream worker 1 (192.168.252.101:8080)")
	}
	if !strings.Contains(content, "192.168.252.102:8080") {
		t.Errorf("Caddyfile missing upstream worker 2 (192.168.252.102:8080)")
	}

	// Verify lb_policy least_conn
	if !strings.Contains(content, "lb_policy least_conn") {
		t.Errorf("Caddyfile missing lb_policy least_conn directive")
	}

	// Verify active healthcheck directives
	if !strings.Contains(content, "health_uri /healthz") {
		t.Errorf("Caddyfile missing health_uri /healthz")
	}
	if !strings.Contains(content, "health_interval 3s") {
		t.Errorf("Caddyfile missing health_interval 3s")
	}
	if !strings.Contains(content, "health_timeout 1s") {
		t.Errorf("Caddyfile missing health_timeout 1s")
	}
}
