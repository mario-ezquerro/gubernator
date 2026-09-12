package security

import (
	"testing"
	"time"

	"github.com/glebarez/sqlite"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"gorm.io/gorm"
)

func setupTestENSDB(t *testing.T) *gorm.DB {
	database, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to open memory sqlite db: %v", err)
	}

	err = database.AutoMigrate(
		&db.SecurityConfig{},
		&db.LocalUser{},
		&db.Backup{},
		&db.AuditLog{},
		&db.Node{},
		&db.TrustedSigningKey{},
		&db.ImageScan{},
		&db.SecurityPolicy{},
	)
	if err != nil {
		t.Fatalf("failed to auto-migrate tables: %v", err)
	}

	return database
}

func TestEvaluateENSComplianceDefault(t *testing.T) {
	database := setupTestENSDB(t)

	// Seed with default ENS Medio config
	secConfig := db.SecurityConfig{
		ID:                        "default",
		MaxFailedLogins:           5,
		LockoutDurationMinutes:    15,
		PasswordMinLength:         12,
		PasswordRequireComplexity: true,
		SessionTimeoutMinutes:     15,
		SIEMEnabled:               true,
		SIEMHost:                  "192.168.1.100",
		SIEMPort:                  514,
		SIEMProtocol:              "UDP",
		SIEMFormat:                "CEF",
	}
	database.Create(&secConfig)

	// Seed users (including auditor and admin with MFA)
	now := time.Now()
	database.Create(&db.LocalUser{
		ID:         "user-admin",
		Username:   "admin",
		Role:       "admin",
		MFAEnabled: true,
		CreatedAt:  now,
	})
	database.Create(&db.LocalUser{
		ID:         "user-auditor",
		Username:   "auditor",
		Role:       "auditor",
		MFAEnabled: false,
		CreatedAt:  now,
	})

	// Seed encrypted backup
	database.Create(&db.Backup{
		ID:             "backup-1",
		Name:           "daily-backup-db",
		IsEncrypted:    true,
		EncryptionAlgo: "AES-256-GCM",
		Status:         "completed",
		CreatedAt:      now,
	})

	// Seed audit log
	database.Create(&db.AuditLog{
		ID:        "log-1",
		Action:    "LOGIN_SUCCESS",
		Username:  "admin",
		Timestamp: now,
		Hash:      "abc123hash",
	})

	// Seed multi-node cluster
	database.Create(&db.Node{
		ID:     "node-1",
		Role:   "manager",
		Status: "active",
	})
	database.Create(&db.Node{
		ID:     "node-2",
		Role:   "worker",
		Status: "active",
	})
	database.Create(&db.Node{
		ID:     "node-3",
		Role:   "worker",
		Status: "active",
	})

	// Seed image security
	database.Create(&db.TrustedSigningKey{
		ID:           "key-1",
		Name:         "cluster-cosign-1",
		PublicKeyPEM: "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA\n-----END PUBLIC KEY-----",
		KeyType:      "cosign-ecdsa",
	})

	summary := EvaluateENSCompliance(database)

	if summary.TotalMeasures == 0 {
		t.Fatalf("expected measures to be evaluated, got 0")
	}

	if summary.BasicoScore < 85.0 {
		t.Errorf("expected high Basico score, got %.1f", summary.BasicoScore)
	}

	if summary.MedioScore < 75.0 {
		t.Errorf("expected high Medio score, got %.1f", summary.MedioScore)
	}

	if summary.OverallCategory != ENSCategoryMedio && summary.OverallCategory != ENSCategoryAlto {
		t.Errorf("expected category MEDIO or ALTO, got %s", summary.OverallCategory)
	}

	// Verify Markdown report generation
	report := GenerateENSReportMarkdown(summary, "v2.86.0")
	if len(report) == 0 {
		t.Fatalf("expected non-empty markdown report")
	}
	if !contains(report, "INFORME TÉCNICO DE CONFORMIDAD") {
		t.Errorf("report missing title")
	}
	if !contains(report, "op.acc.2") {
		t.Errorf("report missing op.acc.2 measure")
	}
	if !contains(report, "AES-256-GCM") {
		t.Errorf("report missing AES-256-GCM evidence")
	}
}

func TestEvaluateENSComplianceDegraded(t *testing.T) {
	database := setupTestENSDB(t)

	// Weak config (no lockout, short password, no complexity)
	secConfig := db.SecurityConfig{
		ID:                        "default",
		MaxFailedLogins:           0,
		LockoutDurationMinutes:    0,
		PasswordMinLength:         6,
		PasswordRequireComplexity: false,
		SessionTimeoutMinutes:     60,
		SIEMEnabled:               false,
	}
	database.Create(&secConfig)

	// Only admin, no auditor, no MFA
	database.Create(&db.LocalUser{
		ID:         "user-admin",
		Username:   "admin",
		Role:       "admin",
		MFAEnabled: false,
	})

	// Unencrypted backup
	database.Create(&db.Backup{
		ID:          "backup-plain",
		Name:        "plain-backup",
		IsEncrypted: false,
	})

	summary := EvaluateENSCompliance(database)

	if summary.CompliantCount > summary.PartialCount+summary.NonCompliantCount {
		t.Errorf("expected degraded cluster to have mostly partial/non-compliant measures")
	}

	if summary.OverallCategory == ENSCategoryAlto {
		t.Errorf("degraded cluster should not achieve ALTO category")
	}

	// Verify that recommendations exist for non-compliant measures
	for _, m := range summary.Measures {
		if m.Status != ENSStatusCompliant && m.Recommendation == "" {
			t.Errorf("expected recommendation for measure %s", m.ID)
		}
	}
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || (len(s) > 0 && len(substr) > 0 && (stringIndex(s, substr) >= 0)))
}

func stringIndex(s, substr string) int {
	for i := 0; i+len(substr) <= len(s); i++ {
		if s[i:i+len(substr)] == substr {
			return i
		}
	}
	return -1
}

