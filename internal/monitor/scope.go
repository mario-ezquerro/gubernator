package monitor

import (
	"fmt"
	"os/exec"
	"strings"

	"github.com/mario-ezquerro/gubernator/internal/db"
)

const (
	ScopeContainerName = "gbnt-monitor-scope"
	ScopePort          = "4040"
)

// ScopeStatusResponse holds the status information for Weave Scope.
type ScopeStatusResponse struct {
	Enabled   bool   `json:"enabled"`
	Status    string `json:"status"`
	Port      string `json:"port"`
	URL       string `json:"url,omitempty"`
	Container string `json:"container"`
}

// IsScopeRunning checks if the Weave Scope container is currently running.
func IsScopeRunning() bool {
	out, err := exec.Command("docker", "inspect", "-f", "{{.State.Running}}", ScopeContainerName).Output()
	if err != nil {
		return false
	}
	return strings.TrimSpace(string(out)) == "true"
}

// GetScopeStatus returns detailed status of the Weave Scope superpower.
func GetScopeStatus(hostIP string) ScopeStatusResponse {
	running := IsScopeRunning()
	statusStr := "stopped"
	if running {
		statusStr = "running"
	}

	urlStr := ""
	if running {
		if hostIP != "" {
			urlStr = fmt.Sprintf("http://%s:%s", hostIP, ScopePort)
		} else {
			urlStr = fmt.Sprintf("http://localhost:%s", ScopePort)
		}
	}

	return ScopeStatusResponse{
		Enabled:   running,
		Status:    statusStr,
		Port:      ScopePort,
		URL:       urlStr,
		Container: ScopeContainerName,
	}
}

// EnableScope deploys and starts the Weave Scope container.
func EnableScope() error {
	if IsScopeRunning() {
		return nil
	}

	fmt.Println("\n🕸️  Deploying Network Topology (Weave Scope)...")
	args := []string{
		"--net", "host",
		"--pid", "host",
		"--privileged",
		"-v", "/var/run/docker.sock:/var/run/docker.sock",
		"weaveworks/scope:latest",
		"--weave=false",
		"--app.http.address=:" + ScopePort,
	}

	if err := runContainer(ScopeContainerName, args); err != nil {
		return fmt.Errorf("failed to start Weave Scope container: %w", err)
	}

	if db.DB != nil {
		RegisterScopeStackInDB(db.DB)
	}

	fmt.Println("✅ Network Topology (Weave Scope) is now active on port 4040.")
	return nil
}

// DisableScope stops and removes the Weave Scope container.
func DisableScope() error {
	fmt.Println("\n⏹  Stopping Network Topology (Weave Scope)...")
	exec.Command("docker", "rm", "-f", ScopeContainerName).Run()

	if db.DB != nil {
		UnregisterScopeStackFromDB(db.DB)
	}

	fmt.Println("✅ Network Topology (Weave Scope) stopped.")
	return nil
}
