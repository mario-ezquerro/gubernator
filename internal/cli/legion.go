package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/docker"
	"github.com/spf13/cobra"
)

var legionCmd = &cobra.Command{
	Use:   "legion",
	Short: "Manage cluster grouping (The Legion)",
}

var legionInitCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialize the cluster and show the join token",
	Run: func(cmd *cobra.Command, args []string) {
		// Fetches the token from the local manager API
		resp, err := DoAPIRequest("GET", "/v1/cluster/token", nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reaching local Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			fmt.Fprintf(os.Stderr, "Access denied. Are you running this on the Manager node?\n")
			os.Exit(1)
		}

		var data struct {
			Token string `json:"token"`
		}
		json.NewDecoder(resp.Body).Decode(&data)

		fmt.Println("🏛 Gubernator Legion Initialized!")
		fmt.Println("\nTo add a worker to this swarm, run the following command on the worker node:")
		fmt.Printf("\n  gbnt legion join --token %s --manager <MANAGER-IP>:4000\n\n", data.Token)
	},
}

var (
	joinToken   string
	managerAddr string
	apiToken    string // Bearer token for the Manager API (used by workers)
)

var legionJoinCmd = &cobra.Command{
	Use:   "join",
	Short: "Join an existing Gubernator cluster as a worker",
	Run: func(cmd *cobra.Command, args []string) {
		if joinToken == "" || managerAddr == "" {
			fmt.Fprintln(os.Stderr, "Error: --token and --manager flags are required.")
			cmd.Help()
			os.Exit(1)
		}

		// Ensure managerAddr has a scheme
		addr := managerAddr
		if len(addr) > 0 && addr[:4] != "http" {
			addr = "http://" + addr
		}

		hostname, _ := os.Hostname()
		nodeID := "node-" + hostname

		// Detect the local outbound IP (best effort)
		localIP := detectLocalIP()

		payload := map[string]interface{}{
			"id":    nodeID,
			"ip":    localIP,
			"token": joinToken,
			"labels": map[string]string{
				"gbnt.node.role":     "worker",
				"gbnt.node.hostname": hostname,
			},
		}

		body, _ := json.Marshal(payload)

		// Use an authenticated request — the join endpoint is protected by Bearer
		req, err := http.NewRequest("POST", fmt.Sprintf("%s/v1/node/join", addr), bytes.NewBuffer(body))
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to create request: %v\n", err)
			os.Exit(1)
		}
		req.Header.Set("Content-Type", "application/json")
		if apiToken != "" {
			req.Header.Set("Authorization", "Bearer "+apiToken)
		}

		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			bodyBytes, _ := io.ReadAll(resp.Body)
			fmt.Fprintf(os.Stderr, "Failed to join: %s\n", string(bodyBytes))
			os.Exit(1)
		}

		fmt.Println("✅ Successfully joined the Legion!")
		fmt.Printf("   Node ID  : %s\n", nodeID)
		fmt.Printf("   Local IP : %s\n", localIP)
		fmt.Printf("   Manager  : %s\n", addr)

		// Start heartbeat loop
		fmt.Println("\n💓 Starting background loops (Heartbeat & Executor)...")

		go func() {
			for {
				time.Sleep(10 * time.Second)
				hbPayload, _ := json.Marshal(map[string]string{"id": nodeID})
				req, err := http.NewRequest("POST", fmt.Sprintf("%s/v1/node/heartbeat", addr), bytes.NewBuffer(hbPayload))
				if err != nil {
					continue
				}
				req.Header.Set("Content-Type", "application/json")
				if apiToken != "" {
					req.Header.Set("Authorization", "Bearer "+apiToken)
				}
				http.DefaultClient.Do(req)
			}
		}()

		// Executor loop
		for {
			time.Sleep(5 * time.Second)

			// Fetch tasks assigned to this node
			req, err := http.NewRequest("GET", fmt.Sprintf("%s/v1/node/tasks/%s", addr, nodeID), nil)
			if err != nil {
				continue
			}
			if apiToken != "" {
				req.Header.Set("Authorization", "Bearer "+apiToken)
			}
			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				continue
			}

			var data struct {
				Tasks []struct {
					Task struct {
						ID string `json:"id"`
					} `json:"task"`
					Image   string   `json:"image"`
					Ports   []string `json:"ports"`
					Env     []string `json:"env"`
					Volumes []string `json:"volumes"`
					Command string   `json:"command"`
				} `json:"tasks"`
			}

			if err := json.NewDecoder(resp.Body).Decode(&data); err == nil {
				for _, t := range data.Tasks {
					fmt.Printf("Received task %s (Image: %s). Starting...\n", t.Task.ID, t.Image)

					fmt.Printf("Pulling image %s...\n", t.Image)
					if err := docker.PullImage(t.Image); err != nil {
						fmt.Printf("Failed to pull image: %v\n", err)
						continue
					}

					cfg := docker.ContainerConfig{
						TaskID:  t.Task.ID,
						Image:   t.Image,
						Ports:   t.Ports,
						Env:     t.Env,
						Volumes: t.Volumes,
						Command: t.Command,
					}

					fmt.Printf("Starting container for task %s...\n", t.Task.ID)
					containerName, ip, err := docker.StartContainer(cfg)
					if err != nil {
						fmt.Printf("Failed to start container: %v\n", err)
						continue
					}

					fmt.Printf("Container %s started successfully with IP: %s\n", containerName, ip)

					statusPayload, _ := json.Marshal(map[string]string{
						"status":         "running",
						"container_ip":   ip,
						"container_name": containerName,
					})
					statusReq, err := http.NewRequest("POST", fmt.Sprintf("%s/v1/node/tasks/%s/status", addr, t.Task.ID), bytes.NewBuffer(statusPayload))
					if err == nil {
						statusReq.Header.Set("Content-Type", "application/json")
						if apiToken != "" {
							statusReq.Header.Set("Authorization", "Bearer "+apiToken)
						}
						http.DefaultClient.Do(statusReq)
					}
				}
			}
			resp.Body.Close()
		}
	},
}

