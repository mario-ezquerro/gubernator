package cli

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"text/tabwriter"

	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/spf13/cobra"
)

var taskCmd = &cobra.Command{
	Use:   "task",
	Short: "Manage tasks",
}

var taskLsCmd = &cobra.Command{
	Use:   "ls",
	Short: "List all tasks",
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := http.Get("http://localhost:4000/v1/task/ls")
		if err != nil {
			fmt.Printf("Failed to fetch tasks: %v\n", err)
			return
		}
		defer resp.Body.Close()

		var tasks []db.Task
		json.NewDecoder(resp.Body).Decode(&tasks)

		w := tabwriter.NewWriter(os.Stdout, 0, 0, 3, ' ', 0)
		fmt.Fprintln(w, "ID\tNODE\tSERVICE\tSTATUS\tIP")
		for _, t := range tasks {
			fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\n", t.ID[:8], t.NodeID, t.ServiceID[:8], t.Status, t.ContainerIP)
		}
		w.Flush()
	},
}

var taskRmCmd = &cobra.Command{
	Use:   "rm [task_id]",
	Short: "Remove a task",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		req, _ := http.NewRequest("DELETE", "http://localhost:4000/v1/task/"+args[0], nil)
		resp, err := http.DefaultClient.Do(req)
		if err == nil && resp.StatusCode == 200 {
			fmt.Printf("Task %s removed\n", args[0])
		} else {
			fmt.Printf("Failed to remove task\n")
		}
	},
}

func init() {
	rootCmd.AddCommand(taskCmd)
	taskCmd.AddCommand(taskLsCmd)
	taskCmd.AddCommand(taskRmCmd)
}
