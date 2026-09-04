package cli

import (
	"fmt"
	"os"
	"strings"

	"github.com/mario-ezquerro/gubernator/internal/monitor"
	"github.com/spf13/cobra"
)

var monitorCmd = &cobra.Command{
	Use:   "monitor",
	Short: "Manage the SRE observability stack (Prometheus, Grafana, Loki, cAdvisor)",
	Long: `Deploy and manage a production-grade SRE monitoring stack on your Gubernator cluster.

On the Manager node, 'gbnt monitor init' deploys the full observability stack:
  • cAdvisor    — Container resource metrics   (:8081)
  • Prometheus  — Metrics collection           (:9090)
  • Grafana     — Dashboards & visualization   (:3000)
  • Loki        — Log aggregation              (:3100)
  • Promtail    — Log shipping agent`,
}

var monitorInitCmd = &cobra.Command{
	Use:   "init",
	Short: "Deploy the full SRE monitoring stack on this Manager node",
	Long: `Initializes the Gubernator SRE monitoring stack by deploying five containers:

  1. cAdvisor    — Collects container CPU, memory, disk, and network metrics
  2. Prometheus  — Scrapes metrics from Gubernator (:4002), cAdvisor, and workers
  3. Loki        — Aggregates logs from all nodes via Promtail
  4. Promtail    — Ships local container and system logs to Loki
  5. Grafana     — Pre-configured dashboards with Prometheus and Loki datasources

All containers run on a dedicated Docker network (gbnt-monitor-net) and persist
their configuration in ~/.gbnt/monitor/.

Access points after deployment:
  • Grafana:    http://localhost:3000  (admin/admin)
  • Prometheus: http://localhost:9090
  • Loki:       http://localhost:3100`,
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("🛡️  Gubernator SRE Monitor — Initializing...")
		fmt.Println()

		// 1. Create Docker network
		if err := monitor.EnsureNetwork(); err != nil {
			fmt.Fprintf(os.Stderr, "❌ Failed to create network: %v\n", err)
			os.Exit(1)
		}

		webUser := os.Getenv("GBNT_WEB_USER")
		webPass := os.Getenv("GBNT_WEB_PASSWORD")
		if webUser == "" {
			webUser = "admin"
		}
		if webPass == "" {
			webPass = "admin"
		}

		if monitorProfileFlag != "" && monitorProfileFlag != "cloud-native" {
			if err := monitor.SwitchProfile(monitorProfileFlag, webUser, webPass); err != nil {
				fmt.Fprintf(os.Stderr, "\n❌ Deployment failed for profile %s: %v\n", monitorProfileFlag, err)
				os.Exit(1)
			}
		} else {
			// 2. Generate config files
			if err := monitor.WriteConfigs(nil); err != nil {
				fmt.Fprintf(os.Stderr, "❌ Failed to write configs: %v\n", err)
				os.Exit(1)
			}

			// 3. Deploy all containers (pass Gubernator web credentials for Grafana SSO)
			if err := monitor.DeployManagerStack(webUser, webPass); err != nil {
				fmt.Fprintf(os.Stderr, "\n❌ Deployment failed: %v\n", err)
				fmt.Fprintln(os.Stderr, "Run 'gbnt monitor stop' to clean up partially deployed containers.")
				os.Exit(1)
			}
			_ = monitor.SetActiveProfile("cloud-native")
		}

		fmt.Println()
		fmt.Println("═══════════════════════════════════════════════════════════")
		fmt.Println("  ✅ SRE Monitoring Stack deployed successfully!")
		fmt.Println()
		fmt.Printf("  📈 Grafana:     http://localhost:3000   (%s/***)\n", webUser)
		fmt.Println("  🔥 Prometheus:  http://localhost:9090")
		fmt.Println("  📋 Loki:        http://localhost:3100")
		fmt.Println("  📊 cAdvisor:    http://localhost:8081")
		fmt.Println()
		fmt.Println("  Run 'gbnt monitor status' to check container health.")
		fmt.Println("  Run 'gbnt monitor stop'   to tear down the stack.")
		fmt.Println("═══════════════════════════════════════════════════════════")
	},
}

var monitorStatusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show the status of all monitoring containers",
	Run: func(cmd *cobra.Command, args []string) {
		monitor.Status()
	},
}

var monitorStopCmd = &cobra.Command{
	Use:   "stop",
	Short: "Stop and remove all monitoring containers",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("🛡️  Gubernator SRE Monitor — Stopping...")
		fmt.Println()
		monitor.StopAll()
		fmt.Println()
		fmt.Println("✅ All monitoring containers stopped and removed.")
	},
}

