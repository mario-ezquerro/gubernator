package security

import (
	"testing"

	"github.com/glebarez/sqlite"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"

	"github.com/mario-ezquerro/gubernator/internal/db"
)

func setupComplianceTestDB(t *testing.T) *gorm.DB {
	database, err := gorm.Open(sqlite.Open("file:compliance_test?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to open sqlite in-memory db: %v", err)
	}

	err = database.AutoMigrate(
		&db.LocalUser{},
		&db.SecurityConfig{},
		&db.SecurityPolicy{},
		&db.AuditLog{},
		&db.Backup{},
		&db.BackupSchedule{},
		&db.Node{},
		&db.TrustedSigningKey{},
		&db.ImageScan{},
		&db.Stack{},
		&db.Service{},
		&db.Task{},
		&db.LDAPConfig{},
		&db.OIDCConfig{},
		&db.ImageSBOM{},
		&db.StoragePool{},
		&db.StorageMount{},
	)
	if err != nil {
		t.Fatalf("failed to auto-migrate: %v", err)
	}

	db.DB = database

	// Seed security config with strict parameters
	secConfig := db.SecurityConfig{
		ID:                        "default",
		MaxFailedLogins:           5,
		LockoutDurationMinutes:    15,
		PasswordMinLength:         14,
		PasswordRequireComplexity: true,
		SessionTimeoutMinutes:     15,
		MFAEnforced:               true,
		MFAEnforcePrivileged:      true,
	}
	database.Create(&secConfig)

	// Seed admin user with MFA
	hash, _ := bcrypt.GenerateFromPassword([]byte("StrongAdminP@ss123!"), bcrypt.DefaultCost)
	adminUser := db.LocalUser{
		ID:           "usr-admin",
		Username:     "admin",
		PasswordHash: string(hash),
		Role:         "admin",
		Enabled:      true,
		MFAEnabled:   true,
		MFASecret:    "JBSWY3DPEHPK3PXP",
	}
	database.Create(&adminUser)

	// Seed auditor user
	auditorUser := db.LocalUser{
		ID:           "usr-auditor",
		Username:     "auditor",
		PasswordHash: string(hash),
		Role:         "auditor",
		Enabled:      true,
		MFAEnabled:   true,
		MFASecret:    "JBSWY3DPEHPK3PXP",
	}
	database.Create(&auditorUser)

	return database
}

func TestEvaluateAllCompliance(t *testing.T) {
	database := setupComplianceTestDB(t)

	// 1. Initial evaluation
	overview := EvaluateAllCompliance(database, "TEST_INITIAL")

	if overview.OverallScore <= 0 {
		t.Errorf("expected positive overall score, got %.2f", overview.OverallScore)
	}
	if len(overview.Standards) != 5 {
		t.Fatalf("expected 5 standards, got %d", len(overview.Standards))
	}
	if overview.Standards[0].Code != "ENS" || overview.Standards[1].Code != "NIS2" ||
		overview.Standards[2].Code != "CIS" || overview.Standards[3].Code != "ISO27001" ||
		overview.Standards[4].Code != "DORA" {
		t.Errorf("unexpected standards order: %+v", overview.Standards)
	}

	initialENSScore := overview.Standards[0].Score

	// 2. Simulate security degradation: Administrator removes MFA and relaxes lockout policy
	database.Model(&db.LocalUser{}).Where("id = ?", "usr-admin").Update("mfa_enabled", false)
	database.Model(&db.SecurityConfig{}).Where("id = ?", "default").Updates(map[string]interface{}{
		"mfa_enforced":           false,
		"mfa_enforce_privileged": false,
		"max_failed_logins":      50,
	})

	// 3. Second evaluation: should detect degradation
	degradedOverview := EvaluateAllCompliance(database, "TEST_DEGRADATION")

	degradedENSScore := degradedOverview.Standards[0].Score
	if degradedENSScore >= initialENSScore {
		t.Errorf("expected ENS score to decrease after removing MFA, initial: %.2f, degraded: %.2f",
			initialENSScore, degradedENSScore)
	}

	// Verify that degradation was recorded
	foundDegraded := false
	for _, std := range degradedOverview.DegradedStandards {
		if std == "ENS" || std == "NIS2" || std == "DORA" {
			foundDegraded = true
			break
		}
	}
	if !foundDegraded {
		t.Errorf("expected degraded standards to include ENS, NIS2, or DORA, got: %v", degradedOverview.DegradedStandards)
	}

	// 4. Verify GetLatestOverview returns cached overview
	cached := GetLatestOverview(database)
	if cached.OverallScore != degradedOverview.OverallScore {
		t.Errorf("expected cached overall score to match latest evaluation, got: %.2f vs %.2f",
			cached.OverallScore, degradedOverview.OverallScore)
	}
}

func TestTriggerComplianceAudit(t *testing.T) {
	// Trigger non-blocking audit
	TriggerComplianceAudit("TEST_TRIGGER")
	// Should not block or panic
}
