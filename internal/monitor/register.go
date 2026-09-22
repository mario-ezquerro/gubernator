package monitor

import (
	"fmt"
	"os/exec"
	"strings"
	"time"

	"gorm.io/gorm"

	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/mario-ezquerro/gubernator/internal/docker"
)

const (
	// SREStackID is the fixed stack ID used for the Manager SRE monitoring stack in the DB.
	SREStackID = "sre-monitor-stack"
	// SREStackName is the display name for the Manager SRE stack in the dashboard.
	SREStackName = "[SRE] Monitor (Manager)"
)

// monitorService describes a monitoring container for DB registration.
type monitorService struct {
	Name          string
	ContainerName string
	Image         string
	Ports         []string
}

var managerMonitorServices = []monitorService{
	{Name: "cadvisor", ContainerName: CadvisorName, Image: "gcr.io/cadvisor/cadvisor:latest", Ports: []string{"8081:8080"}},
	{Name: "node-exporter", ContainerName: NodeExporterName, Image: "prom/node-exporter:latest", Ports: []string{"9100:9100"}},
	{Name: "prometheus", ContainerName: PrometheusName, Image: "prom/prometheus:latest", Ports: []string{"9090:9090"}},
	{Name: "loki", ContainerName: LokiName, Image: "grafana/loki:latest", Ports: []string{"3100:3100"}},
	{Name: "promtail", ContainerName: PromtailName, Image: "grafana/promtail:latest", Ports: []string{}},
	{Name: "grafana", ContainerName: GrafanaName, Image: "grafana/grafana:latest", Ports: []string{"3000:3000"}},
	{Name: "jaeger", ContainerName: JaegerName, Image: "jaegertracing/all-in-one:latest", Ports: []string{"4317:4317", "4318:4318", "16686:16686"}},
}

var workerMonitorServices = []monitorService{
	{Name: "cadvisor", ContainerName: CadvisorName, Image: "gcr.io/cadvisor/cadvisor:latest", Ports: []string{"8081:8080"}},
	{Name: "node-exporter", ContainerName: NodeExporterName, Image: "prom/node-exporter:latest", Ports: []string{"9100:9100"}},
	{Name: "promtail", ContainerName: PromtailName, Image: "grafana/promtail:latest", Ports: []string{}},
}

// RegisterInDB registers the active SRE monitoring containers as special stacks in the
// Gubernator database so they appear in the Flutter dashboard (Manager + Workers).
func RegisterInDB(database *gorm.DB) error {
	if database == nil {
		return nil
	}
	activeID := GetActiveProfile()
	profile := GetProfileByID(activeID)
	if profile == nil {
		for _, p := range predefinedProfiles {
			if p.ID == DefaultProfileID {
				profile = &p
				break
			}
		}
	}
	if profile == nil && len(predefinedProfiles) > 0 {
		profile = &predefinedProfiles[0]
	}
	if profile != nil {
		return RegisterInDBWithProfile(database, *profile)
	}
	return nil
}

