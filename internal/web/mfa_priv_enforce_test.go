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

func setupMFAPrivEnforceTestDB(t *testing.T) *gin.Engine {
	gin.SetMode(gin.TestMode)
	var err error
	db.DB, err = gorm.Open(sqlite.Open("file::memory:?cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to connect memory db: %v", err)
	}

	sqlDB, _ := db.DB.DB()
	if sqlDB != nil {
		sqlDB.SetMaxOpenConns(1)
	}

	_ = db.DB.AutoMigrate(&db.LocalUser{}, &db.AuditLog{}, &db.SecurityConfig{})

	// Seed SecurityConfig with MFAEnforcePrivileged = true
	cfg := db.SecurityConfig{
		ID:                   "default",
		MFAEnforced:          false,
		MFAEnforcePrivileged: true,
		MaxFailedLogins:      5,
		UpdatedAt:            time.Now(),
	}
	db.DB.Save(&cfg)

	// Hash password "RomanEagle#2026"
	hash, _ := bcrypt.GenerateFromPassword([]byte("RomanEagle#2026"), bcrypt.DefaultCost)

	// Create privileged admin user (without MFA yet)
	db.DB.Save(&db.LocalUser{
		ID:           "usr-adm-1",
		Username:     "centurion_admin",
		PasswordHash: string(hash),
		Role:         "admin",
		Enabled:      true,
		MFAEnabled:   false,
	})

	// Create non-privileged readonly user (without MFA)
	db.DB.Save(&db.LocalUser{
		ID:           "usr-ro-1",
		Username:     "plebeian_viewer",
		PasswordHash: string(hash),
		Role:         "readonly",
		Enabled:      true,
		MFAEnabled:   false,
	})

	r := gin.New()
	r.POST("/api/auth/login", authLoginHandler)
	r.POST("/api/auth/mfa/verify", authMFAVerifyHandler)
	r.POST("/api/auth/mfa/setup-complete", authMFASetupCompleteHandler)

	return r
}

