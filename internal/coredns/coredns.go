package coredns

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

const (
	// ContainerName is the name of the CoreDNS Docker container managed by Gubernator.
	ContainerName = "gbnt-coredns"

	// ImageName is the official CoreDNS Docker image.
	ImageName = "coredns/coredns:latest"

	// DNSPort is the port CoreDNS listens on (UDP+TCP 53 mapped to host 5354 to avoid privilege issues).
	DNSPort = "5354:53/udp"

	// VolumeName is the Docker named volume for CoreDNS config files.
	VolumeName = "gbnt-coredns-conf"

	// ConfigDir returns the path inside the container where config is mounted.
	ConfigMountPath = "/etc/coredns"
)

// CoreDNSDir returns the path to the CoreDNS config directory on the host (~/.gbnt/coredns/).
func CoreDNSDir() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".gbnt", "coredns")
}

// HostsFilePath returns the absolute path to the gubernator.hosts file.
func HostsFilePath() string {
	return filepath.Join(CoreDNSDir(), "gubernator.hosts")
}

// CorefilePath returns the absolute path to the Corefile.
func CorefilePath() string {
	return filepath.Join(CoreDNSDir(), "Corefile")
}

// EnsureConfigDir creates the CoreDNS config directory and writes default config files if they don't exist.
func EnsureConfigDir() error {
	dir := CoreDNSDir()
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create coredns config dir: %w", err)
	}

	// Write Corefile if it doesn't exist
	corefilePath := CorefilePath()
	if _, err := os.Stat(corefilePath); os.IsNotExist(err) {
		if err := os.WriteFile(corefilePath, []byte(defaultCorefile()), 0644); err != nil {
			return fmt.Errorf("failed to write Corefile: %w", err)
		}
	}

	// Write empty hosts file if it doesn't exist
	hostsPath := HostsFilePath()
	if _, err := os.Stat(hostsPath); os.IsNotExist(err) {
		if err := os.WriteFile(hostsPath, []byte("# Gubernator Auto-Generated CoreDNS Hosts File\n"), 0644); err != nil {
			return fmt.Errorf("failed to write initial hosts file: %w", err)
		}
	}

	return nil
}

// defaultCorefile returns the CoreDNS configuration.
// Uses the 'hosts' plugin to serve *.gbnt from gubernator.hosts,
// with auto-reload every 3s. Unknown queries are forwarded to public DNS.
func defaultCorefile() string {
	forwarders := os.Getenv("GBNT_DNS_FORWARDERS")
	if forwarders == "" {
		forwarders = "8.8.8.8 1.1.1.1"
	}
	return fmt.Sprintf(`# Gubernator CoreDNS Configuration
# Managed automatically — do not edit manually.

gbnt {
    hosts /etc/coredns/gubernator.hosts {
        ttl 5
        reload 3s
        fallthrough
    }
    log
    errors
}

. {
    forward . %s
    cache 30
    log
    errors
}
`, forwarders)
}

// EnsureRunning starts the CoreDNS container if it is not already running.
// This function is idempotent: calling it multiple times is safe.
func EnsureRunning() error {
	if err := EnsureConfigDir(); err != nil {
		return err
	}

	// Populate the config volume
	if err := populateConfigVolume(); err != nil {
		return fmt.Errorf("failed to populate coredns config volume: %w", err)
	}

	// Check if container already exists and is running
	out, err := exec.Command("docker", "inspect", "-f", "{{.State.Status}}", ContainerName).Output()
	if err == nil {
		status := strings.TrimSpace(string(out))
		if status == "running" {
			fmt.Println("🌐 CoreDNS: already running.")
			return nil
		}
		// Container exists but not running — remove it first
		exec.Command("docker", "rm", "-f", ContainerName).Run()
	}

	fmt.Println("🌐 Starting CoreDNS container (gbnt-coredns)...")

	baseArgs := []string{
		"run", "-d",
		"--name", ContainerName,
		"--restart", "unless-stopped",
		"--net", NetworkName,
		"-p", DNSPort,
		"-p", strings.Replace(DNSPort, "udp", "tcp", 1),
		"-v", VolumeName + ":" + ConfigMountPath + ":ro",
	}

	// Try with privileged port 53 mapping first (for macOS resolver compatibility)
	argsPrivileged := append([]string{}, baseArgs...)
	argsPrivileged = append(argsPrivileged, 
		"-p", "127.0.0.1:53:53/udp", 
		"-p", "127.0.0.1:53:53/tcp", 
		ImageName, 
		"-conf", "/etc/coredns/Corefile")

	cmd := exec.Command("docker", argsPrivileged...)
	if err := cmd.Run(); err != nil {
		// Clean up the failed container attempt
		exec.Command("docker", "rm", "-f", ContainerName).Run()
		
		fmt.Println("⚠️  Could not bind to local port 53 (in use). Falling back to 5354 only...")
		
		argsFallback := append(baseArgs, ImageName, "-conf", "/etc/coredns/Corefile")
		cmdFallback := exec.Command("docker", argsFallback...)
		cmdFallback.Stdout = os.Stdout
		cmdFallback.Stderr = os.Stderr
		if err := cmdFallback.Run(); err != nil {
			return fmt.Errorf("failed to start CoreDNS container: %w", err)
		}
	} else {
		fmt.Println("🌟 Bound successfully to 127.0.0.1:53 (macOS native resolver compatibility active!)")
	}

	fmt.Println("✅ CoreDNS started successfully. DNS domain: *.gbnt")
	fmt.Printf("   📡 Listening on port 5354 (UDP+TCP)\n")
	fmt.Printf("   📁 Config: %s\n", CoreDNSDir())
	return nil
}

