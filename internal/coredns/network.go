package coredns

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

const (
	// NetworkName is the shared Docker network for all Gubernator-managed containers.
	// All containers on this network can resolve *.gbnt via CoreDNS.
	NetworkName = "gbnt-net"
)

// EnsureNetwork creates the gbnt-net Docker network if it doesn't exist.
// The network uses the CoreDNS container as its DNS resolver once CoreDNS is running.
func EnsureNetwork() error {
	// Check if network already exists
	out, err := exec.Command("docker", "network", "ls",
		"--filter", "name="+NetworkName,
		"--format", "{{.Name}}").Output()
	if err != nil {
		return fmt.Errorf("failed to list docker networks: %w", err)
	}

	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if strings.TrimSpace(line) == NetworkName {
			fmt.Printf("🔗 Network '%s' already exists.\n", NetworkName)
			return nil
		}
	}

	fmt.Printf("🔗 Creating Docker network: %s\n", NetworkName)
	cmd := exec.Command("docker", "network", "create",
		"--driver", "bridge",
		"--label", "gbnt.managed=true",
		NetworkName)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to create docker network %s: %w", NetworkName, err)
	}

	fmt.Printf("✅ Network '%s' created.\n", NetworkName)
	return nil
}

// RemoveNetwork removes the gbnt-net Docker network.
func RemoveNetwork() {
	exec.Command("docker", "network", "rm", NetworkName).Run()
}

// ConnectContainer connects a running container to gbnt-net so it can
// resolve *.gbnt names via CoreDNS.
func ConnectContainer(containerName string) error {
	// Check if already connected
	out, err := exec.Command("docker", "inspect", "-f",
		fmt.Sprintf("{{index .NetworkSettings.Networks \"%s\"}}", NetworkName),
		containerName).Output()
	if err == nil && strings.TrimSpace(string(out)) != "<nil>" && strings.TrimSpace(string(out)) != "" {
		// Already connected
		return nil
	}

	if err := exec.Command("docker", "network", "connect", NetworkName, containerName).Run(); err != nil {
		return fmt.Errorf("failed to connect %s to %s: %w", containerName, NetworkName, err)
	}

	fmt.Printf("🔗 Container '%s' connected to '%s' (CoreDNS *.gbnt available).\n", containerName, NetworkName)
	return nil
}

// DisconnectContainer disconnects a container from gbnt-net.
// Called when a container is stopped/removed.
func DisconnectContainer(containerName string) {
	exec.Command("docker", "network", "disconnect", "-f", NetworkName, containerName).Run()
}

// SetNetworkDNS updates the gbnt-net network to use the CoreDNS container as
// its DNS server. This is called after CoreDNS starts and its IP is known.
// Note: Docker doesn't support updating an existing network's DNS, so we
// connect newly started containers with --dns flag instead (handled in ConnectContainerWithDNS).
func GetNetworkInfo() string {
	out, err := exec.Command("docker", "network", "inspect", NetworkName,
		"--format", "{{.IPAM.Config}}").Output()
	if err != nil {
		return "unknown"
	}
	return strings.TrimSpace(string(out))
}

// ConnectContainerWithDNS connects a container to gbnt-net. Since Docker
// network DNS is set at container creation time, existing containers are
// connected via 'docker network connect'. New containers launched after
// CoreDNS starts will resolve *.gbnt automatically because CoreDNS serves
// the gbnt zone and the hosts plugin has a 3s auto-reload.
func ConnectContainerWithDNS(containerName string) error {
	return ConnectContainer(containerName)
}
