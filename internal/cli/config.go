package cli

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"text/tabwriter"

	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"
)

type ConfigContext struct {
	Name   string `yaml:"name"`
	Server string `yaml:"server"`
	Token  string `yaml:"token,omitempty"`
}

type CLIConfig struct {
	CurrentContext string          `yaml:"current-context"`
	Contexts       []ConfigContext `yaml:"contexts"`
}

var configCmd = &cobra.Command{
	Use:   "config",
	Short: "Manage gbnt configuration and contexts",
}

var configGetContextsCmd = &cobra.Command{
	Use:   "get-contexts",
	Short: "List all contexts",
	Run: func(cmd *cobra.Command, args []string) {
		cfg := loadConfig()
		w := tabwriter.NewWriter(os.Stdout, 0, 0, 3, ' ', 0)
		fmt.Fprintln(w, "CURRENT\tNAME\tSERVER")
		for _, ctx := range cfg.Contexts {
			current := ""
			if ctx.Name == cfg.CurrentContext {
				current = "*"
			}
			fmt.Fprintf(w, "%s\t%s\t%s\n", current, ctx.Name, ctx.Server)
		}
		w.Flush()
	},
}

var configUseContextCmd = &cobra.Command{
	Use:   "use-context [name]",
	Short: "Set the current context",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		name := args[0]
		cfg := loadConfig()
		found := false
		for _, ctx := range cfg.Contexts {
			if ctx.Name == name {
				found = true
				break
			}
		}
		if !found {
			fmt.Printf("Context '%s' not found.\n", name)
			os.Exit(1)
		}
		cfg.CurrentContext = name
		saveConfig(cfg)
		fmt.Printf("Switched to context \"%s\".\n", name)
	},
}

func init() {
	rootCmd.AddCommand(configCmd)
	configCmd.AddCommand(configGetContextsCmd)
	configCmd.AddCommand(configUseContextCmd)
	configCmd.AddCommand(configAddContextCmd)
	configCmd.AddCommand(configCurrentContextCmd)

	configAddContextCmd.Flags().StringVar(&contextServer, "server", "", "Manager API URL (e.g., http://192.168.1.10:4000)")
	configAddContextCmd.Flags().StringVar(&contextToken, "token", "", "Bearer API token (from gbnt legion info)")
	configAddContextCmd.MarkFlagRequired("server")
	configAddContextCmd.MarkFlagRequired("token")
}

// configAddContextCmd adds or updates a context in ~/.gbntctl/config.
var (
	contextServer string
	contextToken  string
)

var configAddContextCmd = &cobra.Command{
	Use:   "add-context [name]",
	Short: "Add or update a server context in ~/.gbntctl/config",
	Long: `Add a named context so you can manage a remote Gubernator manager.

Example:
  gbnt config add-context production \
      --server http://192.168.1.10:4000 \
      --token <API_TOKEN>

  gbnt config use-context production
  gbnt node ls`,
	Args: cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		name := args[0]
		if contextServer == "" || contextToken == "" {
			fmt.Fprintln(os.Stderr, "Error: --server and --token are required.")
			cmd.Help()
			os.Exit(1)
		}

		cfg := loadConfig()

		// Update existing or append new context
		found := false
		for i, ctx := range cfg.Contexts {
			if ctx.Name == name {
				cfg.Contexts[i].Server = contextServer
				cfg.Contexts[i].Token = contextToken
				found = true
				break
			}
		}
		if !found {
			cfg.Contexts = append(cfg.Contexts, ConfigContext{
				Name:   name,
				Server: contextServer,
				Token:  contextToken,
			})
		}

		// Auto-select if it's the first context
		if cfg.CurrentContext == "" {
			cfg.CurrentContext = name
		}

		saveConfig(cfg)
		fmt.Printf("✅ Context \"%s\" saved → %s\n", name, configPath())
		if cfg.CurrentContext == name {
			fmt.Printf("   This is now the active context. Run: gbnt node ls\n")
		} else {
			fmt.Printf("   To use this context: gbnt config use-context %s\n", name)
		}
	},
}

var configCurrentContextCmd = &cobra.Command{
	Use:   "current-context",
	Short: "Show the currently active context",
	Run: func(cmd *cobra.Command, args []string) {
		cfg := loadConfig()
		if cfg.CurrentContext == "" {
			fmt.Println("No active context. Using default: http://localhost:4000")
			return
		}
		fmt.Println(cfg.CurrentContext)
	},
}


func configPath() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".gbntctl", "config")
}

func loadConfig() CLIConfig {
	var cfg CLIConfig
	data, err := os.ReadFile(configPath())
	if err == nil {
		yaml.Unmarshal(data, &cfg)
	}
	return cfg
}

func saveConfig(cfg CLIConfig) {
	data, _ := yaml.Marshal(cfg)
	os.MkdirAll(filepath.Dir(configPath()), 0755)
	os.WriteFile(configPath(), data, 0600)
}

// GetAPIEndpoint returns the server URL from the current context without a trailing slash.
func GetAPIEndpoint() string {
	cfg := loadConfig()
	for _, ctx := range cfg.Contexts {
		if ctx.Name == cfg.CurrentContext {
			return ctx.Server
		}
	}
	// Fallback to localhost if no config exists
	return "http://localhost:4000"
}

// DoAPIRequest securely sends an HTTP request to the active Manager
func DoAPIRequest(method, path string, body io.Reader) (*http.Response, error) {
	cfg := loadConfig()
	var server, token string
	for _, ctx := range cfg.Contexts {
		if ctx.Name == cfg.CurrentContext {
			server = ctx.Server
			token = ctx.Token
			break
		}
	}
	if server == "" {
		server = "http://localhost:4000"
		token = "admin" // Default fallback
	}

	req, err := http.NewRequest(method, server+path, body)
	if err != nil {
		return nil, err
	}

	if envToken := os.Getenv("GBNT_API_TOKEN"); envToken != "" {
		token = envToken
	}

	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	return http.DefaultClient.Do(req)
}