// RegisterInDBWithProfile registers the given SRE profile containers into the DB cleanly,
// removing any duplicate or orphaned legacy tasks, setting correct ports and container IPs.
func RegisterInDBWithProfile(database *gorm.DB, profile SREProfile) error {
	if database == nil {
		return nil
	}
	now := time.Now()

	// 1) Purge any legacy/rogue duplicate manager tasks and services
	database.Where("id LIKE ?", "task-gbnt-monitor-%").Delete(&db.Task{})
	database.Where("id LIKE ?", "task-sre-%").Delete(&db.Task{})
	database.Where("service_id LIKE ?", SREStackID+"-%").Delete(&db.Task{})
	database.Where("service_id LIKE ?", "sre-monitor-%").Delete(&db.Task{})
	database.Where("id LIKE ?", SREStackID+"-%").Delete(&db.Service{})
	database.Where("id LIKE ?", "sre-svc-gbnt-monitor-%").Delete(&db.Service{})

	// 2) Register or update Manager SRE Stack
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

	// 3) Register / update canonical services and tasks for this profile
	activeServiceIDs := make(map[string]bool)
	activeTaskIDs := make(map[string]bool)

	for _, cName := range profile.Containers {
		meta := getMonitorServiceMeta(cName)
		serviceID := "sre-svc-mgr-" + meta.Name
		taskID := "sre-task-mgr-" + meta.Name
		activeServiceIDs[serviceID] = true
		activeTaskIDs[taskID] = true

		status := "dead"
		image := meta.Image
		ports := meta.Ports

		// Inspect container for live status and image
		inspectOut, inspectErr := exec.Command("docker", "inspect", "-f", "{{.State.Status}}|{{.Config.Image}}", cName).Output()
		if inspectErr == nil {
			parts := strings.Split(strings.TrimSpace(string(inspectOut)), "|")
			if len(parts) >= 1 && parts[0] != "" {
				if parts[0] == "running" {
					status = "running"
				} else {
					status = parts[0]
				}
			}
			if len(parts) >= 2 && parts[1] != "" {
				image = parts[1]
			}
		}

		// Extract live dynamic port bindings if container is running
		if livePorts := getLiveContainerPorts(cName); len(livePorts) > 0 {
			ports = livePorts
		}

		var existingService db.Service
		if err := database.First(&existingService, "id = ?", serviceID).Error; err != nil {
			service := db.Service{
				ID:              serviceID,
				StackID:         SREStackID,
				Name:            meta.Name,
				Image:           image,
				DesiredReplicas: 1,
				Ports:           ports,
				CreatedAt:       now,
				UpdatedAt:       now,
			}
			database.Create(&service)
		} else {
			existingService.Name = meta.Name
			existingService.Image = image
			existingService.Ports = ports
			existingService.UpdatedAt = now
			database.Save(&existingService)
		}

		containerIP := getContainerIP(cName)
		var existingTask db.Task
		if err := database.First(&existingTask, "id = ?", taskID).Error; err != nil {
			task := db.Task{
				ID:            taskID,
				ServiceID:     serviceID,
				NodeID:        "node-local-manager",
				Status:        status,
				ContainerIP:   containerIP,
				ContainerName: cName,
				CreatedAt:     now,
				UpdatedAt:     now,
			}
			database.Create(&task)
		} else {
			database.Model(&existingTask).Updates(map[string]interface{}{
				"service_id":     serviceID,
				"status":         status,
				"container_ip":   containerIP,
				"container_name": cName,
				"error":          "",
				"updated_at":     now,
			})
		}
	}

	// 4) Prune any manager SRE services or tasks that are not part of the active profile
	var existingMgrSvcs []db.Service
	database.Where("stack_id = ?", SREStackID).Find(&existingMgrSvcs)
	for _, s := range existingMgrSvcs {
		if !activeServiceIDs[s.ID] {
			database.Where("service_id = ?", s.ID).Delete(&db.Task{})
			database.Delete(&s)
		}
	}

	var existingMgrTasks []db.Task
	database.Where("id LIKE 'sre-task-mgr-%' AND node_id = ?", "node-local-manager").Find(&existingMgrTasks)
	for _, t := range existingMgrTasks {
		if !activeTaskIDs[t.ID] {
			database.Delete(&t)
		}
	}

	// 5) Sync active Worker SRE Stacks
	SyncWorkerSreStacks(database)

	// 6) Sync Network Topology stacks if Scope is running
	if IsScopeRunning() {
		RegisterScopeStackInDB(database)
	}

	fmt.Printf("📋 Manager SRE stack [%s] and Worker stacks synced in database (clean 1-to-1 registration).\n", profile.Name)
	return nil
}

