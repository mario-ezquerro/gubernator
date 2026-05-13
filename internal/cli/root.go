package cli

import (
	"fmt"
	"os"

	"github.com/mario-ezquerro/gubernator/internal/api"
	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "gbnt",
	Short: "Gubernator is a lightweight container orchestrator",
	Long:  `A Goldilocks orchestrator combining the simplicity of Docker Swarm with the flexibility of Nomad.`,
}

var serveCmd = &cobra.Command{
	Use:   "serve",
	Short: "Start the Gubernator Manager API",
	Run: func(cmd *cobra.Command, args []string) {
		api.Start()
	},
}

func init() {
	rootCmd.AddCommand(serveCmd)
	// We will add 'nodeCmd' in node.go
}

// Execute adds all child commands to the root command and sets flags appropriately.
func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
