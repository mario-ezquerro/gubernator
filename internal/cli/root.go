package cli

import (
	"context"
	"fmt"
	"log"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/mario-ezquerro/gubernator/internal/api"
	"github.com/mario-ezquerro/gubernator/internal/telemetry"
	"github.com/spf13/cobra"
)

var Version = "dev"

var rootCmd = &cobra.Command{
	Use:   "gbnt",
	Short: "Gubernator is a lightweight container orchestrator",
	Long:  `A Goldilocks orchestrator combining the simplicity of Docker Swarm with the flexibility of Nomad.`,
}

var serveCmd = &cobra.Command{
	Use:   "serve",
	Short: "Start the Gubernator Manager API",
	Run: func(cmd *cobra.Command, args []string) {
		// Configure structured logger; JSON when GBNT_LOG_FORMAT=json
		var h slog.Handler = slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelInfo})
		if os.Getenv("GBNT_LOG_FORMAT") == "json" {
			h = slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelInfo})
		}
		slog.SetDefault(slog.New(h))

		ctx, cancel := context.WithCancel(context.Background())

		quit := make(chan os.Signal, 1)
		signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
		go func() {
			<-quit
			slog.Info("shutting down Gubernator")
			cancel()
		}()

		if err := api.Start(ctx); err != nil {
			log.Fatalf("Gubernator exited with error: %v", err)
		}
	},
}

var showMetrics bool

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Print the Gubernator version and adoption metrics",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Printf("Gubernator %s\n", Version)
		if showMetrics {
			stats := telemetry.GetAdoptionStats(false)
			fmt.Println("\n📊 Community Adoption & Release Metrics:")
			fmt.Printf("  • Total Releases:     %d\n", stats.TotalReleases)
			fmt.Printf("  • Total Downloads:    %d\n", stats.TotalDownloads)
			fmt.Printf("    - Linux:            %d\n", stats.DownloadsByOS["linux"])
			fmt.Printf("    - macOS:            %d\n", stats.DownloadsByOS["darwin"])
			fmt.Printf("    - Windows:          %d\n", stats.DownloadsByOS["windows"])
			fmt.Printf("  • GitHub Stars:       %d ⭐\n", stats.GitHubStars)
			fmt.Printf("  • GitHub Forks:       %d 🍴\n", stats.GitHubForks)
			fmt.Println("\n🛡️ Data Transparency & Privacy:")
			fmt.Printf("  • Data Source:        %s\n", stats.DataSource)
			fmt.Printf("  • Privacy Policy:     %s\n", stats.PrivacyPolicy)
		}
	},
}

func init() {
	versionCmd.Flags().BoolVarP(&showMetrics, "metrics", "m", false, "Display public adoption and GitHub release download metrics")
	rootCmd.AddCommand(serveCmd)
	rootCmd.AddCommand(versionCmd)
}

// Execute adds all child commands to the root command and sets flags appropriately.
func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