var monitorScopeCmd = &cobra.Command{
	Use:   "scope",
	Short: "Manage Network Topology & Container Graphics (Weave Scope)",
	Long: `Weave Scope provides an interactive, real-time visualization of container networks,
processes, Docker sockets, and open ports.

Disabled by default for performance. Use 'gbnt monitor scope start' to enable.`,
}

var monitorScopeStatusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show status of Weave Scope Network Topology",
	Run: func(cmd *cobra.Command, args []string) {
		status := monitor.GetScopeStatus("")
		fmt.Printf("🕸️  Network Topology (Weave Scope): %s (Container: %s, Port: %s)\n",
			status.Status, status.Container, status.Port)
		if status.Enabled {
			fmt.Printf("   URL: %s\n", status.URL)
		}
	},
}

var monitorScopeStartCmd = &cobra.Command{
	Use:     "start",
	Aliases: []string{"enable", "deploy"},
	Short:   "Start Weave Scope container for Network Topology visualization",
	Run: func(cmd *cobra.Command, args []string) {
		if err := monitor.EnableScope(); err != nil {
			fmt.Fprintf(os.Stderr, "❌ Failed to start Weave Scope: %v\n", err)
			os.Exit(1)
		}
	},
}

var monitorScopeStopCmd = &cobra.Command{
	Use:     "stop",
	Aliases: []string{"disable"},
	Short:   "Stop and remove Weave Scope Network Topology container",
	Run: func(cmd *cobra.Command, args []string) {
		if err := monitor.DisableScope(); err != nil {
			fmt.Fprintf(os.Stderr, "❌ Failed to stop Weave Scope: %v\n", err)
			os.Exit(1)
		}
	},
}

var monitorProfilesCmd = &cobra.Command{
	Use:   "profiles",
	Short: "List all SRE Observability architecture profiles and sizing recommendations",
	Run: func(cmd *cobra.Command, args []string) {
		profiles := monitor.ListProfiles()
		active := monitor.GetActiveProfile()
		fmt.Println("\n🛡️  Gubernator SRE Observability Profiles")
		fmt.Println(strings.Repeat("═", 100))
		for _, p := range profiles {
			statusMark := "  "
			if p.ID == active {
				statusMark = "✓ "
			}
			fmt.Printf("%s[%s] %s (%s)\n", statusMark, p.ID, p.Name, p.Subtitle)
			fmt.Printf("   🏷️  Hosts: %s   | 📦 Contenedores: %s   | 💾 RAM: %s\n",
				p.RecommendedHosts, p.RecommendedContainers, p.RecommendedRAM)
			fmt.Printf("   📝 Entorno ideal: %s\n", p.IdealEnvironment)
			fmt.Println(strings.Repeat("─", 100))
		}
		fmt.Printf("Active Profile: %s\n", active)
		fmt.Println("To switch profile: gbnt monitor switch <profile_id>")
		fmt.Println()
	},
}

var monitorSwitchCmd = &cobra.Command{
	Use:   "switch [profile_id]",
	Short: "Switch the active SRE Observability stack architecture profile",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		targetID := args[0]
		webUser := os.Getenv("GBNT_WEB_USER")
		webPass := os.Getenv("GBNT_WEB_PASSWORD")
		if webUser == "" {
			webUser = "admin"
		}
		if webPass == "" {
			webPass = "admin"
		}
		if err := monitor.SwitchProfile(targetID, webUser, webPass); err != nil {
			fmt.Fprintf(os.Stderr, "❌ Failed to switch SRE profile: %v\n", err)
			os.Exit(1)
		}
	},
}

var monitorProfileFlag string

func init() {
	rootCmd.AddCommand(monitorCmd)
	monitorCmd.AddCommand(monitorInitCmd)
	monitorCmd.AddCommand(monitorStatusCmd)
	monitorCmd.AddCommand(monitorStopCmd)
	monitorCmd.AddCommand(monitorProfilesCmd)
	monitorCmd.AddCommand(monitorSwitchCmd)

	monitorInitCmd.Flags().StringVarP(&monitorProfileFlag, "profile", "p", "cloud-native", "Observability architecture profile (ultra-light, cloud-native, unified-otel, enterprise-elk, external-saas)")

	monitorCmd.AddCommand(monitorScopeCmd)
	monitorScopeCmd.AddCommand(monitorScopeStatusCmd)
	monitorScopeCmd.AddCommand(monitorScopeStartCmd)
	monitorScopeCmd.AddCommand(monitorScopeStopCmd)
}
