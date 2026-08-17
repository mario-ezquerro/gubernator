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
	ScopeImage         = "marioezquerro/scope:latest"
)

// ScopeStatusResponse holds the status information for Weave Scope.
type ScopeStatusResponse struct {
	Enabled   bool   `json:"enabled"`
	Status    string `json:"status"`
	Port      string `json:"port"`
	URL       string `json:"url,omitempty"`
	Container string `json:"container"`
	Image     string `json:"image"`
	ImageID   string `json:"image_id,omitempty"`
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

	imgID := ""
	if out, err := exec.Command("docker", "inspect", "-f", "{{.Image}}", ScopeContainerName).Output(); err == nil {
		raw := strings.TrimSpace(string(out))
		if len(raw) > 19 {
			imgID = raw[:19]
		} else {
			imgID = raw
		}
	}

	return ScopeStatusResponse{
		Enabled:   running,
		Status:    statusStr,
		Port:      ScopePort,
		URL:       urlStr,
		Container: ScopeContainerName,
		Image:     ScopeImage,
		ImageID:   imgID,
	}
}

// getManagerHostIP returns the public/LAN IP of the manager node.
func getManagerHostIP() string {
	var managerNode db.Node
	if db.DB != nil && db.DB.Where("role = ?", "manager").First(&managerNode).Error == nil && managerNode.IP != "" {
		return managerNode.IP
	}
	return "127.0.0.1"
}

// EnableScope deploys and starts the Weave Scope container.
func EnableScope() error {
	if IsScopeRunning() {
		return nil
	}

	fmt.Println("\n🕸️  Deploying Network Topology (marioezquerro/scope)...")

	// Pull latest image to ensure the most updated image is used
	_ = exec.Command("docker", "pull", ScopeImage).Run()

	args := []string{
		"-e", "CHECKPOINT_DISABLE=1",
		"--net", "host",
		"--pid", "host",
		"--privileged",
		"-v", "/var/run/docker.sock:/var/run/docker.sock",
		"-v", "/proc:/host/proc:ro",
		"-v", "/sys:/sys:ro",
		ScopeImage,
		"--weave=false",
		"--probe.docker=true",
		"--probe.processes=true",
		"--probe.proc.spy=true",
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

// UpdateScopeImage pulls the latest image from Docker Hub and recreates Scope container.
func UpdateScopeImage() (string, error) {
	fmt.Println("\n🔄 Pulling latest marioezquerro/scope:latest from Docker Hub...")
	pullOut, err := exec.Command("docker", "pull", ScopeImage).CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("failed to pull image: %w (output: %s)", err, string(pullOut))
	}

	wasRunning := IsScopeRunning()
	if wasRunning {
		_ = DisableScope()
		if err := EnableScope(); err != nil {
			return "", fmt.Errorf("failed to restart scope with updated image: %w", err)
		}
	}

	return strings.TrimSpace(string(pullOut)), nil
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
