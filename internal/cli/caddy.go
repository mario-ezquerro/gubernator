package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/spf13/cobra"
)

var caddyCmd = &cobra.Command{
	Use:   "caddy",
	Short: "Manage Caddy Ingress, TLS certificates, and WAF Threat Shield",
}

var caddyWAFCmd = &cobra.Command{
	Use:   "waf",
	Short: "Manage Web Application Firewall (WAF) & Threat Shield engine",
}

var caddyWAFStatusCmd = &cobra.Command{
	Use:   "status",
	Short: "Display Threat Shield global status, stats, and protected routes",
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := DoAPIRequest("GET", "/v1/caddy/waf/stats", nil)
		if err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer func() { _ = resp.Body.Close() }()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			_, _ = fmt.Fprintf(os.Stderr, "Failed to fetch WAF stats: %s\n", string(body))
			os.Exit(1)
		}

		var stats map[string]interface{}
		if err := json.NewDecoder(resp.Body).Decode(&stats); err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "Failed to parse response: %v\n", err)
			os.Exit(1)
		}

		enabled, _ := stats["waf_enabled"].(bool)
		statusStr := "🔴 DISABLED"
		if enabled {
			statusStr = "🟢 ACTIVE (ENFORCING)"
			if stats["waf_mode"] == "detection" {
				statusStr = "🟡 ACTIVE (DETECTION ONLY)"
			}
		}

		fmt.Println("🛡️  Gubernator Caddy Threat Shield & WAF Engine")
		fmt.Println("==================================================")
		fmt.Printf("Status:             %s\n", statusStr)
		fmt.Printf("Default Mode:       %v\n", stats["waf_mode"])
		fmt.Printf("Paranoia Level:     %v\n", stats["paranoia_level"])
		fmt.Printf("Requests Evaluated: %v\n", stats["total_requests_evaluated"])
		fmt.Printf("Blocked Attacks:    %v\n", stats["total_blocked_attacks"])
		fmt.Printf("Blacklisted IPs:    %v\n", stats["blacklisted_ips_count"])
		fmt.Println("--------------------------------------------------")
		fmt.Println("Threat Vectors Protected:")
		fmt.Printf("  • SQLi (SQL Injection):       %v\n", stats["block_sqli"])
		fmt.Printf("  • XSS (Cross-Site Scripting): %v\n", stats["block_xss"])
		fmt.Printf("  • RCE / Log4j:                %v\n", stats["block_rce"])
		fmt.Printf("  • Path Traversal / LFI:       %v\n", stats["block_lfi"])
		fmt.Printf("  • Scanners & Automated Bots:  %v\n", stats["block_scanners"])
		fmt.Println("--------------------------------------------------")

		// List per-route overrides
		routeResp, err := DoAPIRequest("GET", "/v1/caddy/waf/routes", nil)
		if err == nil && routeResp.StatusCode == http.StatusOK {
			defer func() { _ = routeResp.Body.Close() }()
			var routeData struct {
				Routes []struct {
					Host         string `json:"host"`
					Enabled      bool   `json:"enabled"`
					Mode         string `json:"mode"`
					OverriddenBy string `json:"overridden_by"`
				} `json:"routes"`
			}
			if err := json.NewDecoder(routeResp.Body).Decode(&routeData); err == nil && len(routeData.Routes) > 0 {
				fmt.Println("\nPer-Route Overrides (\"A Mano\" / Compose):")
				fmt.Printf("%-35s %-12s %-12s %-12s\n", "HOST", "STATUS", "MODE", "ORIGIN")
				fmt.Println(strings.Repeat("-", 75))
				for _, r := range routeData.Routes {
					rStatus := "DISABLED"
					if r.Enabled {
						rStatus = "ENABLED"
					}
					fmt.Printf("%-35s %-12s %-12s %-12s\n", r.Host, rStatus, r.Mode, r.OverriddenBy)
				}
			}
		}
	},
}

var (
	wafRouteModeFlag string
)

