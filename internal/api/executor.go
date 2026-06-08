package api

import (
	"context"
	"fmt"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/aqueducts"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/mario-ezquerro/gubernator/internal/docker"
)

const localManagerNodeID = "node-local-manager"

// startLocalExecutor polls for pending tasks on the local node and executes them.
// Exits cleanly when ctx is cancelled.
func startLocalExecutor(ctx context.Context) {
	fmt.Println("[Executor] Local executor started. Watching for pending tasks on node:", localManagerNodeID)

	for {
		select {
		case <-ctx.Done():
			fmt.Println("[Executor] Shutting down.")
			return
		case <-time.After(5 * time.Second):
		}

		var tasks []db.Task
		if err := db.DB.Where("node_id = ? AND status = ?", localManagerNodeID, "pending").Find(&tasks).Error; err != nil {
			continue
		}

		for _, task := range tasks {
			// Mark as "starting" immediately to avoid double-execution
			db.DB.Model(&db.Task{}).Where("id = ?", task.ID).Update("status", "starting")

			var svc db.Service
			if err := db.DB.First(&svc, "id = ?", task.ServiceID).Error; err != nil {
				fmt.Printf("[Executor] Task %s: service not found, skipping.\n", task.ID[:8])
				db.DB.Model(&db.Task{}).Where("id = ?", task.ID).Updates(map[string]interface{}{"status": "dead", "error": "service not found"})
				continue
			}

			go executeTask(task, svc)
		}
	}
}

// executeTask pulls the image and starts the container for a given task+service.
func executeTask(task db.Task, svc db.Service) {
	fmt.Printf("[Executor] Task %s: pulling image %s...\n", task.ID[:8], svc.Image)

	if err := docker.PullImage(svc.Image); err != nil {
		fmt.Printf("[Executor] Task %s: pull failed: %v\n", task.ID[:8], err)
		db.DB.Model(&db.Task{}).Where("id = ?", task.ID).Updates(map[string]interface{}{"status": "dead", "error": fmt.Sprintf("pull failed: %v", err)})
		return
	}

	cfg := docker.ContainerConfig{
		TaskID:  task.ID,
		Image:   svc.Image,
		Ports:   svc.Ports,
		Env:     svc.Env,
		Volumes: svc.Volumes,
		Command: svc.Command,
	}

	containerName, ip, err := docker.StartContainer(cfg)
	if err != nil {
		fmt.Printf("[Executor] Task %s: start failed: %v\n", task.ID[:8], err)
		db.DB.Model(&db.Task{}).Where("id = ?", task.ID).Updates(map[string]interface{}{"status": "dead", "error": fmt.Sprintf("start failed: %v", err)})
		return
	}

	fmt.Printf("[Executor] Task %s: container %s started (IP: %s)\n", task.ID[:8], containerName, ip)

	db.DB.Model(&db.Task{}).Where("id = ?", task.ID).Updates(map[string]interface{}{
		"status":         "running",
		"container_ip":   ip,
		"container_name": containerName,
	})

	// Update DNS and Ingress
	go func() {
		aqueducts.GenerateHostsFile()
		aqueducts.GenerateCaddyfile()
	}()
}

// StopStackContainers stops and removes all containers belonging to a stack's tasks.
func StopStackContainers(stackID string) {
	var services []db.Service
	db.DB.Where("stack_id = ?", stackID).Find(&services)

	for _, svc := range services {
		var tasks []db.Task
		db.DB.Where("service_id = ? AND container_name != ''", svc.ID).Find(&tasks)

		for _, task := range tasks {
			fmt.Printf("[Executor] Stopping container %s for task %s...\n", task.ContainerName, task.ID[:8])
			if err := docker.StopContainer(task.ContainerName); err != nil {
				fmt.Printf("[Executor] Warning: %v\n", err)
			}
		}
	}
}
