package storage

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/glebarez/sqlite"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

func setupTestDB(t *testing.T) {
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "test.db")

	var err error
	db.DB, err = gorm.Open(sqlite.Open(dbPath), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Silent),
	})
	if err != nil {
		t.Fatalf("failed to open test db: %v", err)
	}

	err = db.DB.AutoMigrate(
		&db.Stack{}, &db.Service{}, &db.Task{}, &db.Node{},
		&db.StorageVolume{}, &db.Backup{}, &db.BackupSchedule{}, &db.StoragePool{},
		&db.StorageMount{}, &ManagedGlusterVolume{},
	)
	if err != nil {
		t.Fatalf("failed to migrate test db: %v", err)
	}
}

func TestFormatBytes(t *testing.T) {
	tests := []struct {
		bytes    int64
		expected string
	}{
		{500, "500 B"},
		{1024, "1.0 KB"},
		{1048576, "1.0 MB"},
		{1572864, "1.5 MB"},
		{1073741824, "1.0 GB"},
	}

	for _, tt := range tests {
		got := FormatBytes(tt.bytes)
		if got != tt.expected {
			t.Errorf("FormatBytes(%d) = %s; want %s", tt.bytes, got, tt.expected)
		}
	}
}

func TestBackupAndRestore(t *testing.T) {
	setupTestDB(t)

	// Create test source directory with dummy files
	sourceDir := t.TempDir()
	file1 := filepath.Join(sourceDir, "hello.txt")
	file2 := filepath.Join(sourceDir, "data.json")

	if err := os.WriteFile(file1, []byte("Hello Gubernator Storage"), 0644); err != nil {
		t.Fatalf("failed to write test file1: %v", err)
	}
	if err := os.WriteFile(file2, []byte(`{"status":"ok"}`), 0644); err != nil {
		t.Fatalf("failed to write test file2: %v", err)
	}

	// 1. Create Backup
	req := CreateBackupRequest{
		Name:            "test-backup",
		StackID:         "stack-test",
		SourcePath:      sourceDir,
		PauseContainers: false,
	}

	backup, err := CreateBackup(req)
	if err != nil {
		t.Fatalf("CreateBackup failed: %v", err)
	}

	if backup.ID == "" || backup.SHA256 == "" {
		t.Fatalf("invalid backup record: %+v", backup)
	}

	if backup.SizeBytes <= 0 {
		t.Fatalf("expected positive backup size, got %d", backup.SizeBytes)
	}

	// 2. List Backups
	list, err := ListBackups()
	if err != nil || len(list) != 1 {
		t.Fatalf("ListBackups failed, expected 1 record, got %d (err: %v)", len(list), err)
	}

	// 3. Restore to a new directory
	restoreDir := t.TempDir()
	err = RestoreBackup(RestoreBackupRequest{
		BackupID:   backup.ID,
		TargetPath: restoreDir,
	})
	if err != nil {
		t.Fatalf("RestoreBackup failed: %v", err)
	}

	restoredFile1 := filepath.Join(restoreDir, "hello.txt")
	content, err := os.ReadFile(restoredFile1)
	if err != nil || string(content) != "Hello Gubernator Storage" {
		t.Fatalf("restored file mismatch: got %q, err: %v", string(content), err)
	}

	// 4. Delete Backup
	err = DeleteBackup(backup.ID)
	if err != nil {
		t.Fatalf("DeleteBackup failed: %v", err)
	}

	listAfter, _ := ListBackups()
	if len(listAfter) != 0 {
		t.Fatalf("expected 0 backups after delete, got %d", len(listAfter))
	}
}

func TestPruneRetainedBackups(t *testing.T) {
	setupTestDB(t)

	scheduleID := "sched-123"
	sourceDir := t.TempDir()
	os.WriteFile(filepath.Join(sourceDir, "test.txt"), []byte("test"), 0644)

	// Create 5 backups for the schedule
	for i := 1; i <= 5; i++ {
		b, err := CreateBackup(CreateBackupRequest{
			Name:        "retention-test",
			SourcePath:  sourceDir,
			IsScheduled: true,
			ScheduleID:  scheduleID,
		})
		if err != nil {
			t.Fatalf("failed to create backup: %v", err)
		}
		// Stagger creation time
		time.Sleep(10 * time.Millisecond)
		db.DB.Model(&db.Backup{}).Where("id = ?", b.ID).Update("created_at", time.Now().Add(time.Duration(i)*time.Second))
	}

	// Keep only last 2
	err := PruneRetainedBackups(scheduleID, 2)
	if err != nil {
		t.Fatalf("PruneRetainedBackups failed: %v", err)
	}

	var remaining []db.Backup
	db.DB.Where("schedule_id = ?", scheduleID).Find(&remaining)
	if len(remaining) != 2 {
		t.Fatalf("expected 2 remaining backups after retention prune, got %d", len(remaining))
	}
}
