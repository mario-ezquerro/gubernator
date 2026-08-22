package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"text/tabwriter"

	"github.com/spf13/cobra"
)

var nodeCmd = &cobra.Command{
	Use:   "node",
	Short: "Manage Gubernator nodes",
}

var nodeLsCmd = &cobra.Command{
	Use:   "ls",
	Short: "List nodes in the swarm",
	Run: func(cmd *cobra.Command, args []string) {
		// Call the API endpoint
		resp, err := DoAPIRequest("GET", "/v1/node/ls", nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reaching API: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			fmt.Fprintf(os.Stderr, "API Error (Status %d): %s\n", resp.StatusCode, string(body))
			os.Exit(1)
		}

		body, err := io.ReadAll(resp.Body)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reading response: %v\n", err)
			os.Exit(1)
		}

		// Basic JSON parsing
		var data struct {
			Nodes []struct {
				ID            string  `json:"id"`
				IP            string  `json:"ip"`
				Role          string  `json:"role"`
				Status        string  `json:"status"`
				CpuPercent    float64 `json:"cpu_percent"`
				MemUsedBytes  uint64  `json:"mem_used_bytes"`
				MemTotalBytes uint64  `json:"mem_total_bytes"`
				MemPercent    float64 `json:"mem_percent"`
				DiskUsedBytes uint64  `json:"disk_used_bytes"`
				DiskTotalBytes uint64 `json:"disk_total_bytes"`
				DiskPercent   float64 `json:"disk_percent"`
			} `json:"nodes"`
		}

		if err := json.Unmarshal(body, &data); err != nil {
			fmt.Fprintf(os.Stderr, "Error parsing JSON: %v\n", err)
			os.Exit(1)
		}

		formatBytes := func(b uint64) string {
			if b == 0 {
				return "0 B"
			}
			const unit = 1024
			if b < unit {
				return fmt.Sprintf("%d B", b)
			}
			div, exp := uint64(unit), 0
			for n := b / unit; n >= unit; n /= unit {
				div *= unit
				exp++
			}
			return fmt.Sprintf("%.1f %cB", float64(b)/float64(div), "KMGTPE"[exp])
		}

		// Print nicely formatted table
		w := tabwriter.NewWriter(os.Stdout, 0, 0, 3, ' ', 0)
		fmt.Fprintln(w, "ID\tIP\tROLE\tSTATUS\tCPU\tMEMORY\tHOST DISK\t")
		for _, n := range data.Nodes {
			cpuStr := fmt.Sprintf("%.1f%%", n.CpuPercent)
			memStr := "-"
			if n.MemTotalBytes > 0 {
				memStr = fmt.Sprintf("%.0f%% (%s)", n.MemPercent, formatBytes(n.MemUsedBytes))
			}
			diskStr := "-"
			if n.DiskTotalBytes > 0 {
				diskStr = fmt.Sprintf("%.0f%% (%s / %s)", n.DiskPercent, formatBytes(n.DiskUsedBytes), formatBytes(n.DiskTotalBytes))
			}
			fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\t%s\t%s\t\n", n.ID, n.IP, n.Role, n.Status, cpuStr, memStr, diskStr)
		}
		w.Flush()
	},
}

var nodeInspectCmd = &cobra.Command{
	Use:   "inspect [node_id]",
	Short: "Display detailed information on one node",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := DoAPIRequest("GET", "/v1/node/"+args[0], nil)
		if err != nil {
			fmt.Printf("Failed to contact API: %v\n", err)
			return
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			fmt.Fprintf(os.Stderr, "API Error (Status %d): %s\n", resp.StatusCode, string(body))
			os.Exit(1)
		}

		io.Copy(os.Stdout, resp.Body)
		fmt.Println()
	},
}

var nodePromoteCmd = &cobra.Command{
	Use:   "promote [node_id]",
	Short: "Promote a worker node to a manager in the legion",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		payload := `{"role":"manager"}`
		resp, err := DoAPIRequest("POST", "/v1/node/"+args[0]+"/role", bytes.NewBufferString(payload))
		if err == nil && resp.StatusCode == 200 {
			fmt.Printf("Node %s promoted to a manager.\n", args[0])
		} else {
			fmt.Printf("Failed to promote node.\n")
		}
	},
}

var nodeDemoteCmd = &cobra.Command{
	Use:   "demote [node_id]",
	Short: "Demote a manager node to a worker in the legion",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		payload := `{"role":"worker"}`
		resp, err := DoAPIRequest("POST", "/v1/node/"+args[0]+"/role", bytes.NewBufferString(payload))
		if err == nil && resp.StatusCode == 200 {
			fmt.Printf("Node %s demoted to a worker.\n", args[0])
		} else {
			fmt.Printf("Failed to demote node.\n")
		}
	},
}

var (
	nodeAvailability string
	nodeLabelAdd     []string
	nodeLabelRm      []string
)

var nodeUpdateCmd = &cobra.Command{
	Use:   "update [node_id]",
	Short: "Update a node",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		if nodeAvailability != "" {
			payload := fmt.Sprintf(`{"availability":"%s"}`, nodeAvailability)
			resp, err := DoAPIRequest("POST", "/v1/node/"+args[0]+"/availability", bytes.NewBufferString(payload))
			if err == nil && resp.StatusCode == 200 {
				fmt.Printf("Node %s availability updated to %s.\n", args[0], nodeAvailability)
			} else {
				fmt.Printf("Failed to update node availability.\n")
			}
		}

		if len(nodeLabelAdd) > 0 || len(nodeLabelRm) > 0 {
			updateNodeLabelsCLI(args[0], nodeLabelAdd, nodeLabelRm)
		}
	},
}

