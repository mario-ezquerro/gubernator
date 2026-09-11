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
	db.DB, err = gorm.Open(sqlite.Open("file:mfa_test?mode=memory&cache=shared"), &gorm.Config{})
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
		api.GET("/auth/mfa/qr", authMFAQRCodeHandler)
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

func TestMFASetupQRCode(t *testing.T) {
	router := setupWebTestDB(t)

	// Create a token for admin user
	token, err := auth.GenerateToken(auth.UserSession{
		Username: "admin",
		Role:     "admin",
		Provider: "LOCAL",
	})
	if err != nil {
		t.Fatalf("failed to generate token: %v", err)
	}

	// 1. Call POST /api/auth/mfa/setup
	req, _ := http.NewRequest("POST", "/api/auth/mfa/setup", bytes.NewBufferString("{}"))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 OK from mfa/setup, got %d: %s", w.Code, w.Body.String())
	}

	var setupResp map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &setupResp); err != nil {
		t.Fatalf("failed to unmarshal setup response: %v", err)
	}

	secret, ok := setupResp["secret"].(string)
	if !ok || secret == "" {
		t.Fatalf("expected non-empty secret, got %v", setupResp["secret"])
	}

	uri, ok := setupResp["otpauth_uri"].(string)
	if !ok || uri == "" {
		t.Fatalf("expected non-empty otpauth_uri, got %v", setupResp["otpauth_uri"])
	}

	qrDataURI, ok := setupResp["qr_data_uri"].(string)
	if !ok || qrDataURI == "" {
		t.Fatalf("expected non-empty qr_data_uri, got %v", setupResp["qr_data_uri"])
	}
	expectedPrefix := "data:image/png;base64,"
	if len(qrDataURI) <= len(expectedPrefix) || qrDataURI[:len(expectedPrefix)] != expectedPrefix {
		t.Fatalf("expected qr_data_uri to start with '%s', got '%s'", expectedPrefix, qrDataURI)
	}

	// 2. Call GET /api/auth/mfa/qr
	qrReq, _ := http.NewRequest("GET", "/api/auth/mfa/qr?secret="+secret+"&username=admin", nil)
	qrReq.Header.Set("Authorization", "Bearer "+token)
	qrW := httptest.NewRecorder()
	router.ServeHTTP(qrW, qrReq)

	if qrW.Code != http.StatusOK {
		t.Fatalf("expected 200 OK from GET /api/auth/mfa/qr, got %d: %s", qrW.Code, qrW.Body.String())
	}
	if ct := qrW.Header().Get("Content-Type"); ct != "image/png" {
		t.Fatalf("expected Content-Type image/png, got %s", ct)
	}
	bodyBytes := qrW.Body.Bytes()
	if len(bodyBytes) < 4 || bodyBytes[0] != 0x89 || bodyBytes[1] != 'P' || bodyBytes[2] != 'N' || bodyBytes[3] != 'G' {
		t.Fatalf("expected valid PNG header, got %v", bodyBytes[:4])
	}
}

