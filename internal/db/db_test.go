package db

import (
	"testing"
)

func TestInitDB(t *testing.T) {
	// Use an in-memory SQLite database for testing
	Init("file::memory:?cache=shared")

	// Test if models are properly migrated
	if !DB.Migrator().HasTable(&Node{}) {
		t.Error("Expected Node table to exist")
	}
	if !DB.Migrator().HasTable(&Stack{}) {
		t.Error("Expected Stack table to exist")
	}
	if !DB.Migrator().HasTable(&Service{}) {
		t.Error("Expected Service table to exist")
	}
	if !DB.Migrator().HasTable(&Task{}) {
		t.Error("Expected Task table to exist")
	}
}

func TestNodeCreation(t *testing.T) {
	Init("file::memory:?cache=shared")

	node := Node{
		ID:     "test-node-1",
		IP:     "127.0.0.1",
		Role:   "manager",
		Status: "active",
	}

	if err := DB.Create(&node).Error; err != nil {
		t.Fatalf("Failed to create node: %v", err)
	}

	var fetchedNode Node
	if err := DB.First(&fetchedNode, "id = ?", "test-node-1").Error; err != nil {
		t.Fatalf("Failed to fetch node: %v", err)
	}

	if fetchedNode.Role != "manager" {
		t.Errorf("Expected role 'manager', got '%s'", fetchedNode.Role)
	}
}
