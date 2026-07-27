package monitor

import (
	_ "embed"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
)

//go:embed gubernator_dashboard.json
var gubernatorDashboardJSON string

//go:embed network_dashboard.json
var networkDashboardJSON string

// WriteConfigs generates all monitoring config files to ~/.gbnt/monitor/.
// workerTargets is a list of worker IPs to add to Prometheus scrape targets.
func WriteConfigs(workerTargets []string) error {
	if len(workerTargets) == 0 {
		workerTargets = getWorkerIPs()
	}
	dir := MonitorDir()

	dirs := []string{
		filepath.Join(dir, "prometheus"),
		filepath.Join(dir, "loki"),
		filepath.Join(dir, "promtail"),
		filepath.Join(dir, "grafana", "provisioning", "datasources"),
		filepath.Join(dir, "grafana", "provisioning", "dashboards"),
	}
	for _, d := range dirs {
		if err := os.MkdirAll(d, 0755); err != nil {
			return fmt.Errorf("failed to create directory %s: %w", d, err)
		}
	}

	files := map[string]string{
		filepath.Join(dir, "prometheus", "prometheus.yml"):                             prometheusConfig(workerTargets),
		filepath.Join(dir, "loki", "loki-config.yml"):                                  lokiConfig(),
		filepath.Join(dir, "promtail", "promtail-config.yml"):                          promtailConfig(),
		filepath.Join(dir, "grafana", "provisioning", "datasources", "ds.yml"):         grafanaDatasources(),
		filepath.Join(dir, "grafana", "provisioning", "dashboards", "dash.yml"):        grafanaDashboardProv(),
		filepath.Join(dir, "grafana", "provisioning", "dashboards", "gubernator.json"): gubernatorDashboardJSON,
		filepath.Join(dir, "grafana", "provisioning", "dashboards", "network.json"):    networkDashboardJSON,
	}

	for path, content := range files {
		if err := os.WriteFile(path, []byte(content), 0644); err != nil {
			return fmt.Errorf("failed to write %s: %w", path, err)
		}
	}

	fmt.Printf("📝 Config files written to %s\n", dir)
	return nil
}

// prometheusConfig generates prometheus.yml with scrape targets for
// Gubernator, cAdvisor, Node Exporter, and Prometheus self-monitoring.
func prometheusConfig(workerTargets []string) string {
	// Build cAdvisor targets
	cadvisorTargets := []string{"'gbnt-monitor-cadvisor:8080'"}
	for _, ip := range workerTargets {
		cadvisorTargets = append(cadvisorTargets, fmt.Sprintf("'%s:8081'", ip))
	}

	// Build Node Exporter targets
	nodeExporterTargets := []string{"'host.docker.internal:9100'"}
	for _, ip := range workerTargets {
		nodeExporterTargets = append(nodeExporterTargets, fmt.Sprintf("'%s:9100'", ip))
	}

	return fmt.Sprintf(`global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'gubernator'

scrape_configs:
  # Gubernator Manager telemetry (port 4002, no auth)
  - job_name: 'gubernator'
    scrape_interval: 15s
    metrics_path: '/metrics'
    static_configs:
      - targets: ['host.docker.internal:4002']
        labels:
          service: 'gubernator'
          role: 'manager'

  # cAdvisor — container resource metrics
  - job_name: 'cadvisor'
    scrape_interval: 15s
    metrics_path: '/metrics'
    static_configs:
      - targets: [%s]
        labels:
          service: 'cadvisor'

  # Node Exporter — host hardware and OS metrics
  - job_name: 'node-exporter'
    scrape_interval: 15s
    metrics_path: '/metrics'
    static_configs:
      - targets: [%s]
        labels:
          service: 'node-exporter'

  # Prometheus self-monitoring
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Loki health
  - job_name: 'loki'
    static_configs:
      - targets: ['gbnt-monitor-loki:3100']
        labels:
          service: 'loki'
`, strings.Join(cadvisorTargets, ", "), strings.Join(nodeExporterTargets, ", "))
}

func lokiConfig() string {
	return `auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    join_after: 0s
    min_ready_duration: 0s

common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2020-10-24
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  ingestion_rate_mb: 50
  ingestion_burst_size_mb: 100
  per_stream_rate_limit: 50MB
  per_stream_rate_limit_burst: 100MB

analytics:
  reporting_enabled: false
`
}