// SyncWorkerSreStacks creates or updates SRE monitoring stacks for all active worker nodes.
func SyncWorkerSreStacks(database *gorm.DB) {
	now := time.Now()

	var workerNodes []db.Node
	if err := database.Where("role = ? AND status != ?", "worker", "left").Find(&workerNodes).Error; err != nil {
		return
	}

	activeNodeIDs := make(map[string]bool)
	for _, n := range workerNodes {
		activeNodeIDs[n.ID] = true
	}

	// Purge orphan worker SRE stacks whose node no longer exists or left
	var allSreWorkerStacks []db.Stack
	database.Where("id LIKE ?", "sre-stack-%").Find(&allSreWorkerStacks)
	for _, st := range allSreWorkerStacks {
		nodeID := strings.TrimPrefix(st.ID, "sre-stack-")
		if !activeNodeIDs[nodeID] {
			database.Where("stack_id = ?", st.ID).Delete(&db.Service{})
			database.Where("id = ?", st.ID).Delete(&db.Stack{})
		}
	}

	for _, node := range workerNodes {
		stackID := "sre-stack-" + node.ID
		stackName := fmt.Sprintf("[SRE] Monitor (%s)", node.ID)

		var existingStack db.Stack
		if err := database.First(&existingStack, "id = ?", stackID).Error; err != nil {
			stack := db.Stack{
				ID:             stackID,
				Name:           stackName,
				RawComposeFile: fmt.Sprintf("# Managed by Gubernator SRE Engine\n# Worker Node Monitoring: %s", node.ID),
				CreatedAt:      now,
				UpdatedAt:      now,
			}
			database.Create(&stack)
		} else {
			database.Model(&existingStack).Update("updated_at", now)
		}

		for _, ms := range workerMonitorServices {
			serviceID := fmt.Sprintf("sre-svc-%s-%s", node.ID, ms.Name)
			var existingService db.Service
			if err := database.First(&existingService, "id = ?", serviceID).Error; err != nil {
				service := db.Service{
					ID:              serviceID,
					StackID:         stackID,
					Name:            ms.Name,
					Image:           ms.Image,
					DesiredReplicas: 1,
					Ports:           ms.Ports,
					CreatedAt:       now,
					UpdatedAt:       now,
				}
				database.Create(&service)
			}

			taskID := fmt.Sprintf("sre-task-%s-%s", node.ID, ms.Name)
			var existingTask db.Task
			if err := database.First(&existingTask, "id = ?", taskID).Error; err != nil {
				task := db.Task{
					ID:            taskID,
					ServiceID:     serviceID,
					NodeID:        node.ID,
					Status:        "running",
					ContainerIP:   node.IP,
					ContainerName: ms.ContainerName,
					CreatedAt:     now,
					UpdatedAt:     now,
				}
				database.Create(&task)
			} else {
				database.Model(&existingTask).Updates(map[string]interface{}{
					"status":         "running",
					"container_ip":   node.IP,
					"container_name": ms.ContainerName,
					"error":          "",
					"updated_at":     now,
				})
			}

			// Purge any rogue or duplicate tasks for this worker SRE service
			var rogueTasks []db.Task
			database.Where("service_id = ? AND id != ?", serviceID, taskID).Find(&rogueTasks)
			for _, rt := range rogueTasks {
				cName := rt.ContainerName
				if cName == "" {
					cName = "gbnt-" + rt.ID
				}
				_ = docker.RemoveContainerOnNode(rt.NodeID, cName)
				database.Delete(&rt)
			}
		}
	}
}