var caddyWAFEnableCmd = &cobra.Command{
	Use:   "enable [host]",
	Short: "Enable Threat Shield globally or for a specific ingress route",
	Run: func(cmd *cobra.Command, args []string) {
		if len(args) > 0 && strings.TrimSpace(args[0]) != "" {
			// Per-route enable
			host := strings.TrimSpace(args[0])
			mode := "enforce"
			if wafRouteModeFlag != "" {
				mode = wafRouteModeFlag
			}
			payload, _ := json.Marshal(map[string]interface{}{
				"host":    host,
				"enabled": true,
				"mode":    mode,
			})
			resp, err := DoAPIRequest("POST", "/v1/caddy/waf/routes/toggle", bytes.NewReader(payload))
			if err != nil {
				_, _ = fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
				os.Exit(1)
			}
			defer func() { _ = resp.Body.Close() }()
			if resp.StatusCode != http.StatusOK {
				body, _ := io.ReadAll(resp.Body)
				_, _ = fmt.Fprintf(os.Stderr, "Failed to enable route WAF: %s\n", string(body))
				os.Exit(1)
			}
			fmt.Printf("✅ Threat Shield manually ENABLED for route: %s (mode: %s)\n", host, mode)
			return
		}

		// Global enable
		cfgResp, err := DoAPIRequest("GET", "/v1/caddy/waf/config", nil)
		if err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "Failed to connect: %v\n", err)
			os.Exit(1)
		}
		defer func() { _ = cfgResp.Body.Close() }()
		var cfg map[string]interface{}
		_ = json.NewDecoder(cfgResp.Body).Decode(&cfg)
		cfg["enabled"] = true
		if wafRouteModeFlag != "" {
			cfg["mode"] = wafRouteModeFlag
		}

		bodyBytes, _ := json.Marshal(cfg)
		updateResp, err := DoAPIRequest("POST", "/v1/caddy/waf/config", bytes.NewReader(bodyBytes))
		if err != nil || updateResp.StatusCode != http.StatusOK {
			_, _ = fmt.Fprintf(os.Stderr, "Failed to update global WAF config\n")
			os.Exit(1)
		}
		defer func() { _ = updateResp.Body.Close() }()
		fmt.Println("✅ Threat Shield globally ENABLED across cluster Caddy Ingress.")
	},
}

var caddyWAFDisableCmd = &cobra.Command{
	Use:   "disable [host]",
	Short: "Disable Threat Shield globally or for a specific ingress route",
	Run: func(cmd *cobra.Command, args []string) {
		if len(args) > 0 && strings.TrimSpace(args[0]) != "" {
			host := strings.TrimSpace(args[0])
			payload, _ := json.Marshal(map[string]interface{}{
				"host":    host,
				"enabled": false,
				"mode":    "inherit",
			})
			resp, err := DoAPIRequest("POST", "/v1/caddy/waf/routes/toggle", bytes.NewReader(payload))
			if err != nil {
				_, _ = fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
				os.Exit(1)
			}
			defer func() { _ = resp.Body.Close() }()
			if resp.StatusCode != http.StatusOK {
				body, _ := io.ReadAll(resp.Body)
				_, _ = fmt.Fprintf(os.Stderr, "Failed to disable route WAF: %s\n", string(body))
				os.Exit(1)
			}
			fmt.Printf("🛑 Threat Shield manually DISABLED for route: %s\n", host)
			return
		}

		// Global disable
		cfgResp, err := DoAPIRequest("GET", "/v1/caddy/waf/config", nil)
		if err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "Failed to connect: %v\n", err)
			os.Exit(1)
		}
		defer func() { _ = cfgResp.Body.Close() }()
		var cfg map[string]interface{}
		_ = json.NewDecoder(cfgResp.Body).Decode(&cfg)
		cfg["enabled"] = false

		bodyBytes, _ := json.Marshal(cfg)
		updateResp, err := DoAPIRequest("POST", "/v1/caddy/waf/config", bytes.NewReader(bodyBytes))
		if err != nil || updateResp.StatusCode != http.StatusOK {
			_, _ = fmt.Fprintf(os.Stderr, "Failed to update global WAF config\n")
			os.Exit(1)
		}
		defer func() { _ = updateResp.Body.Close() }()
		fmt.Println("🛑 Threat Shield globally DISABLED.")
	},
}

var (
	wafTargetHostFlag string
)

