package coredns

import (
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/db"
	"gorm.io/gorm"
)

const (
	// CoreStackID is the fixed stack ID used for the Core Gubernator stack in the DB.
	CoreStackID = "core-gbnt-stack"
	// CoreStackName is the display name for the Core stack in the dashboard.
	CoreStackName = "CORE-GBNT"
)

// RegisterInDB registers the CoreDNS and Caddy containers as a special stack in the
// Gubernator database so they appear in the Flutter dashboard.
func RegisterInDB(database *gorm.DB) error {
	// Remove any previous Core stack records
	UnregisterFromDB(database)

	now := time.Now()

	// Create the Core Stack
	stack := db.Stack{
		ID:             CoreStackID,
		Name:           CoreStackName,
		RawComposeFile: "# Managed by Gubernator Core\n# Do not edit manually.",
		CreatedAt:      now,
		UpdatedAt:      now,
	}
	if err := database.Create(&stack).Error; err != nil {
		return fmt.Errorf("failed to create Core stack: %w", err)
	}

	services := []struct {
		Name          string
		ContainerName string
		Image         string
		Ports         []string
	}{
		{Name: "coredns", ContainerName: ContainerName, Image: ImageName, Ports: []string{DNSPort}},
		{Name: "caddy", ContainerName: "gbnt-caddy", Image: "caddy:latest", Ports: []string{"80:80", "443:443"}},
	}

	for _, ms := range services {
		serviceID := "core-svc-" + ms.Name
		service := db.Service{
			ID:              serviceID,
			StackID:         CoreStackID,
			Name:            ms.Name,
			Image:           ms.Image,
			DesiredReplicas: 1,
			Ports:           ms.Ports,
			CreatedAt:       now,
			UpdatedAt:       now,
		}
		if err := database.Create(&service).Error; err != nil {
			return fmt.Errorf("failed to create Core service %s: %w", ms.Name, err)
		}

		// Inspect the container to get its IP
		containerIP := getContainerIP(ms.ContainerName)
		status := "running"
		if containerIP == "" {
			status = "dead"
		}

		task := db.Task{
			ID:            "core-task-" + ms.Name,
			ServiceID:     serviceID,
			NodeID:        "node-local-manager",
			Status:        status,
			ContainerIP:   containerIP,
			ContainerName: ms.ContainerName,
			CreatedAt:     now,
			UpdatedAt:     now,
		}
		if err := database.Create(&task).Error; err != nil {
			return fmt.Errorf("failed to create Core task %s: %w", ms.Name, err)
		}
	}

	fmt.Println("📋 Core stack registered in dashboard database.")
	return nil
}

// UnregisterFromDB removes the Core stack from the database.
func UnregisterFromDB(database *gorm.DB) {
	var services []db.Service
	database.Where("stack_id = ?", CoreStackID).Find(&services)
	for _, s := range services {
		database.Where("service_id = ?", s.ID).Delete(&db.Task{})
	}
	database.Where("stack_id = ?", CoreStackID).Delete(&db.Service{})
	database.Where("id = ?", CoreStackID).Delete(&db.Stack{})
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
