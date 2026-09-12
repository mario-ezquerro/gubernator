package web

import (
	"bytes"
	"encoding/json"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/glebarez/sqlite"
	"github.com/mario-ezquerro/gubernator/internal/audit"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"gorm.io/gorm"
)

func setupSIEMTestServer(t *testing.T) *gin.Engine {
	gin.SetMode(gin.TestMode)
	var err error
	db.DB, err = gorm.Open(sqlite.Open("file:siem_test?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to connect database: %v", err)
	}

	sqlDB, _ := db.DB.DB()
	if sqlDB != nil {
		sqlDB.SetMaxOpenConns(1)
	}

	_ = db.DB.AutoMigrate(&db.LocalUser{}, &db.AuditLog{}, &db.SecurityConfig{})

	cfg := db.SecurityConfig{
		ID:           "default",
		SIEMEnabled:  false,
		SIEMHost:     "",
		SIEMPort:     514,
		SIEMProtocol: "UDP",
		SIEMFormat:   "RFC5424",
		UpdatedAt:    time.Now(),
	}
	db.DB.Save(&cfg)

	r := gin.New()
	r.GET("/api/security/siem", getSIEMConfigHandler)
	r.GET("/api/security/siem/status", getSIEMStatusHandler)
	r.POST("/api/security/siem", updateSIEMConfigHandler)
	r.POST("/api/security/siem/test", testSIEMHandler)

	return r
}

func TestSIEMStatusAndProbeEndpoints(t *testing.T) {
	r := setupSIEMTestServer(t)
	audit.ResetSIEMStats()

	// 1. Initial status: disabled
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/security/siem/status", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 OK from /status, got %d: %s", w.Code, w.Body.String())
	}

	var statusResp map[string]interface{}
	_ = json.Unmarshal(w.Body.Bytes(), &statusResp)
	if statusResp["ens_compliant"] != false {
		t.Errorf("expected ens_compliant to be false initially, got %v", statusResp["ens_compliant"])
	}
	statsMap := statusResp["stats"].(map[string]interface{})
	if statsMap["status"] != "DISABLED" {
		t.Errorf("expected status DISABLED, got %s", statsMap["status"])
	}

	// 2. Start mock UDP listener
	conn, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("failed to listen UDP: %v", err)
	}
	defer conn.Close()
	mockPort := conn.LocalAddr().(*net.UDPAddr).Port

	// 3. Update configuration to enable SIEM
	updatePayload := map[string]interface{}{
		"siem_enabled":  true,
		"siem_host":     "127.0.0.1",
		"siem_port":     mockPort,
		"siem_protocol": "UDP",
		"siem_format":   "RFC5424",
	}
	body, _ := json.Marshal(updatePayload)
	w = httptest.NewRecorder()
	req, _ = http.NewRequest("POST", "/api/security/siem", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 OK from update SIEM, got %d: %s", w.Code, w.Body.String())
	}

	// 4. Test probe endpoint
	testPayload := map[string]interface{}{
		"siem_host":     "127.0.0.1",
		"siem_port":     mockPort,
		"siem_protocol": "UDP",
		"siem_format":   "RFC5424",
	}
	body, _ = json.Marshal(testPayload)
	w = httptest.NewRecorder()
	req, _ = http.NewRequest("POST", "/api/security/siem/test", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 OK from test probe, got %d: %s", w.Code, w.Body.String())
	}

	var testResp map[string]interface{}
	_ = json.Unmarshal(w.Body.Bytes(), &testResp)
	if testResp["success"] != true {
		t.Errorf("expected success true in test probe response, got %v", testResp)
	}

	// 5. Verify status endpoint reflects ACTIVE, delivery count, and ens_compliant = true
	w = httptest.NewRecorder()
	req, _ = http.NewRequest("GET", "/api/security/siem/status", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 OK from /status, got %d", w.Code)
	}

	_ = json.Unmarshal(w.Body.Bytes(), &statusResp)
	if statusResp["ens_compliant"] != true {
		t.Errorf("expected ens_compliant to be true after enabling SIEM, got %v", statusResp["ens_compliant"])
	}
	statsMap = statusResp["stats"].(map[string]interface{})
	if statsMap["status"] != "ACTIVE" {
		t.Errorf("expected status ACTIVE, got %s", statsMap["status"])
	}
	if statsMap["total_dispatched"].(float64) < 1 {
		t.Errorf("expected total_dispatched >= 1, got %v", statsMap["total_dispatched"])
	}
}
