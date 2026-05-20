package docker

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/mario-ezquerro/gubernator/internal/coredns"
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
	TaskID  string
	Image   string
	Ports   []string // ["8080:80", "443:443"]
	Env     []string // ["FOO=bar", "BAR=baz"]
	Volumes []string // ["/host:/container", "namedvol:/data"]
	Command string   // optional override command
}

// PullImage pulls a Docker image from a registry.
func PullImage(imageName string) error {
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

	args := []string{"run", "-d", "--name", containerName, "-l", "gbnt.task.id=" + cfg.TaskID}

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

	args = append(args, cfg.Image)

	// Optional command override
	if cfg.Command != "" {
		args = append(args, strings.Fields(cfg.Command)...)
	}

	cmd := exec.Command("docker", args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err = cmd.Run(); err != nil {
		return "", "", fmt.Errorf("failed to run container: %w", err)
	}

	// Fetch container IP (default bridge network)
	ipCmd := exec.Command("docker", "inspect", "-f", "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}", containerName)
	var out bytes.Buffer
	ipCmd.Stdout = &out
	if err = ipCmd.Run(); err != nil {
		return containerName, "", fmt.Errorf("container started but failed to inspect IP: %w", err)
	}

	ip = strings.TrimSpace(out.String())

	// Connect the container to gbnt-net so it can resolve *.gbnt via CoreDNS.
	// This is done after start to not block the initial container launch.
	if connErr := coredns.ConnectContainer(containerName); connErr != nil {
		// Non-fatal: container is running, DNS is just not available on gbnt-net
		fmt.Printf("⚠️  docker: failed to connect %s to gbnt-net: %v\n", containerName, connErr)
	}

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
