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
// It automatically detects public domains (e.g. demo.fiware.app) and lets Caddy obtain
// real Let's Encrypt / ZeroSSL TLS certificates, while using 'tls internal' for local domains (*.gbnt.local).
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
	// hostTLS stores optional custom TLS configuration per hostname (e.g. email, "internal", "off").
	hostTLS := make(map[string]string)
	// Preserve insertion order for deterministic output.
	var hostOrder []string

	for _, svc := range services {
		var ingressHost string
		var ingressEmail string
		var ingressTLS string

		for _, constraint := range svc.Constraints {
			var key, val string
			if strings.Contains(constraint, "==") {
				parts := strings.Split(constraint, "==")
				if len(parts) == 2 {
					key = strings.TrimSpace(parts[0])
					val = strings.TrimSpace(parts[1])
				}
			} else if strings.Contains(constraint, "=") {
				parts := strings.SplitN(constraint, "=", 2)
				if len(parts) == 2 {
					key = strings.TrimSpace(parts[0])
					val = strings.TrimSpace(parts[1])
				}
			}

			switch key {
			case "ingress.host", "node.labels.gbnt.ingress.host", "gbnt.ingress.host":
				ingressHost = val
			case "ingress.email", "node.labels.gbnt.ingress.email", "gbnt.ingress.email":
				ingressEmail = val
			case "ingress.tls", "node.labels.gbnt.ingress.tls", "gbnt.ingress.tls":
				ingressTLS = strings.ToLower(val)
			}
		}

		if ingressHost == "" {
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

		for _, t := range tasks {
			if t.NodeID != "node-local-manager" {
				continue
			}
			targetIP := t.ContainerIP
			targetPort := port

			if _, seen := hostUpstreams[ingressHost]; !seen {
				hostOrder = append(hostOrder, ingressHost)
			}
			hostUpstreams[ingressHost] = append(hostUpstreams[ingressHost], fmt.Sprintf("%s:%s", targetIP, targetPort))

			// Record TLS preference
			if ingressTLS != "" {
				hostTLS[ingressHost] = ingressTLS
			} else if ingressEmail != "" {
				hostTLS[ingressHost] = ingressEmail
			}
		}
	}

	content := "# Gubernator Auto-Generated Caddyfile\n\n"

	for _, host := range hostOrder {
		upstreams := hostUpstreams[host]
		tlsDirective := ""

		tlsOpt := hostTLS[host]
		if tlsOpt == "internal" || (tlsOpt == "" && caddy.IsLocalDomain(host)) {
			tlsDirective = "\ttls internal\n"
		} else if tlsOpt == "off" || tlsOpt == "none" {
			// No TLS directive, user requested plain HTTP or explicit handling
			tlsDirective = ""
		} else if strings.Contains(tlsOpt, "@") {
			// ACME registration email specified (e.g. admin@fiware.app)
			tlsDirective = fmt.Sprintf("\ttls %s\n", tlsOpt)
		} else if tlsOpt != "" && tlsOpt != "letsencrypt" && tlsOpt != "auto" {
			tlsDirective = fmt.Sprintf("\ttls %s\n", tlsOpt)
		}
		// For public domains without explicit flags, omit 'tls internal' so Caddy
		// automatically requests and manages public Let's Encrypt / ZeroSSL certificates!

		content += fmt.Sprintf(
			"%s {\n%s\treverse_proxy %s {\n\t\tlb_policy round_robin\n\t}\n}\n\n",
			host, tlsDirective, strings.Join(upstreams, " "),
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
