package aqueducts

import (
	"fmt"
	"log/slog"
	"os"
	"strings"
	"sync"

	"github.com/mario-ezquerro/gubernator/internal/coredns"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

// aqueductMutex protects concurrent access to file generation and database queries
var aqueductMutex sync.Mutex

// WG tracks background/asynchronous config generation tasks (primarily used in tests)
var WG sync.WaitGroup

// GenerateAllAsync triggers hosts and caddy file generation asynchronously.
func GenerateAllAsync() {
	WG.Add(1)
	go func() {
		defer WG.Done()
		GenerateHostsFile()
		GenerateCaddyfile()
	}()
}

// SanitizeDNSLabel converts a string into an RFC 1123 compliant DNS subdomain label.
// Allowed characters are lowercase [a-z0-9] and hyphens '-'.
// Spaces, brackets, parentheses, underscores, slashes, colons, and dots are converted to hyphens.
func SanitizeDNSLabel(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	var sb strings.Builder
	for _, r := range s {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '-' {
			sb.WriteRune(r)
		} else if r == ' ' || r == '_' || r == '.' || r == '(' || r == ')' || r == '[' || r == ']' || r == '/' || r == ':' {
			sb.WriteRune('-')
		}
	}
	res := sb.String()
	for strings.Contains(res, "--") {
		res = strings.ReplaceAll(res, "--", "-")
	}
	return strings.Trim(res, "-")
}

// GetNodeSlugs extracts clean DNS host prefixes for a given cluster node.
func GetNodeSlugs(nodeID string, labels map[string]string) []string {
	var slugs []string
	seen := make(map[string]bool)

	addSlug := func(slug string) {
		clean := SanitizeDNSLabel(slug)
		if clean != "" && !seen[clean] {
			seen[clean] = true
			slugs = append(slugs, clean)
		}
	}

	cleanID := SanitizeDNSLabel(nodeID)
	if cleanID == "" || cleanID == "node-local-manager" || cleanID == "manager" {
		addSlug("manager")
		addSlug("node-local-manager")
	} else {
		addSlug(cleanID)
		if strings.HasPrefix(cleanID, "node-") {
			addSlug(strings.TrimPrefix(cleanID, "node-"))
		}
		if strings.HasPrefix(cleanID, "gbnt-") {
			addSlug(strings.TrimPrefix(cleanID, "gbnt-"))
		}
	}

	if labels != nil {
		if h, ok := labels["hostname"]; ok && h != "" {
			addSlug(h)
		}
		if n, ok := labels["gbnt.node.name"]; ok && n != "" {
			addSlug(n)
		}
	}

	return slugs
}

// GetStackSlugs returns sanitized stack slugs, including full and base names.
func GetStackSlugs(stackName string) []string {
	var slugs []string
	seen := make(map[string]bool)

	addSlug := func(slug string) {
		clean := SanitizeDNSLabel(slug)
		if clean != "" && !seen[clean] {
			seen[clean] = true
			slugs = append(slugs, clean)
		}
	}

	fullClean := SanitizeDNSLabel(stackName)
	addSlug(fullClean)

	// If stackName has parentheses or brackets (e.g. "CORE-GBNT (worker-1)" or "[SRE] Monitor (Manager)"),
	// also extract the base stack name (e.g. "core-gbnt" or "sre-monitor").
	idx := strings.IndexAny(stackName, "([")
	if idx > 0 {
		base := strings.TrimSpace(stackName[:idx])
		addSlug(base)
	} else if strings.HasPrefix(stackName, "[") {
		endBracket := strings.Index(stackName, "]")
		if endBracket != -1 {
			rem := stackName[endBracket+1:]
			parenIdx := strings.Index(rem, "(")
			if parenIdx != -1 {
				addSlug(rem[:parenIdx])
			} else {
				addSlug(rem)
			}
		}
	}

	return slugs
}

// GenerateHostsFile queries the DB for all running tasks and regenerates the CoreDNS hosts file.
// After writing, it signals CoreDNS to reload the new records.
func GenerateHostsFile() {
	aqueductMutex.Lock()
	defer aqueductMutex.Unlock()

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
	content += "# Format: <IP> <domain>\n\n"

	seenRecords := make(map[string]bool)
	addRecord := func(ip, domain string) {
		ip = strings.TrimSpace(ip)
		domain = strings.TrimSpace(domain)
		if ip == "" || domain == "" {
			return
		}
		key := fmt.Sprintf("%s\t%s", ip, domain)
		if !seenRecords[key] {
			seenRecords[key] = true
			content += key + "\n"
		}
	}

	for _, t := range tasks {
		var svc db.Service
		if err := db.DB.First(&svc, "id = ?", t.ServiceID).Error; err != nil {
			continue
		}
		var stack db.Stack
		if err := db.DB.First(&stack, "id = ?", svc.StackID).Error; err != nil {
			continue
		}

		targetIP := t.ContainerIP
		var nodeSlugs []string

		if t.NodeID == "node-local-manager" || t.NodeID == "" {
			nodeSlugs = GetNodeSlugs("node-local-manager", nil)
		} else {
			var taskNode db.Node
			if err := db.DB.First(&taskNode, "id = ?", t.NodeID).Error; err == nil {
				if taskNode.IP != "" {
					targetIP = taskNode.IP
				}
				nodeSlugs = GetNodeSlugs(taskNode.ID, taskNode.Labels)
			} else {
				nodeSlugs = GetNodeSlugs(t.NodeID, nil)
			}
		}

		cleanSvc := SanitizeDNSLabel(svc.Name)
		if cleanSvc == "" {
			continue
		}
		cleanTaskID := SanitizeDNSLabel(t.ID)
		stackSlugs := GetStackSlugs(stack.Name)

		// 1. Host-Specific Scheme (<node>.<service>.gbnt and <node>.<service>.gbnt.local)
		for _, nodeSlug := range nodeSlugs {
			addRecord(targetIP, fmt.Sprintf("%s.%s.gbnt.local", nodeSlug, cleanSvc))
			addRecord(targetIP, fmt.Sprintf("%s.%s.gbnt", nodeSlug, cleanSvc))

			// 2. Node + Service + Stack Scheme (<node>.<service>.<stack>.gbnt)
			for _, stSlug := range stackSlugs {
				addRecord(targetIP, fmt.Sprintf("%s.%s.%s.gbnt.local", nodeSlug, cleanSvc, stSlug))
				addRecord(targetIP, fmt.Sprintf("%s.%s.%s.gbnt", nodeSlug, cleanSvc, stSlug))
			}
		}

		// 3. Task Specific Scheme (<task_id>.<service>.<stack>.gbnt)
		for _, stSlug := range stackSlugs {
			if cleanTaskID != "" {
				addRecord(targetIP, fmt.Sprintf("%s.%s.%s.gbnt.local", cleanTaskID, cleanSvc, stSlug))
				addRecord(targetIP, fmt.Sprintf("%s.%s.%s.gbnt", cleanTaskID, cleanSvc, stSlug))
			}

			// 4. Service + Stack Scheme (<service>.<stack>.gbnt)
			addRecord(targetIP, fmt.Sprintf("%s.%s.gbnt.local", cleanSvc, stSlug))
			addRecord(targetIP, fmt.Sprintf("%s.%s.gbnt", cleanSvc, stSlug))
		}

		// 5. Generic Service Aliases (<service>.gbnt)
		addRecord(targetIP, fmt.Sprintf("%s.gbnt.local", cleanSvc))
		addRecord(targetIP, fmt.Sprintf("%s.gbnt", cleanSvc))
	}

	// Add records for ingress.host to point to the correct node IPs where the tasks are running
	var services []db.Service
	if err := db.DB.Find(&services).Error; err == nil {
		seenHosts := make(map[string]bool)
		for _, svc := range services {
			for _, constraint := range svc.Constraints {
				parts := strings.Split(constraint, "==")
				if len(parts) == 2 {
					key := strings.TrimSpace(parts[0])
					val := strings.TrimSpace(parts[1])
					if key == "ingress.host" || key == "node.labels.gbnt.ingress.host" {
						// Find all running tasks for this service
						var tasks []db.Task
						if err := db.DB.Where("service_id = ? AND status = ?", svc.ID, "running").Find(&tasks).Error; err == nil && len(tasks) > 0 {
							nodeIPs := make(map[string]bool)
							for _, t := range tasks {
								var node db.Node
								if err := db.DB.First(&node, "id = ?", t.NodeID).Error; err == nil && node.IP != "" {
									nodeIPs[node.IP] = true
								}
							}
							for ip := range nodeIPs {
								addRecord(ip, val)
							}
							seenHosts[val] = true
						} else if !seenHosts[val] {
							// Fallback if no tasks are running yet, point to Manager IP
							seenHosts[val] = true
							addRecord(hostIP, val)
						}
					}
				}
			}
		}
	}

	// Add Custom User-Defined Static DNS Records
	var customRecords []db.CustomDNSRecord
	if err := db.DB.Find(&customRecords).Error; err == nil && len(customRecords) > 0 {
		content += "\n# Custom User-Defined Static DNS Records\n"
		for _, rec := range customRecords {
			addRecord(rec.IP, rec.Domain)
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
