package caddy

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/mario-ezquerro/gubernator/internal/coredns"
)

const (
	// ContainerName is the name of the Caddy container managed by Gubernator.
	ContainerName = "gbnt-caddy"

	// ImageName is the official Caddy Docker image.
	ImageName = "caddy:latest"

	// VolumeName is the Docker named volume for Caddy configs.
	VolumeName = "gbnt-caddy-conf"

	// ConfigMountPath is the path where the config is mounted inside the container.
	ConfigMountPath = "/etc/caddy"
)

// CaddyDir returns the path to the Caddy config directory on the host (~/.gbnt/caddy/).
func CaddyDir() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".gbnt", "caddy")
}

// CaddyfilePath returns the absolute path to the Caddyfile.
func CaddyfilePath() string {
	return filepath.Join(CaddyDir(), "Caddyfile")
}

// EnsureConfigDir creates the Caddy config directory and writes a default Caddyfile if it doesn't exist.
func EnsureConfigDir() error {
	dir := CaddyDir()
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create caddy config dir: %w", err)
	}

	caddyfilePath := CaddyfilePath()
	if _, err := os.Stat(caddyfilePath); os.IsNotExist(err) {
		defaultContent := "# Gubernator Auto-Generated Caddyfile\n# Managed automatically — do not edit manually.\n\n:80 {\n\trespond \"Gubernator Caddy Ingress is running!\" 200\n}\n"
		if err := os.WriteFile(caddyfilePath, []byte(defaultContent), 0644); err != nil {
			return fmt.Errorf("failed to write default Caddyfile: %w", err)
		}
	}

	return nil
}

// EnsureRunning starts the Caddy container if it is not already running.
func EnsureRunning() error {
	if err := EnsureConfigDir(); err != nil {
		return err
	}

	// Populate the config volume
	if err := populateConfigVolume(); err != nil {
		return fmt.Errorf("failed to populate caddy config volume: %w", err)
	}

	// Check if container already exists and is running
	out, err := exec.Command("docker", "inspect", "-f", "{{.State.Status}}", ContainerName).Output()
	if err == nil {
		status := strings.TrimSpace(string(out))
		if status == "running" {
			fmt.Println("🔒 Caddy Ingress: already running.")
			return nil
		}
		// Container exists but not running — remove it first
		exec.Command("docker", "rm", "-f", ContainerName).Run()
	}

	fmt.Println("🔒 Starting Caddy Ingress container (gbnt-caddy)...")

	args := []string{
		"run", "-d",
		"--name", ContainerName,
		"--restart", "unless-stopped",
		"--net", coredns.NetworkName,
		"-p", "80:80",
		"-p", "443:443",
		"-v", VolumeName + ":" + ConfigMountPath + ":ro",
	}

	dnsIP := coredns.GetContainerIP()
	if dnsIP != "" {
		args = append(args, "--dns", dnsIP)
	}

	args = append(args, ImageName)

	cmd := exec.Command("docker", args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to start Caddy container: %w", err)
	}

	fmt.Println("✅ Caddy Ingress started successfully on ports 80 & 443.")
	return nil
}

// ReloadConfig reloads the Caddy configuration inside the container.
func ReloadConfig() error {
	out, err := exec.Command("docker", "inspect", "-f", "{{.State.Running}}", ContainerName).Output()
	if err != nil || strings.TrimSpace(string(out)) != "true" {
		// Caddy not running, skip reload silently
		return nil
	}

	// Update Caddyfile in the volume
	if err := updateCaddyfileInVolume(); err != nil {
		return fmt.Errorf("failed to update Caddyfile in volume: %w", err)
	}

	// Execute reload command in the container
	if err := exec.Command("docker", "exec", ContainerName, "caddy", "reload", "--config", "/etc/caddy/Caddyfile").Run(); err != nil {
		return fmt.Errorf("failed to reload Caddy: %w", err)
	}

	fmt.Println("🔄 Caddy Ingress: configuration reloaded.")
	return nil
}

// Stop stops and removes the Caddy container.
func Stop() {
	fmt.Printf("⏹  Stopping %s...\n", ContainerName)
	exec.Command("docker", "stop", ContainerName).Run()
	exec.Command("docker", "rm", "-f", ContainerName).Run()
	exec.Command("docker", "volume", "rm", "-f", VolumeName).Run()
}

// Status returns the current status of the Caddy container.
func Status() string {
	out, err := exec.Command("docker", "inspect", "-f",
		"{{.State.Status}} | {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}",
		ContainerName).Output()
	if err != nil {
		return "not running"
	}
	return strings.TrimSpace(string(out))
}

// populateConfigVolume creates the named volume and copies config files into it.
func populateConfigVolume() error {
	dir := CaddyDir()

	// Create volume
	exec.Command("docker", "volume", "create", VolumeName).Run()

	helperName := "gbnt-caddy-vol-helper"
	exec.Command("docker", "rm", "-f", helperName).Run()

	if err := exec.Command("docker", "create",
		"--name", helperName,
		"-v", VolumeName+":/data",
		"alpine:latest").Run(); err != nil {
		return fmt.Errorf("failed to create volume helper: %w", err)
	}
	defer exec.Command("docker", "rm", "-f", helperName).Run()

	if err := exec.Command("docker", "cp", dir+"/.", helperName+":/data/").Run(); err != nil {
		return fmt.Errorf("failed to copy configs into caddy volume: %w", err)
	}

	return nil
}

// updateCaddyfileInVolume copies the updated Caddyfile into the config volume.
func updateCaddyfileInVolume() error {
	caddyfilePath := CaddyfilePath()

	cmd := exec.Command("docker", "run", "--rm", "-i",
		"-v", VolumeName+":/data",
		"alpine:latest",
		"sh", "-c", "cat > /data/Caddyfile")

	content, err := os.ReadFile(caddyfilePath)
	if err != nil {
		return fmt.Errorf("failed to read Caddyfile: %w", err)
	}

	cmd.Stdin = strings.NewReader(string(content))
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to update Caddyfile in volume: %w", err)
	}
	return nil
}
