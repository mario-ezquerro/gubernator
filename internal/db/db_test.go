package db

import (
	"fmt"
	"testing"
)

// initTestDB opens a unique in-memory SQLite database per test so tests don't
// share state through the package-level DB variable.
func initTestDB(t *testing.T) {
	t.Helper()
	// Each test gets its own cache name → isolated schema + data.
	dsn := fmt.Sprintf("file:%s?mode=memory&cache=private", t.Name())
	if err := Init(dsn); err != nil {
		t.Fatalf("db.Init: %v", err)
	}
}

// ── Schema migration ──────────────────────────────────────────────────────────

func TestInitDB_TablesExist(t *testing.T) {
	initTestDB(t)

	for _, table := range []interface{}{&Node{}, &Stack{}, &Service{}, &Task{}, &ClusterConfig{}} {
		if !DB.Migrator().HasTable(table) {
			t.Errorf("expected table for %T to exist after Init", table)
		}
	}
}

func TestInitDB_SeedsManagerNode(t *testing.T) {
	initTestDB(t)

	var node Node
	if err := DB.First(&node, "id = ?", "node-local-manager").Error; err != nil {
		t.Fatalf("manager node not seeded: %v", err)
	}
	if node.Role != "manager" {
		t.Errorf("expected role=manager, got %q", node.Role)
	}
	if node.Status != "active" {
		t.Errorf("expected status=active, got %q", node.Status)
	}
}

func TestInitDB_CreatesClusterConfig(t *testing.T) {
	initTestDB(t)

	token := GetAPIToken()
	if token == "" {
		t.Error("GetAPIToken returned empty string after Init")
	}
	joinToken := GetJoinToken()
	if joinToken == "" {
		t.Error("GetJoinToken returned empty string after Init")
	}
}

// ── Node CRUD ─────────────────────────────────────────────────────────────────

func TestNodeCreation(t *testing.T) {
	initTestDB(t)

	node := Node{
		ID:     "worker-1",
		IP:     "10.0.0.2",
		Role:   "worker",
		Status: "active",
		Labels: map[string]string{"env": "prod"},
	}
	if err := DB.Create(&node).Error; err != nil {
		t.Fatalf("create node: %v", err)
	}

	var got Node
	if err := DB.First(&got, "id = ?", "worker-1").Error; err != nil {
		t.Fatalf("fetch node: %v", err)
	}
	if got.Role != "worker" {
		t.Errorf("expected role=worker, got %q", got.Role)
	}
	if got.Labels["env"] != "prod" {
		t.Errorf("expected label env=prod, got %q", got.Labels["env"])
	}
}

func TestNodeUpdate(t *testing.T) {
	initTestDB(t)

	node := Node{ID: "worker-2", IP: "10.0.0.3", Role: "worker", Status: "active"}
	DB.Create(&node)

	DB.Model(&Node{}).Where("id = ?", "worker-2").Update("status", "down")

	var got Node
	DB.First(&got, "id = ?", "worker-2")
	if got.Status != "down" {
		t.Errorf("expected status=down, got %q", got.Status)
	}
}

func TestNodeDelete(t *testing.T) {
	initTestDB(t)

	node := Node{ID: "worker-3", IP: "10.0.0.4", Role: "worker", Status: "active"}
	DB.Create(&node)
	DB.Delete(&Node{}, "id = ?", "worker-3")

	var got Node
	err := DB.First(&got, "id = ?", "worker-3").Error
	if err == nil {
		t.Error("expected record-not-found after delete, got nil error")
	}
}

// ── Stack / Service / Task CRUD ───────────────────────────────────────────────

func TestStackCRUD(t *testing.T) {
	initTestDB(t)

	stack := Stack{ID: "stack-1", Name: "myapp", RawComposeFile: "version: '3'"}
	if err := DB.Create(&stack).Error; err != nil {
		t.Fatalf("create stack: %v", err)
	}

	var got Stack
	if err := DB.First(&got, "id = ?", "stack-1").Error; err != nil {
		t.Fatalf("fetch stack: %v", err)
	}
	if got.Name != "myapp" {
		t.Errorf("expected name=myapp, got %q", got.Name)
	}

	DB.Delete(&Stack{}, "id = ?", "stack-1")
	var count int64
	DB.Model(&Stack{}).Where("id = ?", "stack-1").Count(&count)
	if count != 0 {
		t.Error("expected stack to be deleted")
	}
}

func TestServiceCRUD(t *testing.T) {
	initTestDB(t)

	stack := Stack{ID: "stack-2", Name: "svctest"}
	DB.Create(&stack)

	svc := Service{
		ID:              "svc-1",
		StackID:         "stack-2",
		Name:            "web",
		Image:           "nginx:latest",
		DesiredReplicas: 2,
	}
	if err := DB.Create(&svc).Error; err != nil {
		t.Fatalf("create service: %v", err)
	}

	var got Service
	DB.First(&got, "id = ?", "svc-1")
	if got.Image != "nginx:latest" {
		t.Errorf("expected image=nginx:latest, got %q", got.Image)
	}
	if got.DesiredReplicas != 2 {
		t.Errorf("expected replicas=2, got %d", got.DesiredReplicas)
	}
}

func TestTaskCRUD(t *testing.T) {
	initTestDB(t)

	stack := Stack{ID: "stack-3", Name: "tasktest"}
	DB.Create(&stack)
	svc := Service{ID: "svc-2", StackID: "stack-3", Name: "api", Image: "alpine"}
	DB.Create(&svc)

	task := Task{ID: "task-1", ServiceID: "svc-2", NodeID: "node-local-manager", Status: "pending"}
	if err := DB.Create(&task).Error; err != nil {
		t.Fatalf("create task: %v", err)
	}

	DB.Model(&Task{}).Where("id = ?", "task-1").Update("status", "running")

	var got Task
	DB.First(&got, "id = ?", "task-1")
	if got.Status != "running" {
		t.Errorf("expected status=running, got %q", got.Status)
	}
}

// ── Token helpers ─────────────────────────────────────────────────────────────

func TestGetAPIToken_ReturnsEmptyOnMissingRow(t *testing.T) {
	initTestDB(t)

	// Delete the config row to simulate a corrupt state
	DB.Delete(&ClusterConfig{}, "id = ?", "global")

	if tok := GetAPIToken(); tok != "" {
		t.Errorf("expected empty token for missing config, got %q", tok)
	}
}

func TestGetJoinToken_ReturnsEmptyOnMissingRow(t *testing.T) {
	initTestDB(t)

	DB.Delete(&ClusterConfig{}, "id = ?", "global")

	if tok := GetJoinToken(); tok != "" {
		t.Errorf("expected empty join token for missing config, got %q", tok)
	}
}
