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

// ConnectGubernator connects the current gubernator container (if running inside Docker) to the monitor network.
func ConnectGubernator() error {
	hostname, err := os.Hostname()
	if err != nil {
		return nil // Hostname not available, probably not in docker or no permission
	}

	// Check if this hostname is a docker container by trying to inspect it
	err = exec.Command("docker", "inspect", hostname).Run()
	if err != nil {
		// Not running inside a docker container, or docker CLI is not available
		return nil
	}

	// Check if already connected to gbnt-monitor-net
	out, err := exec.Command("docker", "inspect", "-f",
		"{{index .NetworkSettings.Networks \"gbnt-monitor-net\"}}",
		hostname).Output()
	if err == nil && strings.TrimSpace(string(out)) != "<nil>" && strings.TrimSpace(string(out)) != "" {
		// Already connected
		return nil
	}

	if err := exec.Command("docker", "network", "connect", "gbnt-monitor-net", hostname).Run(); err != nil {
		return fmt.Errorf("failed to connect gubernator container (%s) to gbnt-monitor-net: %w", hostname, err)
	}

	fmt.Printf("🔗 Gubernator container (%s) connected to gbnt-monitor-net\n", hostname)
	return nil
}

// DisconnectGubernator disconnects the current gubernator container from the monitor network.
func DisconnectGubernator() {
	hostname, err := os.Hostname()
	if err != nil {
		return
	}

	if err := exec.Command("docker", "inspect", hostname).Run(); err == nil {
		exec.Command("docker", "network", "disconnect", "-f", "gbnt-monitor-net", hostname).Run()
	}
}

