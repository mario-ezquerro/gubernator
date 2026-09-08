package auth

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"math/big"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

// ─────────────────────────────────────────────────────────────────────────────
// OIDC Discovery & JWKS types
// ─────────────────────────────────────────────────────────────────────────────

// OIDCDiscovery is the response from the /.well-known/openid-configuration endpoint.
type OIDCDiscovery struct {
	Issuer                string   `json:"issuer"`
	AuthorizationEndpoint string   `json:"authorization_endpoint"`
	TokenEndpoint         string   `json:"token_endpoint"`
	UserinfoEndpoint      string   `json:"userinfo_endpoint"`
	JwksURI               string   `json:"jwks_uri"`
	ScopesSupported       []string `json:"scopes_supported"`
}

// jwksResponse is the raw JSON Web Key Set from the IdP's JWKS endpoint.
type jwksResponse struct {
	Keys []jwk `json:"keys"`
}

// jwk represents a single JSON Web Key.
type jwk struct {
	Kty string `json:"kty"` // Key Type: "RSA"
	Kid string `json:"kid"` // Key ID
	Use string `json:"use"` // "sig"
	Alg string `json:"alg"` // "RS256"
	N   string `json:"n"`   // RSA modulus (base64url)
	E   string `json:"e"`   // RSA public exponent (base64url)
}

// ─────────────────────────────────────────────────────────────────────────────
// Pending OIDC auth state (in-memory PKCE + anti-CSRF state store)
// ─────────────────────────────────────────────────────────────────────────────

type pendingOIDCState struct {
	ConfigID     string
	State        string
	CodeVerifier string
	ExpiresAt    time.Time
}

var (
	pendingStatesMu sync.Mutex
	pendingStates   = make(map[string]*pendingOIDCState)
)

func init() {
	// Cleanup goroutine: removes expired OIDC states every 5 minutes.
	go func() {
		ticker := time.NewTicker(5 * time.Minute)
		defer ticker.Stop()
		for range ticker.C {
			now := time.Now()
			pendingStatesMu.Lock()
			for k, v := range pendingStates {
				if now.After(v.ExpiresAt) {
					delete(pendingStates, k)
				}
			}
			pendingStatesMu.Unlock()
		}
	}()
}

// ─────────────────────────────────────────────────────────────────────────────
// OIDC Discovery
// ─────────────────────────────────────────────────────────────────────────────