var nodeLabelCmd = &cobra.Command{
	Use:   "label [node_id] [key=value | key]...",
	Short: "Manage labels for a node",
	Long:  `Add, update or remove labels of a node. Arguments with "=" (key=value) will add or update a label. Arguments without "=" (key) will remove that label.`,
	Args:  cobra.MinimumNArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		nodeID := args[0]
		toAdd := []string{}
		toRm := []string{}

		for _, arg := range args[1:] {
			if strings.Contains(arg, "=") {
				toAdd = append(toAdd, arg)
			} else {
				toRm = append(toRm, arg)
			}
		}

		if len(toAdd) == 0 && len(toRm) == 0 {
			fmt.Fprintln(os.Stderr, "Error: must specify at least one label to add (key=value) or remove (key)")
			cmd.Help()
			os.Exit(1)
		}

		updateNodeLabelsCLI(nodeID, toAdd, toRm)
	},
}

func updateNodeLabelsCLI(nodeID string, toAdd []string, toRm []string) {
	if len(toAdd) == 0 && len(toRm) == 0 {
		return
	}

	// 1. Fetch current node data to inspect its labels
	resp, err := DoAPIRequest("GET", "/v1/node/"+nodeID, nil)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to contact API: %v\n", err)
		os.Exit(1)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		fmt.Fprintf(os.Stderr, "API Error (Status %d): %s\n", resp.StatusCode, string(body))
		os.Exit(1)
	}

	var node struct {
		Labels map[string]string `json:"labels"`
	}
	err = json.NewDecoder(resp.Body).Decode(&node)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error decoding node response: %v\n", err)
		os.Exit(1)
	}

	if node.Labels == nil {
		node.Labels = make(map[string]string)
	}

	// 2. Process removals
	for _, key := range toRm {
		if key == "gbnt.node.role" || key == "gbnt.node.arch" {
			fmt.Fprintf(os.Stderr, "Error: Label '%s' is a system/fixed label and cannot be removed.\n", key)
			os.Exit(1)
		}
		delete(node.Labels, key)
	}

	// 3. Process additions
	for _, item := range toAdd {
		parts := strings.SplitN(item, "=", 2)
		if len(parts) != 2 {
			fmt.Fprintf(os.Stderr, "Error: Invalid label format '%s'. Must be key=value.\n", item)
			os.Exit(1)
		}
		key, value := parts[0], parts[1]
		if key == "" {
			fmt.Fprintf(os.Stderr, "Error: Label key cannot be empty.\n")
			os.Exit(1)
		}
		if key == "gbnt.node.role" || key == "gbnt.node.arch" {
			fmt.Fprintf(os.Stderr, "Error: Label '%s' is a system/fixed label and cannot be modified.\n", key)
			os.Exit(1)
		}
		node.Labels[key] = value
	}

	// 4. Send the updated labels map
	payload, err := json.Marshal(map[string]interface{}{"labels": node.Labels})
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error encoding request payload: %v\n", err)
		os.Exit(1)
	}

	respUpdate, err := DoAPIRequest("POST", "/v1/node/"+nodeID+"/labels", bytes.NewReader(payload))
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to contact API to update labels: %v\n", err)
		os.Exit(1)
	}
	defer respUpdate.Body.Close()

	if respUpdate.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(respUpdate.Body)
		fmt.Fprintf(os.Stderr, "Failed to update labels (Status %d): %s\n", respUpdate.StatusCode, string(body))
		os.Exit(1)
	}

	fmt.Printf("Node %s labels updated successfully.\n", nodeID)
}

var nodeRebootCmd = &cobra.Command{
	Use:   "reboot [node_id]",
	Short: "Reboot a node",
	Long:  "Drain tasks off the node, mark it as maintenance, and trigger a system reboot on the host.",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := DoAPIRequest("POST", "/v1/node/"+args[0]+"/reboot", nil)
		if err == nil && resp.StatusCode == 200 {
			fmt.Printf("Node %s reboot initiated. Host is draining tasks and rebooting...\n", args[0])
		} else {
			fmt.Printf("Failed to initiate reboot for node %s.\n", args[0])
		}
	},
}

func init() {
	rootCmd.AddCommand(nodeCmd)
	nodeCmd.AddCommand(nodeLsCmd)
	nodeCmd.AddCommand(nodeInspectCmd)
	nodeCmd.AddCommand(nodePromoteCmd)
	nodeCmd.AddCommand(nodeDemoteCmd)
	nodeCmd.AddCommand(nodeUpdateCmd)
	nodeCmd.AddCommand(nodeLabelCmd)
	nodeCmd.AddCommand(nodeRebootCmd)

	nodeUpdateCmd.Flags().StringVar(&nodeAvailability, "availability", "", "Availability of the node (active, pause, drain, maintenance)")
	nodeUpdateCmd.Flags().StringSliceVar(&nodeLabelAdd, "label-add", []string{}, "Add or update labels (key=value)")
	nodeUpdateCmd.Flags().StringSliceVar(&nodeLabelRm, "label-rm", []string{}, "Remove labels by key")
}
