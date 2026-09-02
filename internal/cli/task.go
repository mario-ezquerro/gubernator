package cli

import (
	"encoding/json"
	"fmt"
	"os"
	"text/tabwriter"

	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/spf13/cobra"
)

var taskCmd = &cobra.Command{
	Use:     "task",
	Aliases: []string{"container", "containers", "tasks"},
	Short:   "Manage containers & tasks",
}

var taskLsCmd = &cobra.Command{
	Use:     "ls",
	Aliases: []string{"list", "ps"},
	Short:   "List all containers",
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := DoAPIRequest("GET", "/v1/task/ls", nil)
		if err != nil {
			fmt.Printf("Failed to fetch tasks: %v\n", err)
			return
		}
		defer resp.Body.Close()

		var tasks []db.Task
		json.NewDecoder(resp.Body).Decode(&tasks)

		w := tabwriter.NewWriter(os.Stdout, 0, 0, 3, ' ', 0)
		fmt.Fprintln(w, "ID\tNODE\tSERVICE\tSTATUS\tCPU\tMEMORY\tIP\tERROR")
		for _, t := range tasks {
			errStr := t.Error
			if len(errStr) > 40 {
				errStr = errStr[:37] + "..."
			}
			cpuStr := t.CpuLimit
			if cpuStr == "" {
				cpuStr = "-"
			}
			memStr := t.MemoryLimit
			if memStr == "" {
				memStr = "-"
			}
			tID := t.ID
			if len(tID) > 8 {
				tID = tID[:8]
			}
			sID := t.ServiceID
			if len(sID) > 8 {
				sID = sID[:8]
			}
			fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", tID, t.NodeID, sID, t.Status, cpuStr, memStr, t.ContainerIP, errStr)
		}
		w.Flush()
	},
}

var taskRmCmd = &cobra.Command{
	Use:     "rm [container_id]",
	Aliases: []string{"delete", "remove", "stop"},
	Short:   "Remove or stop a container",
	Args:    cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := DoAPIRequest("DELETE", "/v1/task/"+args[0], nil)
		if err == nil && resp.StatusCode == 200 {
			fmt.Printf("Container %s removed\n", args[0])
		} else {
			fmt.Printf("Failed to remove container\n")
		}
	},
}

func init() {
	rootCmd.AddCommand(taskCmd)
	taskCmd.AddCommand(taskLsCmd)
	taskCmd.AddCommand(taskRmCmd)
}
