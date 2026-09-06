package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"

	"github.com/mario-ezquerro/gubernator/internal/docker"
	"github.com/spf13/cobra"
)

var (
	daemonScope    string
	daemonNode     string
	daemonPreset   string
	daemonFilePath string
	daemonAction   string
	daemonNoBackup bool
)

var daemonCmd = &cobra.Command{
	Use:   "daemon",
	Short: "Manage /etc/docker/daemon.json across cluster nodes",
	Long:  "Inspect, configure, and reload Docker Engine daemon (/etc/docker/daemon.json) across All Centurions, GPU nodes, Manager, or specific hosts.",
}

var daemonInspectCmd = &cobra.Command{
	Use:   "inspect",
	Short: "Inspect /etc/docker/daemon.json and GPU status on cluster nodes",
	Run: func(cmd *cobra.Command, args []string) {
		endpoint := fmt.Sprintf("/v1/docker/daemon?scope=%s", daemonScope)
		if daemonNode != "" {
			endpoint += fmt.Sprintf("&node=%s", daemonNode)
		}

		resp, err := DoAPIRequest("GET", endpoint, nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			fmt.Fprintf(os.Stderr, "Error (Status %d): %s\n", resp.StatusCode, string(body))
			os.Exit(1)
		}

		var data struct {
			Hosts []docker.HostDaemonStatus `json:"hosts"`
		}
		if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
			fmt.Fprintf(os.Stderr, "Failed to parse response: %v\n", err)
			os.Exit(1)
		}

		if len(data.Hosts) == 0 {
			fmt.Println("No matching Centurion hosts found.")
			return
		}

		for _, h := range data.Hosts {
			fmt.Println("================================================================================")
			fmt.Printf("CENTURION: %s (%s) | Role: %s\n", h.NodeID, h.NodeIP, strings.ToUpper(h.Role))
			gpuStatus := "No"
			if h.HasGPU {
				gpuStatus = "Yes"
				if h.GPUInfo != "" {
					gpuStatus += fmt.Sprintf(" (%s)", h.GPUInfo)
				}
			}
			fmt.Printf("GPU Detected:        %s\n", gpuStatus)
			fmt.Printf("Docker Running:      %v\n", h.DaemonRunning)
			fmt.Printf("Config Exists:       %v (%s)\n", h.ConfigExists, h.ConfigPath)
			if h.LastModified != "" {
				fmt.Printf("Last Modified:       %s\n", h.LastModified)
			}
			fmt.Printf("Live-Restore Active: %v\n", h.LiveRestoreActive)

			if h.Error != "" {
				fmt.Printf("Error:               %s\n", h.Error)
			}

			if h.RawJSON != "" {
				fmt.Println("\nConfiguration (/etc/docker/daemon.json):")
				var pretty bytes.Buffer
				if err := json.Indent(&pretty, []byte(h.RawJSON), "  ", "  "); err == nil {
					fmt.Println("  " + pretty.String())
				} else {
					fmt.Println("  " + h.RawJSON)
				}
			} else if h.ConfigExists {
				fmt.Println("\n(Config file is empty or unreadable)")
			} else {
				fmt.Println("\n(No /etc/docker/daemon.json found; engine running with defaults)")
			}
		}
		fmt.Println("================================================================================")
	},
}

var daemonApplyCmd = &cobra.Command{
	Use:   "apply",
	Short: "Apply /etc/docker/daemon.json configuration to target nodes",
	Run: func(cmd *cobra.Command, args []string) {
		var configJSON string

		if daemonFilePath != "" {
			data, err := os.ReadFile(daemonFilePath)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Failed to read config file '%s': %v\n", daemonFilePath, err)
				os.Exit(1)
			}
			configJSON = string(data)
		} else if daemonPreset != "" {
			presets := docker.BuiltinDaemonPresets()
			presetKey := strings.ToLower(strings.TrimSpace(daemonPreset))
			presetData, ok := presets[presetKey]
			if !ok {
				fmt.Fprintf(os.Stderr, "Unknown preset '%s'. Available presets: production, gpu, sre, minimal\n", daemonPreset)
				os.Exit(1)
			}
			bytesData, _ := json.MarshalIndent(presetData, "", "  ")
			configJSON = string(bytesData)
			fmt.Printf("Using built-in preset '%s'...\n", presetKey)
		} else {
			fmt.Fprintln(os.Stderr, "Error: Specify either --preset (production|gpu|sre|minimal) or --file=<path>")
			os.Exit(1)
		}

		backup := !daemonNoBackup
		payload := map[string]interface{}{
			"target_scope": daemonScope,
			"node_id":      daemonNode,
			"raw_json":     configJSON,
			"action":       daemonAction,
			"backup":       backup,
		}

		bodyBytes, _ := json.Marshal(payload)
		resp, err := DoAPIRequest("POST", "/v1/docker/daemon", bytes.NewReader(bodyBytes))
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		respBody, _ := io.ReadAll(resp.Body)
		if resp.StatusCode != http.StatusOK {
			fmt.Fprintf(os.Stderr, "Error applying config (Status %d): %s\n", resp.StatusCode, string(respBody))
			os.Exit(1)
		}

		var res struct {
			Message string                     `json:"message"`
			Results []docker.ApplyDaemonResult `json:"results"`
			Action  string                     `json:"action"`
			Scope   string                     `json:"scope"`
		}
		_ = json.Unmarshal(respBody, &res)

		fmt.Printf("\n%s (Action: %s, Scope: %s)\n", res.Message, res.Action, res.Scope)
		fmt.Println("--------------------------------------------------------------------------------")
		for _, r := range res.Results {
			statusIcon := "✅ SUCCESS"
			if !r.Success {
				statusIcon = "❌ FAILED"
			}
			fmt.Printf("Node: %-15s (%-15s) -> %s\n", r.NodeID, r.NodeIP, statusIcon)
			if r.BackupFile != "" {
				fmt.Printf("  Backup created: %s\n", r.BackupFile)
			}
			if r.Output != "" {
				fmt.Printf("  Output: %s\n", r.Output)
			}
			if r.Error != "" {
				fmt.Printf("  Error:  %s\n", r.Error)
			}
		}
		fmt.Println("--------------------------------------------------------------------------------")
	},
}

func init() {
	nodeCmd.AddCommand(daemonCmd)
	daemonCmd.AddCommand(daemonInspectCmd)
	daemonCmd.AddCommand(daemonApplyCmd)

	daemonInspectCmd.Flags().StringVar(&daemonScope, "scope", "all", "Target scope: all, gpu, manager, node")
	daemonInspectCmd.Flags().StringVar(&daemonNode, "node", "", "Target specific Centurion node ID or IP")

	daemonApplyCmd.Flags().StringVar(&daemonScope, "scope", "all", "Target scope: all, gpu, manager, node")
	daemonApplyCmd.Flags().StringVar(&daemonNode, "node", "", "Target specific Centurion node ID or IP")
	daemonApplyCmd.Flags().StringVar(&daemonPreset, "preset", "", "Apply a preset: production, gpu, sre, minimal")
	daemonApplyCmd.Flags().StringVarP(&daemonFilePath, "file", "f", "", "Path to local JSON file containing daemon config")
	daemonApplyCmd.Flags().StringVar(&daemonAction, "action", "apply_and_reload", "Action to execute: apply_and_reload, apply_and_restart, save_only")
	daemonApplyCmd.Flags().BoolVar(&daemonNoBackup, "no-backup", false, "Disable automated /etc/docker/daemon.json.bak.<ts> backup")
}
