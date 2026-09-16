package security

import (
	"strings"
	"testing"
	"time"

	"github.com/glebarez/sqlite"
	"gorm.io/gorm"

	"github.com/mario-ezquerro/gubernator/internal/db"
)

func setupTestNIS2DB(t *testing.T) *gorm.DB {
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
		&db.OIDCConfig{},
	)
	if err != nil {
		t.Fatalf("failed to auto-migrate tables: %v", err)
	}

	return database
}

func TestEvaluateNIS2ComplianceEmpty(t *testing.T) {
	database := setupTestNIS2DB(t)

	summary := EvaluateNIS2Compliance(database)

	if summary.TotalMeasures != 10 {
		t.Fatalf("expected 10 measures, got %d", summary.TotalMeasures)
	}

	if summary.OverallReadiness == "" {
		t.Fatal("expected non-empty overall readiness")
	}

	report := GenerateNIS2ReportMarkdown(summary, "v2.91.0")
	if !strings.Contains(report, "DIRECTIVE (EU) 2022/2555 (NIS 2)") {
		t.Errorf("expected report to contain NIS 2 header, got:\n%s", report)
	}
}

func TestEvaluateNIS2ComplianceFullyCompliant(t *testing.T) {
	database := setupTestNIS2DB(t)

	// 1. Strict security config
	secConfig := db.SecurityConfig{
		ID:                        "default",
		MaxFailedLogins:           5,
		LockoutDurationMinutes:    15,
		PasswordMinLength:         12,
		PasswordRequireComplexity: true,
		SessionTimeoutMinutes:     15,
		SIEMEnabled:               true,
		SIEMHost:                  "192.168.1.50",
		SIEMPort:                  514,
		SIEMProtocol:              "TCP",
		SIEMFormat:                "RFC5424",
		MFAEnforcePrivileged:      true,
	}
	database.Create(&secConfig)

	// 2. Strict policy
	secPolicy := db.SecurityPolicy{
		ID:                "default",
		EnforceSignatures: "enforce",
		BlockCVESeverity:  "critical",
	}
	database.Create(&secPolicy)

	// 3. Local users with admin, auditor, and MFA
	now := time.Now()
	database.Create(&db.LocalUser{
		ID:         "admin-1",
		Username:   "admin",
		Role:       "admin",
		MFAEnabled: true,
		CreatedAt:  now,
	})
	database.Create(&db.LocalUser{
		ID:        "auditor-1",
		Username:  "auditor",
		Role:      "auditor",
		CreatedAt: now,
	})

	// 4. Identity connector
	database.Create(&db.LDAPConfig{
		ID:       "corp-ldap",
		Name:     "Corporate Active Directory",
		Host:     "ldap.corp.local",
		Port:     636,
		Security: "tls",
		BaseDN:   "dc=corp,dc=local",
	})

	// 5. Cluster nodes (HA)
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

	// 6. Encrypted backups and schedules
	database.Create(&db.Backup{
		ID:          "bak-01",
		VolumeName:  "db-data",
		IsEncrypted: true,
		CreatedAt:   now,
	})
	database.Create(&db.BackupSchedule{
		ID:             "sched-01",
		Name:           "Daily Backup",
		TargetID:       "db-data",
		TargetType:     "volume",
		CronExpression: "0 2 * * *",
		Enabled:        true,
		Encrypted:      true,
	})

	// 7. Signing keys & clean vulnerability scans
	database.Create(&db.TrustedSigningKey{
		ID:        "cosign-key-1",
		Name:      "cluster-root",
		IsDefault: true,
	})
	database.Create(&db.ImageScan{
		ID:            "scan-01",
		ImageName:     "redis:alpine",
		CriticalCount: 0,
		HighCount:     0,
		MediumCount:   1,
		LowCount:      2,
		ScannedAt:     now,
	})

	// 8. Audit logs
	database.Create(&db.AuditLog{
		ID:        "log-1",
		Action:    "STACK_DEPLOY",
		Username:  "admin",
		Timestamp: now,
		Hash:      "abc123sha256",
	})

	summary := EvaluateNIS2Compliance(database)

	if summary.EssentialScore < 85.0 {
		t.Errorf("expected EssentialScore >= 85.0, got %.1f", summary.EssentialScore)
	}
	if summary.ImportantScore < 90.0 {
		t.Errorf("expected ImportantScore >= 90.0, got %.1f", summary.ImportantScore)
	}
	if summary.OverallReadiness != NIS2ReadinessHigh {
		t.Errorf("expected HIGH readiness, got %s", summary.OverallReadiness)
	}
	if summary.CompliantCount != 10 {
		t.Errorf("expected all 10 measures compliant, got %d compliant, %d partial, %d non-compliant",
			summary.CompliantCount, summary.PartialCount, summary.NonCompliantCount)
	}

	report := GenerateNIS2ReportMarkdown(summary, "v2.91.0")
	if !strings.Contains(report, "HIGH") {
		t.Errorf("expected report to contain HIGH readiness, got:\n%s", report)
	}
}