// RegisterScopeStackInDB registers [SUPER] Net-Topology stack in the DB when enabled for Manager and active Workers.
func RegisterScopeStackInDB(database *gorm.DB) {
	now := time.Now()
	mgrStackID := "super-net-topology-mgr"
	mgrStackName := "[BASE] Net-Topology (Manager)"
	serviceID := "super-svc-scope-mgr"
	taskID := "super-task-scope-mgr"

	var existingStack db.Stack
	if err := database.First(&existingStack, "id = ?", mgrStackID).Error; err != nil {
		stack := db.Stack{
			ID:             mgrStackID,
			Name:           mgrStackName,
			RawComposeFile: "# Managed by Gubernator Base Infrastructure Engine\n# Weave Scope App & Probe (Manager)",
			CreatedAt:      now,
			UpdatedAt:      now,
		}
		database.Create(&stack)
	} else {
		database.Model(&existingStack).Update("name", mgrStackName)
	}

	var existingService db.Service
	if err := database.First(&existingService, "id = ?", serviceID).Error; err != nil {
		service := db.Service{
			ID:              serviceID,
			StackID:         mgrStackID,
			Name:            "weave-scope",
			Image:           "marioezquerro/scope:latest",
			DesiredReplicas: 1,
			Ports:           []string{"4040:4040"},
			CreatedAt:       now,
			UpdatedAt:       now,
		}
		database.Create(&service)
	} else {
		database.Model(&existingService).Update("image", "marioezquerro/scope:latest")
	}

	status := "dead"
	if IsScopeRunning() {
		status = "running"
	}

	var existingTask db.Task
	if err := database.First(&existingTask, "id = ?", taskID).Error; err != nil {
		task := db.Task{
			ID:            taskID,
			ServiceID:     serviceID,
			NodeID:        "node-local-manager",
			Status:        status,
			ContainerIP:   getContainerIP(ScopeContainerName),
			ContainerName: ScopeContainerName,
			CreatedAt:     now,
			UpdatedAt:     now,
		}
		database.Create(&task)
	} else {
		database.Model(&existingTask).Updates(map[string]interface{}{
			"status":       status,
			"container_ip": getContainerIP(ScopeContainerName),
			"updated_at":   now,
		})
	}

	// Sync active Worker nodes
	SyncWorkerScopeStacks(database)
}

// SyncWorkerScopeStacks registers [SUPER] Net-Topology stacks for all active worker nodes.
func SyncWorkerScopeStacks(database *gorm.DB) {
	now := time.Now()

	// If Scope is stopped on Manager, purge worker scope stacks
	if !IsScopeRunning() {
		UnregisterScopeStackFromDB(database)
		return
	}

	managerIP := getManagerHostIP()

	var workerNodes []db.Node
	if err := database.Where("role = ? AND status != ?", "worker", "left").Find(&workerNodes).Error; err != nil {
		return
	}

	activeNodeIDs := make(map[string]bool)
	for _, n := range workerNodes {
		activeNodeIDs[n.ID] = true
	}

	// Purge orphan worker scope stacks
	var allScopeWorkerStacks []db.Stack
	database.Where("id LIKE ?", "super-scope-stack-%").Find(&allScopeWorkerStacks)
	for _, st := range allScopeWorkerStacks {
		nodeID := strings.TrimPrefix(st.ID, "super-scope-stack-")
		if !activeNodeIDs[nodeID] {
			database.Where("stack_id = ?", st.ID).Delete(&db.Service{})
			database.Where("id = ?", st.ID).Delete(&db.Stack{})
		}
	}

	for _, node := range workerNodes {
		stackID := "super-scope-stack-" + node.ID
		stackName := fmt.Sprintf("[BASE] Net-Topology (%s)", node.ID)

		var existingStack db.Stack
		if err := database.First(&existingStack, "id = ?", stackID).Error; err != nil {
			stack := db.Stack{
				ID:             stackID,
				Name:           stackName,
				RawComposeFile: fmt.Sprintf("# Managed by Gubernator Base Infrastructure Engine\n# Weave Scope Probe (%s)", node.ID),
				CreatedAt:      now,
				UpdatedAt:      now,
			}
			database.Create(&stack)
		} else {
			database.Model(&existingStack).Update("name", stackName)
		}

		serviceID := fmt.Sprintf("super-svc-%s-scope", node.ID)
		cmdStr := fmt.Sprintf("/home/weave/scope --weave=false --mode=probe --probe.docker=true --probe.processes=true --probe.proc.spy=true %s:4040", managerIP)
		var existingService db.Service
		if err := database.First(&existingService, "id = ?", serviceID).Error; err != nil {
			service := db.Service{
				ID:              serviceID,
				StackID:         stackID,
				Name:            "weave-scope-probe",
				Image:           "marioezquerro/scope:latest",
				Command:         cmdStr,
				DesiredReplicas: 1,
				Ports:           []string{},
				CreatedAt:       now,
				UpdatedAt:       now,
			}
			database.Create(&service)
		} else {
			database.Model(&existingService).Updates(map[string]interface{}{
				"command": cmdStr,
				"image":   "marioezquerro/scope:latest",
			})
		}

		taskID := fmt.Sprintf("super-task-%s-scope", node.ID)
		var existingTask db.Task
		if err := database.First(&existingTask, "id = ?", taskID).Error; err != nil {
			task := db.Task{
				ID:            taskID,
				ServiceID:     serviceID,
				NodeID:        node.ID,
				Status:        "running",
				ContainerIP:   node.IP,
				ContainerName: "gbnt-monitor-scope-probe",
				CreatedAt:     now,
				UpdatedAt:     now,
			}
			database.Create(&task)
		} else {
			database.Model(&existingTask).Updates(map[string]interface{}{
				"status":         "running",
				"container_ip":   node.IP,
				"container_name": "gbnt-monitor-scope-probe",
				"updated_at":     now,
			})
		}
	}
}

