package monitor

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/db"
	"gorm.io/gorm"
)

// SREProfile represents an observability architecture profile / preset.
type SREProfile struct {
	ID                    string            `json:"id"`
	Name                  string            `json:"name"`
	Subtitle              string            `json:"subtitle"`
	Icon                  string            `json:"icon"`
	RecommendedHosts      string            `json:"recommended_hosts"`
	RecommendedContainers string            `json:"recommended_containers"`
	RecommendedRAM        string            `json:"recommended_ram"`
	IdealEnvironment      string            `json:"ideal_environment"`
	Description           string            `json:"description"`
	Components            map[string]string `json:"components"`
	IsActive              bool              `json:"is_active"`
	Containers            []string          `json:"containers"`
}

// DefaultProfileID is the standard balanced cloud-native stack.
const DefaultProfileID = "cloud-native"

var predefinedProfiles = []SREProfile{
	{
		ID:                    "ultra-light",
		Name:                  "Ultra-Lightweight",
		Subtitle:              "VictoriaMetrics + VictoriaLogs + Fluent Bit",
		Icon:                  "bolt",
		RecommendedHosts:      "1 – 5 Centuriones",
		RecommendedContainers: "Hasta 30 contenedores",
		RecommendedRAM:        "< 500 MB",
		IdealEnvironment:      "VPS económicos (Hetzner, Linode, OVH 2-4GB), Edge computing, mini-PCs o laboratorios. Consumo mínimo de RAM y compresión de disco extrema.",
		Description:           "Pila SRE de ultra-bajo consumo impulsada por VictoriaMetrics y VictoriaLogs. Ingesta veloz y compresión de logs hasta 10x superior con apenas 400MB de RAM.",
		Components: map[string]string{
			"Metrics":    "VictoriaMetrics (:8428)",
			"Logs":       "VictoriaLogs (:9428)",
			"Shipper":    "Fluent Bit",
			"Dashboards": "Grafana / VMUI (:3000)",
			"Hardware":   "cAdvisor + Node Exporter",
		},
		Containers: []string{
			CadvisorName,
			NodeExporterName,
			"gbnt-monitor-victoriametrics",
			"gbnt-monitor-victorialogs",
			"gbnt-monitor-fluentbit",
			GrafanaName,
		},
	},
	{
		ID:                    "cloud-native",
		Name:                  "Cloud-Native Balanced",
		Subtitle:              "Prometheus + Loki + Promtail + Grafana + Sloth",
		Icon:                  "cloud",
		RecommendedHosts:      "3 – 15 Centuriones",
		RecommendedContainers: "20 – 100 contenedores",
		RecommendedRAM:        "1.5 – 2 GB",
		IdealEnvironment:      "Startups y empresas, propósito general, cálculo de SLOs en tiempo real con Sloth y dashboards analíticos listos para producción.",
		Description:           "Pila SRE oficial de Gubernator. Métricas con Prometheus, agregación de logs con Loki, trazas OTLP con Jaeger y cálculo nativo de Error Budgets con Sloth.",
		Components: map[string]string{
			"Metrics":    "Prometheus (:9090)",
			"Logs":       "Grafana Loki (:3100)",
			"Shipper":    "Promtail",
			"Dashboards": "Grafana (:3000)",
			"Tracing":    "Jaeger OTLP (:4317 / :16686)",
			"SLO Engine": "Sloth (Google SRE Multi-Burn-Rate)",
		},
		Containers: []string{
			CadvisorName,
			NodeExporterName,
			PrometheusName,
			LokiName,
			PromtailName,
			GrafanaName,
			JaegerName,
		},
	},
	{
		ID:                    "unified-otel",
		Name:                  "Next-Gen Unified OTel",
		Subtitle:              "ClickHouse + OpenTelemetry Collector + SigNoz",
		Icon:                  "rocket_launch",
		RecommendedHosts:      "5 – 25 Centuriones",
		RecommendedContainers: "50 – 200 contenedores",
		RecommendedRAM:        "2 – 4 GB",
		IdealEnvironment:      "Microservicios modernos con tracing intensivo. Unifica métricas, logs y trazas distribuidas en un único motor ClickHouse de alta velocidad.",
		Description:           "Arquitectura moderna basada en ClickHouse y OpenTelemetry Collector. Correlación end-to-end de métricas, trazas y logs unificados por trace_id.",
		Components: map[string]string{
			"Unified DB": "ClickHouse Server (:8123 / :9000)",
			"Collector":  "OpenTelemetry Collector Contrib (:4317 / :4318)",
			"Shipper":    "OTel Host Agent",
			"Dashboards": "SigNoz / Grafana (:3000)",
			"Tracing":    "OTLP Distributed Tracing",
		},
		Containers: []string{
			CadvisorName,
			NodeExporterName,
			"gbnt-monitor-clickhouse",
			"gbnt-monitor-otel-collector",
			GrafanaName,
		},
	},
	{
		ID:                    "enterprise-elk",
		Name:                  "Enterprise SIEM & Analytics",
		Subtitle:              "OpenSearch / ELK + Fluent Bit + Metricbeat",
		Icon:                  "business",
		RecommendedHosts:      "10+ Centuriones",
		RecommendedContainers: "Más de 100 contenedores",
		RecommendedRAM:        "4 – 8 GB",
		IdealEnvironment:      "Clústeres corporativos medianos/grandes con auditoría estricta (SOC2/PCI-DSS), análisis forense de seguridad y búsqueda de texto completo.",
		Description:           "Motor corporativo OpenSearch para búsqueda profunda a texto completo, agregaciones analíticas de alta escala y auditoría de seguridad SIEM.",
		Components: map[string]string{
			"Search DB":   "OpenSearch (:9200)",
			"Logs Engine": "Lucene Inverted Index Full-Text",
			"Shipper":     "Fluent Bit (C-optimized)",
			"Dashboards":  "OpenSearch Dashboards (:5601)",
			"Security":    "SIEM & Compliance Audit Logs",
		},
		Containers: []string{
			CadvisorName,
			NodeExporterName,
			"gbnt-monitor-opensearch",
			"gbnt-monitor-opensearch-dashboards",
			"gbnt-monitor-fluentbit",
		},
	},
	{
		ID:                    "external-saas",
		Name:                  "Zero-Footprint Forwarder",
		Subtitle:              "Vector / Fluent Bit ➔ Datadog, Splunk, Cloud",
		Icon:                  "language",
		RecommendedHosts:      "Cualquier escala",
		RecommendedContainers: "Ilimitados",
		RecommendedRAM:        "< 100 MB",
		IdealEnvironment:      "Para organizaciones que ya utilizan Datadog, Splunk, Elastic Cloud o Grafana Cloud. Cero consumo en el clúster; sólo reenvía métricas y logs hacia fuera.",
		Description:           "Exportación ligera sin almacenar datos en el clúster local. Reenvío directo de telemetría y logs a plataformas SaaS externas vía Vector o Fluent Bit.",
		Components: map[string]string{
			"Storage":    "Zero in-cluster storage (Forwarder-only)",
			"Shipper":    "Vector / Fluent Bit Daemon",
			"Destiny":    "Datadog / Splunk / Grafana Cloud / Elastic",
			"Dashboards": "External Provider UI",
		},
		Containers: []string{
			"gbnt-monitor-vector-forwarder",
		},
	},
}

