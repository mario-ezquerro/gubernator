package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"text/tabwriter"

	"github.com/mario-ezquerro/gubernator/internal/db"
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
		resp, err := http.Post(GetAPIEndpoint() + "/v1/stack/deploy", "application/json", bytes.NewBuffer(body))
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

var stackLsCmd = &cobra.Command{
	Use:   "ls",
	Short: "List stacks",
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := http.Get(GetAPIEndpoint() + "/v1/stack/ls")
		if err != nil {
			fmt.Printf("Failed to fetch stacks: %v\n", err)
			return
		}
		defer resp.Body.Close()

		var stacks []db.Stack
		json.NewDecoder(resp.Body).Decode(&stacks)

		w := tabwriter.NewWriter(os.Stdout, 0, 0, 3, ' ', 0)
		fmt.Fprintln(w, "ID\tNAME\tDEPLOYED")
		for _, s := range stacks {
			fmt.Fprintf(w, "%s\t%s\t%s\n", s.ID[:8], s.Name, s.CreatedAt.Format("2006-01-02 15:04"))
		}
		w.Flush()
	},
}

var stackServicesCmd = &cobra.Command{
	Use:   "services [stack_id]",
	Short: "List the services in the stack",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := http.Get(GetAPIEndpoint() + "/v1/stack/" + args[0] + "/services")
		if err != nil {
			fmt.Printf("Failed to fetch services: %v\n", err)
			return
		}
		defer resp.Body.Close()

		var services []db.Service
		json.NewDecoder(resp.Body).Decode(&services)

		w := tabwriter.NewWriter(os.Stdout, 0, 0, 3, ' ', 0)
		fmt.Fprintln(w, "ID\tNAME\tIMAGE\tREPLICAS")
		for _, s := range services {
			fmt.Fprintf(w, "%s\t%s\t%s\t%d\n", s.ID[:8], s.Name, s.Image, s.DesiredReplicas)
		}
		w.Flush()
	},
}

var stackRmCmd = &cobra.Command{
	Use:   "rm [stack_id]",
	Short: "Remove one or more stacks",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		req, _ := http.NewRequest("DELETE", GetAPIEndpoint() + "/v1/stack/"+args[0], nil)
		resp, err := http.DefaultClient.Do(req)
		if err == nil && resp.StatusCode == 200 {
			fmt.Printf("Stack %s removed\n", args[0])
		} else {
			fmt.Printf("Failed to remove stack\n")
		}
	},
}

func init() {
	rootCmd.AddCommand(stackCmd)
	stackCmd.AddCommand(stackDeployCmd)
	stackCmd.AddCommand(stackLsCmd)
	stackCmd.AddCommand(stackServicesCmd)
	stackCmd.AddCommand(stackRmCmd)

	stackDeployCmd.Flags().StringVarP(&composeFile, "compose-file", "c", "", "Path to a Compose file")
}


