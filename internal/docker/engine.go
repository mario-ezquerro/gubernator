package docker

import (
	"bytes"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/mario-ezquerro/gubernator/internal/coredns"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

func init() {
	// Verify docker is installed
	if err := exec.Command("docker", "--version").Run(); err != nil {
		fmt.Printf("Warning: Docker CLI not found or not accessible: %v\n", err)
	}
}

// ContainerConfig holds all the runtime options for a container,
// mirroring what a docker-compose service definition can provide.
type ContainerConfig struct {
	TaskID            string
	Image             string
	Ports             []string // ["8080:80", "443:443"]
	Env               []string // ["FOO=bar", "BAR=baz"]
	Volumes           []string // ["/host:/container", "namedvol:/data"]
	Command           string   // optional override command
	Restart           string   // restart policy e.g. "unless-stopped", "always", "on-failure"
	CpuLimit          string   // e.g. "1.5"
	MemoryLimit       string   // e.g. "512M", "2G"
	MemoryReservation string   // e.g. "128M"
}

// PullImage pulls a Docker image from a registry.
func PullImage(imageName string) error {
	if err := exec.Command("docker", "image", "inspect", imageName).Run(); err == nil {
		return nil
	}
	cmd := exec.Command("docker", "pull", imageName)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to pull image: %w", err)
	}
	return nil
}

