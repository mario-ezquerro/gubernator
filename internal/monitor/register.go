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
	// SREStackID is the fixed stack ID used for the SRE monitoring stack in the DB.
	SREStackID = "sre-monitor-stack"
	// SREStackName is the display name for the SRE stack in the dashboard.
	SREStackName = "[SRE] Monitor"
)

// monitorService describes a monitoring container for DB registration.
type monitorService struct {
	Name          string
	ContainerName string
	Image         string
	Ports         []string
}

var monitorServices = []monitorService{
	{Name: "cadvisor", ContainerName: CadvisorName, Image: "gcr.io/cadvisor/cadvisor:latest", Ports: []string{"8081:8080"}},
	{Name: "prometheus", ContainerName: PrometheusName, Image: "prom/prometheus:latest", Ports: []string{"9090:9090"}},
	{Name: "loki", ContainerName: LokiName, Image: "grafana/loki:latest", Ports: []string{"3100:3100"}},
	{Name: "promtail", ContainerName: PromtailName, Image: "grafana/promtail:latest", Ports: []string{}},
	{Name: "grafana", ContainerName: GrafanaName, Image: "grafana/grafana:latest", Ports: []string{"3000:3000"}},
}

// RegisterInDB registers the monitoring containers as a special stack in the
// Gubernator database so they appear in the Flutter dashboard.
func RegisterInDB(database *gorm.DB) error {
	// Remove any previous SRE stack records
	UnregisterFromDB(database)

	now := time.Now()

	// Create the SRE Stack
	stack := db.Stack{
		ID:             SREStackID,
		Name:           SREStackName,
		RawComposeFile: "# Managed by 'gbnt monitor init'\n# Do not edit manually.",
		CreatedAt:      now,
		UpdatedAt:      now,
	}
	if err := database.Create(&stack).Error; err != nil {
		return fmt.Errorf("failed to create SRE stack: %w", err)
	}

	for _, ms := range monitorServices {
		serviceID := "sre-svc-" + ms.Name
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
		if err := database.Create(&service).Error; err != nil {
			return fmt.Errorf("failed to create SRE service %s: %w", ms.Name, err)
		}

		// Inspect the container to get its IP
		containerIP := getContainerIP(ms.ContainerName)
		status := "running"
		if containerIP == "" {
			status = "dead"
		}

		task := db.Task{
			ID:            "sre-task-" + ms.Name,
			ServiceID:     serviceID,
			NodeID:        "node-local-manager",
			Status:        status,
			ContainerIP:   containerIP,
			ContainerName: ms.ContainerName,
			CreatedAt:     now,
			UpdatedAt:     now,
		}
		if err := database.Create(&task).Error; err != nil {
			return fmt.Errorf("failed to create SRE task %s: %w", ms.Name, err)
		}
	}

	fmt.Println("📋 SRE stack registered in dashboard database.")
	return nil
}

// UnregisterFromDB removes the SRE monitoring stack from the database.
func UnregisterFromDB(database *gorm.DB) {
	database.Where("stack_id = ?", SREStackID).Delete(&db.Task{})
	// Delete tasks via service IDs
	var services []db.Service
	database.Where("stack_id = ?", SREStackID).Find(&services)
	for _, s := range services {
		database.Where("service_id = ?", s.ID).Delete(&db.Task{})
	}
	database.Where("stack_id = ?", SREStackID).Delete(&db.Service{})
	database.Where("id = ?", SREStackID).Delete(&db.Stack{})
}

// getContainerIP inspects a Docker container and returns its IP address.
func getContainerIP(name string) string {
	out, err := exec.Command("docker", "inspect", "--format",
		"{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}", name).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}