// FetchOIDCDiscovery fetches and parses the OIDC discovery document from the IdP.
func FetchOIDCDiscovery(cfg db.OIDCConfig) (*OIDCDiscovery, error) {
	issuer := strings.TrimRight(cfg.IssuerURL, "/")

	// GitHub uses a non-standard discovery URL
	discoveryURL := issuer + "/.well-known/openid-configuration"

	client := httpClientForConfig(cfg)
	resp, err := client.Get(discoveryURL)
	if err != nil {
		return nil, fmt.Errorf("OIDC discovery request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return nil, fmt.Errorf("OIDC discovery returned HTTP %d: %s", resp.StatusCode, string(body))
	}

	var disc OIDCDiscovery
	if err := json.NewDecoder(resp.Body).Decode(&disc); err != nil {
		return nil, fmt.Errorf("failed to parse OIDC discovery document: %w", err)
	}

	if disc.AuthorizationEndpoint == "" || disc.TokenEndpoint == "" {
		return nil, errors.New("OIDC discovery document missing required endpoints")
	}

	return &disc, nil
}

// ─────────────────────────────────────────────────────────────────────────────
// Authorization URL Generation (PKCE + state)
// ─────────────────────────────────────────────────────────────────────────────

// GenerateOIDCAuthURL creates a PKCE authorization URL and stores the pending state.
// Returns the full URL to redirect the user to, and the state token.
func GenerateOIDCAuthURL(cfg db.OIDCConfig, disc *OIDCDiscovery, redirectURI string) (authURL string, state string, err error) {
	// Generate cryptographically secure state (anti-CSRF)
	stateBytes := make([]byte, 32)
	if _, err = rand.Read(stateBytes); err != nil {
		return "", "", fmt.Errorf("failed to generate state: %w", err)
	}
	state = base64.RawURLEncoding.EncodeToString(stateBytes)

	// Generate PKCE code_verifier (128 random bytes → base64url)
	verifierBytes := make([]byte, 64)
	if _, err = rand.Read(verifierBytes); err != nil {
		return "", "", fmt.Errorf("failed to generate PKCE verifier: %w", err)
	}
	codeVerifier := base64.RawURLEncoding.EncodeToString(verifierBytes)

	// Compute PKCE code_challenge = BASE64URL(SHA256(code_verifier))
	sum := sha256.Sum256([]byte(codeVerifier))
	codeChallenge := base64.RawURLEncoding.EncodeToString(sum[:])

	// Store pending state
	pendingStatesMu.Lock()
	pendingStates[state] = &pendingOIDCState{
		ConfigID:     cfg.ID,
		State:        state,
		CodeVerifier: codeVerifier,
		ExpiresAt:    time.Now().Add(10 * time.Minute),
	}
	pendingStatesMu.Unlock()

	// Build scopes list
	scopes := cfg.Scopes
	if scopes == "" {
		scopes = "openid profile email"
	}

	// Build authorization URL
	params := url.Values{}
	params.Set("response_type", "code")
	params.Set("client_id", cfg.ClientID)
	params.Set("redirect_uri", redirectURI)
	params.Set("scope", strings.ReplaceAll(scopes, ",", " "))
	params.Set("state", state)
	params.Set("code_challenge", codeChallenge)
	params.Set("code_challenge_method", "S256")
	params.Set("nonce", GenerateRandomKey(16))

	authURL = disc.AuthorizationEndpoint + "?" + params.Encode()
	return authURL, state, nil
}

// ─────────────────────────────────────────────────────────────────────────────
// Token Exchange & ID Token Validation
// ─────────────────────────────────────────────────────────────────────────────

// OIDCCallbackResult holds the authenticated user info returned after callback processing.
type OIDCCallbackResult struct {
	Username    string
	DisplayName string
	Email       string
	Sub         string // Subject identifier from IdP
	Groups      []string
	Role        Role
	ProviderID  string
}

// HandleOIDCCallback validates the callback state, exchanges the code for tokens,
// validates the ID token, and returns the authenticated user info.
func HandleOIDCCallback(state, code, redirectURI string) (*OIDCCallbackResult, error) {
	// 1. Look up and consume pending state (anti-CSRF + PKCE)
	pendingStatesMu.Lock()
	pending, ok := pendingStates[state]
	if ok {
		delete(pendingStates, state)
	}
	pendingStatesMu.Unlock()

	if !ok {
		return nil, errors.New("invalid or expired OAuth2 state token — please try signing in again")
	}
	if time.Now().After(pending.ExpiresAt) {
		return nil, errors.New("OAuth2 state token has expired — please try signing in again")
	}

	// 2. Load OIDC configuration from DB
	var cfg db.OIDCConfig
	if err := db.DB.First(&cfg, "id = ? AND enabled = ?", pending.ConfigID, true).Error; err != nil {
		return nil, fmt.Errorf("OIDC provider %q not found or disabled", pending.ConfigID)
	}

	// 3. Fetch discovery document
	disc, err := FetchOIDCDiscovery(cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch OIDC discovery: %w", err)
	}

	// 4. Exchange authorization code for tokens
	tokenResp, err := exchangeCodeForTokens(cfg, disc, code, pending.CodeVerifier, redirectURI)
	if err != nil {
		return nil, fmt.Errorf("token exchange failed: %w", err)
	}

	// 5. Validate and parse ID token
	claims, err := validateIDToken(cfg, disc, tokenResp.IDToken)
	if err != nil {
		return nil, fmt.Errorf("ID token validation failed: %w", err)
	}

	// 6. Extract user info from claims
	username := claims.Subject
	if username == "" {
		username = claims.Email
	}

	displayName := claims.Name
	if displayName == "" {
		displayName = claims.PreferredUsername
	}
	if displayName == "" {
		displayName = username
	}

	// 7. Extract groups and map to RBAC role
	groups := extractGroups(cfg.RoleClaimPath, claims.Extra)
	role := resolveOIDCRole(cfg, groups)

	slog.Info("OIDC authentication successful",
		"provider", cfg.Name,
		"username", username,
		"email", claims.Email,
		"role", role,
		"groups", groups,
	)

	return &OIDCCallbackResult{
		Username:    username,
		DisplayName: displayName,
		Email:       claims.Email,
		Sub:         claims.Subject,
		Groups:      groups,
		Role:        role,
		ProviderID:  cfg.ID,
	}, nil
}

// ─────────────────────────────────────────────────────────────────────────────
// Token Exchange (Authorization Code → access_token + id_token)
// ─────────────────────────────────────────────────────────────────────────────

type tokenResponse struct {
	AccessToken  string `json:"access_token"`
	IDToken      string `json:"id_token"`
	TokenType    string `json:"token_type"`
	ExpiresIn    int    `json:"expires_in"`
	RefreshToken string `json:"refresh_token"`
}

func exchangeCodeForTokens(cfg db.OIDCConfig, disc *OIDCDiscovery, code, codeVerifier, redirectURI string) (*tokenResponse, error) {
	params := url.Values{}
	params.Set("grant_type", "authorization_code")
	params.Set("code", code)
	params.Set("redirect_uri", redirectURI)
	params.Set("client_id", cfg.ClientID)
	params.Set("client_secret", cfg.ClientSecret)
	params.Set("code_verifier", codeVerifier)

	client := httpClientForConfig(cfg)
	req, err := http.NewRequest("POST", disc.TokenEndpoint, strings.NewReader(params.Encode()))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("token endpoint request failed: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(io.LimitReader(resp.Body, 64*1024))

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("token endpoint returned HTTP %d: %s", resp.StatusCode, string(body))
	}

	var tokenResp tokenResponse
	if err := json.Unmarshal(body, &tokenResp); err != nil {
		return nil, fmt.Errorf("failed to parse token response: %w", err)
	}

	if tokenResp.IDToken == "" {
		return nil, errors.New("IdP did not return an id_token — ensure 'openid' scope is requested")
	}

	return &tokenResp, nil
}

// ─────────────────────────────────────────────────────────────────────────────
// ID Token Validation (JWT + JWKS)
// ─────────────────────────────────────────────────────────────────────────────

// oidcClaims represents the standard + custom JWT claims in an OIDC ID token.
type oidcClaims struct {
	Subject          string                 `json:"sub"`
	Email            string                 `json:"email"`
	Name             string                 `json:"name"`
	PreferredUsername string                 `json:"preferred_username"`
	Extra            map[string]interface{} `json:"-"`
	jwt.RegisteredClaims
}

func (c *oidcClaims) UnmarshalJSON(data []byte) error {
	// First unmarshal into a raw map to capture all claims
	raw := make(map[string]interface{})
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	c.Extra = raw

	// Then unmarshal known fields
	type Alias oidcClaims
	alias := (*Alias)(c)
	return json.Unmarshal(data, alias)
}

func validateIDToken(cfg db.OIDCConfig, disc *OIDCDiscovery, idTokenStr string) (*oidcClaims, error) {
	// Fetch JWKS from IdP
	keys, err := fetchJWKS(cfg, disc.JwksURI)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch JWKS: %w", err)
	}

	var claims oidcClaims
	_, err = jwt.ParseWithClaims(idTokenStr, &claims, func(token *jwt.Token) (interface{}, error) {
		// Verify signing algorithm
		switch token.Method.(type) {
		case *jwt.SigningMethodRSA, *jwt.SigningMethodECDSA, *jwt.SigningMethodHMAC:
			// accepted
		default:
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}

		kid, _ := token.Header["kid"].(string)
		return findPublicKey(keys, kid)
	}, jwt.WithIssuedAt())

	if err != nil {
		return nil, fmt.Errorf("ID token signature invalid: %w", err)
	}

	// Verify issuer
	if claims.Issuer != "" && disc.Issuer != "" {
		// Allow trailing slash mismatch
		normalIssuer := strings.TrimRight(disc.Issuer, "/")
		normalClaim := strings.TrimRight(claims.Issuer, "/")
		if normalIssuer != normalClaim {
			return nil, fmt.Errorf("issuer mismatch: got %q, expected %q", claims.Issuer, disc.Issuer)
		}
	}

	// Verify audience contains our client_id
	if len(claims.Audience) > 0 {
		found := false
		for _, aud := range claims.Audience {
			if aud == cfg.ClientID {
				found = true
				break
			}
		}
		if !found {
			return nil, fmt.Errorf("id_token audience %v does not contain client_id %q", claims.Audience, cfg.ClientID)
		}
	}

	return &claims, nil
}

