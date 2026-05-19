package monitor

import (
	"fmt"
	"os"
	"os/exec"
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

	// Docker volume names for config persistence
	VolPrometheus       = "gbnt-monitor-prom-conf"
	VolLoki             = "gbnt-monitor-loki-conf"
	VolPromtail         = "gbnt-monitor-promtail-conf"
	VolGrafanaProv      = "gbnt-monitor-grafana-prov"
	VolPrometheusData   = "gbnt-monitor-prom-data"
	VolGrafanaData      = "gbnt-monitor-grafana-data"
)

// AllContainers returns all monitoring container names.
func AllContainers() []string {
	return []string{CadvisorName, PrometheusName, LokiName, PromtailName, GrafanaName}
}

// AllVolumes returns all monitoring volume names.
func AllVolumes() []string {
	return []string{VolPrometheus, VolLoki, VolPromtail, VolGrafanaProv, VolPrometheusData, VolGrafanaData}
}

// DeployManagerStack deploys the full SRE monitoring stack on the Manager node.
// It uses Docker named volumes populated via "docker cp" to avoid bind-mount issues
// when gbnt itself runs inside a container.
func DeployManagerStack() error {
	// Populate config volumes from generated files in MonitorDir()
	if err := populateConfigVolumes(); err != nil {
		return fmt.Errorf("failed to populate config volumes: %w", err)
	}

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
		"-v", VolLoki + ":/etc/loki:ro",
		"grafana/loki:latest",
		"-config.file=/etc/loki/loki-config.yml",
	}); err != nil {
		return fmt.Errorf("Loki failed: %w", err)
	}

	// 3) Promtail
	fmt.Println("📤 Deploying Promtail (log shipper)...")
	if err := runContainer(PromtailName, []string{
		"--net", NetworkName,
		"-v", VolPromtail + ":/etc/promtail:ro",
		"-v", "/var/log:/var/log:ro",
		"-v", "/var/lib/docker/containers:/var/lib/docker/containers:ro",
		"grafana/promtail:latest",
		"-config.file=/etc/promtail/promtail-config.yml",
	}); err != nil {
		return fmt.Errorf("Promtail failed: %w", err)
	}

	// 4) Prometheus
	fmt.Println("🔥 Deploying Prometheus (metrics collection)...")
	promArgs := []string{
		"--net", NetworkName,
		"-p", "9090:9090",
		"-v", VolPrometheus + ":/etc/prometheus:ro",
		"-v", VolPrometheusData + ":/prometheus",
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
		"-v", VolGrafanaProv + ":/etc/grafana/provisioning:ro",
		"-v", VolGrafanaData + ":/var/lib/grafana",
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

// StopAll stops and removes all monitoring containers, the network, and config volumes.
func StopAll() {
	for _, name := range AllContainers() {
		fmt.Printf("⏹  Stopping %s...\n", name)
		exec.Command("docker", "stop", name).Run()
		exec.Command("docker", "rm", "-f", name).Run()
	}
	for _, vol := range AllVolumes() {
		exec.Command("docker", "volume", "rm", "-f", vol).Run()
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

// populateConfigVolumes creates Docker named volumes and copies config files into them
// using a temporary alpine container. This works whether gbnt runs on the host or inside a container.
func populateConfigVolumes() error {
	dir := MonitorDir()

	type volCopy struct {
		volume    string
		srcDir    string // local dir to copy FROM
		destPath  string // path INSIDE the volume
	}

	copies := []volCopy{
		{VolPrometheus, dir + "/prometheus", "/data"},
		{VolLoki, dir + "/loki", "/data"},
		{VolPromtail, dir + "/promtail", "/data"},
		{VolGrafanaProv, dir + "/grafana/provisioning", "/data"},
	}

	for _, c := range copies {
		// Create volume
		exec.Command("docker", "volume", "create", c.volume).Run()

		helperName := "gbnt-vol-helper-" + c.volume

		// Remove any existing helper
		exec.Command("docker", "rm", "-f", helperName).Run()

		// Create a temporary container that mounts the volume
		if err := exec.Command("docker", "create", "--name", helperName,
			"-v", c.volume+":"+c.destPath,
			"alpine:latest").Run(); err != nil {
			return fmt.Errorf("failed to create helper for %s: %w", c.volume, err)
		}

		// Copy all files from the local source dir into the volume via docker cp
		// docker cp copies the CONTENTS of srcDir into destPath
		if err := exec.Command("docker", "cp", c.srcDir+"/.", helperName+":"+c.destPath+"/").Run(); err != nil {
			exec.Command("docker", "rm", "-f", helperName).Run()
			return fmt.Errorf("failed to copy configs into volume %s: %w", c.volume, err)
		}

		// Remove the helper container
		exec.Command("docker", "rm", "-f", helperName).Run()
	}

	fmt.Println("📦 Config volumes populated successfully.")
	return nil
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
