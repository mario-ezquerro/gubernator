package monitor

import (
	_ "embed"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

//go:embed gubernator_dashboard.json
var gubernatorDashboardJSON string


// WriteConfigs generates all monitoring config files to ~/.gbnt/monitor/.
// workerTargets is a list of worker IPs to add to Prometheus scrape targets.
func WriteConfigs(workerTargets []string) error {
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
		filepath.Join(dir, "prometheus", "prometheus.yml"):                         prometheusConfig(workerTargets),
		filepath.Join(dir, "loki", "loki-config.yml"):                              lokiConfig(),
		filepath.Join(dir, "promtail", "promtail-config.yml"):                      promtailConfig(),
		filepath.Join(dir, "grafana", "provisioning", "datasources", "ds.yml"):     grafanaDatasources(),
		filepath.Join(dir, "grafana", "provisioning", "dashboards", "dash.yml"):    grafanaDashboardProv(),
		filepath.Join(dir, "grafana", "provisioning", "dashboards", "gubernator.json"): gubernatorDashboardJSON,
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
// Gubernator, cAdvisor (local + workers), and Prometheus self-monitoring.
func prometheusConfig(workerTargets []string) string {
	// Build cAdvisor targets
	cadvisorTargets := []string{"'gbnt-monitor-cadvisor:8080'"}
	for _, ip := range workerTargets {
		cadvisorTargets = append(cadvisorTargets, fmt.Sprintf("'%s:8081'", ip))
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
`, strings.Join(cadvisorTargets, ", "))
}

func lokiConfig() string {
	return `auth_enabled: false

server:
  http_listen_port: 3100

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
    access: proxy
    url: http://gbnt-monitor-prometheus:9090
    isDefault: true
    editable: false
    jsonData:
      timeInterval: '15s'
      httpMethod: POST

  - name: Loki
    type: loki
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