// ─────────────────────────────────────────────────────────────────────────────
// JWKS Key Fetching & RSA Public Key Parsing
// ─────────────────────────────────────────────────────────────────────────────

func fetchJWKS(cfg db.OIDCConfig, jwksURI string) ([]jwk, error) {
	client := httpClientForConfig(cfg)
	resp, err := client.Get(jwksURI)
	if err != nil {
		return nil, fmt.Errorf("JWKS request failed: %w", err)
	}
	defer resp.Body.Close()

	var keyset jwksResponse
	if err := json.NewDecoder(resp.Body).Decode(&keyset); err != nil {
		return nil, fmt.Errorf("failed to parse JWKS: %w", err)
	}
	return keyset.Keys, nil
}

func findPublicKey(keys []jwk, kid string) (interface{}, error) {
	// If kid is specified, find the matching key; otherwise use the first RSA signing key
	for _, k := range keys {
		if (kid == "" || k.Kid == kid) && k.Kty == "RSA" {
			return parseRSAPublicKey(k)
		}
	}
	// Fallback: return first available RSA key
	for _, k := range keys {
		if k.Kty == "RSA" {
			return parseRSAPublicKey(k)
		}
	}
	return nil, fmt.Errorf("no suitable RSA key found in JWKS (kid=%q)", kid)
}

