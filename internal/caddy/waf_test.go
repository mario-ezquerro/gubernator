package caddy

import (
	"strings"
	"testing"

	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
)

func setupTestDB(t *testing.T) {
	testDB, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to connect memory sqlite: %v", err)
	}

	_ = testDB.AutoMigrate(
		&db.ManagedWAFConfig{},
		&db.ManagedRouteWAF{},
		&db.WAFSecurityEvent{},
	)

	db.DB = testDB
}

func TestWAFConfigCRUD(t *testing.T) {
	setupTestDB(t)

	cfg, err := GetWAFConfig()
	if err != nil {
		t.Fatalf("GetWAFConfig failed: %v", err)
	}
	if cfg.ID != "default" {
		t.Errorf("expected ID 'default', got %q", cfg.ID)
	}
	if cfg.Enabled != false {
		t.Errorf("expected Enabled false initially, got %v", cfg.Enabled)
	}

	// Update config
	cfg.Enabled = true
	cfg.Mode = "enforce"
	cfg.BlockSQLi = true
	cfg.BlockXSS = true
	cfg.BlockRCE = true
	cfg.BlockLFI = true
	cfg.BlockScanners = true

	updated, err := UpdateWAFConfig(*cfg)
	if err != nil {
		t.Fatalf("UpdateWAFConfig failed: %v", err)
	}
	if !updated.Enabled {
		t.Errorf("expected Enabled true, got %v", updated.Enabled)
	}

	// Fetch again
	fetched, err := GetWAFConfig()
	if err != nil {
		t.Fatalf("GetWAFConfig failed: %v", err)
	}
	if !fetched.Enabled {
		t.Errorf("expected fetched Enabled true, got %v", fetched.Enabled)
	}
}

func TestRouteWAFOverrides(t *testing.T) {
	setupTestDB(t)

	host := "api.example.com"

	// Initially no override
	override, err := GetRouteWAF(host)
	if err != nil {
		t.Fatalf("GetRouteWAF error: %v", err)
	}
	if override != nil {
		t.Errorf("expected nil override, got %+v", override)
	}

	// Set manual override
	routeWAF, err := SetRouteWAF(host, true, "enforce", "manual")
	if err != nil {
		t.Fatalf("SetRouteWAF error: %v", err)
	}
	if !routeWAF.Enabled || routeWAF.OverriddenBy != "manual" {
		t.Errorf("unexpected routeWAF state: %+v", routeWAF)
	}

	// Fetch override
	fetched, err := GetRouteWAF(host)
	if err != nil {
		t.Fatalf("GetRouteWAF error: %v", err)
	}
	if fetched == nil || !fetched.Enabled {
		t.Errorf("expected active override for host %s", host)
	}

	// Toggle disable
	disabledRoute, err := SetRouteWAF(host, false, "inherit", "manual")
	if err != nil {
		t.Fatalf("SetRouteWAF disable error: %v", err)
	}
	if disabledRoute.Enabled {
		t.Errorf("expected routeWAF to be disabled")
	}

	// Delete override
	if err := DeleteRouteWAF(host); err != nil {
		t.Fatalf("DeleteRouteWAF error: %v", err)
	}
	afterDelete, _ := GetRouteWAF(host)
	if afterDelete != nil {
		t.Errorf("expected nil after delete, got %+v", afterDelete)
	}
}

func TestBlockUnblockIP(t *testing.T) {
	setupTestDB(t)

	badIP := "198.51.100.42"
	if err := BlockIP(badIP, "Known scanner probe"); err != nil {
		t.Fatalf("BlockIP error: %v", err)
	}

	cfg, _ := GetWAFConfig()
	if !strings.Contains(cfg.BlacklistedIPs, badIP) {
		t.Errorf("expected %s in BlacklistedIPs, got %s", badIP, cfg.BlacklistedIPs)
	}

	// Unblock IP
	if err := UnblockIP(badIP); err != nil {
		t.Fatalf("UnblockIP error: %v", err)
	}
	cfgAfter, _ := GetWAFConfig()
	if strings.Contains(cfgAfter.BlacklistedIPs, badIP) {
		t.Errorf("expected %s to be removed, got %s", badIP, cfgAfter.BlacklistedIPs)
	}
}

func TestBuildWAFSnippet(t *testing.T) {
	cfg := db.ManagedWAFConfig{
		Enabled:       true,
		Mode:          "enforce",
		BlockSQLi:     true,
		BlockXSS:      true,
		BlockRCE:      true,
		BlockLFI:      true,
		BlockScanners: true,
	}

	snippet := BuildWAFSnippet("app.gbnt.local", cfg, nil)
	if snippet == "" {
		t.Fatal("expected non-empty snippet when WAF is enabled")
	}

	expectedDirectives := []string{
		"@waf_sqli",
		"@waf_xss",
		"@waf_rce",
		"@waf_lfi",
		"@waf_scanners",
		"vars_regexp {http.request.uri.query}",
		"header_regexp User-Agent",
		"403 Forbidden - Threat Shield",
	}

	for _, d := range expectedDirectives {
		if !strings.Contains(snippet, d) {
			t.Errorf("expected snippet to contain %q, snippet was:\n%s", d, snippet)
		}
	}

	// Test detection mode
	cfg.Mode = "detection"
	detSnippet := BuildWAFSnippet("app.gbnt.local", cfg, nil)
	if !strings.Contains(detSnippet, "X-Threat-Shield-Warning") {
		t.Errorf("expected detection mode warning header, got:\n%s", detSnippet)
	}

	// Test per-route override disabled
	routeOverride := &db.ManagedRouteWAF{
		Host:    "app.gbnt.local",
		Enabled: false,
	}
	disabledSnippet := BuildWAFSnippet("app.gbnt.local", cfg, routeOverride)
	if disabledSnippet != "" {
		t.Errorf("expected empty snippet when route override disables WAF, got:\n%s", disabledSnippet)
	}
}

func TestSimulateThreatAndEvents(t *testing.T) {
	setupTestDB(t)

	evt, err := SimulateThreat("api.gbnt.local", "SQLI")
	if err != nil {
		t.Fatalf("SimulateThreat failed: %v", err)
	}
	if evt.AttackType != "SQLI" || evt.Action != "BLOCKED" {
		t.Errorf("unexpected event: %+v", evt)
	}

	events, err := ListWAFEvents(10, "all", "all")
	if err != nil {
		t.Fatalf("ListWAFEvents failed: %v", err)
	}
	if len(events) == 0 {
		t.Fatalf("expected at least 1 recorded event, got 0")
	}

	stats, err := GetWAFStats()
	if err != nil {
		t.Fatalf("GetWAFStats failed: %v", err)
	}
	if stats["sqli_attacks_count"].(int64) < 1 {
		t.Errorf("expected sqli_attacks_count >= 1, got %v", stats["sqli_attacks_count"])
	}
}
