package web

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/glebarez/sqlite"
	"github.com/mario-ezquerro/gubernator/internal/auth"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

func setupWebTestDB(t *testing.T) *gin.Engine {
	gin.SetMode(gin.TestMode)
	var err error
	db.DB, err = gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to open memory db: %v", err)
	}
	err = db.DB.AutoMigrate(&db.LocalUser{}, &db.AuditLog{}, &db.SecurityConfig{}, &db.ClusterConfig{})
	if err != nil {
		t.Fatalf("failed to auto migrate: %v", err)
	}

	r := gin.New()
	r.POST("/api/auth/login", authLoginHandler)
	r.POST("/api/auth/mfa/verify", authMFAVerifyHandler)

	api := r.Group("/api", auth.RequireAuth())
	{
		api.POST("/auth/mfa/setup", authMFASetupHandler)
		api.POST("/auth/mfa/enable", authMFAEnableHandler)
		api.POST("/auth/mfa/disable", authMFADisableHandler)
		api.GET("/security/siem", getSIEMConfigHandler)
		api.POST("/security/siem", updateSIEMConfigHandler)
		api.GET("/security/audit-logs/verify", verifyAuditLogsHandler)
		api.GET("/security/audit-logs/export", exportAuditLogsHandler)
	}

	return r
}

func TestMFALoginAndVerificationFlow(t *testing.T) {
	router := setupWebTestDB(t)

	// Seed user with MFA
	secret, _ := auth.GenerateBase32Secret()
	hash, _ := bcrypt.GenerateFromPassword([]byte("password123"), bcrypt.DefaultCost)
	bCodes, _ := auth.GenerateBackupCodes(4)
	bCodesRaw, _ := json.Marshal(bCodes)

	user := db.LocalUser{
		ID:             "usr-test-1",
		Username:       "secadmin",
		PasswordHash:   string(hash),
		Role:           "admin",
		Enabled:        true,
		MFAEnabled:     true,
		MFASecret:      secret,
		MFABackupCodes: string(bCodesRaw),
	}
	db.DB.Create(&user)

	// 1. First step login -> must return mfa_required = true
	loginPayload := map[string]string{
		"username": "secadmin",
		"password": "password123",
		"provider": "local",
	}
	body, _ := json.Marshal(loginPayload)
	req, _ := http.NewRequest("POST", "/api/auth/login", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 OK from login, got %d: %s", w.Code, w.Body.String())
	}

	var loginResp map[string]interface{}
	_ = json.Unmarshal(w.Body.Bytes(), &loginResp)

	if loginResp["mfa_required"] != true {
		t.Fatalf("expected mfa_required = true, got %+v", loginResp)
	}
	mfaToken, ok := loginResp["mfa_token"].(string)
	if !ok || mfaToken == "" {
		t.Fatalf("expected mfa_token string, got %+v", loginResp)
	}

	// 2. Second step -> verify with invalid code -> must return 401
	badVerifyPayload := map[string]string{
		"mfa_token": mfaToken,
		"code":      "999999",
	}
	badBody, _ := json.Marshal(badVerifyPayload)
	reqBad, _ := http.NewRequest("POST", "/api/auth/mfa/verify", bytes.NewBuffer(badBody))
	reqBad.Header.Set("Content-Type", "application/json")
	wBad := httptest.NewRecorder()
	router.ServeHTTP(wBad, reqBad)

	if wBad.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 Unauthorized for invalid code, got %d", wBad.Code)
	}

	// 3. Second step -> verify with valid TOTP code
	validCode, err := auth.GenerateCode(secret, time.Now())
	if err != nil {
		t.Fatalf("failed to generate code: %v", err)
	}

	okVerifyPayload := map[string]string{
		"mfa_token": mfaToken,
		"code":      validCode,
	}
	okBody, _ := json.Marshal(okVerifyPayload)
	reqOk, _ := http.NewRequest("POST", "/api/auth/mfa/verify", bytes.NewBuffer(okBody))
	reqOk.Header.Set("Content-Type", "application/json")
	wOk := httptest.NewRecorder()
	router.ServeHTTP(wOk, reqOk)

	if wOk.Code != http.StatusOK {
		t.Fatalf("expected 200 OK for valid TOTP code, got %d: %s", wOk.Code, wOk.Body.String())
	}

	var okResp map[string]interface{}
	_ = json.Unmarshal(wOk.Body.Bytes(), &okResp)
	sessionToken, ok := okResp["token"].(string)
	if !ok || sessionToken == "" {
		t.Fatalf("expected session token in response, got %+v", okResp)
	}

	// 4. Authenticated call to verify audit chain
	reqAudit, _ := http.NewRequest("GET", "/api/security/audit-logs/verify", nil)
	reqAudit.Header.Set("Authorization", "Bearer "+sessionToken)
	wAudit := httptest.NewRecorder()
	router.ServeHTTP(wAudit, reqAudit)

	if wAudit.Code != http.StatusOK {
		t.Fatalf("expected 200 OK from verifyAuditLogs, got %d: %s", wAudit.Code, wAudit.Body.String())
	}

	var auditResp map[string]interface{}
	_ = json.Unmarshal(wAudit.Body.Bytes(), &auditResp)
	if auditResp["valid"] != true {
		t.Fatalf("expected valid audit chain, got %+v", auditResp)
	}
}
