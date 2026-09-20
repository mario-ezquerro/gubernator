package aqueducts

import (
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"

	"github.com/mario-ezquerro/gubernator/internal/caddy"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

func init() {
	caddy.OnWAFConfigUpdatedHook = func() {
		GenerateCaddyfile()
	}
}

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
	// hostLBPolicy stores the load balancing algorithm per hostname (round_robin, least_conn, ip_hash)
	hostLBPolicy := make(map[string]string)
	// hostHealthURI stores the active healthcheck URI per hostname (e.g. /health)
	hostHealthURI := make(map[string]string)
	hostHealthInterval := make(map[string]string)
	hostHealthTimeout := make(map[string]string)
	// hostWAFCompose tracks Compose-declared WAF policies per hostname
	hostWAFComposeEnabled := make(map[string]bool)
	hostWAFComposeMode := make(map[string]string)
	// Preserve insertion order for deterministic output.
	var hostOrder []string

	for _, svc := range services {
		var ingressHost string
		var ingressEmail string
		var ingressTLS string
		var caddyPort string
		var caddyLB string
		var healthURI string
		var healthInterval string
		var healthTimeout string

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
			case "gbnt.caddy.port", "ingress.port":
				caddyPort = strings.TrimSpace(val)
			case "gbnt.caddy.lb", "ingress.lb", "gbnt.lb_policy":
				caddyLB = strings.TrimSpace(val)
			case "gbnt.caddy.health_uri", "ingress.health_uri":
				healthURI = strings.TrimSpace(val)
			case "gbnt.caddy.health_interval", "ingress.health_interval":
				healthInterval = strings.TrimSpace(val)
			case "gbnt.caddy.health_timeout", "ingress.health_timeout":
				healthTimeout = strings.TrimSpace(val)
			case "gbnt.waf.enabled", "ingress.waf.enabled", "node.labels.gbnt.waf.enabled":
				hostWAFComposeEnabled[ingressHost] = strings.ToLower(val) == "true"
			case "gbnt.waf.mode", "ingress.waf.mode", "node.labels.gbnt.waf.mode":
				hostWAFComposeMode[ingressHost] = strings.ToLower(val)
			}
		}

		if ingressHost == "" {
			continue
		}

		if caddyLB != "" {
			hostLBPolicy[ingressHost] = caddyLB
		}
		if healthURI != "" {
			hostHealthURI[ingressHost] = healthURI
		}
		if healthInterval != "" {
			hostHealthInterval[ingressHost] = healthInterval
		}
		if healthTimeout != "" {
			hostHealthTimeout[ingressHost] = healthTimeout
		}

		// Only include running tasks with a real IP or status running.
		var tasks []db.Task
		if err := db.DB.Where(
			"service_id = ? AND status = ?",
			svc.ID, "running",
		).Find(&tasks).Error; err != nil || len(tasks) == 0 {
			// Skip if no running instances
			continue
		}

		defaultPort := "80"
		if len(svc.Ports) > 0 {
			p := svc.Ports[0]
			parts := strings.Split(p, ":")
			lastPart := parts[len(parts)-1]
			cleaned := strings.TrimSpace(strings.Split(lastPart, "/")[0])
			if cleaned != "" {
				defaultPort = cleaned
			}
		}

		for _, t := range tasks {
			var targetIP string
			targetPort := defaultPort
			if caddyPort != "" {
				targetPort = caddyPort
			}

			if t.NodeID == "node-local-manager" || t.NodeID == "" || strings.Contains(strings.ToLower(t.NodeID), "manager") {
				targetIP = t.ContainerIP
				if targetIP == "" || targetIP == "invalid" {
					targetIP = "127.0.0.1"
				}
			} else {
				// Remote worker task: lookup worker node IP
				var node db.Node
				if err := db.DB.Where("id = ?", t.NodeID).First(&node).Error; err == nil && node.IP != "" {
					targetIP = node.IP
				} else if t.ContainerIP != "" {
					targetIP = t.ContainerIP
				}
				// Determine reachable upstream port on the worker host:
				// If the container published a public host port on the worker, route to it.
				// Otherwise, route to the worker node's Caddy Ingress on port 80.
				hasPublicHostPort := false
				if len(svc.Ports) > 0 {
					for _, portSpec := range svc.Ports {
						spec := strings.TrimSpace(portSpec)
						if idx := strings.Index(spec, "/"); idx != -1 {
							spec = spec[:idx]
						}
						parts := strings.Split(spec, ":")
						var bindHost, hostPort string
						if len(parts) == 2 {
							hostPort = strings.TrimSpace(parts[0])
						} else if len(parts) == 3 {
							bindHost = strings.TrimSpace(parts[0])
							hostPort = strings.TrimSpace(parts[1])
						}
						if hostPort != "" && bindHost != "127.0.0.1" && bindHost != "localhost" {
							if caddyPort == "" || caddyPort == defaultPort {
								targetPort = hostPort
								hasPublicHostPort = true
								break
							}
						}
					}
				}
				if !hasPublicHostPort {
					// No public host port published on the worker node.
					// Route traffic to the worker node's Caddy Ingress on port 80,
					// which locally routes the virtual host to the container IP.
					targetPort = "80"
				}
			}

			// Safety check: Prevent Caddy from reverse proxying to its own listening port 80/443 on the Manager host
			var mgrNode db.Node
			isLocalManagerHost := targetIP == "127.0.0.1" || targetIP == "localhost"
			if err := db.DB.Where("role = ? OR id = ?", "manager", "node-local-manager").First(&mgrNode).Error; err == nil && mgrNode.IP != "" {
				if mgrNode.IP == targetIP {
					isLocalManagerHost = true
				}
			}
			if isLocalManagerHost && (targetPort == "80" || targetPort == "443") {
				if t.ContainerIP != "" && t.ContainerIP != targetIP {
					targetIP = t.ContainerIP
					targetPort = defaultPort
				}
			}

			if targetIP == "" || targetIP == "invalid" {
				continue
			}

			if _, seen := hostUpstreams[ingressHost]; !seen {
				hostOrder = append(hostOrder, ingressHost)
			}

			upstreamAddr := fmt.Sprintf("%s:%s", targetIP, targetPort)
			// Deduplicate upstreams
			alreadyIn := false
			for _, u := range hostUpstreams[ingressHost] {
				if u == upstreamAddr {
					alreadyIn = true
					break
				}
			}
			if !alreadyIn {
				hostUpstreams[ingressHost] = append(hostUpstreams[ingressHost], upstreamAddr)
			}

			// Record TLS preference
			if ingressTLS != "" {
				hostTLS[ingressHost] = ingressTLS
			} else if ingressEmail != "" {
				hostTLS[ingressHost] = ingressEmail
			}
		}
	}

	content := "# Gubernator Auto-Generated Caddyfile\n\n"
	wafConfig, _ := caddy.GetWAFConfig()

	for _, host := range hostOrder {
		upstreams := hostUpstreams[host]
		if len(upstreams) == 0 {
			continue
		}
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

		// Determine WAF snippet for this route
		var routeOverride *db.ManagedRouteWAF
		if existingOverride, err := caddy.GetRouteWAF(host); err == nil && existingOverride != nil {
			routeOverride = existingOverride
		} else if composeEnabled, ok := hostWAFComposeEnabled[host]; ok {
			routeOverride = &db.ManagedRouteWAF{
				Host:         host,
				Enabled:      composeEnabled,
				Mode:         hostWAFComposeMode[host],
				OverriddenBy: "compose",
			}
		}

		wafSnippet := ""
		if wafConfig != nil {
			wafSnippet = caddy.BuildWAFSnippet(host, *wafConfig, routeOverride)
		}

		lbPolicy := hostLBPolicy[host]
		if lbPolicy == "" {
			lbPolicy = "round_robin"
		}
		healthURI := hostHealthURI[host]

		var proxyDirectives []string
		if len(upstreams) > 1 || lbPolicy != "round_robin" || healthURI != "" {
			proxyDirectives = append(proxyDirectives, fmt.Sprintf("\t\tlb_policy %s", lbPolicy))
			if healthURI != "" {
				if !strings.HasPrefix(healthURI, "/") {
					healthURI = "/" + healthURI
				}
				proxyDirectives = append(proxyDirectives, fmt.Sprintf("\t\thealth_uri %s", healthURI))
				interval := hostHealthInterval[host]
				if interval == "" {
					interval = "5s"
				}
				proxyDirectives = append(proxyDirectives, fmt.Sprintf("\t\thealth_interval %s", interval))
				timeout := hostHealthTimeout[host]
				if timeout == "" {
					timeout = "2s"
				}
				proxyDirectives = append(proxyDirectives, fmt.Sprintf("\t\thealth_timeout %s", timeout))
			}
		}

		proxyBlock := ""
		if len(proxyDirectives) > 0 {
			proxyBlock = fmt.Sprintf("\treverse_proxy %s {\n%s\n\t}\n", strings.Join(upstreams, " "), strings.Join(proxyDirectives, "\n"))
		} else {
			proxyBlock = fmt.Sprintf("\treverse_proxy %s\n", strings.Join(upstreams, " "))
		}

		content += fmt.Sprintf(
			"%s {\n%s%s%s}\n\n",
			host, tlsDirective, wafSnippet, proxyBlock,
		)
	}

	// If no reverse proxy rules were generated, write a default block so Caddy starts cleanly.
	if len(hostOrder) == 0 {
		content += ":80 {\n\trespond \"Gubernator Caddy Ingress is running!\" 200\n}\n"
	}

	caddyfilePath := caddy.CaddyfilePath()
	if err := os.MkdirAll(filepath.Dir(caddyfilePath), 0755); err != nil {
		slog.Error("failed to create Caddy directory", "err", err)
		return
	}
	if err := os.WriteFile(caddyfilePath, []byte(content), 0644); err != nil {
		slog.Error("failed to write Caddyfile", "err", err)
		return
	}

	slog.Info("aqueducts: generated new Caddyfile")
	if err := caddy.ReloadConfig(); err != nil {
		slog.Warn("aqueducts: Caddy reload failed", "err", err)
	}
}
