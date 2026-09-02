package security

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/glebarez/sqlite"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"gorm.io/gorm"
)

func setupTestDB(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "security-test-*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	dbPath := filepath.Join(tempDir, "test.db")
	database, err := gorm.Open(sqlite.Open(dbPath), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to open test database: %v", err)
	}

	err = database.AutoMigrate(
		&db.SecurityPolicy{},
		&db.TrustedSigningKey{},
		&db.ImageScan{},
		&db.ImageVulnerability{},
		&db.ImageSBOM{},
		&db.Stack{},
		&db.Service{},
		&db.Task{},
	)
	if err != nil {
		t.Fatalf("failed to migrate test database: %v", err)
	}

	db.DB = database
}

func TestCosignKeyGenerationAndSigning(t *testing.T) {
	setupTestDB(t)

	pubPEM, privPEM, err := GenerateCosignKeypair("test-key")
	if err != nil {
		t.Fatalf("GenerateCosignKeypair failed: %v", err)
	}
	if pubPEM == "" || privPEM == "" {
		t.Fatal("expected non-empty keypair PEM strings")
	}

	// Save trusted key
	key, err := SaveTrustedKey("Release Key", pubPEM, true)
	if err != nil {
		t.Fatalf("SaveTrustedKey failed: %v", err)
	}
	if key.ID == "" || !key.IsDefault {
		t.Errorf("unexpected key state: %+v", key)
	}

	// Sign image digest
	imageName := "company/payment-api:1.0"
	imageDigest := "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
	sig, err := SignImageDigest(imageName, imageDigest, privPEM, "security-team")
	if err != nil {
		t.Fatalf("SignImageDigest failed: %v", err)
	}
	if sig == "" {
		t.Fatal("expected non-empty base64 signature")
	}

	// Verify image signature
	keys, err := ListTrustedKeys()
	if err != nil || len(keys) == 0 {
		t.Fatalf("ListTrustedKeys failed: %v", err)
	}

	status, _ := VerifyImageSignature(imageName, "signed", keys)
	if status != "verified" {
		t.Errorf("expected signature status 'verified', got '%s'", status)
	}
}

func TestImageScanAndSBOM(t *testing.T) {
	setupTestDB(t)

	imageName := "postgres:16-alpine"
	scan, vulns, err := TriggerScan(imageName)
	if err != nil {
		t.Fatalf("TriggerScan failed: %v", err)
	}
	if scan == nil || scan.ImageName != imageName {
		t.Fatalf("unexpected scan output: %+v", scan)
	}
	if len(vulns) == 0 {
		t.Fatal("expected vulnerabilities to be detected")
	}

	// Verify scan details
	s, vList, err := GetScanDetails(scan.ID)
	if err != nil || s == nil || len(vList) != len(vulns) {
		t.Fatalf("GetScanDetails mismatch: %v", err)
	}

	// Verify SBOM
	sbom, err := GetSBOMByImage(imageName)
	if err != nil || sbom == nil {
		t.Fatalf("GetSBOMByImage failed: %v", err)
	}
	if sbom.PackageCount == 0 || sbom.RawSBOMJSON == "" {
		t.Errorf("invalid sbom output: %+v", sbom)
	}

	// Export SBOM in CycloneDX
	cdx, err := ExportSBOM(imageName, "cyclonedx-json")
	if err != nil || len(cdx) == 0 {
		t.Errorf("ExportSBOM cyclonedx failed: %v", err)
	}

	// Export SBOM in SPDX
	spdx, err := ExportSBOM(imageName, "spdx-json")
	if err != nil || len(spdx) == 0 {
		t.Errorf("ExportSBOM spdx failed: %v", err)
	}
}

func TestAdmissionGatekeeper(t *testing.T) {
	setupTestDB(t)

	// Set strict policy
	policy := &db.SecurityPolicy{
		ID:                "default",
		Name:              "Strict Policy",
		EnforceSignatures: "enforce",
		BlockCVESeverity:  "critical",
		AllowUnfixedCVE:   false,
	}
	if err := UpdateClusterPolicy(policy); err != nil {
		t.Fatalf("UpdateClusterPolicy failed: %v", err)
	}

	// Evaluate unsigned image
	decision := EvaluateAdmission("untrusted/app:latest", nil)
	if decision.Allowed {
		t.Errorf("expected unsigned image to be blocked under strict policy, but got allowed")
	}
	if decision.Decision != "BLOCKED" {
		t.Errorf("expected decision 'BLOCKED', got '%s'", decision.Decision)
	}

	// Relax signature enforcement to audit
	policy.EnforceSignatures = "audit"
	policy.BlockCVESeverity = "none"
	UpdateClusterPolicy(policy)

	decision2 := EvaluateAdmission("untrusted/app:latest", nil)
	if !decision2.Allowed {
		t.Errorf("expected image to be allowed under audit policy, but got blocked: %s", decision2.Reason)
	}
}

func TestReplaceImageInComposeYAML(t *testing.T) {
	rawCompose := `version: '3.8'
services:
  db:
    image: postgres:13.2 # production database
    ports:
      - "5432:5432"
    environment:
      POSTGRES_PASSWORD: secret
`
	newCompose, err := ReplaceImageInComposeYAML(rawCompose, "postgres:13.2", "postgres:16-alpine")
	if err != nil {
		t.Fatalf("ReplaceImageInComposeYAML failed: %v", err)
	}

	if !strings.Contains(newCompose, "postgres:16-alpine") {
		t.Errorf("expected 'postgres:16-alpine' in updated compose, got: %s", newCompose)
	}
	if strings.Contains(newCompose, "postgres:13.2") {
		t.Errorf("expected 'postgres:13.2' to be removed from compose, got: %s", newCompose)
	}
}

func TestRemediationPlanAndRollback(t *testing.T) {
	setupTestDB(t)

	// Create test stack and service
	stack := db.Stack{
		ID:             "stack-app",
		Name:           "app-stack",
		RawComposeFile: "version: '3.8'\nservices:\n  redis:\n    image: redis:6.0\n",
	}
	db.DB.Create(&stack)

	service := db.Service{
		ID:              "svc-redis",
		StackID:         "stack-app",
		Name:            "redis",
		Image:           "redis:6.0",
		DesiredReplicas: 1,
	}
	db.DB.Create(&service)

	// 1. Preview suggestions
	preview, err := PreviewRemediation("redis:6.0")
	if err != nil {
		t.Fatalf("PreviewRemediation failed: %v", err)
	}
	if len(preview.SuggestedVersions) == 0 {
		t.Fatal("expected suggested upgrade versions for redis:6.0")
	}
	if len(preview.AffectedStacks) == 0 || preview.AffectedStacks[0].StackName != "app-stack" {
		t.Errorf("expected affected stack 'app-stack', got: %+v", preview.AffectedStacks)
	}

	// 2. Successful remediation
	res, err := RemediateImageInStack("stack-app", "redis:6.0", "redis:7.4-alpine", false)
	if err != nil || res == nil || !res.Success {
		t.Fatalf("RemediateImageInStack failed: %v, res: %+v", err, res)
	}

	var updatedStack db.Stack
	db.DB.First(&updatedStack, "id = ?", "stack-app")
	if !strings.Contains(updatedStack.RawComposeFile, "redis:7.4-alpine") {
		t.Errorf("expected updated compose to have redis:7.4-alpine, got: %s", updatedStack.RawComposeFile)
	}
}

