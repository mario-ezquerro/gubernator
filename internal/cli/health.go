package cli

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"

	"github.com/spf13/cobra"
)

var healthCmd = &cobra.Command{
	Use:   "health",
	Short: "Check the health of the local Gubernator process",
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := http.Get("http://localhost:4002/health")
		if err != nil {
			fmt.Printf("Gubernator is unhealthy: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			fmt.Printf("Gubernator is unhealthy (HTTP %d)\n", resp.StatusCode)
			os.Exit(1)
		}

		var healthStatus struct {
			Status string `json:"status"`
		}
		if err := json.NewDecoder(resp.Body).Decode(&healthStatus); err != nil {
			fmt.Printf("Failed to parse health response: %v\n", err)
			os.Exit(1)
		}

		if healthStatus.Status != "healthy" {
			fmt.Printf("Gubernator is unhealthy (Status: %s)\n", healthStatus.Status)
			os.Exit(1)
		}

		fmt.Println("Gubernator is healthy")
	},
}

func init() {
	rootCmd.AddCommand(healthCmd)
}
