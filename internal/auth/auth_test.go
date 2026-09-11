package auth

import (
	"testing"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/db"
)

func TestRolePermissions(t *testing.T) {
	adminPerms := GetPermissions(RoleAdmin)
	if !adminPerms.CanDeployStacks || !adminPerms.CanManageSecurity || !adminPerms.CanManageNodes {
		t.Errorf("admin role must have full capabilities")
	}

	operatorPerms := GetPermissions(RoleOperator)
	if !operatorPerms.CanDeployStacks || operatorPerms.CanManageSecurity || operatorPerms.CanManageNodes {
		t.Errorf("operator role has incorrect permissions: %+v", operatorPerms)
	}

	readOnlyPerms := GetPermissions(RoleReadOnly)
	if readOnlyPerms.CanDeployStacks || readOnlyPerms.CanDeleteTasks || readOnlyPerms.CanManageCaddy {
		t.Errorf("readonly role must not have write permissions: %+v", readOnlyPerms)
	}
}

func TestJWTSessionToken(t *testing.T) {
	session := UserSession{
		Username:    "jdoe",
		DisplayName: "John Doe",
		Email:       "jdoe@corp.local",
		Role:        RoleOperator,
		Provider:    "ldap:ad-primary",
		Permissions: GetPermissions(RoleOperator),
		ExpiresAt:   time.Now().Add(1 * time.Hour),
	}

	token, err := GenerateToken(session)
	if err != nil {
		t.Fatalf("failed to generate token: %v", err)
	}
	if token == "" {
		t.Fatalf("token is empty")
	}

	parsedSession, err := ValidateToken(token)
	if err != nil {
		t.Fatalf("failed to validate token: %v", err)
	}

	if parsedSession.Username != "jdoe" {
		t.Errorf("expected username jdoe, got %s", parsedSession.Username)
	}
	if parsedSession.Role != RoleOperator {
		t.Errorf("expected role operator, got %s", parsedSession.Role)
	}
	if parsedSession.Provider != "ldap:ad-primary" {
		t.Errorf("expected provider ldap:ad-primary, got %s", parsedSession.Provider)
	}
}

func TestResolveRole(t *testing.T) {
	cfg := db.LDAPConfig{
		AdminGroupDN:    "CN=Gubernator_Admins,OU=Groups,DC=corp,DC=local",
		OperatorGroupDN: "CN=Gubernator_Ops,OU=Groups,DC=corp,DC=local",
		ReadOnlyGroupDN: "CN=Gubernator_Viewers,OU=Groups,DC=corp,DC=local",
		DefaultRole:     "readonly",
	}

	// 1. User with Admin group
	user1Groups := []string{
		"CN=Domain Users,CN=Users,DC=corp,DC=local",
		"CN=Gubernator_Admins,OU=Groups,DC=corp,DC=local",
	}
	if role := ResolveRole(cfg, user1Groups); role != RoleAdmin {
		t.Errorf("expected admin role, got %s", role)
	}

	// 2. User with Operator group
	user2Groups := []string{
		"CN=Domain Users,CN=Users,DC=corp,DC=local",
		"CN=Gubernator_Ops,OU=Groups,DC=corp,DC=local",
	}
	if role := ResolveRole(cfg, user2Groups); role != RoleOperator {
		t.Errorf("expected operator role, got %s", role)
	}

	// 3. User with Viewers group
	user3Groups := []string{
		"CN=Domain Users,CN=Users,DC=corp,DC=local",
		"CN=Gubernator_Viewers,OU=Groups,DC=corp,DC=local",
	}
	if role := ResolveRole(cfg, user3Groups); role != RoleReadOnly {
		t.Errorf("expected readonly role, got %s", role)
	}

	// 4. User without specific group -> fallback to default
	user4Groups := []string{
		"CN=Domain Users,CN=Users,DC=corp,DC=local",
	}
	if role := ResolveRole(cfg, user4Groups); role != RoleReadOnly {
		t.Errorf("expected default readonly role, got %s", role)
	}
}

func TestRoleAuditor(t *testing.T) {
	auditorPerms := GetPermissions(RoleAuditor)
	if !auditorPerms.CanViewAuditLogs || !auditorPerms.CanExportAuditLogs || !auditorPerms.CanViewObservability {
		t.Errorf("auditor must have audit and observability view access: %+v", auditorPerms)
	}
	if auditorPerms.CanDeployStacks || auditorPerms.CanExecuteShell || auditorPerms.CanManageSecurity || auditorPerms.CanDeleteTasks {
		t.Errorf("auditor must not have mutation or shell access: %+v", auditorPerms)
	}
}

func TestMFAPendingToken(t *testing.T) {
	session := UserSession{
		Username:    "audit-user",
		DisplayName: "Auditor Test",
		Role:        RoleAuditor,
		Provider:    "local",
	}

	token, err := GenerateMFAPendingToken(session)
	if err != nil {
		t.Fatalf("failed to generate MFA pending token: %v", err)
	}

	parsed, err := ValidateMFAPendingToken(token)
	if err != nil {
		t.Fatalf("failed to validate MFA pending token: %v", err)
	}
	if parsed.Username != "audit-user" || parsed.Role != RoleAuditor {
		t.Errorf("unexpected parsed MFA user: %+v", parsed)
	}

	// Normal ValidateToken must fail on MFA pending token (purpose isolation)
	if _, err := ValidateToken(token); err == nil {
		t.Error("ValidateToken should reject MFA pending token")
	}
}

