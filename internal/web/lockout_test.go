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
	"github.com/mario-ezquerro/gubernator/internal/db"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

func setupLockoutTestDB(t *testing.T) *gin.Engine {
	gin.SetMode(gin.TestMode)
	var err error
	db.DB, err = gorm.Open(sqlite.Open("file::memory:?cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to connect database: %v", err)
	}

	_ = db.DB.AutoMigrate(&db.LocalUser{}, &db.AuditLog{}, &db.SecurityConfig{}, &db.LDAPConfig{})

	// Seed security config with 5 attempts and 15 min lock
	cfg := db.SecurityConfig{
		ID:                        "default",
		MFAEnforced:               false,
		MaxFailedLogins:           5,
		LockoutDurationMinutes:    15,
		PasswordMinLength:         12,
		PasswordRequireComplexity: true,
		UpdatedAt:                 time.Now(),
	}
	db.DB.Save(&cfg)

	r := gin.New()
	r.POST("/api/auth/login", authLoginHandler)
	r.POST("/api/security/users", createSecurityUserHandler)
	r.POST("/api/security/users/:id/unlock", unlockSecurityUserHandler)

	return r
}

func TestENSAccountLockoutAndUnlock(t *testing.T) {
	r := setupLockoutTestDB(t)

	// 1. Test password policy rejection (too short, no symbols)
	weakUserPayload, _ := json.Marshal(map[string]interface{}{
		"username": "testcenturion",
		"password": "weakpassword",
		"role":     "operator",
		"enabled":  true,
	})
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/security/users", bytes.NewBuffer(weakUserPayload))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected HTTP 400 for weak password, got %d: %s", w.Code, w.Body.String())
	}

	// 2. Create user with valid ENS-compliant password
	compliantPass := "VeniVidiVici#2026!"
	hash, _ := bcrypt.GenerateFromPassword([]byte(compliantPass), bcrypt.DefaultCost)
	testUser := db.LocalUser{
		ID:           "usr-test1",
		Username:     "testcenturion",
		PasswordHash: string(hash),
		Role:         "operator",
		Enabled:      true,
		CreatedAt:    time.Now(),
		UpdatedAt:    time.Now(),
	}
	if err := db.DB.Create(&testUser).Error; err != nil {
		t.Fatalf("failed to insert test user: %v", err)
	}

	// 3. Attempt 4 failed logins with wrong password
	for i := 1; i <= 4; i++ {
		loginPayload, _ := json.Marshal(map[string]string{
			"username": "testcenturion",
			"password": "WrongPassword#999",
		})
		w = httptest.NewRecorder()
		req, _ = http.NewRequest("POST", "/api/auth/login", bytes.NewBuffer(loginPayload))
		req.Header.Set("Content-Type", "application/json")
		r.ServeHTTP(w, req)

		if w.Code != http.StatusUnauthorized {
			t.Fatalf("attempt %d: expected 401 Unauthorized, got %d", i, w.Code)
		}
	}

	// Check that user is NOT locked yet
	var u db.LocalUser
	db.DB.First(&u, "id = ?", "usr-test1")
	if u.FailedLoginAttempts != 4 {
		t.Fatalf("expected 4 failed attempts, got %d", u.FailedLoginAttempts)
	}
	if u.LockedUntil != nil {
		t.Fatalf("expected LockedUntil to be nil after 4 attempts")
	}

	// 4. 5th failed attempt -> MUST lock the account
	loginPayload, _ := json.Marshal(map[string]string{
		"username": "testcenturion",
		"password": "WrongPassword#999",
	})
	w = httptest.NewRecorder()
	req, _ = http.NewRequest("POST", "/api/auth/login", bytes.NewBuffer(loginPayload))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusLocked {
		t.Fatalf("expected 5th attempt to return 423 StatusLocked, got %d: %s", w.Code, w.Body.String())
	}

	// Check DB state
	db.DB.First(&u, "id = ?", "usr-test1")
	if u.FailedLoginAttempts != 5 {
		t.Fatalf("expected 5 failed attempts, got %d", u.FailedLoginAttempts)
	}
	if u.LockedUntil == nil || !u.LockedUntil.After(time.Now()) {
		t.Fatalf("expected account to be locked until future time, got %v", u.LockedUntil)
	}

	// 5. 6th attempt even with CORRECT password must be rejected because account is locked
	loginCorrectPayload, _ := json.Marshal(map[string]string{
		"username": "testcenturion",
		"password": compliantPass,
	})
	w = httptest.NewRecorder()
	req, _ = http.NewRequest("POST", "/api/auth/login", bytes.NewBuffer(loginCorrectPayload))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusLocked {
		t.Fatalf("expected locked account to reject correct password with 423 StatusLocked, got %d: %s", w.Code, w.Body.String())
	}

	// 6. Administrative unlock
	w = httptest.NewRecorder()
	req, _ = http.NewRequest("POST", "/api/security/users/usr-test1/unlock", nil)
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200 on unlock, got %d: %s", w.Code, w.Body.String())
	}

	// Verify DB state after unlock
	var unlockedUser db.LocalUser
	db.DB.First(&unlockedUser, "id = ?", "usr-test1")
	if unlockedUser.FailedLoginAttempts != 0 {
		t.Fatalf("expected failed attempts to reset to 0, got %d", unlockedUser.FailedLoginAttempts)
	}
	if unlockedUser.LockedUntil != nil {
		t.Fatalf("expected LockedUntil to be nil after unlock, got %v", unlockedUser.LockedUntil)
	}

	// 7. Login with correct password now succeeds
	w = httptest.NewRecorder()
	req, _ = http.NewRequest("POST", "/api/auth/login", bytes.NewBuffer(loginCorrectPayload))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200 on successful login after unlock, got %d: %s", w.Code, w.Body.String())
	}

	var resp map[string]interface{}
	_ = json.Unmarshal(w.Body.Bytes(), &resp)
	if resp["token"] == nil {
		t.Fatalf("expected token in response, got %v", resp)
	}

	// 8. Verify audit logs were produced
	var auditCount int64
	db.DB.Model(&db.AuditLog{}).Where("action IN (?)", []string{"ACCOUNT_LOCKED", "ACCOUNT_UNLOCKED", "LOGIN_LOCKED_ATTEMPT"}).Count(&auditCount)
	if auditCount < 2 {
		t.Fatalf("expected at least 2 ENS audit log entries, found %d", auditCount)
	}
}
