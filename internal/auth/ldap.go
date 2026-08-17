package auth

import (
	"crypto/tls"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/go-ldap/ldap/v3"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

// AuthResult represents the outcome of an LDAP authentication attempt.
type AuthResult struct {
	UserDN      string   `json:"user_dn"`
	Username    string   `json:"username"`
	DisplayName string   `json:"display_name"`
	Email       string   `json:"email"`
	Groups      []string `json:"groups"`
	Role        Role     `json:"role"`
	ProviderID  string   `json:"provider_id"`
}

// TestResult represents the diagnostics of testing an LDAP configuration.
type TestResult struct {
	Connected      bool        `json:"connected"`
	TLSActive      bool        `json:"tls_active"`
	BindSuccessful bool        `json:"bind_successful"`
	UserFound      bool        `json:"user_found"`
	AuthResult     *AuthResult `json:"auth_result,omitempty"`
	Message        string      `json:"message"`
	LatencyMs      int64       `json:"latency_ms"`
}

// ConnectLDAP opens a connection to the specified LDAP server.
func ConnectLDAP(cfg db.LDAPConfig) (*ldap.Conn, error) {
	addr := fmt.Sprintf("%s:%d", cfg.Host, cfg.Port)
	tlsConfig := &tls.Config{
		InsecureSkipVerify: cfg.InsecureSkipVerify,
		ServerName:         cfg.Host,
	}

	var conn *ldap.Conn
	var err error

	switch strings.ToLower(cfg.Security) {
	case "tls", "ldaps", "ssl":
		conn, err = ldap.DialTLS("tcp", addr, tlsConfig)
	case "starttls":
		conn, err = ldap.DialURL(fmt.Sprintf("ldap://%s", addr))
		if err == nil {
			err = conn.StartTLS(tlsConfig)
		}
	default:
		conn, err = ldap.DialURL(fmt.Sprintf("ldap://%s", addr))
	}

	if err != nil {
		return nil, fmt.Errorf("connect to LDAP server %s: %w", addr, err)
	}

	// Set connection timeout
	conn.SetTimeout(10 * time.Second)
	return conn, nil
}

// AuthenticateLDAP attempts user authentication against an active LDAP configuration.
func AuthenticateLDAP(cfg db.LDAPConfig, username, password string) (*AuthResult, error) {
	if username == "" || password == "" {
		return nil, errors.New("username and password cannot be empty")
	}

	conn, err := ConnectLDAP(cfg)
	if err != nil {
		return nil, err
	}
	defer conn.Close()

	// 1. Initial Bind (using Service Account BindDN if specified, otherwise anonymous)
	if cfg.BindDN != "" && cfg.BindPassword != "" {
		if err := conn.Bind(cfg.BindDN, cfg.BindPassword); err != nil {
			return nil, fmt.Errorf("LDAP service account bind failed: %w", err)
		}
	}

	// 2. Search for User
	userFilter := cfg.UserFilter
	if userFilter == "" {
		userFilter = "(&(objectClass=user)(sAMAccountName=%s))"
	}
	formattedFilter := fmt.Sprintf(userFilter, ldap.EscapeFilter(username))

	userAttr := cfg.UserAttr
	if userAttr == "" {
		userAttr = "sAMAccountName"
	}

	attributes := []string{
		"dn", "cn", "displayName", "name", "mail", "userPrincipalName", "memberOf", userAttr,
	}

	searchReq := ldap.NewSearchRequest(
		cfg.BaseDN,
		ldap.ScopeWholeSubtree, ldap.NeverDerefAliases, 0, 0, false,
		formattedFilter,
		attributes,
		nil,
	)

	sr, err := conn.Search(searchReq)
	if err != nil {
		return nil, fmt.Errorf("LDAP user search failed: %w", err)
	}

	if len(sr.Entries) == 0 {
		return nil, fmt.Errorf("user %q not found in LDAP directory", username)
	}
	if len(sr.Entries) > 1 {
		slog.Warn("multiple LDAP entries found for user, using first", "user", username, "count", len(sr.Entries))
	}

	entry := sr.Entries[0]
	userDN := entry.DN

	// 3. Authenticate User credentials via Direct Bind
	userConn, err := ConnectLDAP(cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to open user bind connection: %w", err)
	}
	defer userConn.Close()

	if err := userConn.Bind(userDN, password); err != nil {
		return nil, errors.New("invalid LDAP credentials")
	}

	// 4. Extract User Profile Information
	displayName := entry.GetAttributeValue("displayName")
	if displayName == "" {
		displayName = entry.GetAttributeValue("cn")
	}
	if displayName == "" {
		displayName = entry.GetAttributeValue("name")
	}
	if displayName == "" {
		displayName = username
	}

	email := entry.GetAttributeValue("mail")
	if email == "" {
		email = entry.GetAttributeValue("userPrincipalName")
	}

	// 5. Extract Groups (Active Directory memberOf + POSIX Groups search)
	groups := entry.GetAttributeValues("memberOf")

	if cfg.GroupBaseDN != "" && cfg.GroupFilter != "" {
		groupQuery := fmt.Sprintf(cfg.GroupFilter, ldap.EscapeFilter(userDN))
		groupSearchReq := ldap.NewSearchRequest(
			cfg.GroupBaseDN,
			ldap.ScopeWholeSubtree, ldap.NeverDerefAliases, 0, 0, false,
			groupQuery,
			[]string{"cn", "dn"},
			nil,
		)
		if gsr, gErr := conn.Search(groupSearchReq); gErr == nil {
			for _, ge := range gsr.Entries {
				groups = append(groups, ge.DN, ge.GetAttributeValue("cn"))
			}
		}
	}

	// 6. Map Groups to Role
	role := ResolveRole(cfg, groups)

	return &AuthResult{
		UserDN:      userDN,
		Username:    username,
		DisplayName: displayName,
		Email:       email,
		Groups:      groups,
		Role:        role,
		ProviderID:  cfg.ID,
	}, nil
}

// ResolveRole matches user group memberships against configured role mappings.
func ResolveRole(cfg db.LDAPConfig, userGroups []string) Role {
	matchesGroup := func(targetGroup string) bool {
		if targetGroup == "" {
			return false
		}
		targetClean := strings.ToLower(strings.TrimSpace(targetGroup))
		for _, g := range userGroups {
			gClean := strings.ToLower(strings.TrimSpace(g))
			// Direct match or substring (e.g. cn=admins,ou=...)
			if gClean == targetClean || strings.Contains(gClean, targetClean) {
				return true
			}
		}
		return false
	}

	// 1. Check Admin mapping
	if matchesGroup(cfg.AdminGroupDN) {
		return RoleAdmin
	}

	// 2. Check Operator mapping
	if matchesGroup(cfg.OperatorGroupDN) {
		return RoleOperator
	}

	// 3. Check ReadOnly mapping
	if matchesGroup(cfg.ReadOnlyGroupDN) {
		return RoleReadOnly
	}

	// 4. Fallback to default configured role
	if cfg.DefaultRole != "" && IsValidRole(cfg.DefaultRole) {
		return Role(cfg.DefaultRole)
	}

	return RoleReadOnly
}

// TestLDAPConnection tests connectivity, credentials, and optional user lookup for diagnostics.
func TestLDAPConnection(cfg db.LDAPConfig, testUser, testPass string) (*TestResult, error) {
	start := time.Now()
	conn, err := ConnectLDAP(cfg)
	if err != nil {
		return &TestResult{
			Connected: false,
			Message:   fmt.Sprintf("Connection failed: %v", err),
			LatencyMs: time.Since(start).Milliseconds(),
		}, err
	}
	defer conn.Close()

	tlsActive := strings.ToLower(cfg.Security) == "tls" || strings.ToLower(cfg.Security) == "starttls" || strings.ToLower(cfg.Security) == "ldaps"

	// Test Service Account Bind
	if cfg.BindDN != "" {
		if err := conn.Bind(cfg.BindDN, cfg.BindPassword); err != nil {
			return &TestResult{
				Connected:      true,
				TLSActive:      tlsActive,
				BindSuccessful: false,
				Message:        fmt.Sprintf("Service account bind failed: %v", err),
				LatencyMs:      time.Since(start).Milliseconds(),
			}, err
		}
	}

	res := &TestResult{
		Connected:      true,
		TLSActive:      tlsActive,
		BindSuccessful: true,
		Message:        "Successfully connected and bound to LDAP directory",
		LatencyMs:      time.Since(start).Milliseconds(),
	}

	// If test credentials were provided, attempt user search and authentication test
	if testUser != "" && testPass != "" {
		authRes, authErr := AuthenticateLDAP(cfg, testUser, testPass)
		if authErr != nil {
			res.UserFound = false
			res.Message = fmt.Sprintf("Connected to LDAP, but test user authentication failed: %v", authErr)
			return res, authErr
		}
		res.UserFound = true
		res.AuthResult = authRes
		res.Message = fmt.Sprintf("Successfully authenticated test user %q (Assigned Role: %s, Groups: %d)", testUser, authRes.Role, len(authRes.Groups))
	}

	return res, nil
}
