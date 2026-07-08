package aqueducts

import (
	"fmt"
	"log/slog"
	"os"
	"strings"

	"github.com/mario-ezquerro/gubernator/internal/coredns"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

// GenerateHostsFile queries the DB for all running tasks and regenerates the CoreDNS hosts file.
// After writing, it signals CoreDNS to reload the new records.
func GenerateHostsFile() {
	var tasks []db.Task
	// Only fetch tasks that have an IP
	if err := db.DB.Where("status = ? AND container_ip != ?", "running", "").Find(&tasks).Error; err != nil {
		slog.Error("failed to fetch tasks for DNS generation", "err", err)
		return
	}

	var managerNode db.Node
	hostIP := "127.0.0.1" // Fallback
	if err := db.DB.Where("role = ?", "manager").First(&managerNode).Error; err == nil && managerNode.IP != "" {
		hostIP = managerNode.IP
	}

	content := "# Gubernator Auto-Generated CoreDNS Hosts File\n"

	for _, t := range tasks {
		var svc db.Service
		if err := db.DB.First(&svc, "id = ?", t.ServiceID).Error; err == nil {
			var stack db.Stack
			if err := db.DB.First(&stack, "id = ?", svc.StackID).Error; err == nil {
				// Format: IP task.service.stack.gbnt
				// Example: 172.17.0.2 task-abc.web.mystack.gbnt
				domain := fmt.Sprintf("%s.%s.%s.gbnt", t.ID, svc.Name, stack.Name)
				content += fmt.Sprintf("%s\t%s\n", t.ContainerIP, domain)

				// Short alias (e.g. web.mystack.gbnt points to the first container MVP)
				shortDomain := fmt.Sprintf("%s.%s.gbnt", svc.Name, stack.Name)
				content += fmt.Sprintf("%s\t%s\n", t.ContainerIP, shortDomain)
			}
		}
	}

	// Add records for ingress.host to point to the host IP
	var services []db.Service
	if err := db.DB.Find(&services).Error; err == nil {
		seenHosts := make(map[string]bool)
		for _, svc := range services {
			for _, constraint := range svc.Constraints {
				parts := strings.Split(constraint, "==")
				if len(parts) == 2 {
					key := strings.TrimSpace(parts[0])
					val := strings.TrimSpace(parts[1])
					if (key == "ingress.host" || key == "node.labels.gbnt.ingress.host") && !seenHosts[val] {
						seenHosts[val] = true
						content += fmt.Sprintf("%s\t%s\n", hostIP, val)
					}
				}
			}
		}
	}

	// Write to the CoreDNS config directory (~/.gbnt/coredns/gubernator.hosts)
	hostsPath := coredns.HostsFilePath()
	err := os.WriteFile(hostsPath, []byte(content), 0644)
	if err != nil {
		slog.Error("failed to write gubernator.hosts", "err", err)
		return
	}

	slog.Info("aqueducts: generated new gubernator.hosts file")

	// Signal CoreDNS to reload the updated hosts file
	if err := coredns.ReloadConfig(); err != nil {
		slog.Warn("aqueducts: CoreDNS reload failed", "err", err)
	}
}
