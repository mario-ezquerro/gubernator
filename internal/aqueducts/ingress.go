package aqueducts

import (
	"fmt"
	"log/slog"
	"os"
	"strings"

	"github.com/mario-ezquerro/gubernator/internal/caddy"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

// GenerateCaddyfile creates a Caddyfile based on Service constraints/labels.
// It groups all upstreams by ingress hostname to avoid duplicate site definitions.
// Only services with running tasks are included — no DNS fallback blocks are emitted
// since those cause "ambiguous site definition" errors when combined with IP-based blocks.
func GenerateCaddyfile() {
	aqueductMutex.Lock()
	defer aqueductMutex.Unlock()

	var services []db.Service
	if err := db.DB.Find(&services).Error; err != nil {
		slog.Error("failed to fetch services for ingress", "err", err)
		return
	}

	// hostUpstreams groups container IPs per ingress hostname to avoid duplicate blocks.
	hostUpstreams := make(map[string][]string)
	// Preserve insertion order for deterministic output.
	var hostOrder []string

	for _, svc := range services {
		for _, constraint := range svc.Constraints {
			parts := strings.Split(constraint, "==")
			if len(parts) != 2 {
				continue
			}
			key := strings.TrimSpace(parts[0])
			val := strings.TrimSpace(parts[1])

			if key != "ingress.host" && key != "node.labels.gbnt.ingress.host" {
				continue
			}

			// Only include running tasks with a real IP.
			var tasks []db.Task
			if err := db.DB.Where(
				"service_id = ? AND status = ? AND container_ip != ?",
				svc.ID, "running", "",
			).Find(&tasks).Error; err != nil || len(tasks) == 0 {
				// Skip — no fallback DNS block to avoid duplicates/conflicts.
				continue
			}

			port := "80"
			if len(svc.Ports) > 0 {
				p := svc.Ports[0]
				parts := strings.Split(p, ":")
				lastPart := parts[len(parts)-1]
				cleaned := strings.TrimSpace(strings.Split(lastPart, "/")[0])
				if cleaned != "" {
					port = cleaned
				}
			}

			if _, seen := hostUpstreams[val]; !seen {
				hostOrder = append(hostOrder, val)
			}
			for _, t := range tasks {
				targetIP := t.ContainerIP
				targetPort := port

				if t.NodeID != "node-local-manager" {
					var taskNode db.Node
					if err := db.DB.First(&taskNode, "id = ?", t.NodeID).Error; err == nil && taskNode.IP != "" {
						targetIP = taskNode.IP
						if len(svc.Ports) > 0 {
							parts := strings.Split(svc.Ports[0], ":")
							if len(parts) > 1 {
								targetPort = strings.TrimSpace(parts[0])
							}
						}
					}
				}

				hostUpstreams[val] = append(hostUpstreams[val], fmt.Sprintf("%s:%s", targetIP, targetPort))
			}
		}
	}

	content := "# Gubernator Auto-Generated Caddyfile\n\n"

	for _, host := range hostOrder {
		upstreams := hostUpstreams[host]
		content += fmt.Sprintf(
			"%s {\n\ttls internal\n\treverse_proxy %s {\n\t\tlb_policy round_robin\n\t}\n}\n\n",
			host, strings.Join(upstreams, " "),
		)
	}

	// If no reverse proxy rules were generated, write a default block so Caddy starts cleanly.
	if len(hostOrder) == 0 {
		content += ":80 {\n\trespond \"Gubernator Caddy Ingress is running!\" 200\n}\n"
	}

	caddyfilePath := caddy.CaddyfilePath()
	if err := os.WriteFile(caddyfilePath, []byte(content), 0644); err != nil {
		slog.Error("failed to write Caddyfile", "err", err)
		return
	}

	slog.Info("aqueducts: generated new Caddyfile")
	if err := caddy.ReloadConfig(); err != nil {
		slog.Warn("aqueducts: Caddy reload failed", "err", err)
	}
}
