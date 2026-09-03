package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"text/tabwriter"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/mario-ezquerro/gubernator/internal/examples"
	"github.com/spf13/cobra"
)

var stackCmd = &cobra.Command{
	Use:   "stack",
	Short: "Manage Docker Compose stacks (The Legions)",
}

var (
	composeFile       string
	serverComposeFile string
	serverDirFilter   string
)

var stackDeployCmd = &cobra.Command{
	Use:   "deploy [name]",
	Short: "Deploy a new stack from a local compose file or Master server file (name is optional if defined in compose)",
	Args:  cobra.MaximumNArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		name := ""
		if len(args) > 0 {
			name = args[0]
		}

		// Option 1: Deploy from Master server filesystem
		if serverComposeFile != "" {
			payload := map[string]string{
				"path": serverComposeFile,
				"name": name,
			}
			body, _ := json.Marshal(payload)
			resp, err := DoAPIRequest("POST", "/v1/stack/server-deploy", bytes.NewBuffer(body))
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error reaching API: %v\n", err)
				os.Exit(1)
			}
			defer resp.Body.Close()

			if resp.StatusCode != http.StatusOK {
				bodyBytes, _ := io.ReadAll(resp.Body)
				var errResp map[string]string
				if err := json.Unmarshal(bodyBytes, &errResp); err == nil && errResp["error"] != "" {
					fmt.Fprintf(os.Stderr, "Failed to deploy stack from server: %s\n", errResp["error"])
				} else {
					fmt.Fprintf(os.Stderr, "Failed to deploy stack from server: %s\n", string(bodyBytes))
				}
				os.Exit(1)
			}

			bodyBytes, _ := io.ReadAll(resp.Body)
			var successResp map[string]interface{}
			json.Unmarshal(bodyBytes, &successResp)
			resolvedName := name
			if n, ok := successResp["name"].(string); ok && n != "" {
				resolvedName = n
			}

			fmt.Printf("🚀 Stack '%s' deployed successfully from Master server (%s)!\n", resolvedName, serverComposeFile)
			fmt.Println("The Governor has dispatched the Centurions to schedule the tasks.")
			return
		}

		// Option 2: Deploy from client local machine file
		if composeFile == "" {
			fmt.Fprintln(os.Stderr, "Error: -c/--compose-file or -s/--from-server flag is required")
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
		resp, err := DoAPIRequest("POST", "/v1/stack/deploy", bytes.NewBuffer(body))
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reaching API: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			bodyBytes, _ := io.ReadAll(resp.Body)
			var errResp map[string]string
			if err := json.Unmarshal(bodyBytes, &errResp); err == nil && errResp["error"] != "" {
				fmt.Fprintf(os.Stderr, "Failed to deploy stack: %s\n", errResp["error"])
			} else {
				fmt.Fprintf(os.Stderr, "Failed to deploy stack: %s\n", string(bodyBytes))
			}
			os.Exit(1)
		}

		bodyBytes, _ := io.ReadAll(resp.Body)
		var successResp map[string]interface{}
		json.Unmarshal(bodyBytes, &successResp)
		resolvedName := name
		if n, ok := successResp["name"].(string); ok && n != "" {
			resolvedName = n
		}

		fmt.Printf("🚀 Stack '%s' deployed successfully!\n", resolvedName)
		fmt.Println("The Governor has dispatched the Centurions to schedule the tasks.")
	},
}

