package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"text/tabwriter"

	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/spf13/cobra"
)

var serviceCmd = &cobra.Command{
	Use:   "service",
	Short: "Manage services",
}

var serviceLsCmd = &cobra.Command{
	Use:   "ls",
	Short: "List services",
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := DoAPIRequest("GET", "/v1/service/ls", nil)
		if err != nil {
			fmt.Printf("Failed to fetch services: %v\n", err)
			return
		}
		defer resp.Body.Close()

		var services []db.Service
		json.NewDecoder(resp.Body).Decode(&services)

		w := tabwriter.NewWriter(os.Stdout, 0, 0, 3, ' ', 0)
		fmt.Fprintln(w, "ID\tNAME\tIMAGE\tREPLICAS\tSTACK")
		for _, s := range services {
			fmt.Fprintf(w, "%s\t%s\t%s\t%d\t%s\n", s.ID[:8], s.Name, s.Image, s.DesiredReplicas, s.StackID[:8])
		}
		w.Flush()
	},
}

var servicePsCmd = &cobra.Command{
	Use:   "ps [service_id]",
	Short: "List the tasks of one or more services",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := http.Get(GetAPIEndpoint() + "/v1/service/" + args[0] + "/tasks")
		if err != nil {
			fmt.Printf("Failed to fetch tasks: %v\n", err)
			return
		}
		defer resp.Body.Close()

		var tasks []db.Task
		json.NewDecoder(resp.Body).Decode(&tasks)

		w := tabwriter.NewWriter(os.Stdout, 0, 0, 3, ' ', 0)
		fmt.Fprintln(w, "ID\tNODE\tSTATUS\tIP")
		for _, t := range tasks {
			fmt.Fprintf(w, "%s\t%s\t%s\t%s\n", t.ID[:8], t.NodeID, t.Status, t.ContainerIP)
		}
		w.Flush()
	},
}

var serviceRmCmd = &cobra.Command{
	Use:   "rm [service_id]",
	Short: "Remove one or more services",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		req, _ := http.NewRequest("DELETE", GetAPIEndpoint() + "/v1/service/"+args[0], nil)
		resp, err := http.DefaultClient.Do(req)
		if err == nil && resp.StatusCode == 200 {
			fmt.Printf("Service %s removed\n", args[0])
		} else {
			fmt.Printf("Failed to remove service\n")
		}
	},
}

var serviceScaleCmd = &cobra.Command{
	Use:   "scale [service_id]=[replicas]",
	Short: "Scale one or multiple replicated services",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		// Parse service=replicas
		var serviceID string
		var replicas int
		fmt.Sscanf(args[0], "%s=%d", &serviceID, &replicas)
		
		payload := fmt.Sprintf(`{"replicas":%d}`, replicas)
		resp, err := http.Post(GetAPIEndpoint() + "/v1/service/"+serviceID+"/scale", "application/json", bytes.NewBufferString(payload))
		if err == nil && resp.StatusCode == 200 {
			fmt.Printf("Service %s scaled to %d\n", serviceID, replicas)
		} else {
			fmt.Printf("Failed to scale service\n")
		}
	},
}

// Basic create stub
var serviceCreateCmd = &cobra.Command{
	Use:   "create",
	Short: "Create a new service (MVP Stub)",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("Direct service creation not fully implemented. Please use 'gbnt stack deploy' for MVP.")
	},
}

var serviceUpdateCmd = &cobra.Command{
	Use:   "update",
	Short: "Update a service (MVP Stub)",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("Direct service update not fully implemented. Please use 'gbnt stack deploy' for MVP.")
	},
}

func init() {
	rootCmd.AddCommand(serviceCmd)
	serviceCmd.AddCommand(serviceLsCmd)
	serviceCmd.AddCommand(servicePsCmd)
	serviceCmd.AddCommand(serviceRmCmd)
	serviceCmd.AddCommand(serviceScaleCmd)
	serviceCmd.AddCommand(serviceCreateCmd)
	serviceCmd.AddCommand(serviceUpdateCmd)
}