// StartContainer creates and starts a container with full compose-like config.
// Returns the container name and its internal IP address.
// All managed containers are automatically connected to gbnt-net for DNS resolution.
func StartContainer(cfg ContainerConfig) (containerName, ip string, err error) {
	containerName = "gbnt-" + cfg.TaskID

	restartPolicy := cfg.Restart
	if restartPolicy == "" {
		restartPolicy = "unless-stopped"
	}

	args := []string{"run", "-d", "--name", containerName, "--restart", restartPolicy, "-l", "gbnt.task.id=" + cfg.TaskID}

	// Resource limits & reservations
	if cfg.CpuLimit != "" {
		args = append(args, "--cpus", cfg.CpuLimit)
	}
	if cfg.MemoryLimit != "" {
		args = append(args, "--memory", cfg.MemoryLimit)
	}
	if cfg.MemoryReservation != "" {
		args = append(args, "--memory-reservation", cfg.MemoryReservation)
	}

	// Port mappings: -p host:container
	for _, p := range cfg.Ports {
		args = append(args, "-p", p)
	}

	// Environment variables: -e KEY=VAL
	for _, e := range cfg.Env {
		args = append(args, "-e", e)
	}

	// Volume mounts: -v host:container
	for _, v := range cfg.Volumes {
		args = append(args, "-v", v)
	}

	// Set CoreDNS as resolver if running
	dnsIP := coredns.GetContainerIP()
	if dnsIP != "" {
		args = append(args, "--dns", dnsIP)
	}

	args = append(args, cfg.Image)

	// Optional command override
	if cfg.Command != "" {
		args = append(args, splitCommand(cfg.Command)...)
	}

	cmd := exec.Command("docker", args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err = cmd.Run(); err != nil {
		return "", "", fmt.Errorf("failed to run container: %w", err)
	}

	// Connect the container to gbnt-net so it can resolve *.gbnt via CoreDNS.
	// This must be done before querying the IP on gbnt-net.
	if connErr := coredns.ConnectContainer(containerName); connErr != nil {
		// Non-fatal: container is running, DNS is just not available on gbnt-net
		fmt.Printf("⚠️  docker: failed to connect %s to gbnt-net: %v\n", containerName, connErr)
	}

	// Fetch container IP in gbnt-net
	ipCmd := exec.Command("docker", "inspect", "-f", fmt.Sprintf("{{(index .NetworkSettings.Networks \"%s\").IPAddress}}", coredns.NetworkName), containerName)
	var out bytes.Buffer
	ipCmd.Stdout = &out
	if err = ipCmd.Run(); err != nil {
		return containerName, "", fmt.Errorf("container started but failed to inspect IP on gbnt-net: %w", err)
	}

	ip = strings.TrimSpace(out.String())

	return containerName, ip, nil
}

// StopContainer stops and removes a container by name.
// It also disconnects the container from gbnt-net before removal.
func StopContainer(containerName string) error {
	// Disconnect from gbnt-net first (best effort)
	coredns.DisconnectContainer(containerName)

	// Stop gracefully
	exec.Command("docker", "stop", containerName).Run()
	// Remove
	if err := exec.Command("docker", "rm", "-f", containerName).Run(); err != nil {
		return fmt.Errorf("failed to remove container %s: %w", containerName, err)
	}
	return nil
}

// splitCommand parses a command string into individual arguments,
// SplitCommand splits a command string into arguments (like a shell would),
// respecting single and double quotes.
func SplitCommand(cmd string) []string {
	return splitCommand(cmd)
}

func splitCommand(cmd string) []string {
	var args []string
	var current strings.Builder
	inDoubleQuotes := false
	inSingleQuotes := false
	escaped := false

	for i := 0; i < len(cmd); i++ {
		r := rune(cmd[i])
		if escaped {
			current.WriteRune(r)
			escaped = false
			continue
		}

		if r == '\\' {
			escaped = true
			continue
		}

		if r == '"' && !inSingleQuotes {
			inDoubleQuotes = !inDoubleQuotes
			continue
		}

		if r == '\'' && !inDoubleQuotes {
			inSingleQuotes = !inSingleQuotes
			continue
		}

		if (r == ' ' || r == '\t') && !inDoubleQuotes && !inSingleQuotes {
			if current.Len() > 0 {
				args = append(args, current.String())
				current.Reset()
			}
			continue
		}

		current.WriteRune(r)
	}

	if current.Len() > 0 {
		args = append(args, current.String())
	}

	return args
}

// ExecuteNodeDockerAction executes a docker command (e.g. "stop", "start", "rm -f") on the specified node.
// If nodeID is a remote worker node, it executes over SSH. If local, it runs directly.
func ExecuteNodeDockerAction(nodeID, containerName, action string) error {
	if containerName == "" {
		return nil
	}

	// If assigned to a remote worker node, execute via SSH
	var node db.Node
	if err := db.DB.Where("id = ? OR ip = ?", nodeID, nodeID).First(&node).Error; err == nil &&
		node.Role != "manager" && node.ID != "node-local-manager" && node.IP != "" && node.IP != "127.0.0.1" {
		sshArgs := []string{"-o", "UserKnownHostsFile=/dev/null", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=5"}
		keyCandidates := []string{
			"/root/.ssh/id_ed25519", "/root/.ssh/id_rsa",
			"/data/id_ed25519", "/data/id_rsa",
			"/data/ssh/id_ed25519", "/data/ssh/id_rsa",
			"/home/ubuntu/.ssh/id_ed25519", "/home/ubuntu/.ssh/id_rsa",
		}
		if home, err := os.UserHomeDir(); err == nil {
			keyCandidates = append(keyCandidates, filepath.Join(home, ".ssh", "id_ed25519"), filepath.Join(home, ".ssh", "id_rsa"))
		}
		for _, k := range keyCandidates {
			if _, err := os.Stat(k); err == nil {
				sshArgs = append(sshArgs, "-i", k)
				break
			}
		}
		remoteCmd := fmt.Sprintf("sudo docker %s %s", action, containerName)
		sshArgs = append(sshArgs, fmt.Sprintf("ubuntu@%s", node.IP), remoteCmd)
		return exec.Command("ssh", sshArgs...).Run()
	}

	// Local docker command execution
	fields := strings.Fields(action)
	args := append(fields, containerName)
	return exec.Command("docker", args...).Run()
}

// InspectContainerStatus queries Docker for the State.Status of a container ("running", "exited", "dead", etc.).
func InspectContainerStatus(nodeID, containerName string) (string, error) {
	if containerName == "" {
		return "", fmt.Errorf("empty container name")
	}

	var node db.Node
	if err := db.DB.Where("id = ? OR ip = ?", nodeID, nodeID).First(&node).Error; err == nil &&
		node.Role != "manager" && node.ID != "node-local-manager" && node.IP != "" && node.IP != "127.0.0.1" {
		sshArgs := []string{"-o", "UserKnownHostsFile=/dev/null", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=5"}
		keyCandidates := []string{
			"/root/.ssh/id_ed25519", "/root/.ssh/id_rsa",
			"/data/id_ed25519", "/data/id_rsa",
			"/data/ssh/id_ed25519", "/data/ssh/id_rsa",
		}
		for _, k := range keyCandidates {
			if _, err := os.Stat(k); err == nil {
				sshArgs = append(sshArgs, "-i", k)
				break
			}
		}
		remoteCmd := fmt.Sprintf("sudo docker inspect -f '{{.State.Status}}' %s", containerName)
		sshArgs = append(sshArgs, fmt.Sprintf("ubuntu@%s", node.IP), remoteCmd)
		out, err := exec.Command("ssh", sshArgs...).Output()
		if err != nil {
			return "", err
		}
		return strings.TrimSpace(string(out)), nil
	}

	out, err := exec.Command("docker", "inspect", "-f", "{{.State.Status}}", containerName).Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

// RemoveContainerOnNode disconnects from gbnt-net (if local) and forcibly removes the container.
func RemoveContainerOnNode(nodeID, containerName string) error {
	if containerName == "" {
		return nil
	}
	// Best effort disconnect network
	coredns.DisconnectContainer(containerName)
	return ExecuteNodeDockerAction(nodeID, containerName, "rm -f")
}

// PruneOrphanContainers searches for all gbnt-* containers on the local Docker engine
// and removes any that do not belong to activeContainerNames.
// Skips system containers (gbnt-coredns, gbnt-caddy, gbnt-monitor-*).
func PruneOrphanContainers(activeContainerNames map[string]bool) int {
	out, err := exec.Command("docker", "ps", "-a", "--filter", "name=gbnt-", "--format", "{{.Names}}").Output()
	if err != nil {
		return 0
	}

	lines := strings.Split(string(out), "\n")
	pruned := 0
	for _, line := range lines {
		name := strings.TrimSpace(line)
		if name == "" {
			continue
		}
		// Skip system infrastructure containers
		if name == "gbnt-coredns" || name == "gbnt-caddy" || strings.HasPrefix(name, "gbnt-monitor-") {
			continue
		}

		// If this container is NOT recognized in active/desired tasks, prune it
		if !activeContainerNames[name] {
			if err := exec.Command("docker", "rm", "-f", name).Run(); err == nil {
				pruned++
				slog.Info("docker: pruned orphan container", "name", name)
			}
		}
	}
	return pruned
}