func parseRSAPublicKey(k jwk) (*rsa.PublicKey, error) {
	nBytes, err := base64.RawURLEncoding.DecodeString(k.N)
	if err != nil {
		return nil, fmt.Errorf("failed to decode RSA modulus N: %w", err)
	}
	eBytes, err := base64.RawURLEncoding.DecodeString(k.E)
	if err != nil {
		return nil, fmt.Errorf("failed to decode RSA exponent E: %w", err)
	}

	n := new(big.Int).SetBytes(nBytes)
	e := new(big.Int).SetBytes(eBytes)

	return &rsa.PublicKey{
		N: n,
		E: int(e.Int64()),
	}, nil
}

// ─────────────────────────────────────────────────────────────────────────────
// Group & Role Extraction from Claims
// ─────────────────────────────────────────────────────────────────────────────

// extractGroups extracts group/role values from JWT extra claims using dot-notation path.
// Supports: "groups", "roles", "realm_access.roles", "resource_access.gubernator.roles"
func extractGroups(claimPath string, extra map[string]interface{}) []string {
	if claimPath == "" {
		claimPath = "groups"
	}

	parts := strings.SplitN(claimPath, ".", 2)
	val, ok := extra[parts[0]]
	if !ok {
		return nil
	}

	// Handle nested path (e.g. "realm_access.roles")
	if len(parts) == 2 {
		nested, ok := val.(map[string]interface{})
		if !ok {
			return nil
		}
		val = nested[parts[1]]
	}

	// Convert []interface{} → []string
	switch v := val.(type) {
	case []interface{}:
		var groups []string
		for _, item := range v {
			if s, ok := item.(string); ok {
				groups = append(groups, s)
			}
		}
		return groups
	case []string:
		return v
	case string:
		return []string{v}
	}
	return nil
}

// resolveOIDCRole maps OIDC groups/roles to Gubernator RBAC roles.
func resolveOIDCRole(cfg db.OIDCConfig, groups []string) Role {
	matchesClaim := func(target string) bool {
		if target == "" {
			return false
		}
		targetLower := strings.ToLower(strings.TrimSpace(target))
		for _, g := range groups {
			if strings.ToLower(strings.TrimSpace(g)) == targetLower {
				return true
			}
		}
		return false
	}

	if matchesClaim(cfg.AdminClaim) {
		return RoleAdmin
	}
	if matchesClaim(cfg.OperatorClaim) {
		return RoleOperator
	}
	if matchesClaim(cfg.ReadOnlyClaim) {
		return RoleReadOnly
	}

	if IsValidRole(cfg.DefaultRole) {
		return Role(cfg.DefaultRole)
	}
	return RoleReadOnly
}

// ─────────────────────────────────────────────────────────────────────────────
// OIDC Connection Test
// ─────────────────────────────────────────────────────────────────────────────

// OIDCTestResult holds diagnostic information from a connection test.
type OIDCTestResult struct {
	Connected             bool   `json:"connected"`
	IssuerReachable       bool   `json:"issuer_reachable"`
	DiscoveryOK           bool   `json:"discovery_ok"`
	JwksReachable         bool   `json:"jwks_reachable"`
	AuthorizationEndpoint string `json:"authorization_endpoint,omitempty"`
	TokenEndpoint         string `json:"token_endpoint,omitempty"`
	JwksURI               string `json:"jwks_uri,omitempty"`
	KeyCount              int    `json:"key_count"`
	Message               string `json:"message"`
	LatencyMs             int64  `json:"latency_ms"`
}