var stackServerLsCmd = &cobra.Command{
	Use:   "server-ls",
	Short: "List Compose stack files discovered on the Master server filesystem",
	Run: func(cmd *cobra.Command, args []string) {
		endpoint := "/v1/stack/server-files"
		if serverDirFilter != "" {
			endpoint += "?dir=" + serverDirFilter
		}

		var files []examples.ServerStackFile
		var stacksDir, examplesDir string

		resp, err := DoAPIRequestWithTimeout("GET", endpoint, nil, 1*time.Second)
		if err == nil && resp.StatusCode == http.StatusOK {
			defer resp.Body.Close()
			var data struct {
				Files       []examples.ServerStackFile `json:"files"`
				StacksDir   string                     `json:"stacks_dir"`
				ExamplesDir string                     `json:"examples_dir"`
			}
			if err := json.NewDecoder(resp.Body).Decode(&data); err == nil {
				files = data.Files
				stacksDir = data.StacksDir
				examplesDir = data.ExamplesDir
			}
		}

		if len(files) == 0 && stacksDir == "" {
			// Graceful offline fallback: scan local host directly
			stacksDir = examples.DefaultServerStacksDir()
			examplesDir = examples.DefaultServerExamplesDir()
			files, _ = examples.ListServerStackFiles(serverDirFilter)
		}

		fmt.Println("🖥️ Master Server Stack Files:")
		fmt.Printf("  • User Stacks Dir: %s\n", stacksDir)
		fmt.Printf("  • Examples Dir:    %s\n\n", examplesDir)

		if len(files) == 0 {
			fmt.Println("  (No compose files found. Drop .yml files into the stacks dir above)")
			return
		}

		w := tabwriter.NewWriter(os.Stdout, 0, 0, 3, ' ', 0)
		fmt.Fprintln(w, "FILE\tINFERRED NAME\tSERVICES\tTYPE\tSERVER PATH")
		for _, f := range files {
			fileType := "Custom Stack"
			if f.IsExample {
				fileType = "POC Example"
			}
			fmt.Fprintf(w, "%s\t%s\t%d\t%s\t%s\n", f.Filename, f.InferredName, f.Services, fileType, f.Path)
		}
		w.Flush()
		fmt.Println("\nDeploy any server stack with: gbnt stack deploy --from-server <SERVER-PATH>")
	},
}

var stackLsCmd = &cobra.Command{
	Use:   "ls",
	Short: "List stacks",
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := DoAPIRequest("GET", "/v1/stack/ls", nil)
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
		resp, err := DoAPIRequest("GET", "/v1/stack/"+args[0]+"/services", nil)
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
		resp, err := DoAPIRequest("DELETE", "/v1/stack/"+args[0], nil)
		if err == nil && resp.StatusCode == 200 {
			fmt.Printf("Stack %s removed\n", args[0])
		} else {
			fmt.Printf("Failed to remove stack\n")
		}
	},
}

var stackStopCmd = &cobra.Command{
	Use:   "stop [stack_id]",
	Short: "Stop all running containers in a stack without deleting it",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := DoAPIRequest("POST", "/v1/stack/"+args[0]+"/stop", nil)
		if err == nil && resp.StatusCode == 200 {
			fmt.Printf("Stack %s stopped\n", args[0])
		} else {
			fmt.Printf("Failed to stop stack %s\n", args[0])
		}
	},
}

var stackStartCmd = &cobra.Command{
	Use:   "start [stack_id]",
	Short: "Start all containers in a stopped stack",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := DoAPIRequest("POST", "/v1/stack/"+args[0]+"/start", nil)
		if err == nil && resp.StatusCode == 200 {
			fmt.Printf("Stack %s started\n", args[0])
		} else {
			fmt.Printf("Failed to start stack %s\n", args[0])
		}
	},
}

var stackReconcileCmd = &cobra.Command{
	Use:     "reconcile [stack_id]",
	Aliases: []string{"prune", "sync"},
	Short:   "Reconcile a stack (or all stacks) against desired replicas and purge dead/stale containers",
	Run: func(cmd *cobra.Command, args []string) {
		endpoint := "/v1/tasks/prune"
		if len(args) > 0 && args[0] != "" {
			endpoint = "/v1/stack/" + args[0] + "/reconcile"
		}
		resp, err := DoAPIRequest("POST", endpoint, nil)
		if err != nil {
			fmt.Printf("Failed to reconcile: %v\n", err)
			return
		}
		defer resp.Body.Close()

		var res map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&res)
		if msg, ok := res["message"]; ok {
			fmt.Printf("✅ %v\n", msg)
		} else {
			fmt.Println("✅ Reconciliation complete.")
		}
	},
}

func init() {
	rootCmd.AddCommand(stackCmd)
	stackCmd.AddCommand(stackDeployCmd)
	stackCmd.AddCommand(stackLsCmd)
	stackCmd.AddCommand(stackServerLsCmd)
	stackCmd.AddCommand(stackServicesCmd)
	stackCmd.AddCommand(stackRmCmd)
	stackCmd.AddCommand(stackStopCmd)
	stackCmd.AddCommand(stackStartCmd)
	stackCmd.AddCommand(stackReconcileCmd)

	stackDeployCmd.Flags().StringVarP(&composeFile, "compose-file", "c", "", "Path to a local Compose file on your client machine")
	stackDeployCmd.Flags().StringVarP(&serverComposeFile, "from-server", "s", "", "Path to a Compose file residing on the Master server filesystem")
	stackServerLsCmd.Flags().StringVarP(&serverDirFilter, "dir", "d", "", "Specific directory on Master server to scan for Compose files")
}