// UnregisterScopeStackFromDB removes all [SUPER] Net-Topology stacks from the DB when disabled.
func UnregisterScopeStackFromDB(database *gorm.DB) {
	database.Where("service_id LIKE 'super-%'").Delete(&db.Task{})
	database.Where("stack_id LIKE 'super-%'").Delete(&db.Task{})
	database.Where("stack_id LIKE 'super-%'").Delete(&db.Service{})
	database.Where("id LIKE 'super-%'").Delete(&db.Stack{})
}

// UnregisterFromDB removes all SRE monitoring stacks from the database.
func UnregisterFromDB(database *gorm.DB) {
	if database == nil {
		return
	}
	var services []db.Service
	database.Where("stack_id LIKE 'sre-%'").Find(&services)
	for _, s := range services {
		database.Where("service_id = ?", s.ID).Delete(&db.Task{})
	}
	database.Where("service_id LIKE 'sre-%'").Delete(&db.Task{})
	database.Where("id LIKE 'sre-task-%'").Delete(&db.Task{})
	database.Where("id LIKE 'task-gbnt-monitor-%'").Delete(&db.Task{})
	database.Where("stack_id LIKE 'sre-%'").Delete(&db.Service{})
	database.Where("id LIKE 'sre-%'").Delete(&db.Stack{})
}

// getContainerIP inspects a Docker container and returns its IP address.
func getContainerIP(name string) string {
	out, err := exec.Command("docker", "inspect", "--format",
		"{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}", name).Output()
	if err != nil {
		return ""
	}
	raw := strings.TrimSpace(string(out))
	if raw == "" {
		return ""
	}
	if strings.Contains(strings.ToLower(raw), "invalid") {
		return getManagerHostIP()
	}
	ips := strings.Fields(raw)
	for _, ip := range ips {
		if ip != "" && !strings.EqualFold(ip, "invalid") && !strings.EqualFold(ip, "ip") && !strings.Contains(strings.ToLower(ip), "invalid") {
			return ip
		}
	}
	return getManagerHostIP()
}

