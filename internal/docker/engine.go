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
