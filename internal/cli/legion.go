package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
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

		hostname, _ := os.Hostname()
		nodeID := "node-" + hostname

		payload := map[string]interface{}{
			"id":    nodeID,
			"ip":    "127.0.0.1", // In reality, we'd detect the active interface IP
			"token": joinToken,
			"labels": map[string]string{
				"gbnt.node.role": "worker",
				"gbnt.node.hostname": hostname,
			},
		}

		body, _ := json.Marshal(payload)
		// Ensure managerAddr has a scheme
		addr := managerAddr
		if len(addr) > 0 && addr[:4] != "http" {
			addr = "http://" + addr
		}
		resp, err := http.Post(fmt.Sprintf("%s/v1/node/join", addr), "application/json", bytes.NewBuffer(body))
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
		
		// Start heartbeat loop
		fmt.Println("💓 Starting background loops (Heartbeat & Executor)...")
		
		go func() {
			for {
				time.Sleep(10 * time.Second)
				hbPayload, _ := json.Marshal(map[string]string{"id": nodeID})
				http.Post(fmt.Sprintf("%s/v1/node/heartbeat", managerAddr), "application/json", bytes.NewBuffer(hbPayload))
			}
		}()

		// Executor loop
		for {
			time.Sleep(5 * time.Second)
			
			// Fetch tasks
			resp, err := http.Get(fmt.Sprintf("%s/v1/node/tasks/%s", managerAddr, nodeID))
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
					addr := managerAddr
					if len(addr) > 0 && addr[:4] != "http" {
						addr = "http://" + addr
					}
					http.Post(fmt.Sprintf("%s/v1/node/tasks/%s/status", addr, t.Task.ID), "application/json", bytes.NewBuffer(statusPayload))
				}
			}
			resp.Body.Close()
		}
	},
}

func init() {
	rootCmd.AddCommand(legionCmd)
	legionCmd.AddCommand(legionInitCmd)
	legionCmd.AddCommand(legionJoinCmd)

	legionJoinCmd.Flags().StringVarP(&joinToken, "token", "t", "", "Token to authenticate with the Manager")
	legionJoinCmd.Flags().StringVarP(&managerAddr, "manager", "m", "", "Manager API address (e.g., 192.168.1.100:4000 or http://192.168.1.100:4000)")

	legionCmd.AddCommand(legionJoinTokenCmd)
	legionCmd.AddCommand(legionLeaveCmd)
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
		fmt.Printf("    gbnt legion join --token %s --manager <MANAGER-IP>:4000\n\n", data.Token)
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
