package security

import (
	"strings"
	"testing"
	"time"

	"github.com/glebarez/sqlite"
	"gorm.io/gorm"

	"github.com/mario-ezquerro/gubernator/internal/db"
)

func setupTestISO27001DB(t *testing.T) *gorm.DB {
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
		&db.TrustedSigningKey{},
		&db.ImageScan{},
		&db.SecurityPolicy{},
		&db.LDAPConfig{},
		&db.Task{},
		&db.Stack{},
		&db.ImageSBOM{},
	)
	if err != nil {
		t.Fatalf("failed to auto-migrate tables: %v", err)
	}

	db.DB = database
	return database
}

func TestEvaluateISO27001ComplianceEmpty(t *testing.T) {
	database := setupTestISO27001DB(t)

	summary := EvaluateISO27001Compliance(database)

	if summary.TotalControls != 24 {
		t.Fatalf("expected 24 controls, got %d", summary.TotalControls)
	}

	if summary.PostureGrade == "" {
		t.Fatal("expected posture grade to be calculated")
	}

	report := GenerateISO27001Report(summary)
	if !strings.Contains(report, "ISO/IEC 27001:2022 AUDIT REPORT") {
		t.Errorf("expected report to contain ISO 27001 header, got:\n%s", report)
	}
	if !strings.Contains(report, "STATEMENT OF APPLICABILITY") {
		t.Errorf("expected report to contain Statement of Applicability, got:\n%s", report)
	}
}

func TestEvaluateISO27001ComplianceFullyCompliant(t *testing.T) {
	database := setupTestISO27001DB(t)

	// 1. Strict security config with SIEM
	secConfig := db.SecurityConfig{
		ID:                        "default",
		MaxFailedLogins:           3,
		LockoutDurationMinutes:    15,
		PasswordMinLength:         14,
		PasswordRequireComplexity: true,
		SessionTimeoutMinutes:     15,
		SIEMEnabled:               true,
		SIEMHost:                  "192.168.1.100",
		SIEMPort:                  514,
		SIEMProtocol:              "UDP",
		SIEMFormat:                "RFC5424",
		MFAEnforcePrivileged:      true,
	}
	database.Create(&secConfig)

	// 2. Users with RBAC and MFA
	now := time.Now()
	database.Create(&db.LocalUser{
		ID:         "user-admin",
		Username:   "admin",
		Role:       "admin",
		MFAEnabled: true,
		CreatedAt:  now,
	})
	database.Create(&db.LocalUser{
		ID:         "user-operator",
		Username:   "operator1",
		Role:       "operator",
		MFAEnabled: true,
		CreatedAt:  now,
	})
	database.Create(&db.LocalUser{
		ID:         "user-auditor",
		Username:   "auditor1",
		Role:       "auditor",
		MFAEnabled: true,
		CreatedAt:  now,
	})

	// 3. Multi-node cluster
	database.Create(&db.Node{
		ID:     "manager-1",
		IP:     "192.168.1.10",
		Role:   "manager",
		Status: "active",
	})
	database.Create(&db.Node{
		ID:     "worker-1",
		IP:     "192.168.1.11",
		Role:   "worker",
		Status: "active",
	})

	// 4. Encrypted Backups & Schedule
	database.Create(&db.BackupSchedule{
		ID:             "sched-daily",
		Name:           "Daily Encrypted",
		TargetID:       "db-data",
		TargetType:     "volume",
		CronExpression: "0 2 * * *",
		Encrypted:      true,
		Enabled:        true,
	})
	database.Create(&db.Backup{
		ID:          "bak-001",
		VolumeName:  "db-data",
		IsEncrypted: true,
		CreatedAt:   now,
	})

	// 5. Audit Log
	database.Create(&db.AuditLog{
		ID:        "log-1",
		Action:    "STACK_DEPLOY",
		Username:  "admin",
		Status:    "SUCCESS",
		Timestamp: now,
		Hash:      "sha256demo",
	})

	// 6. Security gatekeeper & scans
	database.Create(&db.SecurityPolicy{
		ID:                "default",
		EnforceSignatures: "enforce",
		BlockCVESeverity:  "critical",
	})
	database.Create(&db.ImageScan{
		ID:            "scan-01",
		ImageName:     "nginx:alpine",
		CriticalCount: 0,
		HighCount:     0,
		ScannedAt:     now,
	})
	database.Create(&db.TrustedSigningKey{
		ID:        "key-1",
		Name:      "Cluster-Production-Key",
		IsDefault: true,
	})
	database.Create(&db.ImageSBOM{
		ID:        "sbom-01",
		ScanID:    "scan-01",
		ImageName: "nginx:alpine",
		Format:    "CycloneDX",
	})

	// 7. Stacks
	database.Create(&db.Stack{
		Name: "web-prod",
	})

	summary := EvaluateISO27001Compliance(database)

	if summary.TotalControls != 24 {
		t.Fatalf("expected 24 controls, got %d", summary.TotalControls)
	}

	if summary.OverallScore < 85.0 {
		t.Fatalf("expected high overall score for hardened cluster, got %.2f", summary.OverallScore)
	}

	if summary.PostureGrade != "A+" && summary.PostureGrade != "A" {
		t.Fatalf("expected grade A or A+, got %s", summary.PostureGrade)
	}

	if summary.ThemeA5Score < 85.0 || summary.ThemeA8Score < 85.0 {
		t.Fatalf("expected high scores across both themes, got A.5=%.2f, A.8=%.2f", summary.ThemeA5Score, summary.ThemeA8Score)
	}
}