// ReloadConfig sends a SIGHUP signal to the CoreDNS container so it reloads
// its hosts file. This is called automatically after GenerateHostsFile().
// Note: The 'hosts' plugin also has a built-in 'reload 3s' option as fallback.
func ReloadConfig() error {
	out, err := exec.Command("docker", "inspect", "-f", "{{.State.Running}}", ContainerName).Output()
	if err != nil || strings.TrimSpace(string(out)) != "true" {
		// CoreDNS not running, skip reload silently
		return nil
	}

	// First update the volume with the new hosts file
	if err := updateHostsInVolume(); err != nil {
		return fmt.Errorf("failed to update hosts in volume: %w", err)
	}

	// Send SIGHUP to trigger reload
	if err := exec.Command("docker", "kill", "-s", "SIGHUP", ContainerName).Run(); err != nil {
		return fmt.Errorf("failed to send SIGHUP to CoreDNS: %w", err)
	}

	fmt.Println("🔄 CoreDNS: hosts file reloaded.")
	return nil
}

// Stop stops and removes the CoreDNS container.
func Stop() {
	fmt.Printf("⏹  Stopping %s...\n", ContainerName)
	exec.Command("docker", "stop", ContainerName).Run()
	exec.Command("docker", "rm", "-f", ContainerName).Run()
	exec.Command("docker", "volume", "rm", "-f", VolumeName).Run()
}

// Restart stops and starts the CoreDNS container.
func Restart() error {
	Stop()
	return EnsureRunning()
}

// Status prints the current status of the CoreDNS container.
func Status() string {
	out, err := exec.Command("docker", "inspect", "-f",
		"{{.State.Status}} | {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}",
		ContainerName).Output()
	if err != nil {
		return "not running"
	}
	return strings.TrimSpace(string(out))
}

// GetContainerIP returns the IP address of the CoreDNS container within gbnt-net.
func GetContainerIP() string {
	out, err := exec.Command("docker", "inspect", "-f",
		fmt.Sprintf("{{(index .NetworkSettings.Networks \"%s\").IPAddress}}", NetworkName),
		ContainerName).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

// populateConfigVolume creates the named volume and copies config files into it
// using a temporary alpine container helper.
func populateConfigVolume() error {
	dir := CoreDNSDir()

	// Create volume
	exec.Command("docker", "volume", "create", VolumeName).Run()

	helperName := "gbnt-coredns-vol-helper"
	exec.Command("docker", "rm", "-f", helperName).Run()

	// Create helper container with the volume
	if err := exec.Command("docker", "create",
		"--name", helperName,
		"-v", VolumeName+":/data",
		"alpine:latest").Run(); err != nil {
		return fmt.Errorf("failed to create volume helper: %w", err)
	}
	defer exec.Command("docker", "rm", "-f", helperName).Run()

	// Copy config files into the volume
	if err := exec.Command("docker", "cp", dir+"/.", helperName+":/data/").Run(); err != nil {
		return fmt.Errorf("failed to copy configs into coredns volume: %w", err)
	}

	return nil
}

// updateHostsInVolume copies the updated gubernator.hosts into the config volume
// without recreating the full volume (faster, used on each DNS refresh).
func updateHostsInVolume() error {
	hostsPath := HostsFilePath()

	// Use a temporary alpine container to update only the hosts file
	cmd := exec.Command("docker", "run", "--rm", "-i",
		"-v", VolumeName+":/data",
		"alpine:latest",
		"sh", "-c", "cat > /data/gubernator.hosts")

	content, err := os.ReadFile(hostsPath)
	if err != nil {
		return fmt.Errorf("failed to read hosts file: %w", err)
	}

	cmd.Stdin = strings.NewReader(string(content))
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to update hosts in volume: %w", err)
	}
	return nil
}
