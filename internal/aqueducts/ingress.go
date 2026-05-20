package aqueducts

import (
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/mario-ezquerro/gubernator/internal/caddy"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

// GenerateCaddyfile creates a Caddyfile based on Service constraints/labels.
// For example, if a service has a constraint "caddy.route == api.gbnt.local",
// it configures Caddy to reverse proxy to the internal DNS of that service.
func GenerateCaddyfile() {
	var services []db.Service
	if err := db.DB.Find(&services).Error; err != nil {
		log.Printf("Failed to fetch services for Ingress: %v\n", err)
		return
	}

	content := "# Gubernator Auto-Generated Caddyfile\n\n"

	for _, svc := range services {
		for _, constraint := range svc.Constraints {
			parts := strings.Split(constraint, "==")
			if len(parts) == 2 {
				key := strings.TrimSpace(parts[0])
				val := strings.TrimSpace(parts[1])

				if key == "ingress.host" || key == "node.labels.gbnt.ingress.host" {
					var stack db.Stack
					if err := db.DB.First(&stack, "id = ?", svc.StackID).Error; err == nil {
						// e.g., web.mystack.gbnt
						internalDNS := fmt.Sprintf("%s.%s.gbnt", svc.Name, stack.Name)
						content += fmt.Sprintf("%s {\n\ttls internal\n\treverse_proxy %s:80\n}\n\n", val, internalDNS)
					}
				}
			}
		}
	}

	// If no reverse proxy rules are generated, write a default block to avoid caddy start error
	if !strings.Contains(content, "reverse_proxy") {
		content += ":80 {\n\trespond \"Gubernator Caddy Ingress is running!\" 200\n}\n"
	}

	caddyfilePath := caddy.CaddyfilePath()
	err := os.WriteFile(caddyfilePath, []byte(content), 0644)
	if err != nil {
		log.Printf("Failed to write Caddyfile: %v\n", err)
	} else {
		log.Println("🌊 Aqueducts: Generated new Caddyfile.")
		if err := caddy.ReloadConfig(); err != nil {
			log.Printf("⚠️  Aqueducts: Caddy reload failed: %v\n", err)
		}
	}
}
