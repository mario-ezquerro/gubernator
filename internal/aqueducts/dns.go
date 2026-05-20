package aqueducts

import (
	"fmt"
	"log"
	"os"

	"github.com/mario-ezquerro/gubernator/internal/coredns"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

// GenerateHostsFile queries the DB for all running tasks and regenerates the CoreDNS hosts file.
// After writing, it signals CoreDNS to reload the new records.
func GenerateHostsFile() {
	var tasks []db.Task
	// Only fetch tasks that have an IP
	if err := db.DB.Where("status = ? AND container_ip != ?", "running", "").Find(&tasks).Error; err != nil {
		log.Printf("Failed to fetch tasks for DNS generation: %v\n", err)
		return
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

	// Write to the CoreDNS config directory (~/.gbnt/coredns/gubernator.hosts)
	hostsPath := coredns.HostsFilePath()
	err := os.WriteFile(hostsPath, []byte(content), 0644)
	if err != nil {
		log.Printf("Failed to write gubernator.hosts: %v\n", err)
		return
	}

	log.Println("🌊 Aqueducts: Generated new gubernator.hosts file.")

	// Signal CoreDNS to reload the updated hosts file
	if err := coredns.ReloadConfig(); err != nil {
		log.Printf("⚠️  Aqueducts: CoreDNS reload failed: %v\n", err)
	}
}
