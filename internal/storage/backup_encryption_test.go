package storage

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/glebarez/sqlite"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"gorm.io/gorm"
)

func setupBackupTestDB(t *testing.T) {
	var err error
	db.DB, err = gorm.Open(sqlite.Open("file:backup_test?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to open memory db: %v", err)
	}
	sqlDB, _ := db.DB.DB()
	if sqlDB != nil {
		sqlDB.SetMaxOpenConns(1)
	}
	if err := db.DB.AutoMigrate(&db.Backup{}, &db.Stack{}, &db.Service{}, &db.Task{}); err != nil {
		t.Fatalf("failed to migrate backup db: %v", err)
	}
}

func TestEncryptedBackupLifecycle(t *testing.T) {
	setupBackupTestDB(t)

	// 1. Create temporary source directory with test files
	tempDir := t.TempDir()
	sourceDir := filepath.Join(tempDir, "source_data")
	destDir := filepath.Join(tempDir, "backups")
	restoreDir := filepath.Join(tempDir, "restored_data")

	_ = os.MkdirAll(sourceDir, 0755)
	_ = os.MkdirAll(destDir, 0755)
	_ = os.MkdirAll(restoreDir, 0755)

	testContent1 := "Gubernator cluster secret configuration data"
	testContent2 := "Database PostgreSQL master dump v16"
	_ = os.WriteFile(filepath.Join(sourceDir, "config.json"), []byte(testContent1), 0644)
	_ = os.WriteFile(filepath.Join(sourceDir, "dump.sql"), []byte(testContent2), 0644)

	passphrase := "ImperialVaultKey#2026@ENS"

	// 2. Create encrypted backup
	createReq := CreateBackupRequest{
		Name:                 "test-ens-encrypted-backup",
		SourcePath:           sourceDir,
		DestinationPath:      destDir,
		Encrypted:            true,
		EncryptionPassphrase: passphrase,
	}

	backupRec, err := CreateBackup(createReq)
	if err != nil {
		t.Fatalf("CreateBackup failed: %v", err)
	}

	if !backupRec.IsEncrypted {
		t.Errorf("expected backup.IsEncrypted to be true")
	}
	if backupRec.EncryptionAlgo != "AES-256-GCM" {
		t.Errorf("expected EncryptionAlgo AES-256-GCM, got %s", backupRec.EncryptionAlgo)
	}
	if filepath.Ext(backupRec.FilePath) != ".enc" {
		t.Errorf("expected file extension .enc, got %s", backupRec.FilePath)
	}

	// 3. Verify magic header
	isEnc, err := IsEncryptedArchive(backupRec.FilePath)
	if err != nil || !isEnc {
		t.Fatalf("expected file to have encryption magic header, got isEnc=%v, err=%v", isEnc, err)
	}

	// 4. Attempt restore with WRONG password -> must fail
	wrongRestoreReq := RestoreBackupRequest{
		BackupID:             backupRec.ID,
		TargetPath:           restoreDir,
		EncryptionPassphrase: "WrongPassword999!",
	}
	err = RestoreBackup(wrongRestoreReq)
	if err == nil {
		t.Fatalf("expected restore to fail with wrong password, but succeeded")
	}

	// 5. Attempt restore with CORRECT password -> must succeed
	correctRestoreReq := RestoreBackupRequest{
		BackupID:             backupRec.ID,
		TargetPath:           restoreDir,
		EncryptionPassphrase: passphrase,
	}
	err = RestoreBackup(correctRestoreReq)
	if err != nil {
		t.Fatalf("RestoreBackup failed with correct password: %v", err)
	}

	// 6. Verify restored file contents match originals
	restored1, err := os.ReadFile(filepath.Join(restoreDir, "config.json"))
	if err != nil || string(restored1) != testContent1 {
		t.Fatalf("restored config.json does not match: got %q, want %q", restored1, testContent1)
	}
	restored2, err := os.ReadFile(filepath.Join(restoreDir, "dump.sql"))
	if err != nil || string(restored2) != testContent2 {
		t.Fatalf("restored dump.sql does not match: got %q, want %q", restored2, testContent2)
	}

	// 7. Test backward-compatibility with unencrypted backup
	plainReq := CreateBackupRequest{
		Name:            "plain-backup",
		SourcePath:      sourceDir,
		DestinationPath: destDir,
		Encrypted:       false,
	}
	plainRec, err := CreateBackup(plainReq)
	if err != nil {
		t.Fatalf("CreateBackup plain failed: %v", err)
	}
	if plainRec.IsEncrypted {
		t.Errorf("expected plain backup to NOT be encrypted")
	}

	plainRestoreDir := filepath.Join(tempDir, "plain_restored")
	_ = os.MkdirAll(plainRestoreDir, 0755)
	err = RestoreBackup(RestoreBackupRequest{
		BackupID:   plainRec.ID,
		TargetPath: plainRestoreDir,
	})
	if err != nil {
		t.Fatalf("RestoreBackup plain failed: %v", err)
	}

	time.Sleep(10 * time.Millisecond)
}