// activeProfileFile returns the path to the active profile marker.
func activeProfileFile() string {
	return filepath.Join(MonitorDir(), "active_profile")
}

// GetActiveProfile returns the current active profile ID (defaults to "cloud-native").
func GetActiveProfile() string {
	path := activeProfileFile()
	if data, err := os.ReadFile(path); err == nil {
		val := strings.TrimSpace(string(data))
		if val != "" {
			return val
		}
	}
	return DefaultProfileID
}

// SetActiveProfile persists the active profile ID to disk.
func SetActiveProfile(id string) error {
	dir := MonitorDir()
	_ = os.MkdirAll(dir, 0755)
	return os.WriteFile(activeProfileFile(), []byte(strings.TrimSpace(id)), 0644)
}

// ListProfiles returns all available SRE profiles with active status computed.
func ListProfiles() []SREProfile {
	activeID := GetActiveProfile()
	result := make([]SREProfile, len(predefinedProfiles))
	copy(result, predefinedProfiles)

	for i := range result {
		result[i].IsActive = (result[i].ID == activeID)
	}
	return result
}

// GetProfileByID returns the SREProfile for a given ID or nil if not found.
func GetProfileByID(id string) *SREProfile {
	for _, p := range predefinedProfiles {
		if p.ID == id {
			p.IsActive = (p.ID == GetActiveProfile())
			return &p
		}
	}
	return nil
}

