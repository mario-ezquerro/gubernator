package audit

import (
	"net"
	"strings"
	"testing"
	"time"

	"github.com/glebarez/sqlite"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"gorm.io/gorm"
)

func setupTestDB(t *testing.T) {
	var err error
	db.DB, err = gorm.Open(sqlite.Open("file:audit_test?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to open memory db: %v", err)
	}
	sqlDB, _ := db.DB.DB()
	if sqlDB != nil {
		sqlDB.SetMaxOpenConns(1)
	}
	err = db.DB.AutoMigrate(&db.AuditLog{}, &db.SecurityConfig{})
	if err != nil {
		t.Fatalf("failed to migrate test db: %v", err)
	}
}

func TestTamperEvidentChain(t *testing.T) {
	setupTestDB(t)

	// 1. Record several audit events
	e1, err := RecordEvent("admin", "LOCAL", "127.0.0.1", "LOGIN_SUCCESS", "SUCCESS", "Logged in via UI")
	if err != nil {
		t.Fatalf("failed to record e1: %v", err)
	}
	if e1.PrevHash != genesisHash {
		t.Errorf("expected genesis hash for first log, got %s", e1.PrevHash)
	}

	e2, err := RecordEvent("admin", "LOCAL", "127.0.0.1", "STACK_DEPLOY", "SUCCESS", "Deployed stack web-app")
	if err != nil {
		t.Fatalf("failed to record e2: %v", err)
	}
	if e2.PrevHash != e1.Hash {
		t.Errorf("expected e2.PrevHash to match e1.Hash, got %s vs %s", e2.PrevHash, e1.Hash)
	}

	e3, err := RecordEvent("operator", "LOCAL", "10.0.0.5", "TASK_RESTART", "SUCCESS", "Restarted container nginx-1")
	if err != nil {
		t.Fatalf("failed to record e3: %v", err)
	}
	if e3.PrevHash != e2.Hash {
		t.Errorf("expected e3.PrevHash to match e2.Hash")
	}

	// 2. Verify intact chain
	res, err := VerifyChainIntegrity()
	if err != nil {
		t.Fatalf("VerifyChainIntegrity failed: %v", err)
	}
	if !res.Valid || res.VerifiedRecords != 3 {
		t.Errorf("expected valid chain with 3 verified records, got %+v", res)
	}

	// 3. Tamper with e2 details in database
	db.DB.Model(&db.AuditLog{}).Where("id = ?", e2.ID).Update("details", "HACKED DETAILS")

	// 4. Verification must catch the tampering
	resTampered, err := VerifyChainIntegrity()
	if err != nil {
		t.Fatalf("VerifyChainIntegrity failed: %v", err)
	}
	if resTampered.Valid {
		t.Errorf("expected tampered chain to be invalid!")
	}
	if resTampered.CompromisedID != e2.ID {
		t.Errorf("expected compromised record %s, got %s", e2.ID, resTampered.CompromisedID)
	}
}

func TestSIEMFormatting(t *testing.T) {
	log := db.AuditLog{
		ID:        "aud-12345",
		Timestamp: time.Date(2026, 9, 10, 12, 0, 0, 0, time.UTC),
		Username:  "admin",
		Provider:  "LOCAL",
		IPAddress: "192.168.1.100",
		Action:    "LOGIN_SUCCESS",
		Status:    "SUCCESS",
		Details:   "Admin authenticated with MFA",
		PrevHash:  genesisHash,
		Hash:      "abcdef123456",
	}

	// RFC5424
	rfc := string(FormatSIEMMessage(&log, "RFC5424"))
	if !strings.Contains(rfc, "LOGIN_SUCCESS") || !strings.Contains(rfc, "admin") || !strings.Contains(rfc, "gubernator") {
		t.Errorf("unexpected RFC5424 output: %s", rfc)
	}

	// CEF
	cef := string(FormatSIEMMessage(&log, "CEF"))
	if !strings.HasPrefix(cef, "CEF:0|Gubernator|Orchestrator|") || !strings.Contains(cef, "suser=admin") {
		t.Errorf("unexpected CEF output: %s", cef)
	}

	// JSON
	jsonMsg := string(FormatSIEMMessage(&log, "JSON"))
	if !strings.Contains(jsonMsg, `"username":"admin"`) || !strings.Contains(jsonMsg, `"action":"LOGIN_SUCCESS"`) {
		t.Errorf("unexpected JSON output: %s", jsonMsg)
	}
}

func TestSIEMTestProbeUDP(t *testing.T) {
	// Start local UDP listener
	conn, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("failed to listen UDP: %v", err)
	}
	defer conn.Close()

	port := conn.LocalAddr().(*net.UDPAddr).Port

	cfg := db.SecurityConfig{
		SIEMHost:     "127.0.0.1",
		SIEMPort:     port,
		SIEMProtocol: "UDP",
		SIEMFormat:   "RFC5424",
	}

	err = SendSIEMTestProbe(cfg)
	if err != nil {
		t.Fatalf("SendSIEMTestProbe failed: %v", err)
	}

	buf := make([]byte, 1024)
	_ = conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	n, _, err := conn.ReadFrom(buf)
	if err != nil {
		t.Fatalf("failed to receive probe on mock UDP listener: %v", err)
	}

	received := string(buf[:n])
	if !strings.Contains(received, "SIEM_TEST_PROBE") {
		t.Errorf("expected received message to contain SIEM_TEST_PROBE, got: %s", received)
	}
}