// TestOIDCConnection validates that the IdP is reachable and its discovery document is valid.
func TestOIDCConnection(cfg db.OIDCConfig) *OIDCTestResult {
	start := time.Now()
	res := &OIDCTestResult{}

	disc, err := FetchOIDCDiscovery(cfg)
	res.LatencyMs = time.Since(start).Milliseconds()

	if err != nil {
		res.Connected = false
		res.Message = "Discovery failed: " + err.Error()
		return res
	}

	res.Connected = true
	res.IssuerReachable = true
	res.DiscoveryOK = true
	res.AuthorizationEndpoint = disc.AuthorizationEndpoint
	res.TokenEndpoint = disc.TokenEndpoint
	res.JwksURI = disc.JwksURI

	// Test JWKS endpoint
	keys, jwksErr := fetchJWKS(cfg, disc.JwksURI)
	if jwksErr != nil {
		res.Message = fmt.Sprintf("Discovery OK (issuer: %s), but JWKS endpoint failed: %v", disc.Issuer, jwksErr)
		return res
	}

	res.JwksReachable = true
	res.KeyCount = len(keys)
	res.Message = fmt.Sprintf("✅ Connected to %s — %d signing key(s) available. Auth: %s",
		disc.Issuer, len(keys), disc.AuthorizationEndpoint)

	return res
}

// ─────────────────────────────────────────────────────────────────────────────
// HTTP Client Helper
// ─────────────────────────────────────────────────────────────────────────────

func httpClientForConfig(cfg db.OIDCConfig) *http.Client {
	transport := &http.Transport{
		TLSClientConfig: &tls.Config{
			InsecureSkipVerify: cfg.InsecureSkipVerify,
		},
	}
	return &http.Client{
		Transport: transport,
		Timeout:   15 * time.Second,
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// Well-Known Provider Presets
// ─────────────────────────────────────────────────────────────────────────────

// OIDCProviderPreset defines a pre-filled template for common OIDC providers.
type OIDCProviderPreset struct {
	Type        string `json:"type"`
	Name        string `json:"name"`
	IssuerURL   string `json:"issuer_url"`
	Scopes      string `json:"scopes"`
	RoleClaim   string `json:"role_claim_path"`
	Description string `json:"description"`
	DocsURL     string `json:"docs_url"`
}

// GetOIDCProviderPresets returns built-in configuration templates for common IdPs.
func GetOIDCProviderPresets() []OIDCProviderPreset {
	return []OIDCProviderPreset{
		{
			Type:        "keycloak",
			Name:        "Keycloak",
			IssuerURL:   "https://keycloak.yourdomain.com/realms/master",
			Scopes:      "openid profile email groups roles",
			RoleClaim:   "realm_access.roles",
			Description: "Self-hosted enterprise SSO. Bundled in Gubernator cluster via example-keycloak-sso stack.",
			DocsURL:     "https://www.keycloak.org/docs/latest/server_admin/#_oidc",
		},
		{
			Type:        "azure",
			Name:        "Microsoft Entra ID (Azure AD)",
			IssuerURL:   "https://login.microsoftonline.com/{tenant-id}/v2.0",
			Scopes:      "openid profile email",
			RoleClaim:   "groups",
			Description: "Microsoft Azure Active Directory / Entra ID SSO via OIDC v2.0.",
			DocsURL:     "https://learn.microsoft.com/en-us/entra/identity-platform/v2-protocols-oidc",
		},
		{
			Type:        "google",
			Name:        "Google Workspace",
			IssuerURL:   "https://accounts.google.com",
			Scopes:      "openid profile email",
			RoleClaim:   "groups",
			Description: "Google OAuth2/OIDC for G Suite / Google Workspace organizations.",
			DocsURL:     "https://developers.google.com/identity/openid-connect/openid-connect",
		},
		{
			Type:        "github",
			Name:        "GitHub OAuth",
			IssuerURL:   "https://token.actions.githubusercontent.com",
			Scopes:      "openid read:user user:email read:org",
			RoleClaim:   "groups",
			Description: "GitHub OAuth2 for developer teams. Uses GitHub Organizations as groups.",
			DocsURL:     "https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps",
		},
		{
			Type:        "okta",
			Name:        "Okta",
			IssuerURL:   "https://your-org.okta.com/oauth2/default",
			Scopes:      "openid profile email groups",
			RoleClaim:   "groups",
			Description: "Okta identity cloud for enterprise SSO with group-based RBAC.",
			DocsURL:     "https://developer.okta.com/docs/reference/api/oidc/",
		},
		{
			Type:        "generic",
			Name:        "Generic OIDC Provider",
			IssuerURL:   "https://your-idp.example.com",
			Scopes:      "openid profile email",
			RoleClaim:   "groups",
			Description: "Any standards-compliant OpenID Connect 1.0 / OAuth2 provider.",
			DocsURL:     "https://openid.net/connect/",
		},
	}
}
