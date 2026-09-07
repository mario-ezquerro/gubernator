package api

import (
	"fmt"
	"testing"

	"github.com/mario-ezquerro/gubernator/internal/db"
	"gopkg.in/yaml.v3"
)

func TestIsMultiHostStack(t *testing.T) {
	tests := []struct {
		name        string
		yaml        string
		targetNode  string
		expectMulti bool
	}{
		{
			name: "Standard single host stack",
			yaml: `services:
  web:
    image: nginx:alpine
    deploy:
      replicas: 1`,
			targetNode:  "auto",
			expectMulti: false,
		},
		{
			name: "Explicit targetNode multi-host",
			yaml: `services:
  web:
    image: nginx:alpine`,
			targetNode:  "multi-host",
			expectMulti: true,
		},
		{
			name: "Spread preference in deploy.placement",
			yaml: `services:
  web:
    image: nginx:alpine
    deploy:
      replicas: 3
      placement:
        preferences:
          - spread: node.id`,
			targetNode:  "auto",
			expectMulti: true,
		},
		{
			name: "Spread strategy in labels",
			yaml: `services:
  web:
    image: nginx:alpine
    labels:
      - "gbnt.placement.strategy=spread"
    deploy:
      replicas: 2`,
			targetNode:  "auto",
			expectMulti: true,
		},
		{
			name: "Multi-replica with caddy load balancing",
			yaml: `services:
  web:
    image: nginx:alpine
    labels:
      - "ingress.host=app.gbnt.local"
      - "gbnt.caddy.lb=least_conn"
    deploy:
      replicas: 2`,
			targetNode:  "auto",
			expectMulti: true,
		},
		{
			name: "Different services target different hosts",
			yaml: `services:
  web:
    image: nginx:alpine
    deploy:
      placement:
        constraints:
          - "node.hostname == worker1"
  db:
    image: postgres:alpine
    deploy:
      placement:
        constraints:
          - "node.hostname == worker2"`,
			targetNode:  "auto",
			expectMulti: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var compose ComposeFile
			if err := yaml.Unmarshal([]byte(tt.yaml), &compose); err != nil {
				t.Fatalf("failed to unmarshal yaml: %v", err)
			}

			isMulti := isMultiHostStack(&compose, tt.targetNode)
			if isMulti != tt.expectMulti {
				t.Errorf("expected isMultiHostStack = %v, got %v", tt.expectMulti, isMulti)
			}
		})
	}
}

func TestScheduleServiceWithSpreadAndAffinity(t *testing.T) {
	testDBMutex.Lock()
	defer testDBMutex.Unlock()

	dsn := fmt.Sprintf("file:%s?mode=memory&cache=private", t.Name())
	if err := db.Init(dsn); err != nil {
		t.Fatalf("db.Init failed: %v", err)
	}

	// Clean out any existing seeded nodes
	db.DB.Where("1 = 1").Delete(&db.Node{})
	db.DB.Where("1 = 1").Delete(&db.Task{})
	db.DB.Where("1 = 1").Delete(&db.Service{})
	db.DB.Where("1 = 1").Delete(&db.Stack{})

	// Seed cluster nodes: 1 Manager, 2 Workers (one with GPU)
	nodeManager := db.Node{
		ID:     "node-mgr",
		IP:     "192.168.252.10",
		Role:   "manager",
		Status: "active",
		Labels: map[string]string{"gbnt.node.hostname": "node-mgr"},
	}
	nodeWorker1 := db.Node{
		ID:     "node-w1",
		IP:     "192.168.252.11",
		Role:   "worker",
		Status: "active",
		Labels: map[string]string{"gbnt.node.hostname": "node-w1"},
	}
	nodeWorker2 := db.Node{
		ID:     "node-w2",
		IP:     "192.168.252.12",
		Role:   "worker",
		Status: "active",
		Labels: map[string]string{
			"gbnt.node.hostname": "node-w2",
			"gbnt.node.gpu":      "nvidia",
			"gpu":                "nvidia",
		},
	}
	db.DB.Create(&nodeManager)
	db.DB.Create(&nodeWorker1)
	db.DB.Create(&nodeWorker2)

	// 1. Test Anti-Affinity Spread across 2 workers
	svcSpread := db.Service{
		ID:              "svc-spread",
		StackID:         "stack-1",
		Name:            "web",
		Image:           "nginx:alpine",
		DesiredReplicas: 2,
		Constraints:     []string{"node.role == worker"},
	}
	db.DB.Create(&svcSpread)

	ScheduleServiceWithSpread(&svcSpread, "auto", true)

	var spreadTasks []db.Task
	db.DB.Where("service_id = ?", svcSpread.ID).Find(&spreadTasks)
	if len(spreadTasks) != 2 {
		t.Fatalf("expected 2 tasks created, got %d", len(spreadTasks))
	}

	// Spread guarantees task 1 and task 2 are on different nodes (w1 and w2)
	if spreadTasks[0].NodeID == spreadTasks[1].NodeID {
		t.Errorf("anti-affinity failure: both replicas scheduled to same node %s", spreadTasks[0].NodeID)
	}
	t.Logf("anti-affinity success: task 1 on %s, task 2 on %s", spreadTasks[0].NodeID, spreadTasks[1].NodeID)

	// 2. Test GPU Hardware Affinity
	svcGPU := db.Service{
		ID:              "svc-gpu",
		StackID:         "stack-1",
		Name:            "ai-inference",
		Image:           "ollama:latest",
		DesiredReplicas: 1,
		Constraints:     []string{"gbnt.node.gpu == nvidia"},
	}
	db.DB.Create(&svcGPU)

	gpuTask := ScheduleSingleReplica(&svcGPU, "auto")
	if gpuTask.NodeID != "node-w2" {
		t.Errorf("hardware affinity failure: expected node-w2 for GPU, got %s", gpuTask.NodeID)
	}
	t.Logf("hardware affinity success: GPU task scheduled to %s", gpuTask.NodeID)

	// 3. Test Hostname constraint pinning
	svcHostPin := db.Service{
		ID:              "svc-hostpin",
		StackID:         "stack-1",
		Name:            "db",
		Image:           "postgres:alpine",
		DesiredReplicas: 1,
		Constraints:     []string{"node.hostname == node-mgr"},
	}
	db.DB.Create(&svcHostPin)

	hostPinTask := ScheduleSingleReplica(&svcHostPin, "auto")
	if hostPinTask.NodeID != "node-mgr" {
		t.Errorf("hostname constraint failure: expected node-mgr, got %s", hostPinTask.NodeID)
	}
	t.Logf("hostname constraint pinning success: task scheduled to %s", hostPinTask.NodeID)
}
