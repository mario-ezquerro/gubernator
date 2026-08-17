package auth

import (
	"encoding/base64"
	"net/http"
	"os"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

const (
	ContextUserKey = "gbnt_auth_user"
)

// ExtractUserSession retrieves the authenticated user from JWT header, session cookie, or basic auth.
func ExtractUserSession(c *gin.Context) *UserSession {
	// 1. Check Context cache
	if val, exists := c.Get(ContextUserKey); exists {
		if session, ok := val.(*UserSession); ok {
			return session
		}
	}

	// 2. Check Bearer JWT Token
	authHeader := c.GetHeader("Authorization")
	if strings.HasPrefix(authHeader, "Bearer ") {
		tokenStr := strings.TrimPrefix(authHeader, "Bearer ")
		if session, err := ValidateToken(tokenStr); err == nil {
			c.Set(ContextUserKey, session)
			return session
		}

		// Also support cluster API token override as Admin
		expectedAPIToken := os.Getenv("GBNT_API_TOKEN")
		if expectedAPIToken == "" {
			expectedAPIToken = db.GetAPIToken()
		}
		if expectedAPIToken != "" && tokenStr == expectedAPIToken {
			adminSession := GenerateLocalAdminSession("api-client")
			c.Set(ContextUserKey, &adminSession)
			return &adminSession
		}
	}

	// 3. Check Query Parameter (?token=... or ?jwt=...) for iframes and websockets
	if tokenParam := c.Query("token"); tokenParam != "" {
		if session, err := ValidateToken(tokenParam); err == nil {
			c.Set(ContextUserKey, session)
			c.SetCookie("gbnt_session", tokenParam, 3600*24, "/", "", false, false)
			return session
		}
	}

	// 4. Check Session Cookie (`gbnt_session`)
	if cookie, err := c.Cookie("gbnt_session"); err == nil && cookie != "" {
		if session, err := ValidateToken(cookie); err == nil {
			c.Set(ContextUserKey, session)
			return session
		}
	}

	// 4. Check Basic Auth (Local Administrator fallback)
	username, password, hasBasic := c.Request.BasicAuth()
	if !hasBasic && strings.HasPrefix(authHeader, "Basic ") {
		payload, _ := base64.StdEncoding.DecodeString(strings.TrimPrefix(authHeader, "Basic "))
		pair := strings.SplitN(string(payload), ":", 2)
		if len(pair) == 2 {
			username, password, hasBasic = pair[0], pair[1], true
		}
	}

	if hasBasic {
		expectedUser := os.Getenv("GBNT_WEB_USER")
		if expectedUser == "" {
			expectedUser = "admin"
		}
		expectedPass := os.Getenv("GBNT_WEB_PASSWORD")
		if expectedPass == "" {
			expectedPass = "admin"
		}

		if username == expectedUser && password == expectedPass {
			adminSession := GenerateLocalAdminSession(username)
			c.Set(ContextUserKey, &adminSession)
			return &adminSession
		}

		// Try Active Directory / LDAP authentication on Basic Auth
		var ldapConfigs []db.LDAPConfig
		if err := db.DB.Where("enabled = ?", true).Find(&ldapConfigs).Error; err == nil {
			for _, cfg := range ldapConfigs {
				if res, authErr := AuthenticateLDAP(cfg, username, password); authErr == nil {
					ldapSession := UserSession{
						Username:    res.Username,
						DisplayName: res.DisplayName,
						Email:       res.Email,
						Role:        res.Role,
						Provider:    "ldap:" + cfg.ID,
						Permissions: GetPermissions(res.Role),
					}
					c.Set(ContextUserKey, &ldapSession)
					return &ldapSession
				}
			}
		}
	}

	return nil
}

// RequireAuth middleware ensures the request has a valid authenticated session.
func RequireAuth() gin.HandlerFunc {
	return func(c *gin.Context) {
		session := ExtractUserSession(c)
		if session == nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error": "Authentication required. Please log in.",
			})
			return
		}
		c.Next()
	}
}

// RequireRole middleware ensures the authenticated user has one of the allowed roles.
func RequireRole(roles ...Role) gin.HandlerFunc {
	return func(c *gin.Context) {
		session := ExtractUserSession(c)
		if session == nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error": "Authentication required",
			})
			return
		}

		for _, r := range roles {
			if session.Role == r {
				c.Next()
				return
			}
		}

		c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
			"error":     "Access denied: insufficient permissions for this operation",
			"user_role": session.Role,
			"required":  roles,
		})
	}
}

// RequirePermission ensures the user has a specific boolean capability.
func RequirePermission(permCheck func(p Permissions) bool) gin.HandlerFunc {
	return func(c *gin.Context) {
		session := ExtractUserSession(c)
		if session == nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error": "Authentication required",
			})
			return
		}

		if !permCheck(session.Permissions) {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"error":     "Access denied: your role does not have permission for this action",
				"user_role": session.Role,
			})
			return
		}

		c.Next()
	}
}
