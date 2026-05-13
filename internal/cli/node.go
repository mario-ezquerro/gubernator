package cli

import (
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
		resp, err := http.Get("http://localhost:4000/v1/node/ls")
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reaching API: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

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

func init() {
	rootCmd.AddCommand(nodeCmd)
	nodeCmd.AddCommand(nodeLsCmd)
}
