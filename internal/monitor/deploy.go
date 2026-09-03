package monitor

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// Container names for the monitoring stack.
const (
	CadvisorName     = "gbnt-monitor-cadvisor"
	NodeExporterName = "gbnt-monitor-node-exporter"
	PrometheusName   = "gbnt-monitor-prometheus"
	LokiName         = "gbnt-monitor-loki"
	PromtailName     = "gbnt-monitor-promtail"
	GrafanaName      = "gbnt-monitor-grafana"
	JaegerName       = "gbnt-monitor-jaeger"
	NetworkName      = "gbnt-monitor-net"

	// Docker volume names for config persistence
	VolPrometheus     = "gbnt-monitor-prom-conf"
	VolLoki           = "gbnt-monitor-loki-conf"
	VolLokiData       = "gbnt-monitor-loki-data"
	VolPromtail       = "gbnt-monitor-promtail-conf"
	VolGrafanaProv    = "gbnt-monitor-grafana-prov"
	VolPrometheusData = "gbnt-monitor-prom-data"
	VolGrafanaData    = "gbnt-monitor-grafana-data"
)

// AllContainers returns all monitoring container names.
func AllContainers() []string {
	return []string{CadvisorName, NodeExporterName, PrometheusName, LokiName, PromtailName, GrafanaName, JaegerName}
}

// AllVolumes returns all monitoring volume names.
func AllVolumes() []string {
	return []string{VolPrometheus, VolLoki, VolLokiData, VolPromtail, VolGrafanaProv, VolPrometheusData, VolGrafanaData}
}

// DeployManagerStack deploys the full SRE monitoring stack on the Manager node.
// It uses Docker named volumes populated via "docker cp" to avoid bind-mount issues
// when gbnt itself runs inside a container.
// webUser/webPass are the Gubernator web credentials (GBNT_WEB_USER / GBNT_WEB_PASSWORD)
// used as Grafana admin credentials for SSO.
func DeployManagerStack(webUser, webPass string) error {
	// Connect Gubernator container to the monitor network
	if err := ConnectGubernator(); err != nil {
		fmt.Printf("⚠️  Warning: failed to connect Gubernator to monitor network: %v\n", err)
	}

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
		return fmt.Errorf("cadvisor failed: %w", err)
	}

	// 1b) Node Exporter
	fmt.Println("\n🖥 Deploying Node Exporter (host metrics)...")
	if err := EnsureNodeExporterRunning(); err != nil {
		return fmt.Errorf("node exporter failed: %w", err)
	}

	// 2) Loki (must start before Promtail)
	fmt.Println("📋 Deploying Loki (log aggregation)...")
	if err := runContainer(LokiName, []string{
		"--net", NetworkName,
		"-p", "3100:3100",
		"-v", VolLoki + ":/etc/loki:ro",
		"-v", VolLokiData + ":/loki",
		"grafana/loki:latest",
		"-config.file=/etc/loki/loki-config.yml",
	}); err != nil {
		return fmt.Errorf("loki failed: %w", err)
	}

	// 3) Promtail
	fmt.Println("📤 Deploying Promtail (log shipper)...")
	if err := runContainer(PromtailName, []string{
		"--net", NetworkName,
		"-v", VolPromtail + ":/etc/promtail:ro",
		"-v", "/var/log:/var/log:ro",
		"-v", "/var/lib/docker/containers:/var/lib/docker/containers:ro",
		"-v", "/var/run/docker.sock:/var/run/docker.sock:ro",
		"grafana/promtail:latest",
		"-config.file=/etc/promtail/promtail-config.yml",
	}); err != nil {
		return fmt.Errorf("promtail failed: %w", err)
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
		return fmt.Errorf("prometheus failed: %w", err)
	}

	// 5) Grafana
	fmt.Println("📈 Deploying Grafana (dashboards)...")
	grafanaArgs := []string{
		"--net", NetworkName,
		"-p", "3000:3000",
		"-v", VolGrafanaProv + ":/etc/grafana/provisioning:ro",
		"-v", VolGrafanaData + ":/var/lib/grafana",
		"-e", "GF_SECURITY_ADMIN_USER=" + webUser,
		"-e", "GF_SECURITY_ADMIN_PASSWORD=" + webPass,
		"-e", "GF_USERS_ALLOW_SIGN_UP=false",
		"-e", "GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/etc/grafana/provisioning/dashboards/gubernator.json",
		"-e", "GF_SERVER_ROOT_URL=/grafana/",
		"-e", "GF_SERVER_SERVE_FROM_SUB_PATH=true",
		"-e", "GF_SECURITY_ALLOW_EMBEDDING=true",
		"-e", "GF_AUTH_PROXY_ENABLED=true",
		"-e", "GF_AUTH_PROXY_HEADER_NAME=X-WEBAUTH-USER",
		"-e", "GF_AUTH_PROXY_HEADER_PROPERTY=username",
		"-e", "GF_AUTH_PROXY_AUTO_SIGN_UP=true",
		"-e", "GF_AUTH_ANONYMOUS_ENABLED=true",
		"-e", "GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer",
		"-e", "GF_AUTH_DISABLE_LOGIN_FORM=false",
		"grafana/grafana:latest",
	}
	if err := runContainer(GrafanaName, grafanaArgs); err != nil {
		return fmt.Errorf("grafana failed: %w", err)
	}

	// 6) Jaeger (distributed tracing collector & UI)
	fmt.Println("🔍 Deploying Jaeger (trace collector & UI)...")
	jaegerArgs := []string{
		"--net", NetworkName,
		"-p", "4317:4317",
		"-p", "4318:4318",
		"-p", "16686:16686",
		"-e", "QUERY_BASE_PATH=/jaeger",
		"jaegertracing/all-in-one:latest",
	}
	if err := runContainer(JaegerName, jaegerArgs); err != nil {
		return fmt.Errorf("jaeger failed: %w", err)
	}

	return nil
}