// getLiveContainerPorts extracts active host:container port mappings from docker inspect.
func getLiveContainerPorts(name string) []string {
	out, err := exec.Command("docker", "inspect", "--format",
		"{{range $p, $conf := .NetworkSettings.Ports}}{{if $conf}}{{$conf0 := index $conf 0}}{{$conf0.HostPort}}:{{$p}} {{end}}{{end}}",
		name).Output()
	if err != nil {
		return nil
	}
	raw := strings.TrimSpace(string(out))
	if raw == "" {
		return nil
	}
	var ports []string
	seen := make(map[string]bool)
	for _, entry := range strings.Fields(raw) {
		clean := strings.TrimSuffix(entry, "/tcp")
		clean = strings.TrimSuffix(clean, "/udp")
		if clean != "" && !seen[clean] {
			seen[clean] = true
			ports = append(ports, clean)
		}
	}
	return ports
}

// getMonitorServiceMeta returns standard service metadata (clean name, image, default ports)
// for any monitoring container across all SRE profiles.
func getMonitorServiceMeta(cName string) monitorService {
	switch cName {
	case CadvisorName:
		return monitorService{Name: "cadvisor", ContainerName: CadvisorName, Image: "gcr.io/cadvisor/cadvisor:latest", Ports: []string{"8081:8080"}}
	case NodeExporterName:
		return monitorService{Name: "node-exporter", ContainerName: NodeExporterName, Image: "prom/node-exporter:latest", Ports: []string{"9100:9100"}}
	case PrometheusName:
		return monitorService{Name: "prometheus", ContainerName: PrometheusName, Image: "prom/prometheus:latest", Ports: []string{"9090:9090"}}
	case LokiName:
		return monitorService{Name: "loki", ContainerName: LokiName, Image: "grafana/loki:latest", Ports: []string{"3100:3100"}}
	case PromtailName:
		return monitorService{Name: "promtail", ContainerName: PromtailName, Image: "grafana/promtail:latest", Ports: []string{}}
	case GrafanaName:
		return monitorService{Name: "grafana", ContainerName: GrafanaName, Image: "grafana/grafana:latest", Ports: []string{"3000:3000"}}
	case JaegerName:
		return monitorService{Name: "jaeger", ContainerName: JaegerName, Image: "jaegertracing/all-in-one:latest", Ports: []string{"4317:4317", "4318:4318", "16686:16686"}}
	case "gbnt-monitor-victoriametrics":
		return monitorService{Name: "victoriametrics", ContainerName: cName, Image: "victoriametrics/victoria-metrics:latest", Ports: []string{"8428:8428"}}
	case "gbnt-monitor-victorialogs":
		return monitorService{Name: "victorialogs", ContainerName: cName, Image: "victoriametrics/victoria-logs:latest", Ports: []string{"9428:9428"}}
	case "gbnt-monitor-fluentbit":
		return monitorService{Name: "fluentbit", ContainerName: cName, Image: "fluent/fluent-bit:latest", Ports: []string{}}
	case "gbnt-monitor-clickhouse":
		return monitorService{Name: "clickhouse", ContainerName: cName, Image: "clickhouse/clickhouse-server:latest", Ports: []string{"8123:8123", "9000:9000"}}
	case "gbnt-monitor-otel-collector":
		return monitorService{Name: "otel-collector", ContainerName: cName, Image: "otel/opentelemetry-collector-contrib:latest", Ports: []string{"4317:4317", "4318:4318"}}
	case "gbnt-monitor-opensearch":
		return monitorService{Name: "opensearch", ContainerName: cName, Image: "opensearchproject/opensearch:latest", Ports: []string{"9200:9200"}}
	case "gbnt-monitor-vector-forwarder":
		return monitorService{Name: "vector-forwarder", ContainerName: cName, Image: "timberio/vector:latest-alpine", Ports: []string{}}
	default:
		clean := strings.TrimPrefix(cName, "gbnt-monitor-")
		clean = strings.TrimPrefix(clean, "gbnt-")
		clean = strings.TrimPrefix(clean, "monitor-")
		return monitorService{Name: clean, ContainerName: cName, Image: "unknown", Ports: []string{}}
	}
}
