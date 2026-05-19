package monitor

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// Container names for the monitoring stack.
const (
	CadvisorName   = "gbnt-monitor-cadvisor"
	PrometheusName = "gbnt-monitor-prometheus"
	LokiName       = "gbnt-monitor-loki"
	PromtailName   = "gbnt-monitor-promtail"
	GrafanaName    = "gbnt-monitor-grafana"
	NetworkName    = "gbnt-monitor-net"
)

// AllContainers returns all monitoring container names.
func AllContainers() []string {
	return []string{CadvisorName, PrometheusName, LokiName, PromtailName, GrafanaName}
}

// DeployManagerStack deploys the full SRE monitoring stack on the Manager node.
func DeployManagerStack() error {
	dir := MonitorDir()

	// 1) cAdvisor
	fmt.Println("\n📊 Deploying cAdvisor (container metrics)...")
	if err := runContainer(CadvisorName, []string{
		"--net", NetworkName,
		"--privileged",
		"-p", "8081:8080",
		"-v", "/:/rootfs:ro",
		"-v", "/var/run:/var/run:ro",
		"-v", "/sys:/sys:ro",
		"-v", "/var/lib/docker/:/var/lib/docker:ro",
		"-v", "/dev/disk/:/dev/disk:ro",
		"--device", "/dev/kmsg",
		"gcr.io/cadvisor/cadvisor:latest",
	}); err != nil {
		return fmt.Errorf("cAdvisor failed: %w", err)
	}

	// 2) Loki (must start before Promtail)
	fmt.Println("📋 Deploying Loki (log aggregation)...")
	if err := runContainer(LokiName, []string{
		"--net", NetworkName,
		"-p", "3100:3100",
		"-v", filepath.Join(dir, "loki", "loki-config.yml") + ":/etc/loki/loki-config.yml:ro",
		"grafana/loki:latest",
		"-config.file=/etc/loki/loki-config.yml",
	}); err != nil {
		return fmt.Errorf("Loki failed: %w", err)
	}

	// 3) Promtail
	fmt.Println("📤 Deploying Promtail (log shipper)...")
	if err := runContainer(PromtailName, []string{
		"--net", NetworkName,
		"-v", filepath.Join(dir, "promtail", "promtail-config.yml") + ":/etc/promtail/config.yml:ro",
		"-v", "/var/log:/var/log:ro",
		"-v", "/var/lib/docker/containers:/var/lib/docker/containers:ro",
		"grafana/promtail:latest",
		"-config.file=/etc/promtail/config.yml",
	}); err != nil {
		return fmt.Errorf("Promtail failed: %w", err)
	}

	// 4) Prometheus
	fmt.Println("🔥 Deploying Prometheus (metrics collection)...")
	promArgs := []string{
		"--net", NetworkName,
		"-p", "9090:9090",
		"-v", filepath.Join(dir, "prometheus", "prometheus.yml") + ":/etc/prometheus/prometheus.yml:ro",
		// Allow Prometheus to reach the host Gubernator on :4002
		"--add-host", "host.docker.internal:host-gateway",
		"prom/prometheus:latest",
		"--config.file=/etc/prometheus/prometheus.yml",
		"--storage.tsdb.path=/prometheus",
		"--web.enable-lifecycle",
	}
	if err := runContainer(PrometheusName, promArgs); err != nil {
		return fmt.Errorf("Prometheus failed: %w", err)
	}

	// 5) Grafana
	fmt.Println("📈 Deploying Grafana (dashboards)...")
	grafanaArgs := []string{
		"--net", NetworkName,
		"-p", "3000:3000",
		"-v", filepath.Join(dir, "grafana", "provisioning") + ":/etc/grafana/provisioning:ro",
		"-e", "GF_SECURITY_ADMIN_USER=admin",
		"-e", "GF_SECURITY_ADMIN_PASSWORD=admin",
		"-e", "GF_USERS_ALLOW_SIGN_UP=false",
		"grafana/grafana:latest",
	}
	if err := runContainer(GrafanaName, grafanaArgs); err != nil {
		return fmt.Errorf("Grafana failed: %w", err)
	}

	return nil
}

// StopAll stops and removes all monitoring containers and the network.
func StopAll() {
	for _, name := range AllContainers() {
		fmt.Printf("⏹  Stopping %s...\n", name)
		exec.Command("docker", "stop", name).Run()
		exec.Command("docker", "rm", "-f", name).Run()
	}
	RemoveNetwork()
}

// Status prints the status of all monitoring containers.
func Status() {
	fmt.Println("\n🛡️  Gubernator SRE Monitor Status")
	fmt.Println(strings.Repeat("─", 70))

	for _, name := range AllContainers() {
		out, err := exec.Command("docker", "inspect", "--format",
			"{{.State.Status}} | {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}} | {{range $p, $conf := .NetworkSettings.Ports}}{{$p}}→{{(index $conf 0).HostPort}} {{end}}",
			name).Output()
		if err != nil {
			fmt.Printf("  %-30s  ❌ not running\n", name)
			continue
		}
		parts := strings.SplitN(strings.TrimSpace(string(out)), " | ", 3)
		status := parts[0]
		ip := ""
		ports := ""
		if len(parts) > 1 {
			ip = parts[1]
		}
		if len(parts) > 2 {
			ports = strings.TrimSpace(parts[2])
		}

		icon := "✅"
		if status != "running" {
			icon = "⚠️"
		}
		fmt.Printf("  %s %-30s  status=%-10s  ip=%-15s  ports=%s\n", icon, name, status, ip, ports)
	}
	fmt.Println()
}

// runContainer runs a container in detached mode with the given name and args.
// If a container with the same name already exists, it is removed first.
func runContainer(name string, args []string) error {
	// Remove if already exists
	exec.Command("docker", "rm", "-f", name).Run()

	fullArgs := []string{"run", "-d", "--name", name, "--restart", "unless-stopped"}
	fullArgs = append(fullArgs, args...)

	cmd := exec.Command("docker", fullArgs...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
