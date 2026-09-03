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
		fmt.Fprintln(w, "ID\tNODE\tSERVICE\tSTATUS\tCPU (LIVE/LIMIT)\tMEMORY (LIVE/LIMIT)\tIP\tERROR")
		for _, t := range tasks {
			errStr := t.Error
			if len(errStr) > 40 {
				errStr = errStr[:37] + "..."
			}
			cpuStr := fmt.Sprintf("%.1f%%", t.CpuPercent)
			if t.CpuLimit != "" {
				cpuStr += fmt.Sprintf(" / %s", t.CpuLimit)
			}
			memStr := "-"
			if t.MemUsedBytes > 0 {
				mb := float64(t.MemUsedBytes) / (1024 * 1024)
				if mb >= 1024 {
					memStr = fmt.Sprintf("%.1f GB", mb/1024)
				} else {
					memStr = fmt.Sprintf("%.1f MB", mb)
				}
			}
			if t.MemoryLimit != "" {
				if memStr == "-" {
					memStr = "0 B / " + t.MemoryLimit
				} else {
					memStr += " / " + t.MemoryLimit
				}
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

var taskPruneCmd = &cobra.Command{
	Use:     "prune",
	Aliases: []string{"cleanup", "clean", "gc"},
	Short:   "Prune all dead, duplicate, and orphan containers across the cluster",
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := DoAPIRequest("POST", "/v1/tasks/prune", nil)
		if err != nil {
			fmt.Printf("Failed to prune tasks: %v\n", err)
			return
		}
		defer resp.Body.Close()

		var res map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&res)
		if msg, ok := res["message"]; ok {
			fmt.Printf("✅ %v\n", msg)
		} else {
			fmt.Println("✅ Tasks pruned successfully.")
		}
	},
}

func init() {
	rootCmd.AddCommand(taskCmd)
	taskCmd.AddCommand(taskLsCmd)
	taskCmd.AddCommand(taskRmCmd)
	taskCmd.AddCommand(taskPruneCmd)
}
