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

func setupUserSuspendTestDB(t *testing.T) *gin.Engine {
	gin.SetMode(gin.TestMode)
	var err error
	db.DB, err = gorm.Open(sqlite.Open("file::memory:?cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to connect database: %v", err)
	}

	sqlDB, _ := db.DB.DB()
	if sqlDB != nil {
		sqlDB.SetMaxOpenConns(1)
	}

	_ = db.DB.AutoMigrate(&db.LocalUser{}, &db.AuditLog{}, &db.SecurityConfig{}, &db.LDAPConfig{})

	cfg := db.SecurityConfig{
		ID:                        "default",
		MFAEnforced:               false,
		MaxFailedLogins:           5,
		LockoutDurationMinutes:    15,
		PasswordMinLength:         12,
		PasswordRequireComplexity: true,
		SessionTimeoutMinutes:     15,
		UpdatedAt:                 time.Now(),
	}
	db.DB.Save(&cfg)

	r := gin.New()
	r.POST("/api/auth/login", authLoginHandler)
	r.POST("/api/security/users", createSecurityUserHandler)
	r.PUT("/api/security/users/:id", updateSecurityUserHandler)
	r.POST("/api/security/users/:id/toggle-status", toggleSecurityUserStatusHandler)

	return r
}

func TestUserSuspendAndReactivate(t *testing.T) {
	r := setupUserSuspendTestDB(t)

	// 1. Seed root admin and a regular operator user
	adminHash, _ := bcrypt.GenerateFromPassword([]byte("AdminPass123!#"), bcrypt.DefaultCost)
	adminUser := db.LocalUser{
		ID:           "usr-admin",
		Username:     "admin",
		PasswordHash: string(adminHash),
		Role:         "admin",
		Enabled:      true,
		CreatedAt:    time.Now(),
		UpdatedAt:    time.Now(),
	}
	db.DB.Create(&adminUser)

	operatorHash, _ := bcrypt.GenerateFromPassword([]byte("OperatorPass123!#"), bcrypt.DefaultCost)
	operatorUser := db.LocalUser{
		ID:           "usr-operator",
		Username:     "operator1",
		PasswordHash: string(operatorHash),
		Role:         "operator",
		Enabled:      true,
		CreatedAt:    time.Now(),
		UpdatedAt:    time.Now(),
	}
	db.DB.Create(&operatorUser)

	// 2. Try to suspend root admin -> MUST be rejected (400)
	suspendAdminReq, _ := http.NewRequest("POST", "/api/security/users/usr-admin/toggle-status", bytes.NewBufferString(`{"enabled":false}`))
	suspendAdminReq.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, suspendAdminReq)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 Bad Request when suspending admin, got %d: %s", w.Code, w.Body.String())
	}

	// 3. Operator logs in initially -> MUST succeed (200)
	loginPayload, _ := json.Marshal(map[string]interface{}{
		"username": "operator1",
		"password": "OperatorPass123!#",
		"provider": "local",
	})
	req, _ := http.NewRequest("POST", "/api/auth/login", bytes.NewBuffer(loginPayload))
	req.Header.Set("Content-Type", "application/json")
	w = httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 OK for active operator login, got %d: %s", w.Code, w.Body.String())
	}

	// 4. Suspend operator1 account -> MUST succeed (200)
	suspendOpReq, _ := http.NewRequest("POST", "/api/security/users/usr-operator/toggle-status", bytes.NewBufferString(`{"enabled":false}`))
	suspendOpReq.Header.Set("Content-Type", "application/json")
	w = httptest.NewRecorder()
	r.ServeHTTP(w, suspendOpReq)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 OK when suspending operator1, got %d: %s", w.Code, w.Body.String())
	}

	// Verify DB state
	var dbUser db.LocalUser
	db.DB.First(&dbUser, "id = ?", "usr-operator")
	if dbUser.Enabled {
		t.Fatalf("expected operator1 to be disabled/suspended in DB, but enabled is true")
	}

	// 5. Try to log in with suspended operator1 -> MUST be rejected (401 with suspended: true)
	req, _ = http.NewRequest("POST", "/api/auth/login", bytes.NewBuffer(loginPayload))
	req.Header.Set("Content-Type", "application/json")
	w = httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 Unauthorized for suspended user, got %d: %s", w.Code, w.Body.String())
	}
	var loginErrResp map[string]interface{}
	_ = json.Unmarshal(w.Body.Bytes(), &loginErrResp)
	if loginErrResp["suspended"] != true {
		t.Fatalf("expected response suspended: true, got %v", loginErrResp)
	}

	// 6. Reactivate operator1 account -> MUST succeed (200)
	resumeOpReq, _ := http.NewRequest("POST", "/api/security/users/usr-operator/toggle-status", bytes.NewBufferString(`{"enabled":true}`))
	resumeOpReq.Header.Set("Content-Type", "application/json")
	w = httptest.NewRecorder()
	r.ServeHTTP(w, resumeOpReq)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 OK when reactivating operator1, got %d: %s", w.Code, w.Body.String())
	}

	// 7. Try to log in again -> MUST succeed (200)
	req, _ = http.NewRequest("POST", "/api/auth/login", bytes.NewBuffer(loginPayload))
	req.Header.Set("Content-Type", "application/json")
	w = httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 OK after reactivation, got %d: %s", w.Code, w.Body.String())
	}

	// 8. Verify audit trail recorded USER_SUSPEND and USER_REACTIVATE events
	var auditLogs []db.AuditLog
	db.DB.Where("username = ?", "operator1").Or("details LIKE ?", "%operator1%").Find(&auditLogs)
	foundSuspend := false
	foundReactivate := false
	for _, l := range auditLogs {
		if l.Action == "USER_SUSPEND" {
			foundSuspend = true
		}
		if l.Action == "USER_REACTIVATE" {
			foundReactivate = true
		}
	}
	if !foundSuspend {
		t.Errorf("expected USER_SUSPEND audit log to be recorded")
	}
	if !foundReactivate {
		t.Errorf("expected USER_REACTIVATE audit log to be recorded")
	}
}
