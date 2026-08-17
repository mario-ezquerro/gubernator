package auth

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

var (
	jwtSecretOnce sync.Once
	jwtSecretKey  []byte
)

// UserSession represents the authenticated identity in memory and in the UI.
type UserSession struct {
	Username    string      `json:"username"`
	DisplayName string      `json:"display_name"`
	Email       string      `json:"email"`
	Role        Role        `json:"role"`
	Provider    string      `json:"provider"` // "local", "ldap:<id>"
	Permissions Permissions `json:"permissions"`
	ExpiresAt   time.Time   `json:"expires_at"`
}

// Claims represents the JWT claims payload.
type Claims struct {
	Username    string `json:"sub"`
	DisplayName string `json:"name"`
	Email       string `json:"email"`
	Role        string `json:"role"`
	Provider    string `json:"provider"`
	jwt.RegisteredClaims
}

func getJWTSecret() []byte {
	jwtSecretOnce.Do(func() {
		if envSecret := os.Getenv("GBNT_JWT_SECRET"); envSecret != "" {
			jwtSecretKey = []byte(envSecret)
			return
		}
		// Generate random 256-bit secret for this runtime instance
		b := make([]byte, 32)
		_, _ = rand.Read(b)
		jwtSecretKey = b
	})
	return jwtSecretKey
}

// GenerateToken generates a signed JWT token valid for 24 hours.
func GenerateToken(user UserSession) (string, error) {
	exp := time.Now().Add(24 * time.Hour)
	claims := Claims{
		Username:    user.Username,
		DisplayName: user.DisplayName,
		Email:       user.Email,
		Role:        string(user.Role),
		Provider:    user.Provider,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(exp),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    "gubernator",
			Subject:   user.Username,
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(getJWTSecret())
}

// ValidateToken parses and validates a JWT token string, returning the UserSession.
func ValidateToken(tokenStr string) (*UserSession, error) {
	token, err := jwt.ParseWithClaims(tokenStr, &Claims{}, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return getJWTSecret(), nil
	})

	if err != nil {
		return nil, err
	}

	if claims, ok := token.Claims.(*Claims); ok && token.Valid {
		role := NormalizeRole(claims.Role)
		return &UserSession{
			Username:    claims.Username,
			DisplayName: claims.DisplayName,
			Email:       claims.Email,
			Role:        role,
			Provider:    claims.Provider,
			Permissions: GetPermissions(role),
			ExpiresAt:   claims.ExpiresAt.Time,
		}, nil
	}

	return nil, errors.New("invalid session token")
}

// GenerateLocalAdminSession creates a session for the local emergency admin.
func GenerateLocalAdminSession(username string) UserSession {
	return UserSession{
		Username:    username,
		DisplayName: "Cluster Administrator (Local)",
		Email:       "admin@gubernator.local",
		Role:        RoleAdmin,
		Provider:    "local",
		Permissions: GetPermissions(RoleAdmin),
		ExpiresAt:   time.Now().Add(24 * time.Hour),
	}
}

// GenerateRandomKey helper
func GenerateRandomKey(length int) string {
	b := make([]byte, length)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
