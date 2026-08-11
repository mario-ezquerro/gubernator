package monitor

import (
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/db"
	"gorm.io/gorm"
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

// RegisterInDB registers the monitoring containers as special stacks in the
// Gubernator database so they appear in the Flutter dashboard (Manager + Workers).
func RegisterInDB(database *gorm.DB) error {
	now := time.Now()

	// 1) Register Manager SRE Stack
	var existingMgrStack db.Stack
	if err := database.First(&existingMgrStack, "id = ?", SREStackID).Error; err != nil {
		managerStack := db.Stack{
			ID:             SREStackID,
			Name:           SREStackName,
			RawComposeFile: "# Managed by Gubernator SRE Engine\n# Manager Node Monitoring Stack",
			CreatedAt:      now,
			UpdatedAt:      now,
		}
		database.Create(&managerStack)
	}

	for _, ms := range managerMonitorServices {
		serviceID := "sre-svc-mgr-" + ms.Name
		var existingService db.Service
		if err := database.First(&existingService, "id = ?", serviceID).Error; err != nil {
			service := db.Service{
				ID:              serviceID,
				StackID:         SREStackID,
				Name:            ms.Name,
				Image:           ms.Image,
				DesiredReplicas: 1,
				Ports:           ms.Ports,
				CreatedAt:       now,
				UpdatedAt:       now,
			}
			database.Create(&service)
		}

		containerIP := getContainerIP(ms.ContainerName)
		status := "dead"
		inspectOut, inspectErr := exec.Command("docker", "inspect", "-f", "{{.State.Status}}", ms.ContainerName).Output()
		if inspectErr == nil && strings.TrimSpace(string(inspectOut)) == "running" {
			status = "running"
		}

		taskID := "sre-task-mgr-" + ms.Name
		var existingTask db.Task
		if err := database.First(&existingTask, "id = ?", taskID).Error; err != nil {
			task := db.Task{
				ID:            taskID,
				ServiceID:     serviceID,
				NodeID:        "node-local-manager",
				Status:        status,
				ContainerIP:   containerIP,
				ContainerName: ms.ContainerName,
				CreatedAt:     now,
				UpdatedAt:     now,
			}
			database.Create(&task)
		} else {
			database.Model(&existingTask).Updates(map[string]interface{}{
				"status":       status,
				"container_ip":  containerIP,
				"updated_at":   now,
			})
		}
	}

	// 2) Sync active Worker SRE Stacks
	SyncWorkerSreStacks(database)

	fmt.Println("📋 Manager and Worker SRE stacks registered in dashboard database.")
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
					"status":       "running",
					"container_ip":  node.IP,
					"updated_at":   now,
				})
			}
		}
	}
}

// RegisterScopeStackInDB registers [SUPER] Net-Topology stack in the DB when enabled for Manager and active Workers.
func RegisterScopeStackInDB(database *gorm.DB) {
	now := time.Now()
	mgrStackID := "super-net-topology-mgr"
	mgrStackName := "[SUPER] Net-Topology (Manager)"
	serviceID := "super-svc-scope-mgr"
	taskID := "super-task-scope-mgr"

	var existingStack db.Stack
	if err := database.First(&existingStack, "id = ?", mgrStackID).Error; err != nil {
		stack := db.Stack{
			ID:             mgrStackID,
			Name:           mgrStackName,
			RawComposeFile: "# Managed by Gubernator Superpower Engine\n# Weave Scope App & Probe (Manager)",
			CreatedAt:      now,
			UpdatedAt:      now,
		}
		database.Create(&stack)
	}

	var existingService db.Service
	if err := database.First(&existingService, "id = ?", serviceID).Error; err != nil {
		service := db.Service{
			ID:              serviceID,
			StackID:         mgrStackID,
			Name:            "weave-scope",
			Image:           "weaveworks/scope:latest",
			DesiredReplicas: 1,
			Ports:           []string{"4040:4040"},
			CreatedAt:       now,
			UpdatedAt:       now,
		}
		database.Create(&service)
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
			"container_ip":  getContainerIP(ScopeContainerName),
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

	managerIP := getDynamicCoreDNSIP()

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
		stackName := fmt.Sprintf("[SUPER] Net-Topology (%s)", node.ID)

		var existingStack db.Stack
		if err := database.First(&existingStack, "id = ?", stackID).Error; err != nil {
			stack := db.Stack{
				ID:             stackID,
				Name:           stackName,
				RawComposeFile: fmt.Sprintf("# Managed by Gubernator Superpower Engine\n# Weave Scope Probe (%s)", node.ID),
				CreatedAt:      now,
				UpdatedAt:      now,
			}
			database.Create(&stack)
		}

		serviceID := fmt.Sprintf("super-svc-%s-scope", node.ID)
		cmdStr := fmt.Sprintf("--probe-only --probe.resolver=%s:5354 %s:4040", managerIP, managerIP)
		var existingService db.Service
		if err := database.First(&existingService, "id = ?", serviceID).Error; err != nil {
			service := db.Service{
				ID:              serviceID,
				StackID:         stackID,
				Name:            "weave-scope-probe",
				Image:           "weaveworks/scope:latest",
				Command:         cmdStr,
				DesiredReplicas: 1,
				Ports:           []string{},
				CreatedAt:       now,
				UpdatedAt:       now,
			}
			database.Create(&service)
		} else if existingService.Command != cmdStr {
			database.Model(&existingService).Update("command", cmdStr)
		}

		taskID := fmt.Sprintf("super-task-%s-scope", node.ID)
		var existingTask db.Task
		if err := database.First(&existingTask, "id = ?", taskID).Error; err != nil {
			task := db.Task{
				ID:            taskID,
				ServiceID:     serviceID,
				NodeID:        node.ID,
				Status:        "pending",
				ContainerIP:   node.IP,
				ContainerName: "gbnt-monitor-scope-probe",
				CreatedAt:     now,
				UpdatedAt:     now,
			}
			database.Create(&task)
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
	var services []db.Service
	database.Where("stack_id LIKE 'sre-%'").Find(&services)
	for _, s := range services {
		database.Where("service_id = ?", s.ID).Delete(&db.Task{})
	}
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
	ips := strings.Fields(strings.TrimSpace(string(out)))
	for _, ip := range ips {
		if ip != "" {
			return ip
		}
	}
	return ""
}