// SwitchProfile gracefully stops running monitoring containers, updates the active profile,
// and deploys the newly selected architecture stack.
func SwitchProfile(targetID string, webUser, webPass string) error {
	profile := GetProfileByID(targetID)
	if profile == nil {
		return fmt.Errorf("unknown SRE profile: %q (available: ultra-light, cloud-native, unified-otel, enterprise-elk, external-saas)", targetID)
	}

	fmt.Printf("\n🔄 Switching SRE Observability Stack to profile [%s: %s]...\n", profile.ID, profile.Name)

	// 1. Stop all current monitoring containers
	StopAll()
	if db.DB != nil {
		UnregisterFromDB(db.DB)
	}

	// 2. Short grace period for Docker daemon
	time.Sleep(2 * time.Second)

	// 3. Ensure base network exists
	if err := EnsureNetwork(); err != nil {
		return fmt.Errorf("failed to ensure monitor network: %w", err)
	}

	if webUser == "" {
		webUser = "admin"
	}
	if webPass == "" {
		webPass = "admin"
	}

	// 4. Deploy the selected profile
	var deployErr error
	switch targetID {
	case "ultra-light":
		deployErr = deployUltraLightStack(webUser, webPass)
	case "cloud-native":
		_ = WriteConfigs(nil)
		deployErr = DeployManagerStack(webUser, webPass)
	case "unified-otel":
		deployErr = deployUnifiedOtelStack(webUser, webPass)
	case "enterprise-elk":
		deployErr = deployEnterpriseStack()
	case "external-saas":
		deployErr = deployExternalForwarderStack()
	default:
		_ = WriteConfigs(nil)
		deployErr = DeployManagerStack(webUser, webPass)
	}

	if deployErr != nil {
		return fmt.Errorf("deployment of profile %s failed: %w", targetID, deployErr)
	}

	// 5. Persist the newly active profile
	if err := SetActiveProfile(targetID); err != nil {
		fmt.Printf("⚠️ Warning: failed to save active profile marker: %v\n", err)
	}

	// 6. Update database representation if DB is initialized
	if db.DB != nil {
		_ = RegisterProfileInDB(db.DB, *profile)
	}

	fmt.Printf("✅ SRE Observability Stack successfully switched to [%s]!\n", profile.Name)
	return nil
}

// deployUltraLightStack spins up VictoriaMetrics, VictoriaLogs, Fluent Bit, cAdvisor, and Grafana.
func deployUltraLightStack(webUser, webPass string) error {
	_ = ConnectGubernator()
	_ = EnsureNodeExporterRunning()

	// cAdvisor
	_ = runContainer(CadvisorName, []string{
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
	})

	// VictoriaMetrics (ultra-light TSDB)
	if err := runContainer("gbnt-monitor-victoriametrics", []string{
		"--net", NetworkName,
		"-p", "8428:8428",
		"-p", "9090:8428", // PromQL compatible port mapping
		"-v", "gbnt-monitor-vm-data:/victoria-metrics-data",
		"victoriametrics/victoria-metrics:latest",
		"-retentionPeriod=1",
	}); err != nil {
		return fmt.Errorf("victoriametrics failed: %w", err)
	}

	// VictoriaLogs (ultra-light log engine)
	if err := runContainer("gbnt-monitor-victorialogs", []string{
		"--net", NetworkName,
		"-p", "9428:9428",
		"-v", "gbnt-monitor-vl-data:/victoria-logs-data",
		"victoriametrics/victoria-logs:latest",
		"-retentionPeriod=7d",
	}); err != nil {
		return fmt.Errorf("victorialogs failed: %w", err)
	}

	// Fluent Bit
	if err := runContainer("gbnt-monitor-fluentbit", []string{
		"--net", NetworkName,
		"-v", "/var/log:/var/log:ro",
		"-v", "/var/lib/docker/containers:/var/lib/docker/containers:ro",
		"-v", "/var/run/docker.sock:/var/run/docker.sock:ro",
		"fluent/fluent-bit:latest",
	}); err != nil {
		return fmt.Errorf("fluent-bit failed: %w", err)
	}

	// Grafana for dashboards
	_ = runContainer(GrafanaName, []string{
		"--net", NetworkName,
		"-p", "3000:3000",
		"-e", "GF_SECURITY_ADMIN_USER=" + webUser,
		"-e", "GF_SECURITY_ADMIN_PASSWORD=" + webPass,
		"-e", "GF_USERS_ALLOW_SIGN_UP=false",
		"-e", "GF_SERVER_ROOT_URL=/grafana/",
		"-e", "GF_SERVER_SERVE_FROM_SUB_PATH=true",
		"-e", "GF_SECURITY_ALLOW_EMBEDDING=true",
		"-e", "GF_AUTH_ANONYMOUS_ENABLED=true",
		"grafana/grafana:latest",
	})

	return nil
}