func promtailConfig() string {
	return `server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://gbnt-monitor-loki:3100/loki/api/v1/push

scrape_configs:
  # Docker container logs via json-file driver
  - job_name: docker
    static_configs:
      - targets:
          - localhost
        labels:
          job: docker
          __path__: /var/lib/docker/containers/*/*-json.log
    pipeline_stages:
      - docker: {}

  # System logs
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: syslog
          __path__: /var/log/*.log
`
}

func grafanaDatasources() string {
	return `apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    uid: prometheus
    access: proxy
    url: http://gbnt-monitor-prometheus:9090
    isDefault: true
    editable: false
    jsonData:
      timeInterval: '15s'
      httpMethod: POST

  - name: Loki
    type: loki
    uid: loki
    access: proxy
    url: http://gbnt-monitor-loki:3100
    editable: false
    jsonData:
      maxLines: 1000
`
}

func grafanaDashboardProv() string {
	return `apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    editable: true
    updateIntervalSeconds: 30
    options:
      path: /etc/grafana/provisioning/dashboards
      foldersFromFilesStructure: false
`
}

// getWorkerIPs retrieves active worker node IPs from database.
func getWorkerIPs() []string {
	var ips []string

	// 1. If we are running inside the server process, db.DB is already initialized
	if db.DB != nil {
		var nodes []db.Node
		if err := db.DB.Where("role = ? AND status = ?", "worker", "active").Find(&nodes).Error; err == nil {
			for _, n := range nodes {
				ips = append(ips, n.IP)
			}
		}
		return ips
	}

	// 2. If db.DB is nil (e.g. running from CLI), try to open the database file locally
	dbPath := "gubernator.db"
	if _, err := os.Stat(dbPath); err == nil {
		tmpDB, err := gorm.Open(sqlite.Open(dbPath), &gorm.Config{})
		if err == nil {
			var nodes []db.Node
			if err := tmpDB.Where("role = ? AND status = ?", "worker", "active").Find(&nodes).Error; err == nil {
				for _, n := range nodes {
					ips = append(ips, n.IP)
				}
			}
			sqlDB, err := tmpDB.DB()
			if err == nil {
				sqlDB.Close()
			}
		}
	}
	return ips
}

// UpdatePrometheusConfig regenerates prometheus.yml based on active workers in the DB,
// writes it to disk, and if the Prometheus container is running, copies it in and sends SIGHUP.
func UpdatePrometheusConfig() error {
	ips := getWorkerIPs()
	dir := MonitorDir()
	promDir := filepath.Join(dir, "prometheus")
	if err := os.MkdirAll(promDir, 0755); err != nil {
		return fmt.Errorf("failed to create prometheus directory: %w", err)
	}

	content := prometheusConfig(ips)
	configPath := filepath.Join(promDir, "prometheus.yml")
	if err := os.WriteFile(configPath, []byte(content), 0644); err != nil {
		return fmt.Errorf("failed to write prometheus.yml: %w", err)
	}

	// Update the named volume via a temporary helper container
	volCmd := exec.Command("docker", "run", "--rm", "-i", "-v", VolPrometheus+":/data", "alpine:latest", "sh", "-c", "cat > /data/prometheus.yml")
	volCmd.Stdin = strings.NewReader(content)
	if err := volCmd.Run(); err != nil {
		return fmt.Errorf("failed to update prometheus config volume: %w", err)
	}

	// If Prometheus container is running, send SIGHUP to reload
	inspectCmd := exec.Command("docker", "inspect", "-f", "{{.State.Running}}", "gbnt-monitor-prometheus")
	out, err := inspectCmd.Output()
	if err == nil && strings.TrimSpace(string(out)) == "true" {
		reloadCmd := exec.Command("docker", "kill", "-s", "SIGHUP", "gbnt-monitor-prometheus")
		if err := reloadCmd.Run(); err != nil {
			return fmt.Errorf("failed to send SIGHUP reload signal: %w", err)
		}
		fmt.Println("🔄 Prometheus configuration reloaded successfully with updated targets.")
	}

	return nil
}
