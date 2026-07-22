package coredns

import (
	"fmt"
	"os"
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

// RegisterInDB registers the CoreDNS, Caddy and Gubernator containers as a special stack in the
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

	// Detect our own container name/ID
	gubernatorContainerName := "gubernator"
	if hostname, err := os.Hostname(); err == nil {
		if exec.Command("docker", "inspect", hostname).Run() == nil {
			gubernatorContainerName = hostname
		}
	}

	gubernatorImage := getContainerImage(gubernatorContainerName)

	services := []struct {
		Name          string
		ContainerName string
		Image         string
		Ports         []string
	}{
		{Name: "gubernator", ContainerName: gubernatorContainerName, Image: gubernatorImage, Ports: []string{"4000:4000", "4001:4001", "4002:4002"}},
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

	// Sync worker core stacks (CoreDNS & Caddy)
	SyncWorkerCoreStacks(database)

	fmt.Println("📋 Core stack registered in dashboard database.")
	return nil
}

// SyncWorkerCoreStacks registers CoreDNS & Caddy services for worker nodes.
func SyncWorkerCoreStacks(database *gorm.DB) {
	now := time.Now()

	var workerNodes []db.Node
	if err := database.Where("role = ? AND status != ?", "worker", "left").Find(&workerNodes).Error; err != nil {
		return
	}

	activeNodeIDs := make(map[string]bool)
	for _, n := range workerNodes {
		activeNodeIDs[n.ID] = true
	}

	// Purge orphan worker core stacks whose node no longer exists or left
	var allCoreWorkerStacks []db.Stack
	database.Where("id LIKE ?", "core-stack-%").Find(&allCoreWorkerStacks)
	for _, st := range allCoreWorkerStacks {
		nodeID := strings.TrimPrefix(st.ID, "core-stack-")
		if !activeNodeIDs[nodeID] {
			database.Where("stack_id = ?", st.ID).Delete(&db.Service{})
			database.Where("id = ?", st.ID).Delete(&db.Stack{})
		}
	}

	for _, node := range workerNodes {
		stackID := "core-stack-" + node.ID
		stackName := fmt.Sprintf("CORE-GBNT (%s)", node.ID)

		stack := db.Stack{
			ID:             stackID,
			Name:           stackName,
			RawComposeFile: fmt.Sprintf("# Managed by Gubernator Core\n# Worker Core Services: %s", node.ID),
			CreatedAt:      now,
			UpdatedAt:      now,
		}
		database.Save(&stack)

		// Clean up obsolete worker coredns service and task from DB
		obsoleteSvcID := fmt.Sprintf("core-svc-%s-coredns", node.ID)
		obsoleteTaskID := fmt.Sprintf("core-task-%s-coredns", node.ID)
		database.Where("id = ?", obsoleteTaskID).Delete(&db.Task{})
		database.Where("id = ?", obsoleteSvcID).Delete(&db.Service{})

		workerCoreServices := []struct {
			Name          string
			ContainerName string
			Image         string
			Ports         []string
		}{
			{Name: "caddy", ContainerName: "gbnt-caddy", Image: "caddy:latest", Ports: []string{"80:80", "443:443"}},
		}

		for _, ms := range workerCoreServices {
			serviceID := fmt.Sprintf("core-svc-%s-%s", node.ID, ms.Name)
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
			database.Save(&service)

			taskID := fmt.Sprintf("core-task-%s-%s", node.ID, ms.Name)
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
			database.Save(&task)
		}
	}
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

// getContainerImage inspects a Docker container and returns its image name.
func getContainerImage(name string) string {
	out, err := exec.Command("docker", "inspect", "--format", "{{.Config.Image}}", name).Output()
	if err != nil {
		return "gubernator:latest"
	}
	img := strings.TrimSpace(string(out))
	if img == "" {
		return "gubernator:latest"
	}
	return img
}
