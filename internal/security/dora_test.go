package security

import (
	"strings"
	"testing"
	"time"

	"github.com/glebarez/sqlite"
	"gorm.io/gorm"

	"github.com/mario-ezquerro/gubernator/internal/db"
)

func setupTestDORADB(t *testing.T) *gorm.DB {
	database, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to open memory sqlite db: %v", err)
	}

	err = database.AutoMigrate(
		&db.SecurityConfig{},
		&db.LocalUser{},
		&db.Backup{},
		&db.BackupSchedule{},
		&db.AuditLog{},
		&db.Node{},
		&db.Task{},
		&db.Stack{},
		&db.Service{},
		&db.ImageSBOM{},
		&db.StoragePool{},
		&db.StorageMount{},
		&db.TrustedSigningKey{},
		&db.ImageScan{},
		&db.SecurityPolicy{},
	)
	if err != nil {
		t.Fatalf("failed to auto-migrate tables: %v", err)
	}

	return database
}

func TestEvaluateDORAComplianceEmpty(t *testing.T) {
	database := setupTestDORADB(t)

	summary := EvaluateDORACompliance(database)

	if summary.TotalMeasures != 16 {
		t.Fatalf("expected 16 measures, got %d", summary.TotalMeasures)
	}

	if summary.OverallReadiness == "" {
		t.Fatal("expected non-empty overall readiness")
	}

	report := GenerateDORAReportMarkdown(summary, "v2.95.15")
	if !strings.Contains(report, "Digital Operational Resilience Act (DORA)") {
		t.Errorf("expected report to contain DORA header, got:\n%s", report)
	}
	if !strings.Contains(report, "Pillar 1: ICT Risk Management") {
		t.Errorf("expected report to contain Pillar 1, got:\n%s", report)
	}
	if !strings.Contains(report, "Pillar 4: Third-Party Risk & Cloud Exit Strategy") {
		t.Errorf("expected report to contain Pillar 4, got:\n%s", report)
	}
}

func TestEvaluateDORAComplianceFullyCompliant(t *testing.T) {
	database := setupTestDORADB(t)

	// Populate high-compliance state
	database.Create(&db.SecurityConfig{
		ID:                        "default",
		MaxFailedLogins:           5,
		LockoutDurationMinutes:    15,
		PasswordMinLength:         14,
		PasswordRequireComplexity: true,
		SessionTimeoutMinutes:     15,
		SIEMEnabled:               true,
		SIEMHost:                  "siem.corp.internal",
		SIEMPort:                  514,
		SIEMProtocol:              "udp",
		SIEMFormat:                "rfc5424",
	})

	database.Create(&db.LocalUser{
		Username:   "admin",
		Role:       "admin",
		MFAEnabled: true,
	})

	database.Create(&db.Backup{
		ID:          "backup-01",
		Name:        "production-db-backup",
		CreatedAt:   time.Now(),
		Status:      "completed",
		SizeBytes:   1024 * 1024 * 50,
		IsEncrypted: true,
	})

	database.Create(&db.BackupSchedule{
		ID:             "daily-sched",
		Name:           "Daily Cluster Backup",
		Enabled:        true,
		CronExpression: "0 3 * * *",
		Encrypted:      true,
	})

	for i := 1; i <= 3; i++ {
		database.Create(&db.Node{
			ID:     string(rune('0' + i)),
			Status: "active",
			Role:   "worker",
		})
	}

	for i := 0; i < 60; i++ {
		database.Create(&db.AuditLog{
			ID:        string(rune('a' + i)),
			Timestamp: time.Now().Add(-time.Duration(i) * time.Minute),
			Action:    "CONTAINER_START",
			Username:  "admin",
			Details:   "Started production container",
		})
	}

	database.Create(&db.TrustedSigningKey{
		ID:           "default-ecdsa",
		KeyType:      "cosign-ecdsa",
		Name:         "cluster-root",
		PublicKeyPEM: "-----BEGIN PUBLIC KEY-----\nMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE\n-----END PUBLIC KEY-----",
	})

	database.Create(&db.SecurityPolicy{
		ID:                "default",
		Name:              "Production Gatekeeper",
		EnforceSignatures: "enforce",
		BlockCVESeverity:  "critical",
	})

	summary := EvaluateDORACompliance(database)

	if summary.OverallScore < 80.0 {
		t.Errorf("expected high DORA score (>80.0), got %.2f", summary.OverallScore)
	}

	if summary.Pillar4Score < 80.0 {
		t.Errorf("expected high Pillar 4 score, got %.2f", summary.Pillar4Score)
	}

	if summary.CompliantCount < 10 {
		t.Errorf("expected at least 10 compliant measures, got %d", summary.CompliantCount)
	}
}
