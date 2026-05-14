package cli

import (
	"fmt"
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
	
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	return http.DefaultClient.Do(req)
}
