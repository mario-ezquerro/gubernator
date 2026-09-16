package security

import (
	"strings"
	"testing"

	"github.com/glebarez/sqlite"
	"gorm.io/gorm"

	"github.com/mario-ezquerro/gubernator/internal/db"
)

func setupTestCISDB(t *testing.T) *gorm.DB {
	database, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to open in-memory db: %v", err)
	}

	err = database.AutoMigrate(
		&db.Node{},
		&db.Stack{},
		&db.Service{},
		&db.Task{},
		&db.SecurityPolicy{},
		&db.TrustedSigningKey{},
		&db.ImageScan{},
		&db.ImageSBOM{},
		&db.StoragePool{},
		&db.StorageMount{},
		&db.AuditLog{},
		&db.LocalUser{},
	)
	if err != nil {
		t.Fatalf("failed to automigrate db: %v", err)
	}
	return database
}

func TestEvaluateCISDockerBenchmarkEmpty(t *testing.T) {
	database := setupTestCISDB(t)

	summary := EvaluateCISDockerBenchmark(database)

	if summary.BenchmarkVersion != CISBenchmarkVersion {
		t.Errorf("expected benchmark version %s, got %s", CISBenchmarkVersion, summary.BenchmarkVersion)
	}

	if summary.TotalChecks == 0 {
		t.Fatal("expected non-zero total checks")
	}

	if len(summary.Checks) != summary.TotalChecks {
		t.Errorf("checks slice length %d does not match total checks %d", len(summary.Checks), summary.TotalChecks)
	}

	if summary.ScorePercent <= 0 {
		t.Errorf("expected baseline score > 0, got %f", summary.ScorePercent)
	}

	if summary.PostureGrade == "" {
		t.Error("expected non-empty posture grade")
	}
}

func TestEvaluateCISDockerBenchmarkHardened(t *testing.T) {
	database := setupTestCISDB(t)

	// Seed hardened state
	database.Create(&db.StoragePool{
		ID:       "pool-1",
		Name:     "nvme-pool",
		Path:     "/var/contenedores",
		IsActive: true,
	})

	database.Create(&db.LocalUser{
		ID:       "usr-admin",
		Username: "admin",
		Role:     "admin",
	})

	database.Create(&db.AuditLog{
		Action: "CLUSTER_INIT",
		Status: "SUCCESS",
	})

	database.Create(&db.TrustedSigningKey{
		ID:           "key-1",
		Name:         "prod-cosign-key",
		PublicKeyPEM: "-----BEGIN PUBLIC KEY-----\nMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE\n-----END PUBLIC KEY-----",
		KeyType:      "cosign-ecdsa",
	})

	database.Create(&db.SecurityPolicy{
		ID:                "default",
		EnforceSignatures: "enforce",
		BlockCVESeverity:  "critical",
	})

	database.Create(&db.ImageScan{
		ID:            "scan-1",
		ImageName:     "redis:7.2.4-alpine",
		CriticalCount: 0,
	})

	composeContent := `
services:
  web:
    image: nginx:1.25.4-alpine
    user: "1000:1000"
    read_only: true
    privileged: false
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost"]
      interval: 10s
`

	database.Create(&db.Stack{
		ID:             "stack-1",
		Name:           "production-web",
		RawComposeFile: composeContent,
	})

	database.Create(&db.Service{
		ID:          "svc-1",
		StackID:     "stack-1",
		Name:        "web",
		Image:       "nginx:1.25.4-alpine",
		MemoryLimit: "256M",
		CpuLimit:    "0.5",
	})

	database.Create(&db.Task{
		ID:        "task-1",
		ServiceID: "svc-1",
		NodeID:    "node-1",
		Status:    "running",
	})

	summary := EvaluateCISDockerBenchmark(database)

	if summary.FailCount > 0 {
		t.Errorf("expected 0 fails in hardened cluster, got %d", summary.FailCount)
	}

	if summary.ScorePercent < 80.0 {
		t.Errorf("expected high score in hardened cluster, got %.1f%%", summary.ScorePercent)
	}

	if summary.PostureGrade != "A" && summary.PostureGrade != "A+" {
		t.Errorf("expected posture grade A or A+, got %s", summary.PostureGrade)
	}

	report := GenerateCISDockerReportMarkdown(summary, "v2.92.0")
	if !strings.Contains(report, "CIS Docker Benchmark v1.6.0") {
		t.Error("report missing title")
	}
	if !strings.Contains(report, "1 - Host Configuration") {
		t.Error("report missing Section 1")
	}
	if !strings.Contains(report, "5 - Container Runtime Configuration") {
		t.Error("report missing Section 5")
	}
}