func TestMFAEnforcePrivilegedFlow(t *testing.T) {
	r := setupMFAPrivEnforceTestDB(t)

	// 1. Non-privileged user (readonly) logs in directly without MFA
	roLoginPayload, _ := json.Marshal(map[string]interface{}{
		"username": "plebeian_viewer",
		"password": "RomanEagle#2026",
	})
	roReq, _ := http.NewRequest("POST", "/api/auth/login", bytes.NewBuffer(roLoginPayload))
	roReq.Header.Set("Content-Type", "application/json")
	roW := httptest.NewRecorder()
	r.ServeHTTP(roW, roReq)

	if roW.Code != http.StatusOK {
		t.Fatalf("expected readonly login 200 OK, got %d: %s", roW.Code, roW.Body.String())
	}
	var roRes map[string]interface{}
	_ = json.Unmarshal(roW.Body.Bytes(), &roRes)
	if roRes["mfa_required"] == true {
		t.Errorf("readonly user should NOT be forced to do MFA when only MFAEnforcePrivileged is active")
	}
	if roRes["token"] == nil {
		t.Errorf("expected session token for readonly user")
	}

	// 2. Privileged admin logs in: MUST be intercepted and receive setup payload
	admLoginPayload, _ := json.Marshal(map[string]interface{}{
		"username": "centurion_admin",
		"password": "RomanEagle#2026",
	})
	admReq, _ := http.NewRequest("POST", "/api/auth/login", bytes.NewBuffer(admLoginPayload))
	admReq.Header.Set("Content-Type", "application/json")
	admW := httptest.NewRecorder()
	r.ServeHTTP(admW, admReq)

	if admW.Code != http.StatusOK {
		t.Fatalf("expected admin login 200 OK, got %d: %s", admW.Code, admW.Body.String())
	}

	var admRes map[string]interface{}
	_ = json.Unmarshal(admW.Body.Bytes(), &admRes)

	if admRes["mfa_required"] != true {
		t.Fatalf("expected mfa_required == true for privileged admin")
	}
	if admRes["mfa_configured"] != false {
		t.Fatalf("expected mfa_configured == false since user has not configured TOTP yet")
	}
	mfaToken, ok := admRes["mfa_token"].(string)
	if !ok || mfaToken == "" {
		t.Fatalf("expected non-empty mfa_token")
	}
	secret, ok := admRes["secret"].(string)
	if !ok || secret == "" {
		t.Fatalf("expected non-empty secret generated for setup")
	}
	qrDataURI, ok := admRes["qr_data_uri"].(string)
	if !ok || qrDataURI == "" {
		t.Fatalf("expected non-empty qr_data_uri")
	}

	// 3. Submitting invalid TOTP code to /api/auth/mfa/setup-complete must fail
	badSetupPayload, _ := json.Marshal(map[string]interface{}{
		"mfa_token": mfaToken,
		"secret":    secret,
		"code":      "999999",
	})
	badReq, _ := http.NewRequest("POST", "/api/auth/mfa/setup-complete", bytes.NewBuffer(badSetupPayload))
	badReq.Header.Set("Content-Type", "application/json")
	badW := httptest.NewRecorder()
	r.ServeHTTP(badW, badReq)

	if badW.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 Bad Request on invalid TOTP, got %d", badW.Code)
	}

	// 4. Generate valid TOTP code and submit to /api/auth/mfa/setup-complete
	validCode, err := auth.GenerateCode(secret, time.Now())
	if err != nil {
		t.Fatalf("failed to generate code for secret: %v", err)
	}

	goodSetupPayload, _ := json.Marshal(map[string]interface{}{
		"mfa_token":    mfaToken,
		"secret":       secret,
		"code":         validCode,
		"backup_codes": []string{"ABCD-1234", "WXYZ-5678"},
	})
	goodReq, _ := http.NewRequest("POST", "/api/auth/mfa/setup-complete", bytes.NewBuffer(goodSetupPayload))
	goodReq.Header.Set("Content-Type", "application/json")
	goodW := httptest.NewRecorder()
	r.ServeHTTP(goodW, goodReq)

	if goodW.Code != http.StatusOK {
		t.Fatalf("expected 200 OK on setup-complete, got %d: %s", goodW.Code, goodW.Body.String())
	}

	var setupRes map[string]interface{}
	_ = json.Unmarshal(goodW.Body.Bytes(), &setupRes)
	if setupRes["token"] == nil {
		t.Errorf("expected final session token in setup-complete response")
	}

	// 5. Verify that in DB, centurion_admin now has MFAEnabled == true and secret saved
	var userInDB db.LocalUser
	if err := db.DB.First(&userInDB, "username = ?", "centurion_admin").Error; err != nil {
		t.Fatalf("failed to query user from DB: %v", err)
	}
	if !userInDB.MFAEnabled {
		t.Errorf("expected user MFAEnabled == true in database")
	}
	if userInDB.MFASecret != secret {
		t.Errorf("expected user MFASecret to match submitted secret")
	}

	// 6. Subsequent login for centurion_admin now returns mfa_configured == true
	nextLoginPayload, _ := json.Marshal(map[string]interface{}{
		"username": "centurion_admin",
		"password": "RomanEagle#2026",
	})
	nextReq, _ := http.NewRequest("POST", "/api/auth/login", bytes.NewBuffer(nextLoginPayload))
	nextReq.Header.Set("Content-Type", "application/json")
	nextW := httptest.NewRecorder()
	r.ServeHTTP(nextW, nextReq)

	if nextW.Code != http.StatusOK {
		t.Fatalf("expected 200 OK on next login, got %d", nextW.Code)
	}
	var nextRes map[string]interface{}
	_ = json.Unmarshal(nextW.Body.Bytes(), &nextRes)
	if nextRes["mfa_required"] != true || nextRes["mfa_configured"] != true {
		t.Errorf("expected mfa_required == true and mfa_configured == true, got required=%v configured=%v",
			nextRes["mfa_required"], nextRes["mfa_configured"])
	}
}
