package cli

import (
	"fmt"
	"os"
	"strings"

	"github.com/mario-ezquerro/gubernator/internal/coredns"
	"github.com/spf13/cobra"
)

var dnsCmd = &cobra.Command{
	Use:   "dns",
	Short: "Manage the Gubernator CoreDNS service (*.gbnt resolution)",
	Long: `Manage CoreDNS — the built-in DNS server for Gubernator-managed containers.

CoreDNS is automatically started when 'gbnt serve' runs. It serves the .gbnt
domain so that all containers on gbnt-net can resolve each other by name.

DNS name format:
  <service>.<stack>.gbnt          → resolves to the first replica of the service
  <task-id>.<service>.<stack>.gbnt → resolves to a specific container

Examples:
  web-nginx.my-app.gbnt           → IP of the web-nginx service in the my-app stack
  api.backend.gbnt                → IP of the api service in the backend stack

The hosts file is regenerated automatically every time a container starts or stops.
CoreDNS reloads it within 3 seconds (auto-reload) or immediately via 'gbnt dns reload'.`,
}

var dnsStatusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show the status of the CoreDNS container",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("🌐 Gubernator CoreDNS Status")
		fmt.Println(strings.Repeat("─", 60))

		status := coredns.Status()
		if status == "not running" {
			fmt.Println("  ❌ gbnt-coredns   not running")
		} else {
			parts := strings.SplitN(status, " | ", 2)
			containerStatus := parts[0]
			ip := ""
			if len(parts) > 1 {
				ip = parts[1]
			}
			icon := "✅"
			if containerStatus != "running" {
				icon = "⚠️"
			}
			fmt.Printf("  %s %-20s  status=%-10s  ip=%s\n", icon, "gbnt-coredns", containerStatus, ip)
		}

		fmt.Println()
		fmt.Printf("  📁 Config dir:   %s\n", coredns.CoreDNSDir())
		fmt.Printf("  📄 Hosts file:   %s\n", coredns.HostsFilePath())
		fmt.Printf("  🔗 Network:      %s\n", coredns.NetworkName)
		fmt.Println()
	},
}

var dnsStartCmd = &cobra.Command{
	Use:   "start",
	Short: "Start the CoreDNS container (if not already running)",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("🌐 Starting CoreDNS...")

		if err := coredns.EnsureNetwork(); err != nil {
			fmt.Fprintf(os.Stderr, "❌ Failed to create gbnt-net: %v\n", err)
			os.Exit(1)
		}

		if err := coredns.EnsureRunning(); err != nil {
			fmt.Fprintf(os.Stderr, "❌ Failed to start CoreDNS: %v\n", err)
			os.Exit(1)
		}
	},
}

var dnsStopCmd = &cobra.Command{
	Use:   "stop",
	Short: "Stop and remove the CoreDNS container",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("🌐 Stopping CoreDNS...")
		coredns.Stop()
		fmt.Println("✅ CoreDNS stopped.")
	},
}

var dnsReloadCmd = &cobra.Command{
	Use:   "reload",
	Short: "Force CoreDNS to reload the hosts file immediately",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("🔄 Reloading CoreDNS configuration...")
		if err := coredns.ReloadConfig(); err != nil {
			fmt.Fprintf(os.Stderr, "❌ Reload failed: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("✅ CoreDNS reloaded.")
	},
}

var dnsLsCmd = &cobra.Command{
	Use:   "ls",
	Short: "List all active DNS records in the gubernator.hosts file",
	Run: func(cmd *cobra.Command, args []string) {
		hostsPath := coredns.HostsFilePath()
		content, err := os.ReadFile(hostsPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "❌ Failed to read hosts file: %v\n", err)
			fmt.Fprintf(os.Stderr, "   (Is Gubernator running? Expected at: %s)\n", hostsPath)
			os.Exit(1)
		}

		fmt.Println("🌐 Gubernator DNS Records")
		fmt.Println(strings.Repeat("─", 60))
		fmt.Printf("  %-18s  %s\n", "IP ADDRESS", "HOSTNAME")
		fmt.Println(strings.Repeat("─", 60))

		lines := strings.Split(string(content), "\n")
		count := 0
		for _, line := range lines {
			line = strings.TrimSpace(line)
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}
			fields := strings.Fields(line)
			if len(fields) >= 2 {
				fmt.Printf("  %-18s  %s\n", fields[0], fields[1])
				count++
			}
		}

		if count == 0 {
			fmt.Println("  (no records — deploy a stack to see DNS entries)")
		}

		fmt.Println(strings.Repeat("─", 60))
		fmt.Printf("  Total: %d record(s)\n\n", count)
	},
}

func init() {
	rootCmd.AddCommand(dnsCmd)
	dnsCmd.AddCommand(dnsStatusCmd)
	dnsCmd.AddCommand(dnsStartCmd)
	dnsCmd.AddCommand(dnsStopCmd)
	dnsCmd.AddCommand(dnsReloadCmd)
	dnsCmd.AddCommand(dnsLsCmd)
}