// detectLocalIP returns the preferred outbound IP of this machine
// by opening a UDP connection (no data is sent) and reading the local address.
func detectLocalIP() string {
	conn, err := net.Dial("udp", "8.8.8.8:53")
	if err == nil {
		defer conn.Close()
		localAddr := conn.LocalAddr().(*net.UDPAddr)
		return localAddr.IP.String()
	}
	// Fallback to hostname
	hostname, _ := os.Hostname()
	return hostname
}

func init() {
	rootCmd.AddCommand(legionCmd)
	legionCmd.AddCommand(legionInitCmd)
	legionCmd.AddCommand(legionJoinCmd)

	legionJoinCmd.Flags().StringVarP(&joinToken, "token", "t", "", "Join token provided by the Manager (gbnt legion join-token)")
	legionJoinCmd.Flags().StringVarP(&managerAddr, "manager", "m", "", "Manager API address (e.g., 192.168.1.100:4000 or http://192.168.1.100:4000)")
	legionJoinCmd.Flags().StringVar(&apiToken, "api-token", "", "Bearer API token for the Manager REST API (GBNT_API_TOKEN)")

	legionCmd.AddCommand(legionJoinTokenCmd)
	legionCmd.AddCommand(legionLeaveCmd)
	legionCmd.AddCommand(legionInfoCmd)
}

var legionJoinTokenCmd = &cobra.Command{
	Use:   "join-token",
	Short: "Print the token needed to join the legion",
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := DoAPIRequest("GET", "/v1/cluster/token", nil)
		if err != nil {
			fmt.Printf("Failed to reach manager: %v\n", err)
			return
		}
		defer resp.Body.Close()

		var data struct {
			Token string `json:"token"`
		}
		if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
			fmt.Println("Failed to decode token")
			return
		}
		fmt.Printf("To add a worker to this legion, run the following command:\n\n")
		fmt.Printf("    gbnt legion join \\\n")
		fmt.Printf("        --token %s \\\n", data.Token)
		fmt.Printf("        --api-token <API_TOKEN> \\\n")
		fmt.Printf("        --manager <MANAGER-IP>:4000\n\n")
		fmt.Printf("💡 Get the API token with: gbnt legion info\n")
	},
}

// legionInfoCmd shows all bootstrap info (localhost only via /v1/cluster/info)
var legionInfoCmd = &cobra.Command{
	Use:   "info",
	Short: "Show cluster bootstrap info (join token + API token). Localhost only.",
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := DoAPIRequest("GET", "/v1/cluster/info", nil)
		if err != nil {
			fmt.Printf("Failed to reach manager: %v\n", err)
			return
		}
		defer resp.Body.Close()

		var data struct {
			JoinToken     string `json:"join_token"`
			APIToken      string `json:"api_token"`
			JoinCommand   string `json:"join_command"`
			ConfigCommand string `json:"config_command"`
		}
		if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
			fmt.Println("Failed to decode cluster info")
			return
		}

		fmt.Println("")
		fmt.Println("╔══════════════════════════════════════════════════════════╗")
		fmt.Println("║         🏛  GUBERNATOR — CLUSTER INFO                   ║")
		fmt.Println("╠══════════════════════════════════════════════════════════╣")
		fmt.Printf( "║  JOIN TOKEN : %-43s ║\n", data.JoinToken)
		fmt.Printf( "║  API TOKEN  : %-43s ║\n", data.APIToken)
		fmt.Println("╠══════════════════════════════════════════════════════════╣")
		fmt.Println("║  Add a WORKER node:                                      ║")
		fmt.Printf( "║  > %s\n", data.JoinCommand)
		fmt.Println("║                                                          ║")
		fmt.Println("║  Configure remote CLI:                                   ║")
		fmt.Printf( "║  > %s\n", data.ConfigCommand)
		fmt.Println("╚══════════════════════════════════════════════════════════╝")
		fmt.Println("")
	},
}

var legionLeaveCmd = &cobra.Command{
	Use:   "leave",
	Short: "Leave the legion",
	Run: func(cmd *cobra.Command, args []string) {
		hostname, _ := os.Hostname()
		nodeID := "node-" + hostname

		resp, err := DoAPIRequest("POST", "/v1/node/"+nodeID+"/leave", nil)
		if err != nil || resp.StatusCode != http.StatusOK {
			fmt.Printf("Failed to leave legion on manager. You might need to manually demote or remove.\n")
		} else {
			fmt.Println("Node successfully left the legion.")
		}
		os.Exit(0)
	},
}