var caddyWAFModeCmd = &cobra.Command{
	Use:   "mode <enforce|detection>",
	Short: "Switch Threat Shield operating mode (enforce or detection)",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		newMode := strings.ToLower(strings.TrimSpace(args[0]))
		if newMode != "enforce" && newMode != "detection" {
			_, _ = fmt.Fprintf(os.Stderr, "Invalid mode: %s (must be 'enforce' or 'detection')\n", newMode)
			os.Exit(1)
		}

		if wafTargetHostFlag != "" {
			payload, _ := json.Marshal(map[string]interface{}{
				"host":    wafTargetHostFlag,
				"enabled": true,
				"mode":    newMode,
			})
			resp, err := DoAPIRequest("POST", "/v1/caddy/waf/routes/toggle", bytes.NewReader(payload))
			if err != nil || resp.StatusCode != http.StatusOK {
				_, _ = fmt.Fprintf(os.Stderr, "Failed to set route mode\n")
				os.Exit(1)
			}
			defer func() { _ = resp.Body.Close() }()
			fmt.Printf("✅ Threat Shield mode for %s updated to: %s\n", wafTargetHostFlag, newMode)
			return
		}

		// Global mode
		cfgResp, err := DoAPIRequest("GET", "/v1/caddy/waf/config", nil)
		if err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "Failed to connect: %v\n", err)
			os.Exit(1)
		}
		defer func() { _ = cfgResp.Body.Close() }()
		var cfg map[string]interface{}
		_ = json.NewDecoder(cfgResp.Body).Decode(&cfg)
		cfg["mode"] = newMode

		bodyBytes, _ := json.Marshal(cfg)
		updateResp, err := DoAPIRequest("POST", "/v1/caddy/waf/config", bytes.NewReader(bodyBytes))
		if err != nil || updateResp.StatusCode != http.StatusOK {
			_, _ = fmt.Fprintf(os.Stderr, "Failed to update global mode\n")
			os.Exit(1)
		}
		defer func() { _ = updateResp.Body.Close() }()
		fmt.Printf("✅ Global Threat Shield mode updated to: %s\n", newMode)
	},
}

var caddyWAFIPCmd = &cobra.Command{
	Use:   "ip",
	Short: "Manage IP blacklist and whitelist filters",
}

var caddyWAFIPBlockCmd = &cobra.Command{
	Use:   "block <ip> [reason]",
	Short: "Add an IP address or CIDR subnet to the Threat Shield blacklist",
	Args:  cobra.MinimumNArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		ip := strings.TrimSpace(args[0])
		reason := "Blocked via CLI"
		if len(args) > 1 {
			reason = strings.Join(args[1:], " ")
		}

		payload, _ := json.Marshal(map[string]string{
			"ip":     ip,
			"reason": reason,
		})
		resp, err := DoAPIRequest("POST", "/v1/caddy/waf/ip/block", bytes.NewReader(payload))
		if err != nil || resp.StatusCode != http.StatusOK {
			_, _ = fmt.Fprintf(os.Stderr, "Failed to block IP %s\n", ip)
			os.Exit(1)
		}
		defer func() { _ = resp.Body.Close() }()
		fmt.Printf("🚫 IP %s has been added to Threat Shield blacklist (reason: %s)\n", ip, reason)
	},
}

var caddyWAFIPUnblockCmd = &cobra.Command{
	Use:   "unblock <ip>",
	Short: "Remove an IP address or CIDR subnet from the Threat Shield blacklist",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		ip := strings.TrimSpace(args[0])
		payload, _ := json.Marshal(map[string]string{"ip": ip})
		resp, err := DoAPIRequest("POST", "/v1/caddy/waf/ip/unblock", bytes.NewReader(payload))
		if err != nil || resp.StatusCode != http.StatusOK {
			_, _ = fmt.Fprintf(os.Stderr, "Failed to unblock IP %s\n", ip)
			os.Exit(1)
		}
		defer func() { _ = resp.Body.Close() }()
		fmt.Printf("✅ IP %s removed from Threat Shield blacklist\n", ip)
	},
}

var (
	wafEventLimitFlag int
	wafEventTypeFlag  string
	wafEventHostFlag  string
)

var caddyWAFEventsCmd = &cobra.Command{
	Use:   "events",
	Short: "List intercepted security threat events and attack logs",
	Run: func(cmd *cobra.Command, args []string) {
		url := fmt.Sprintf("/v1/caddy/waf/events?limit=%d", wafEventLimitFlag)
		if wafEventTypeFlag != "" {
			url += "&type=" + wafEventTypeFlag
		}
		if wafEventHostFlag != "" {
			url += "&host=" + wafEventHostFlag
		}

		resp, err := DoAPIRequest("GET", url, nil)
		if err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "Failed to connect: %v\n", err)
			os.Exit(1)
		}
		defer func() { _ = resp.Body.Close() }()

		var data struct {
			Events []struct {
				ID         string    `json:"id"`
				Timestamp  time.Time `json:"timestamp"`
				ClientIP   string    `json:"client_ip"`
				Host       string    `json:"host"`
				URI        string    `json:"uri"`
				AttackType string    `json:"attack_type"`
				RuleID     string    `json:"rule_id"`
				Severity   string    `json:"severity"`
				Action     string    `json:"action"`
				Details    string    `json:"details"`
			} `json:"events"`
		}

		if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "Failed to decode events: %v\n", err)
			os.Exit(1)
		}

		if len(data.Events) == 0 {
			fmt.Println("No security threat events recorded.")
			return
		}

		fmt.Printf("%-20s %-15s %-25s %-10s %-8s %-10s %-30s\n", "TIMESTAMP", "CLIENT IP", "HOST / URI", "ATTACK", "RULE", "ACTION", "DETAILS")
		fmt.Println(strings.Repeat("-", 125))
		for _, e := range data.Events {
			target := fmt.Sprintf("%s%s", e.Host, e.URI)
			if len(target) > 24 {
				target = target[:21] + "..."
			}
			details := e.Details
			if len(details) > 30 {
				details = details[:27] + "..."
			}
			fmt.Printf("%-20s %-15s %-25s %-10s %-8s %-10s %-30s\n",
				e.Timestamp.Format("2006-01-02 15:04:05"),
				e.ClientIP,
				target,
				e.AttackType,
				e.RuleID,
				e.Action,
				details,
			)
		}
	},
}

