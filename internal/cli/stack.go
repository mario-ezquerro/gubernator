package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"

	"github.com/spf13/cobra"
)

var stackCmd = &cobra.Command{
	Use:   "stack",
	Short: "Manage Docker Compose stacks (The Legions)",
}

var composeFile string

var stackDeployCmd = &cobra.Command{
	Use:   "deploy [name]",
	Short: "Deploy a new stack from a docker-compose.yml file",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		name := args[0]

		if composeFile == "" {
			fmt.Fprintln(os.Stderr, "Error: -c/--compose flag is required")
			cmd.Help()
			os.Exit(1)
		}

		yamlData, err := os.ReadFile(composeFile)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to read compose file: %v\n", err)
			os.Exit(1)
		}

		payload := map[string]string{
			"name":        name,
			"compose_raw": string(yamlData),
		}

		body, _ := json.Marshal(payload)
		resp, err := http.Post("http://localhost:4000/v1/stack/deploy", "application/json", bytes.NewBuffer(body))
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reaching API: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			bodyBytes, _ := io.ReadAll(resp.Body)
			fmt.Fprintf(os.Stderr, "Failed to deploy stack: %s\n", string(bodyBytes))
			os.Exit(1)
		}

		fmt.Printf("🚀 Stack '%s' deployed successfully!\n", name)
		fmt.Println("The Governor has dispatched the Centurions to schedule the tasks.")
	},
}

func init() {
	rootCmd.AddCommand(stackCmd)
	stackCmd.AddCommand(stackDeployCmd)

	stackDeployCmd.Flags().StringVarP(&composeFile, "compose", "c", "", "Path to the docker-compose.yml file")
}
