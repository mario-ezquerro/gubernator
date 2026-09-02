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
	"time"

	"github.com/mario-ezquerro/gubernator/internal/examples"
	"github.com/spf13/cobra"
)

var examplesCmd = &cobra.Command{
	Use:   "examples",
	Short: "Manage built-in POC examples and architectural blueprints",
}

var exampleTargetNode string

var examplesLsCmd = &cobra.Command{
	Use:   "ls",
	Short: "List all built-in POC examples and templates",
	Run: func(cmd *cobra.Command, args []string) {
		var exList []examples.POCExample

		resp, err := DoAPIRequestWithTimeout("GET", "/v1/examples", nil, 1*time.Second)
		if err == nil && resp.StatusCode == http.StatusOK {
			defer resp.Body.Close()
			var data struct {
				Examples []examples.POCExample `json:"examples"`
				Total    int                   `json:"total"`
			}
			if err := json.NewDecoder(resp.Body).Decode(&data); err == nil && len(data.Examples) > 0 {
				exList = data.Examples
			}
		}

		if len(exList) == 0 {
			// Graceful offline fallback to embedded catalog
			exList = examples.GetAllPOCExamples()
		}

		fmt.Println("🏛️ Gubernator Built-in POC Examples Library:")
		fmt.Printf("Total Available: %d POC blueprints\n\n", len(exList))

		w := tabwriter.NewWriter(os.Stdout, 0, 0, 3, ' ', 0)
		fmt.Fprintln(w, "ID\tNAME\tCATEGORY\tDEFAULT STACK\tSERVICES")
		for _, ex := range exList {
			svcs := strings.Join(ex.Services, ", ")
			fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\n", ex.ID, ex.Name, ex.Category, ex.DefaultStack, svcs)
		}
		w.Flush()

		fmt.Println("\nTo deploy a POC example:")
		fmt.Println("  gbnt examples deploy <ID>")
		fmt.Println("  gbnt examples deploy all")
	},
}

var examplesDeployCmd = &cobra.Command{
	Use:   "deploy [id|all]",
	Short: "Deploy one or all POC examples into the cluster",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		exampleID := strings.TrimSpace(args[0])

		payload := map[string]string{
			"id":          exampleID,
			"target_node": exampleTargetNode,
		}

		body, _ := json.Marshal(payload)
		resp, err := DoAPIRequest("POST", "/v1/examples/deploy", bytes.NewBuffer(body))
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reaching API: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		bodyBytes, _ := io.ReadAll(resp.Body)
		if resp.StatusCode != http.StatusOK {
			var errResp map[string]string
			if err := json.Unmarshal(bodyBytes, &errResp); err == nil && errResp["error"] != "" {
				fmt.Fprintf(os.Stderr, "❌ Failed to deploy POC example: %s\n", errResp["error"])
			} else {
				fmt.Fprintf(os.Stderr, "❌ Failed to deploy POC example: %s\n", string(bodyBytes))
			}
			os.Exit(1)
		}

		var res map[string]interface{}
		json.Unmarshal(bodyBytes, &res)

		if exampleID == "all" {
			count := res["deployed_count"]
			fmt.Printf("🚀 Successfully deployed %v POC examples into the cluster!\n", count)
			if errs, ok := res["errors"].([]interface{}); ok && len(errs) > 0 {
				fmt.Println("⚠️  Some examples encountered warnings:")
				for _, e := range errs {
					fmt.Printf("  • %v\n", e)
				}
			}
		} else {
			stackName := res["stack_name"]
			fmt.Printf("🚀 POC Example '%s' successfully deployed as Stack '%v'!\n", exampleID, stackName)
		}
		fmt.Println("Check running tasks with: gbnt task ls")
	},
}

func init() {
	rootCmd.AddCommand(examplesCmd)
	examplesCmd.AddCommand(examplesLsCmd)
	examplesCmd.AddCommand(examplesDeployCmd)

	examplesDeployCmd.Flags().StringVarP(&exampleTargetNode, "target-node", "t", "auto", "Target Centurion node (or 'auto' for scheduler placement)")
}