var wafTestVectorFlag string

var caddyWAFTestCmd = &cobra.Command{
	Use:   "test <host>",
	Short: "Simulate a security attack probe to test Threat Shield interception",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		host := strings.TrimSpace(args[0])
		vector := "SQLI"
		if wafTestVectorFlag != "" {
			vector = strings.ToUpper(wafTestVectorFlag)
		}

		payload, _ := json.Marshal(map[string]string{
			"host":   host,
			"vector": vector,
		})
		resp, err := DoAPIRequest("POST", "/v1/caddy/waf/test", bytes.NewReader(payload))
		if err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "Failed to connect: %v\n", err)
			os.Exit(1)
		}
		defer func() { _ = resp.Body.Close() }()

		var result struct {
			Message string `json:"message"`
			Event   struct {
				ID         string `json:"id"`
				AttackType string `json:"attack_type"`
				RuleID     string `json:"rule_id"`
				Severity   string `json:"severity"`
				Action     string `json:"action"`
				Details    string `json:"details"`
			} `json:"event"`
		}

		_ = json.NewDecoder(resp.Body).Decode(&result)
		fmt.Println("🧪 Threat Shield Attack Probe Result:")
		fmt.Printf("  • Target Host:   %s\n", host)
		fmt.Printf("  • Vector Tested: %s\n", vector)
		fmt.Printf("  • Rule Trigger:  %s (%s)\n", result.Event.RuleID, result.Event.AttackType)
		fmt.Printf("  • Action Taken:  %s\n", result.Event.Action)
		fmt.Printf("  • Details:       %s\n", result.Event.Details)
		if result.Event.Action == "BLOCKED" {
			fmt.Println("🛡️  PASS: Threat was successfully intercepted and blocked with 403!")
		} else {
			fmt.Println("⚠️  DETECT: Threat was detected and logged (detection mode).")
		}
	},
}

func init() {
	caddyWAFEnableCmd.Flags().StringVar(&wafRouteModeFlag, "mode", "enforce", "Operating mode (enforce or detection)")
	caddyWAFModeCmd.Flags().StringVar(&wafTargetHostFlag, "host", "", "Target specific route hostname")

	caddyWAFIPCmd.AddCommand(caddyWAFIPBlockCmd)
	caddyWAFIPCmd.AddCommand(caddyWAFIPUnblockCmd)

	caddyWAFEventsCmd.Flags().IntVar(&wafEventLimitFlag, "limit", 25, "Maximum number of events to show")
	caddyWAFEventsCmd.Flags().StringVar(&wafEventTypeFlag, "type", "", "Filter by attack type (SQLI, XSS, RCE, LFI, SCANNER)")
	caddyWAFEventsCmd.Flags().StringVar(&wafEventHostFlag, "host", "", "Filter by hostname")

	caddyWAFTestCmd.Flags().StringVar(&wafTestVectorFlag, "vector", "SQLI", "Attack vector (SQLI, XSS, RCE, LFI, SCANNER)")

	caddyWAFCmd.AddCommand(caddyWAFStatusCmd)
	caddyWAFCmd.AddCommand(caddyWAFEnableCmd)
	caddyWAFCmd.AddCommand(caddyWAFDisableCmd)
	caddyWAFCmd.AddCommand(caddyWAFModeCmd)
	caddyWAFCmd.AddCommand(caddyWAFIPCmd)
	caddyWAFCmd.AddCommand(caddyWAFEventsCmd)
	caddyWAFCmd.AddCommand(caddyWAFTestCmd)

	caddyCmd.AddCommand(caddyWAFCmd)
	rootCmd.AddCommand(caddyCmd)
}
