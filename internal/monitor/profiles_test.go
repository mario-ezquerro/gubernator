package monitor

import (
	"testing"

	"github.com/glebarez/sqlite"
	"gorm.io/gorm"

	"github.com/mario-ezquerro/gubernator/internal/db"
)

func TestListProfiles(t *testing.T) {
	profiles := ListProfiles()
	if len(profiles) != 5 {
		t.Fatalf("expected 5 SRE profiles, got %d", len(profiles))
	}

	foundActive := false
	for _, p := range profiles {
		if p.ID == "" || p.Name == "" || p.RecommendedHosts == "" || p.RecommendedContainers == "" || p.RecommendedRAM == "" {
			t.Errorf("profile %s has missing fields: %+v", p.ID, p)
		}
		if p.IsActive {
			foundActive = true
		}
	}

	if !foundActive {
		t.Errorf("expected at least one active profile, none was active")
	}
}

func TestGetProfileByID(t *testing.T) {
	p := GetProfileByID("ultra-light")
	if p == nil {
		t.Fatalf("expected ultra-light profile, got nil")
	}
	if p.Name != "Ultra-Lightweight" {
		t.Errorf("expected name Ultra-Lightweight, got %s", p.Name)
	}

	invalid := GetProfileByID("non-existent")
	if invalid != nil {
		t.Errorf("expected nil for non-existent profile, got %+v", invalid)
	}
}

func TestRegisterInDBWithProfile_Deduplication(t *testing.T) {
	testDB, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to open sqlite in-memory db: %v", err)
	}

	// Auto-migrate models
	if err := testDB.AutoMigrate(&db.Stack{}, &db.Service{}, &db.Task{}, &db.Node{}); err != nil {
		t.Fatalf("failed to auto migrate: %v", err)
	}

	// Seed duplicate/legacy tasks and services like the old bug
	legacySvc := db.Service{
		ID:      "sre-monitor-stack-gbnt-monitor-cadvisor",
		StackID: SREStackID,
		Name:    "gbnt-monitor-cadvisor",
	}
	testDB.Create(&legacySvc)

	legacyTask := db.Task{
		ID:        "task-gbnt-monitor-cadvisor",
		ServiceID: legacySvc.ID,
		NodeID:    "node-local-manager",
		Status:    "running",
	}
	testDB.Create(&legacyTask)

	// Run clean registration for cloud-native profile
	profile := GetProfileByID("cloud-native")
	if profile == nil {
		t.Fatalf("cloud-native profile not found")
	}

	if err := RegisterInDBWithProfile(testDB, *profile); err != nil {
		t.Fatalf("RegisterInDBWithProfile failed: %v", err)
	}

	// Verify legacy task and service are deleted
	var legacyTasksCount int64
	testDB.Model(&db.Task{}).Where("id LIKE ?", "task-gbnt-monitor-%").Count(&legacyTasksCount)
	if legacyTasksCount != 0 {
		t.Errorf("expected 0 legacy tasks, got %d", legacyTasksCount)
	}

	var legacySvcsCount int64
	testDB.Model(&db.Service{}).Where("id LIKE ?", SREStackID+"-%").Count(&legacySvcsCount)
	if legacySvcsCount != 0 {
		t.Errorf("expected 0 legacy services, got %d", legacySvcsCount)
	}

	// Verify exactly 7 services and 7 tasks exist on manager
	var services []db.Service
	testDB.Where("stack_id = ?", SREStackID).Find(&services)
	if len(services) != 7 {
		t.Errorf("expected 7 services for cloud-native, got %d", len(services))
	}

	var tasks []db.Task
	testDB.Where("node_id = ?", "node-local-manager").Find(&tasks)
	if len(tasks) != 7 {
		t.Errorf("expected 7 manager tasks, got %d", len(tasks))
	}

	// Verify cadvisor has clean name and port 8081:8080
	var cadvisorSvc db.Service
	if err := testDB.First(&cadvisorSvc, "id = ?", "sre-svc-mgr-cadvisor").Error; err != nil {
		t.Errorf("expected sre-svc-mgr-cadvisor to exist: %v", err)
	} else {
		if cadvisorSvc.Name != "cadvisor" {
			t.Errorf("expected name 'cadvisor', got %s", cadvisorSvc.Name)
		}
		if len(cadvisorSvc.Ports) == 0 || cadvisorSvc.Ports[0] != "8081:8080" {
			t.Errorf("expected ports ['8081:8080'], got %+v", cadvisorSvc.Ports)
		}
	}
}