// StopAll stops and removes all monitoring containers, the network, and config volumes.
func StopAll() {
	// Disconnect Gubernator from the monitor network before removing it
	DisconnectGubernator()

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

// IsRunning checks if the Grafana monitoring container is currently running.
func IsRunning() bool {
	out, err := exec.Command("docker", "inspect", "-f", "{{.State.Running}}", GrafanaName).Output()
	if err != nil {
		return false
	}
	return strings.TrimSpace(string(out)) == "true"
}

// Status prints the status of all monitoring containers.
func Status() {
	fmt.Println("\n🛡️  Gubernator SRE Monitor Status")
	fmt.Println(strings.Repeat("─", 70))

	for _, name := range AllContainers() {
		out, err := exec.Command("docker", "inspect", "--format",
			"{{.State.Status}} | {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}} | {{range $p, $conf := .NetworkSettings.Ports}}{{if $conf}}{{$p}}→{{(index $conf 0).HostPort}} {{end}}{{end}}",
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
		volume   string
		srcDir   string // local dir to copy FROM
		destPath string // path INSIDE the volume
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

// cleanupPortContainers finds any container publishing the given host port and removes it if it's not the target container.
func cleanupPortContainers(port, targetName string) {
	out, err := exec.Command("docker", "ps", "-a", "-q", "--filter", fmt.Sprintf("publish=%s", port)).Output()
	if err == nil {
		ids := strings.Fields(string(out))
		for _, id := range ids {
			nameOut, err := exec.Command("docker", "inspect", "-f", "{{.Name}}", id).Output()
			if err == nil {
				cName := strings.TrimPrefix(strings.TrimSpace(string(nameOut)), "/")
				if cName != targetName {
					exec.Command("docker", "rm", "-f", id).Run()
				}
			}
		}
	}
}

// runContainer runs a container in detached mode with the given name and args.
// If a container with the same name already exists, it is removed first.
func runContainer(name string, args []string) error {
	// Remove if already exists
	exec.Command("docker", "rm", "-f", name).Run()

	// Clean up any conflicting containers publishing host ports specified in args
	for i, arg := range args {
		if (arg == "-p" || arg == "--publish") && i+1 < len(args) {
			portMapping := args[i+1]
			parts := strings.Split(portMapping, ":")
			if len(parts) >= 2 {
				hostPort := parts[0]
				if len(parts) == 3 {
					hostPort = parts[1]
				}
				cleanupPortContainers(hostPort, name)
			}
		}
	}

	fullArgs := []string{"run", "-d", "--name", name, "--restart", "unless-stopped"}
	fullArgs = append(fullArgs, args...)

	cmd := exec.Command("docker", fullArgs...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// EnsureCadvisorRunning starts cAdvisor locally on the node (used on workers).
func EnsureCadvisorRunning() error {
	out, err := exec.Command("docker", "inspect", "-f", "{{.State.Status}}", CadvisorName).Output()
	if err == nil && strings.TrimSpace(string(out)) == "running" {
		return nil
	}

	return runContainer(CadvisorName, []string{
		"--privileged",
		"-p", "8081:8080",
		"-v", "/:/rootfs:ro",
		"-v", "/var/run:/var/run:ro",
		"-v", "/sys:/sys:ro",
		"-v", "/var/lib/docker/:/var/lib/docker:ro",
		"-v", "/dev/disk/:/dev/disk:ro",
		"--device", "/dev/kmsg",
		"gcr.io/cadvisor/cadvisor:latest",
	})
}

// EnsureNodeExporterRunning starts Node Exporter locally on the node (used on workers/manager).
func EnsureNodeExporterRunning() error {
	out, err := exec.Command("docker", "inspect", "-f", "{{.State.Status}}", NodeExporterName).Output()
	if err == nil && strings.TrimSpace(string(out)) == "running" {
		return nil
	}

	return runContainer(NodeExporterName, []string{
		"--net", "host",
		"--pid", "host",
		"-v", "/:/host:ro,rslave",
		"prom/node-exporter:latest",
		"--path.rootfs=/host",
	})
}

// EnsureWorkerMonitoring starts cAdvisor, Node Exporter and Promtail locally on a worker node.
// managerIP is the IP of the Manager node hosting the Loki log aggregator on port :3100.
func EnsureWorkerMonitoring(managerIP string) error {
	// 1) Ensure cAdvisor is running on port 8081
	if err := EnsureCadvisorRunning(); err != nil {
		fmt.Printf("⚠️ Failed to start cAdvisor: %v\n", err)
	}

	// 1b) Ensure Node Exporter is running on port 9100
	if err := EnsureNodeExporterRunning(); err != nil {
		fmt.Printf("⚠️ Failed to start Node Exporter: %v\n", err)
	}

	// 2) Ensure Promtail is running pointing to Manager Loki
	out, err := exec.Command("docker", "inspect", "-f", "{{.State.Status}}", PromtailName).Output()
	if err == nil && strings.TrimSpace(string(out)) == "running" {
		return nil
	}

	// Generate worker promtail config pointing to Manager Loki:3100
	lokiURL := fmt.Sprintf("http://%s:3100/loki/api/v1/push", managerIP)
	promtailYaml := fmt.Sprintf(`server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: %s

scrape_configs:
  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s
    relabel_configs:
      - source_labels: ['__meta_docker_container_name']
        regex: '/(.*)'
        target_label: 'container'
`, lokiURL)

	// Populate promtail config volume
	exec.Command("docker", "volume", "create", VolPromtail).Run()
	volCmd := exec.Command("docker", "run", "--rm", "-i", "-v", VolPromtail+":/data", "alpine:latest", "sh", "-c", "cat > /data/promtail-config.yml")
	volCmd.Stdin = strings.NewReader(promtailYaml)
	_ = volCmd.Run()

	return runContainer(PromtailName, []string{
		"-v", VolPromtail + ":/etc/promtail:ro",
		"-v", "/var/log:/var/log:ro",
		"-v", "/var/lib/docker/containers:/var/lib/docker/containers:ro",
		"-v", "/var/run/docker.sock:/var/run/docker.sock:ro",
		"grafana/promtail:latest",
		"-config.file=/etc/promtail/promtail-config.yml",
	})
}
