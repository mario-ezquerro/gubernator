package api

import (
	"context"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/db"
)

// StartSelfHealingWatchdog periodically reconciles all services across cluster nodes.
// If a container dies, fails to start, or has fewer active replicas than desired,
// Gubernator automatically re-schedules and starts replacement replicas on healthy nodes.
func StartSelfHealingWatchdog(ctx context.Context) {
	slog.Info("self-healing watchdog: cluster reconciliation engine started")

	// Wait 10 seconds after boot before first reconciliation to allow cluster nodes to report heartbeats
	select {
	case <-ctx.Done():
		return
	case <-time.After(10 * time.Second):
	}

	ticker := time.NewTicker(15 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			slog.Info("self-healing watchdog: stopped")
			return
		case <-ticker.C:
			ReconcileClusterServices()
		}
	}
}

// ReconcileClusterServices scans all active stacks and ensures desired replicas are running.
func ReconcileClusterServices() {
	var stacks []db.Stack
	if err := db.DB.Find(&stacks).Error; err != nil {
		return
	}

	for _, stack := range stacks {
		// Skip system stacks (Caddy/CoreDNS and SRE monitor have their own dedicated sync lifecycles)
		sID := strings.ToLower(stack.ID)
		sName := strings.ToLower(stack.Name)
		if strings.HasPrefix(sID, "core-") || strings.HasPrefix(sID, "sre-") ||
			strings.Contains(sName, "core-gbnt") || strings.Contains(sName, "monitor") {
			continue
		}

		var services []db.Service
		if err := db.DB.Where("stack_id = ?", stack.ID).Find(&services).Error; err != nil {
			continue
		}

		for _, svc := range services {
			if svc.DesiredReplicas <= 0 {
				continue
			}

			var tasks []db.Task
			if err := db.DB.Where("service_id = ?", svc.ID).Find(&tasks).Error; err != nil {
				continue
			}

			// Check health of assigned nodes for running tasks
			var healthyCount int
			for _, task := range tasks {
				if task.Status == "running" || task.Status == "pulling" || task.Status == "starting" || task.Status == "pending" {
					// Verify node is still active/ready
					var node db.Node
					if err := db.DB.First(&node, "id = ?", task.NodeID).Error; err == nil {
						if node.Status == "active" || node.Status == "ready" {
							healthyCount++
							continue
						} else {
							// Node went down or left: mark task dead so it can be rescheduled
							slog.Warn("self-healing: node unreachable for task, marking dead", "task", task.ID[:8], "node", task.NodeID, "node_status", node.Status)
							db.DB.Model(&db.Task{}).Where("id = ?", task.ID).Updates(map[string]interface{}{
								"status": "dead",
								"error":  fmt.Sprintf("Node %s is %s", task.NodeID, node.Status),
							})
						}
					}
				}
			}

			// If missing replicas, schedule new tasks on healthy nodes
			if healthyCount < svc.DesiredReplicas {
				missing := svc.DesiredReplicas - healthyCount
				slog.Info("self-healing watchdog: repairing degraded service", "stack", stack.Name, "service", svc.Name, "running", healthyCount, "desired", svc.DesiredReplicas, "missing", missing)

				// Clean up older dead tasks if there are more than 2 dead tasks for this service
				var deadTasks []db.Task
				db.DB.Where("service_id = ? AND status = ?", svc.ID, "dead").Order("created_at asc").Find(&deadTasks)
				if len(deadTasks) > 2 {
					for _, dt := range deadTasks[:len(deadTasks)-2] {
						db.DB.Delete(&dt)
					}
				}

				for i := 0; i < missing; i++ {
					ScheduleSingleReplica(&svc, "")
				}
			}
		}
	}
}