// deployUnifiedOtelStack spins up ClickHouse and OpenTelemetry Collector.
func deployUnifiedOtelStack(webUser, webPass string) error {
	_ = ConnectGubernator()
	_ = EnsureNodeExporterRunning()

	// cAdvisor
	_ = runContainer(CadvisorName, []string{
		"--net", NetworkName,
		"--privileged",
		"-p", "8081:8080",
		"-v", "/:/rootfs:ro",
		"-v", "/var/run:/var/run:ro",
		"-v", "/sys:/sys:ro",
		"-v", "/var/lib/docker/:/var/lib/docker:ro",
		"gcr.io/cadvisor/cadvisor:latest",
	})

	// ClickHouse Single Node Server
	if err := runContainer("gbnt-monitor-clickhouse", []string{
		"--net", NetworkName,
		"-p", "8123:8123",
		"-p", "9000:9000",
		"-v", "gbnt-monitor-clickhouse-data:/var/lib/clickhouse",
		"-e", "CLICKHOUSE_DB=gubernator_otel",
		"-e", "CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1",
		"clickhouse/clickhouse-server:latest",
	}); err != nil {
		return fmt.Errorf("clickhouse failed: %w", err)
	}

	// OpenTelemetry Collector Contrib
	if err := runContainer("gbnt-monitor-otel-collector", []string{
		"--net", NetworkName,
		"-p", "4317:4317",
		"-p", "4318:4318",
		"-p", "8888:8888",
		"otel/opentelemetry-collector-contrib:latest",
	}); err != nil {
		return fmt.Errorf("otel collector failed: %w", err)
	}

	// Grafana with ClickHouse Datasource ready
	_ = runContainer(GrafanaName, []string{
		"--net", NetworkName,
		"-p", "3000:3000",
		"-e", "GF_SECURITY_ADMIN_USER=" + webUser,
		"-e", "GF_SECURITY_ADMIN_PASSWORD=" + webPass,
		"-e", "GF_USERS_ALLOW_SIGN_UP=false",
		"-e", "GF_SERVER_ROOT_URL=/grafana/",
		"-e", "GF_SERVER_SERVE_FROM_SUB_PATH=true",
		"-e", "GF_SECURITY_ALLOW_EMBEDDING=true",
		"-e", "GF_AUTH_ANONYMOUS_ENABLED=true",
		"grafana/grafana:latest",
	})

	return nil
}

// deployEnterpriseStack spins up OpenSearch, OpenSearch Dashboards, and Fluent Bit.
func deployEnterpriseStack() error {
	_ = ConnectGubernator()
	_ = EnsureNodeExporterRunning()

	// cAdvisor
	_ = runContainer(CadvisorName, []string{
		"--net", NetworkName,
		"--privileged",
		"-p", "8081:8080",
		"-v", "/:/rootfs:ro",
		"-v", "/var/run:/var/run:ro",
		"-v", "/sys:/sys:ro",
		"-v", "/var/lib/docker/:/var/lib/docker:ro",
		"gcr.io/cadvisor/cadvisor:latest",
	})

	// OpenSearch Single Node (Security plugin disabled for local ease of use)
	if err := runContainer("gbnt-monitor-opensearch", []string{
		"--net", NetworkName,
		"-p", "9200:9200",
		"-p", "9600:9600",
		"-e", "discovery.type=single-node",
		"-e", "plugins.security.disabled=true",
		"-e", "OPENSEARCH_INITIAL_ADMIN_PASSWORD=GubernatorSRE2026!",
		"-v", "gbnt-monitor-opensearch-data:/usr/share/opensearch/data",
		"opensearchproject/opensearch:latest",
	}); err != nil {
		return fmt.Errorf("opensearch failed: %w", err)
	}

	// OpenSearch Dashboards
	if err := runContainer("gbnt-monitor-opensearch-dashboards", []string{
		"--net", NetworkName,
		"-p", "5601:5601",
		"-e", "OPENSEARCH_HOSTS=http://gbnt-monitor-opensearch:9200",
		"-e", "DISABLE_SECURITY_DASHBOARDS_PLUGIN=true",
		"opensearchproject/opensearch-dashboards:latest",
	}); err != nil {
		return fmt.Errorf("opensearch dashboards failed: %w", err)
	}

	// Fluent Bit
	_ = runContainer("gbnt-monitor-fluentbit", []string{
		"--net", NetworkName,
		"-v", "/var/log:/var/log:ro",
		"-v", "/var/lib/docker/containers:/var/lib/docker/containers:ro",
		"-v", "/var/run/docker.sock:/var/run/docker.sock:ro",
		"fluent/fluent-bit:latest",
	})

	return nil
}

