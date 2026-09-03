package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/caddy"
	"github.com/mario-ezquerro/gubernator/internal/coredns"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/mario-ezquerro/gubernator/internal/docker"
	"github.com/mario-ezquerro/gubernator/internal/monitor"
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

		if withExamples {
			fmt.Println("🚀 Deploying bundled POC examples into cluster (--with-examples)...")
			payload := map[string]string{"id": "all", "target_node": "auto"}
			body, _ := json.Marshal(payload)
			respEx, errEx := DoAPIRequest("POST", "/v1/examples/deploy", bytes.NewBuffer(body))
			if errEx == nil && respEx.StatusCode == http.StatusOK {
				var resEx map[string]interface{}
				json.NewDecoder(respEx.Body).Decode(&resEx)
				fmt.Printf("✅ Successfully deployed %v POC examples for testing and demonstration!\n", resEx["deployed_count"])
			} else {
				fmt.Println("ℹ️  POC examples deployment submitted. Check 'gbnt task ls' or dashboard.")
			}
		}
	},
}

var (
	withExamples bool
	joinToken    string
	managerAddr  string
	apiToken     string // Bearer token for the Manager API (used by workers)
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
				"gbnt.node.arch":     db.DetectArch(),
			},
			"caddy_status": caddy.Status(),
			"caddyfile":    readLocalCaddyfile(),
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

		// Parse manager IP from managerAddr
		var managerIP string
		cleanAddr := managerAddr
		if strings.Contains(cleanAddr, "://") {
			cleanAddr = strings.Split(cleanAddr, "://")[1]
		}
		if strings.Contains(cleanAddr, ":") {
			managerIP = strings.Split(cleanAddr, ":")[0]
		} else {
			managerIP = cleanAddr
		}
		if managerIP == "" {
			managerIP = "127.0.0.1"
		}

		// ── SSH Key Exchange: Fetch Manager's public key and install on worker host ──
		fmt.Println("🔑 Fetching Manager SSH public key for remote shell access...")
		sshReq, _ := http.NewRequest("GET", fmt.Sprintf("%s/v1/cluster/ssh-pubkey", addr), nil)
		if apiToken != "" {
			sshReq.Header.Set("Authorization", "Bearer "+apiToken)
		}
		sshResp, sshErr := http.DefaultClient.Do(sshReq)
		if sshErr == nil && sshResp.StatusCode == http.StatusOK {
			var sshData map[string]string
			if decErr := json.NewDecoder(sshResp.Body).Decode(&sshData); decErr == nil {
				if pubkey, ok := sshData["ssh_pubkey"]; ok && pubkey != "" {
					cleanKey := strings.TrimSpace(pubkey)

					// Always install directly on host via Docker root volume mount (-v /:/host)
					installCmd := fmt.Sprintf(
						"mkdir -p /host/home/ubuntu/.ssh && chmod 700 /host/home/ubuntu/.ssh && "+
							"grep -qF '%s' /host/home/ubuntu/.ssh/authorized_keys 2>/dev/null || echo '%s' >> /host/home/ubuntu/.ssh/authorized_keys && "+
							"chmod 600 /host/home/ubuntu/.ssh/authorized_keys",
						cleanKey, cleanKey,
					)
					dockerCmd := exec.Command("docker", "run", "--rm", "-v", "/:/host", "alpine", "sh", "-c", installCmd)
					if _, runErr := dockerCmd.CombinedOutput(); runErr != nil {
						// Fallback: try local file write if running directly on host binary
						sshDir := "/home/ubuntu/.ssh"
						authKeysPath := sshDir + "/authorized_keys"
						_ = os.MkdirAll(sshDir, 0700)
						existing, _ := os.ReadFile(authKeysPath)
						if !strings.Contains(string(existing), cleanKey) {
							f, fErr := os.OpenFile(authKeysPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
							if fErr == nil {
								f.WriteString(cleanKey + "\n")
								f.Close()
								fmt.Println("   ✅ Manager SSH public key installed in /home/ubuntu/.ssh/authorized_keys")
							}
						}
					} else {
						fmt.Println("   ✅ Manager SSH public key auto-installed on host authorized_keys")
					}
				}
			}
			sshResp.Body.Close()
		} else {
			fmt.Println("   ⚠️  Could not fetch Manager SSH public key (Shell access may not work)")
		}

		// Ensure network and start Caddy Ingress locally on worker node
		fmt.Println("🌐 Starting local Caddy Ingress on worker node...")
		if err := coredns.EnsureNetwork(); err != nil {
			fmt.Printf("⚠️ Failed to create gbnt-net network: %v\n", err)
		} else {
			if err := caddy.EnsureRunning(); err != nil {
				fmt.Printf("⚠️ Failed to start worker Caddy Ingress: %v\n", err)
			}
			// Start cAdvisor metrics & Promtail log shipper on worker node
			if err := monitor.EnsureWorkerMonitoring(managerIP); err != nil {
				fmt.Printf("⚠️ Failed to start worker cAdvisor/Promtail monitoring: %v\n", err)
			} else {
				fmt.Println("📊 Worker cAdvisor & Promtail monitoring started successfully.")
			}
		}

		// Start heartbeat loop
		fmt.Println("\n💓 Starting background loops (Heartbeat & Executor)...")

		// Start lightweight health endpoint for Docker healthcheck
		go func() {
			mux := http.NewServeMux()
			mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusOK)
				w.Write([]byte(`{"status":"healthy","role":"worker"}`))
			})
			_ = http.ListenAndServe(":4002", mux)
		}()

		go func() {
			hbClient := &http.Client{Timeout: 5 * time.Second}
			for {
				time.Sleep(10 * time.Second)
				hbPayload, _ := json.Marshal(map[string]interface{}{
					"id":           nodeID,
					"caddy_status": caddy.Status(),
					"caddyfile":    readLocalCaddyfile(),
				})
				req, err := http.NewRequest("POST", fmt.Sprintf("%s/v1/node/heartbeat", addr), bytes.NewBuffer(hbPayload))
				if err != nil {
					continue
				}
				req.Header.Set("Content-Type", "application/json")
				if apiToken != "" {
					req.Header.Set("Authorization", "Bearer "+apiToken)
				} else if joinToken != "" {
					req.Header.Set("Authorization", "Bearer "+joinToken)
				}
				resp, err := hbClient.Do(req)
				if err != nil {
					fmt.Fprintf(os.Stderr, "⚠️  Heartbeat network error: %v\n", err)
				} else {
					if resp.StatusCode != http.StatusOK {
						fmt.Fprintf(os.Stderr, "⚠️  Heartbeat rejected by manager (HTTP %d)\n", resp.StatusCode)
					}
					resp.Body.Close()
				}
			}
		}()

		// Executor loop
		execClient := &http.Client{Timeout: 10 * time.Second}
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
			resp, err := execClient.Do(req)
			if err != nil {
				continue
			}

			var data struct {
				Tasks []struct {
					Task struct {
						ID            string `json:"id"`
						Status        string `json:"status"`
						ContainerIP   string `json:"container_ip"`
						ContainerName string `json:"container_name"`
					} `json:"task"`
					Image       string   `json:"image"`
					Ports       []string `json:"ports"`
					Env         []string `json:"env"`
					Volumes     []string `json:"volumes"`
					Command     string   `json:"command"`
					Constraints []string `json:"constraints"`
				} `json:"tasks"`
			}

			if err := json.NewDecoder(resp.Body).Decode(&data); err == nil {
				activeTasks := make(map[string]bool)
				for _, t := range data.Tasks {
					activeTasks[t.Task.ID] = true
				}

				reportStatus := func(taskID, status, ip, containerName, errMsg string) {
					statusPayload, _ := json.Marshal(map[string]string{
						"status":         status,
						"container_ip":   ip,
						"container_name": containerName,
						"error":          errMsg,
					})
					statusReq, err := http.NewRequest("POST", fmt.Sprintf("%s/v1/node/tasks/%s/status", addr, taskID), bytes.NewBuffer(statusPayload))
					if err == nil {
						statusReq.Header.Set("Content-Type", "application/json")
						if apiToken != "" {
							statusReq.Header.Set("Authorization", "Bearer "+apiToken)
						} else if joinToken != "" {
							statusReq.Header.Set("Authorization", "Bearer "+joinToken)
						}
						http.DefaultClient.Do(statusReq)
					}
				}

				for i, t := range data.Tasks {
					containerName := t.Task.ContainerName
					if containerName == "" {
						containerName = "gbnt-" + t.Task.ID
					}

					// Check if container is actually running locally on this worker
					inspectCmd := exec.Command("docker", "inspect", "-f", "{{.State.Running}}", containerName)
					isRunning := false
					if out, err := inspectCmd.Output(); err == nil && strings.TrimSpace(string(out)) == "true" {
						isRunning = true
					}

					if isRunning {
						if t.Task.Status != "running" {
							reportStatus(t.Task.ID, "running", t.Task.ContainerIP, containerName, "")
						}
						continue
					}

					// Health check for tasks expected to be running but container not running
					if t.Task.Status == "running" {
						// Container is dead or stopped: attempt restart
						fmt.Printf("⚠️ Task %s container %s is not running. Attempting restart...\n", t.Task.ID, containerName)
						startCmd := exec.Command("docker", "start", containerName)
						if sErr := startCmd.Run(); sErr != nil {
							fmt.Printf("❌ Failed to restart container %s: %v. Reporting dead...\n", containerName, sErr)
							reportStatus(t.Task.ID, "dead", "", containerName, fmt.Sprintf("container exited and restart failed: %v", sErr))
						} else {
							fmt.Printf("✅ Container %s restarted successfully.\n", containerName)
						}
						continue
					}

					if t.Task.Status == "pending" || t.Task.Status == "pulling" || t.Task.Status == "starting" {

						// SRE monitor containers (cAdvisor, Node Exporter, Promtail) are managed as local base daemons
						if strings.HasPrefix(t.Task.ID, "sre-task-") || strings.HasPrefix(containerName, "gbnt-monitor-") {
							_ = monitor.EnsureWorkerMonitoring(managerIP)
							inspectCheck := exec.Command("docker", "inspect", "-f", "{{.State.Running}}", containerName)
							if out, err := inspectCheck.Output(); err == nil && strings.TrimSpace(string(out)) == "true" {
								reportStatus(t.Task.ID, "running", t.Task.ContainerIP, containerName, "")
								continue
							}
						}

						fmt.Printf("Received task %s (Image: %s). Starting...\n", t.Task.ID, t.Image)

						// 1. Report "pulling" status immediately so manager & dashboard show live progress
						reportStatus(t.Task.ID, "pulling", "", "", fmt.Sprintf("Pulling image %s...", t.Image))

						fmt.Printf("Pulling image %s...\n", t.Image)
						if err := docker.PullImage(t.Image); err != nil {
							fmt.Printf("Failed to pull image: %v\n", err)
							reportStatus(t.Task.ID, "dead", "", "", fmt.Sprintf("pull failed: %v", err))
							continue
						}

						if strings.Contains(t.Image, "scope") {
							fmt.Printf("🕸️ Starting Weave Scope probe on worker node...\n")
							exec.Command("docker", "rm", "-f", "gbnt-monitor-scope-probe").Run()

							args := []string{
								"run", "-d",
								"--name", "gbnt-monitor-scope-probe",
								"--restart", "unless-stopped",
								"-e", "CHECKPOINT_DISABLE=1",
								"--net", "host",
								"--pid", "host",
								"--privileged",
								"-v", "/var/run/docker.sock:/var/run/docker.sock",
								"-v", "/proc:/host/proc:ro",
								"-v", "/sys:/sys:ro",
								"marioezquerro/scope:latest",
							}
							if t.Command != "" {
								args = append(args, strings.Fields(t.Command)...)
							}

							if err := exec.Command("docker", args...).Run(); err != nil {
								fmt.Printf("Failed to start scope probe: %v\n", err)
								reportStatus(t.Task.ID, "dead", "", "", fmt.Sprintf("scope probe start failed: %v", err))
								continue
							}

							reportStatus(t.Task.ID, "running", t.Task.ContainerIP, "gbnt-monitor-scope-probe", "")
							data.Tasks[i].Task.Status = "running"
							continue
						}

						// 2. Report "starting" status
						reportStatus(t.Task.ID, "starting", "", "", "Starting container...")

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
							reportStatus(t.Task.ID, "dead", "", "", fmt.Sprintf("start failed: %v", err))
							continue
						}

						fmt.Printf("Container %s started successfully with IP: %s\n", containerName, ip)

						reportStatus(t.Task.ID, "running", ip, containerName, "")

						// Update local t.Task details for immediate Caddyfile update
						data.Tasks[i].Task.Status = "running"
						data.Tasks[i].Task.ContainerIP = ip
					}
				}

				// Reconcile and clean up orphaned containers on this worker node
				out, err := exec.Command("docker", "ps", "-a", "--filter", "name=gbnt-", "--format", "{{.Names}}").Output()
				if err == nil {
					lines := strings.Split(string(out), "\n")
					for _, line := range lines {
						containerName := strings.TrimSpace(line)
						if containerName == "" {
							continue
						}
						// Skip system core/monitoring containers
						if containerName == "gbnt-manager" || containerName == "gbnt-worker" || containerName == "gbnt-coredns" || containerName == "gbnt-caddy" || strings.HasPrefix(containerName, "gbnt-monitor-") {
							continue
						}
						// Extract task ID from name "gbnt-<taskID>"
						taskID := strings.TrimPrefix(containerName, "gbnt-")
						if !activeTasks[taskID] {
							fmt.Printf("Reconciliation: stopping and removing orphaned container %s\n", containerName)
							docker.StopContainer(containerName)
						}
					}
				}

				// Generate local Caddyfile for all running tasks on this worker node
				hostUpstreams := make(map[string][]string)
				var hostOrder []string

				for _, t := range data.Tasks {
					taskIP := t.Task.ContainerIP
					if t.Task.Status != "running" || taskIP == "" {
						continue
					}

					for _, constraint := range t.Constraints {
						parts := strings.Split(constraint, "==")
						if len(parts) != 2 {
							continue
						}
						key := strings.TrimSpace(parts[0])
						val := strings.TrimSpace(parts[1])

						if key != "ingress.host" && key != "node.labels.gbnt.ingress.host" {
							continue
						}

						port := "80"
						if len(t.Ports) > 0 {
							p := t.Ports[0]
							parts := strings.Split(p, ":")
							lastPart := parts[len(parts)-1]
							cleaned := strings.TrimSpace(strings.Split(lastPart, "/")[0])
							if cleaned != "" {
								port = cleaned
							}
						}

						if _, seen := hostUpstreams[val]; !seen {
							hostOrder = append(hostOrder, val)
						}
						hostUpstreams[val] = append(hostUpstreams[val], fmt.Sprintf("%s:%s", taskIP, port))
					}
				}

				caddyfileContent := "# Gubernator Worker Auto-Generated Caddyfile\n\n"
				for _, host := range hostOrder {
					upstreams := hostUpstreams[host]
					tlsDirective := ""
					if caddy.IsLocalDomain(host) {
						tlsDirective = "\ttls internal\n"
					}
					caddyfileContent += fmt.Sprintf(
						"%s {\n%s\treverse_proxy %s {\n\t\tlb_policy round_robin\n\t}\n}\n\n",
						host, tlsDirective, strings.Join(upstreams, " "),
					)
				}

				if len(hostOrder) == 0 {
					caddyfileContent += ":80 {\n\trespond \"Gubernator Worker Caddy Ingress is running!\" 200\n}\n"
				}

				caddyfilePath := caddy.CaddyfilePath()
				currContent, _ := os.ReadFile(caddyfilePath)
				if string(currContent) != caddyfileContent {
					if err := os.WriteFile(caddyfilePath, []byte(caddyfileContent), 0644); err == nil {
						caddy.ReloadConfig()
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

	legionInitCmd.Flags().BoolVar(&withExamples, "with-examples", false, "Deploy bundled POC examples immediately upon cluster initialization")

	legionJoinCmd.Flags().StringVarP(&joinToken, "token", "t", "", "Join token provided by the Manager (gbnt legion join-token)")
	legionJoinCmd.Flags().StringVarP(&managerAddr, "manager", "m", "", "Manager API address (e.g., 192.168.1.100:4000 or http://192.168.1.100:4000)")
	legionJoinCmd.Flags().StringVar(&apiToken, "api-token", "", "Bearer API token for the Manager REST API (GBNT_API_TOKEN)")

	// Register `gbnt agent` alias for systemd / script compatibility
	agentCmd := &cobra.Command{
		Use:   "agent",
		Short: "Start worker agent and join cluster (alias for gbnt legion join)",
		Run:   legionJoinCmd.Run,
	}
	agentCmd.Flags().StringVarP(&joinToken, "token", "t", "", "Join token provided by the Manager")
	agentCmd.Flags().StringVarP(&managerAddr, "manager", "m", "", "Manager API address")
	agentCmd.Flags().StringVar(&apiToken, "api-token", "", "Bearer API token for Manager REST API")
	rootCmd.AddCommand(agentCmd)

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

		if resp.StatusCode != http.StatusOK {
			bodyBytes, _ := io.ReadAll(resp.Body)
			fmt.Printf("Failed to get join token: Status %d - %s\n", resp.StatusCode, string(bodyBytes))
			return
		}

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

		if resp.StatusCode != http.StatusOK {
			bodyBytes, _ := io.ReadAll(resp.Body)
			fmt.Printf("Failed to get cluster info: Status %d - %s\n", resp.StatusCode, string(bodyBytes))
			return
		}

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

func readLocalCaddyfile() string {
	content, err := os.ReadFile(caddy.CaddyfilePath())
	if err != nil {
		return ""
	}
	return string(content)
}
