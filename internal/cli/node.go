package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
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
				ID     string `json:"id"`
				IP     string `json:"ip"`
				Role   string `json:"role"`
				Status string `json:"status"`
			} `json:"nodes"`
		}

		if err := json.Unmarshal(body, &data); err != nil {
			fmt.Fprintf(os.Stderr, "Error parsing JSON: %v\n", err)
			os.Exit(1)
		}

		// Print nicely formatted table
		w := tabwriter.NewWriter(os.Stdout, 0, 0, 3, ' ', 0)
		fmt.Fprintln(w, "ID\tIP\tROLE\tSTATUS\t")
		for _, n := range data.Nodes {
			fmt.Fprintf(w, "%s\t%s\t%s\t%s\t\n", n.ID, n.IP, n.Role, n.Status)
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
	},
}

func init() {
	rootCmd.AddCommand(nodeCmd)
	nodeCmd.AddCommand(nodeLsCmd)
	nodeCmd.AddCommand(nodeInspectCmd)
	nodeCmd.AddCommand(nodePromoteCmd)
	nodeCmd.AddCommand(nodeDemoteCmd)
	nodeCmd.AddCommand(nodeUpdateCmd)

	nodeUpdateCmd.Flags().StringVar(&nodeAvailability, "availability", "", "Availability of the node (active, pause, drain)")
}
