package cli

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"

	"github.com/spf13/cobra"
)

type sloItem struct {
	ServiceID            string  `json:"service_id"`
	ServiceName          string  `json:"service_name"`
	StackID              string  `json:"stack_id"`
	Target               float64 `json:"target"`
	Window               string  `json:"window"`
	ErrorBudgetRemaining float64 `json:"error_budget_remaining"`
	BurnRate             float64 `json:"burn_rate"`
	Status               string  `json:"status"`
}

var sloCmd = &cobra.Command{
	Use:   "slo",
	Short: "Manage Service Level Objectives (SLOs) and Error Budgets",
}

var sloLsCmd = &cobra.Command{
	Use:   "ls",
	Short: "List active SLOs and error budget metrics",
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := DoAPIRequest("GET", "/v1/slo/ls", nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			fmt.Fprintf(os.Stderr, "Failed to fetch SLOs: %s\n", string(body))
			os.Exit(1)
		}

		var items []sloItem
		if err := json.NewDecoder(resp.Body).Decode(&items); err != nil {
			fmt.Fprintf(os.Stderr, "Failed to parse response: %v\n", err)
			os.Exit(1)
		}

		if len(items) == 0 {
			fmt.Println("No active SLOs configured on services.")
			return
		}

		fmt.Printf("%-20s %-15s %-10s %-10s %-20s %-12s %-10s\n", "SERVICE", "STACK", "TARGET", "WINDOW", "ERROR BUDGET REMAINING", "BURN RATE", "STATUS")
		fmt.Println("----------------------------------------------------------------------------------------------------")
		for _, item := range items {
			fmt.Printf("%-20s %-15s %-10.1f%% %-10s %-20.2f%% %-12.2fx %-10s\n",
				item.ServiceName, item.StackID, item.Target, item.Window, item.ErrorBudgetRemaining, item.BurnRate, stringsToUpper(item.Status))
		}
	},
}

var sloSyncCmd = &cobra.Command{
	Use:   "sync",
	Short: "Synchronize SLO rules to Prometheus",
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := DoAPIRequest("POST", "/v1/slo/sync", nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			fmt.Fprintf(os.Stderr, "Failed to sync SLOs: %s\n", string(body))
			os.Exit(1)
		}

		fmt.Println("✅ SLO rules successfully generated and synced to Prometheus!")
	},
}

func stringsToUpper(s string) string {
	switch s {
	case "healthy":
		return "HEALTHY 🟢"
	case "warning":
		return "WARNING 🟡"
	case "exhausted":
		return "EXHAUSTED 🔴"
	default:
		return s
	}
}

func init() {
	sloCmd.AddCommand(sloLsCmd)
	sloCmd.AddCommand(sloSyncCmd)
	rootCmd.AddCommand(sloCmd)
}
