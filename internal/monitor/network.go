package monitor

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// MonitorDir returns the path to the monitor config directory (~/.gbnt/monitor/).
func MonitorDir() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".gbnt", "monitor")
}

// EnsureNetwork creates the gbnt-monitor-net Docker network if it doesn't exist.
func EnsureNetwork() error {
	// Check if network exists
	out, err := exec.Command("docker", "network", "ls", "--filter", "name=gbnt-monitor-net", "--format", "{{.Name}}").Output()
	if err != nil {
		return fmt.Errorf("failed to list docker networks: %w", err)
	}
	if strings.TrimSpace(string(out)) == "gbnt-monitor-net" {
		return nil // already exists
	}
	fmt.Println("🔗 Creating Docker network: gbnt-monitor-net")
	cmd := exec.Command("docker", "network", "create", "gbnt-monitor-net")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// RemoveNetwork removes the gbnt-monitor-net Docker network.
func RemoveNetwork() {
	exec.Command("docker", "network", "rm", "gbnt-monitor-net").Run()
}
