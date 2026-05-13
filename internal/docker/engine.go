package docker

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

func init() {
	// Verify docker is installed
	if err := exec.Command("docker", "--version").Run(); err != nil {
		fmt.Printf("Warning: Docker CLI not found or not accessible: %v\n", err)
	}
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

// StartContainer creates and starts a container with the given image and name, returning its IP address.
func StartContainer(taskID, imageName string) (string, error) {
	containerName := "gbnt-" + taskID

	// Run container detached
	cmd := exec.Command("docker", "run", "-d", "--name", containerName, "-l", "gbnt.task.id="+taskID, imageName)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("failed to run container: %w", err)
	}

	// Fetch container IP
	ipCmd := exec.Command("docker", "inspect", "-f", "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}", containerName)
	var out bytes.Buffer
	ipCmd.Stdout = &out
	if err := ipCmd.Run(); err != nil {
		return "", fmt.Errorf("failed to inspect container IP: %w", err)
	}

	ip := strings.TrimSpace(out.String())
	return ip, nil
}