// deployExternalForwarderStack deploys Vector or Fluent Bit configured as forwarder only.
func deployExternalForwarderStack() error {
	_ = ConnectGubernator()

	// Deploy lightweight Vector forwarder
	if err := runContainer("gbnt-monitor-vector-forwarder", []string{
		"--net", NetworkName,
		"-v", "/var/log:/var/log:ro",
		"-v", "/var/lib/docker/containers:/var/lib/docker/containers:ro",
		"-v", "/var/run/docker.sock:/var/run/docker.sock:ro",
		"timberio/vector:latest-alpine",
	}); err != nil {
		return fmt.Errorf("vector forwarder failed: %w", err)
	}
	return nil
}

// RegisterProfileInDB registers the profile containers into Gubernator SQLite database.
func RegisterProfileInDB(database *gorm.DB, profile SREProfile) error {
	now := time.Now()

	// Update or create Manager SRE Stack
	var existingMgrStack db.Stack
	stackDisplayName := fmt.Sprintf("[SRE] Monitor — %s", profile.Name)
	if err := database.First(&existingMgrStack, "id = ?", SREStackID).Error; err != nil {
		managerStack := db.Stack{
			ID:             SREStackID,
			Name:           stackDisplayName,
			RawComposeFile: fmt.Sprintf("# Managed by Gubernator SRE Engine\n# Profile: %s (%s)\n# %s", profile.ID, profile.Name, profile.Subtitle),
			CreatedAt:      now,
			UpdatedAt:      now,
		}
		database.Create(&managerStack)
	} else {
		database.Model(&existingMgrStack).Updates(map[string]interface{}{
			"name":             stackDisplayName,
			"raw_compose_file": fmt.Sprintf("# Managed by Gubernator SRE Engine\n# Profile: %s (%s)\n# %s", profile.ID, profile.Name, profile.Subtitle),
			"updated_at":       now,
		})
	}

	// Clear old manager SRE tasks and services
	database.Where("service_id LIKE ?", SREStackID+"-%").Delete(&db.Task{})
	database.Where("stack_id = ?", SREStackID).Delete(&db.Service{})

	// Register current profile containers
	for _, cName := range profile.Containers {
		out, err := exec.Command("docker", "inspect", "-f", "{{.State.Status}}|{{.Config.Image}}", cName).Output()
		status := "stopped"
		image := "unknown"
		if err == nil {
			parts := strings.Split(strings.TrimSpace(string(out)), "|")
			if len(parts) >= 1 && parts[0] != "" {
				status = parts[0]
			}
			if len(parts) >= 2 && parts[1] != "" {
				image = parts[1]
			}
		}

		serviceID := fmt.Sprintf("%s-%s", SREStackID, cName)
		svc := db.Service{
			ID:              serviceID,
			StackID:         SREStackID,
			Name:            cName,
			Image:           image,
			DesiredReplicas: 1,
			CreatedAt:       now,
			UpdatedAt:       now,
		}
		database.Create(&svc)

		task := db.Task{
			ID:            fmt.Sprintf("task-%s", cName),
			ServiceID:     serviceID,
			NodeID:        "node-local-manager",
			Status:        status,
			ContainerName: cName,
			CreatedAt:     now,
			UpdatedAt:     now,
		}
		database.Create(&task)
	}

	return nil
}
