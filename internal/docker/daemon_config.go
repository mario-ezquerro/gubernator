package docker

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log/slog"
	"path/filepath"
	"strings"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/mario-ezquerro/gubernator/internal/storage"
)

// DockerDaemonConfig represents the structured configuration of /etc/docker/daemon.json.
type DockerDaemonConfig struct {
	LogDriver              string                 `json:"log-driver,omitempty"`
	LogOpts                map[string]string      `json:"log-opts,omitempty"`
	LiveRestore            *bool                  `json:"live-restore,omitempty"`
	StorageDriver          string                 `json:"storage-driver,omitempty"`
	DataRoot               string                 `json:"data-root,omitempty"`
	DNS                    []string               `json:"dns,omitempty"`
	DNSSearch              []string               `json:"dns-search,omitempty"`
	Bip                    string                 `json:"bip,omitempty"`
	DefaultAddressPools    []AddressPool          `json:"default-address-pools,omitempty"`
	InsecureRegistries     []string               `json:"insecure-registries,omitempty"`
	RegistryMirrors        []string               `json:"registry-mirrors,omitempty"`
	MetricsAddr            string                 `json:"metrics-addr,omitempty"`
	Experimental           *bool                  `json:"experimental,omitempty"`
	MaxConcurrentDownloads int                    `json:"max-concurrent-downloads,omitempty"`
	MaxConcurrentUploads   int                    `json:"max-concurrent-uploads,omitempty"`
	DefaultRuntime         string                 `json:"default-runtime,omitempty"`
	Runtimes               map[string]interface{} `json:"runtimes,omitempty"`
	NoNewPrivileges        *bool                  `json:"no-new-privileges,omitempty"`
	UsernsRemap            string                 `json:"userns-remap,omitempty"`
	ICC                    *bool                  `json:"icc,omitempty"`
	IPForward              *bool                  `json:"ip-forward,omitempty"`
	IPTables               *bool                  `json:"iptables,omitempty"`
	Extra                  map[string]interface{} `json:"-"`
}

// AddressPool represents default-address-pools in daemon.json
type AddressPool struct {
	Base string `json:"base"`
	Size int    `json:"size"`
}

// HostDaemonStatus reports the state of /etc/docker/daemon.json on a cluster Centurion node.
type HostDaemonStatus struct {
	NodeID            string                 `json:"node_id"`
	NodeIP            string                 `json:"node_ip"`
	Role              string                 `json:"role"`
	HasGPU            bool                   `json:"has_gpu"`
	GPUInfo           string                 `json:"gpu_info,omitempty"`
	DaemonRunning     bool                   `json:"daemon_running"`
	ConfigExists      bool                   `json:"config_exists"`
	ConfigPath        string                 `json:"config_path"`
	RawJSON           string                 `json:"raw_json"`
	ParsedConfig      map[string]interface{} `json:"parsed_config,omitempty"`
	LastModified      string                 `json:"last_modified,omitempty"`
	LiveRestoreActive bool                   `json:"live_restore_active"`
	Error             string                 `json:"error,omitempty"`
}

// ApplyDaemonResult reports the outcome of an apply operation on a single host.
type ApplyDaemonResult struct {
	NodeID     string `json:"node_id"`
	NodeIP     string `json:"node_ip"`
	Success    bool   `json:"success"`
	BackupFile string `json:"backup_file,omitempty"`
	Action     string `json:"action"`
	Output     string `json:"output,omitempty"`
	Error      string `json:"error,omitempty"`
}

// BuiltinDaemonPresets returns sensible, production-tested configuration blueprints.
func BuiltinDaemonPresets() map[string]map[string]interface{} {
	return map[string]map[string]interface{}{
		"production": {
			"log-driver": "json-file",
			"log-opts": map[string]interface{}{
				"max-size": "20m",
				"max-file": "3",
			},
			"live-restore":             true,
			"storage-driver":           "overlay2",
			"dns":                      []string{"1.1.1.1", "8.8.8.8"},
			"max-concurrent-downloads": 10,
		},
		"gpu": {
			"log-driver": "json-file",
			"log-opts": map[string]interface{}{
				"max-size": "20m",
				"max-file": "3",
			},
			"live-restore":             true,
			"storage-driver":           "overlay2",
			"dns":                      []string{"1.1.1.1", "8.8.8.8"},
			"max-concurrent-downloads": 10,
			"default-runtime":          "nvidia",
			"runtimes": map[string]interface{}{
				"nvidia": map[string]interface{}{
					"path":        "nvidia-container-runtime",
					"runtimeArgs": []string{},
				},
			},
		},
		"sre": {
			"log-driver": "json-file",
			"log-opts": map[string]interface{}{
				"max-size": "20m",
				"max-file": "3",
			},
			"live-restore":             true,
			"storage-driver":           "overlay2",
			"dns":                      []string{"1.1.1.1", "8.8.8.8"},
			"metrics-addr":             "0.0.0.0:9323",
			"experimental":             true,
			"max-concurrent-downloads": 10,
		},
		"minimal": {
			"log-driver": "json-file",
			"log-opts": map[string]interface{}{
				"max-size": "10m",
				"max-file": "3",
			},
			"live-restore": true,
		},
	}
}

// NodeHasGPU checks whether a node has GPU hardware labels or hardware devices.
func NodeHasGPU(n db.Node) bool {
	if n.Labels != nil {
		for k, v := range n.Labels {
			kl := strings.ToLower(k)
			vl := strings.ToLower(v)
			if strings.Contains(kl, "gpu") || strings.Contains(kl, "nvidia") || strings.Contains(kl, "cuda") {
				if vl != "false" && vl != "none" && vl != "0" {
					return true
				}
			}
		}
	}
	return false
}

// ResolveTargetNodes returns a list of db.Node items matching targetScope and optional targetNode.
func ResolveTargetNodes(targetScope, targetNode string) []db.Node {
	targetScope = strings.TrimSpace(strings.ToLower(targetScope))
	targetNode = strings.TrimSpace(strings.ToLower(targetNode))

	var all []db.Node
	if db.DB != nil {
		db.DB.Find(&all)
	}
	if len(all) == 0 {
		all = append(all, db.Node{ID: "manager", IP: "127.0.0.1", Role: "manager", Status: "active"})
	}

	switch targetScope {
	case "gpu":
		var result []db.Node
		for _, n := range all {
			if NodeHasGPU(n) {
				result = append(result, n)
			}
		}
		// If no nodes explicitly labeled GPU yet, include any node where targetNode mentions gpu
		if len(result) == 0 && targetNode != "" && targetNode != "all" {
			return resolveSingleNode(all, targetNode)
		}
		return result

	case "manager", "local":
		var result []db.Node
		for _, n := range all {
			if strings.EqualFold(n.Role, "manager") || storage.IsLocalHost(n.IP) {
				result = append(result, n)
				break
			}
		}
		if len(result) == 0 {
			result = append(result, db.Node{ID: "manager", IP: "127.0.0.1", Role: "manager", Status: "active"})
		}
		return result

	case "node", "single":
		if targetNode != "" {
			return resolveSingleNode(all, targetNode)
		}
		return all

	default: // "all" or empty
		if targetNode != "" && targetNode != "all" && targetNode != "all-nodes" && targetNode != "cluster" {
			return resolveSingleNode(all, targetNode)
		}
		return all
	}
}

func resolveSingleNode(all []db.Node, target string) []db.Node {
	for _, n := range all {
		if strings.EqualFold(n.ID, target) || strings.EqualFold(n.IP, target) {
			return []db.Node{n}
		}
	}
	// Fallback to synthetic node with specified IP
	return []db.Node{{ID: target, IP: target, Role: "worker", Status: "active"}}
}

// GetClusterDockerDaemonStatus retrieves the current /etc/docker/daemon.json and system status from target hosts.
func GetClusterDockerDaemonStatus(targetScope, targetNode string) ([]HostDaemonStatus, error) {
	nodes := ResolveTargetNodes(targetScope, targetNode)
	statuses := make([]HostDaemonStatus, 0, len(nodes))

	for _, n := range nodes {
		status := HostDaemonStatus{
			NodeID:       n.ID,
			NodeIP:       n.IP,
			Role:         n.Role,
			HasGPU:       NodeHasGPU(n),
			ConfigPath:   "/etc/docker/daemon.json",
			ConfigExists: false,
		}

		// Probe script: checks /etc/docker/daemon.json, nvidia-smi, and systemctl is-active docker
		script := `
CONFIG=""
EXISTS="false"
LAST_MOD=""
GPU_INFO=""
DAEMON_ACTIVE="false"

if [ -f /etc/docker/daemon.json ]; then
  EXISTS="true"
  CONFIG=$(base64 < /etc/docker/daemon.json 2>/dev/null | tr -d '\n')
  LAST_MOD=$(stat -c %y /etc/docker/daemon.json 2>/dev/null || stat -f "%Sm" /etc/docker/daemon.json 2>/dev/null || date)
fi

if which nvidia-smi >/dev/null 2>&1; then
  GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -n 1)
elif [ -e /dev/nvidia0 ] || [ -d /proc/driver/nvidia ]; then
  GPU_INFO="NVIDIA GPU Detected"
fi

if systemctl is-active docker >/dev/null 2>&1; then
  DAEMON_ACTIVE="true"
elif pgrep dockerd >/dev/null 2>&1; then
  DAEMON_ACTIVE="true"
fi

printf "%s||%s||%s||%s||%s" "$EXISTS" "$LAST_MOD" "$GPU_INFO" "$DAEMON_ACTIVE" "$CONFIG"
`
		out, err := storage.ExecuteRemoteScript(n.IP, script)
		if err != nil {
			status.Error = err.Error()
			statuses = append(statuses, status)
			continue
		}

		parts := strings.Split(out, "||")
		if len(parts) >= 5 {
			status.ConfigExists = strings.TrimSpace(parts[0]) == "true"
			status.LastModified = strings.TrimSpace(parts[1])
			detectedGPU := strings.TrimSpace(parts[2])
			if detectedGPU != "" {
				status.HasGPU = true
				status.GPUInfo = detectedGPU
			}
			status.DaemonRunning = strings.TrimSpace(parts[3]) == "true"

			b64Config := strings.TrimSpace(parts[4])
			if b64Config != "" {
				if decoded, err := base64.StdEncoding.DecodeString(b64Config); err == nil {
					status.RawJSON = string(decoded)
					var parsed map[string]interface{}
					if err := json.Unmarshal(decoded, &parsed); err == nil {
						status.ParsedConfig = parsed
						if lr, ok := parsed["live-restore"].(bool); ok && lr {
							status.LiveRestoreActive = true
						}
					}
				}
			}
		}

		statuses = append(statuses, status)
	}

	return statuses, nil
}

// ValidateDaemonJSON verifies that raw JSON conforms to valid JSON syntax and basic Docker daemon rules.
func ValidateDaemonJSON(rawJSON string) (map[string]interface{}, error) {
	rawJSON = strings.TrimSpace(rawJSON)
	if rawJSON == "" {
		return map[string]interface{}{}, nil
	}

	var parsed map[string]interface{}
	decoder := json.NewDecoder(strings.NewReader(rawJSON))
	decoder.UseNumber()
	if err := decoder.Decode(&parsed); err != nil {
		return nil, fmt.Errorf("invalid JSON syntax: %w", err)
	}

	// Basic safety checks
	if dr, ok := parsed["data-root"].(string); ok && dr != "" {
		if !filepath.IsAbs(dr) {
			return nil, fmt.Errorf("data-root must be an absolute path (got: %s)", dr)
		}
	}

	return parsed, nil
}

// SaveAndApplyDockerDaemonConfig writes /etc/docker/daemon.json on target nodes and executes reload/restart.
func SaveAndApplyDockerDaemonConfig(targetScope, targetNode, rawJSON, action string, backup bool) ([]ApplyDaemonResult, error) {
	parsed, err := ValidateDaemonJSON(rawJSON)
	if err != nil {
		return nil, fmt.Errorf("pre-validation failed: %w", err)
	}

	// Re-format nicely indented
	formattedBytes, err := json.MarshalIndent(parsed, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("failed to format json: %w", err)
	}
	formattedStr := string(formattedBytes)
	b64Config := base64.StdEncoding.EncodeToString(formattedBytes)

	nodes := ResolveTargetNodes(targetScope, targetNode)
	if len(nodes) == 0 {
		return nil, fmt.Errorf("no target nodes found for scope '%s' (node: '%s')", targetScope, targetNode)
	}

	results := make([]ApplyDaemonResult, 0, len(nodes))
	action = strings.ToLower(strings.TrimSpace(action))
	if action == "" {
		action = "apply_and_reload"
	}

	for _, n := range nodes {
		res := ApplyDaemonResult{
			NodeID:  n.ID,
			NodeIP:  n.IP,
			Action:  action,
			Success: false,
		}

		timestamp := time.Now().Unix()
		backupFile := fmt.Sprintf("/etc/docker/daemon.json.bak.%d", timestamp)

		var script strings.Builder
		script.WriteString("set -e\n")
		script.WriteString("sudo mkdir -p /etc/docker\n")

		if backup {
			script.WriteString(fmt.Sprintf(`
if [ -f /etc/docker/daemon.json ]; then
  sudo cp /etc/docker/daemon.json %s
fi
`, backupFile))
			res.BackupFile = backupFile
		}

		script.WriteString(fmt.Sprintf("echo '%s' | base64 -d | sudo tee /etc/docker/daemon.json >/dev/null\n", b64Config))
		script.WriteString("sudo chmod 644 /etc/docker/daemon.json\n")

		switch action {
		case "apply_and_reload", "reload":
			script.WriteString(`
if systemctl is-active docker >/dev/null 2>&1; then
  sudo systemctl reload docker 2>&1 || sudo kill -SIGHUP $(pidof dockerd) 2>&1 || sudo systemctl restart docker 2>&1
fi
echo "Docker daemon reloaded successfully"
`)

		case "apply_and_restart", "restart":
			script.WriteString(`
if systemctl is-active docker >/dev/null 2>&1; then
  sudo systemctl restart docker 2>&1
fi
echo "Docker daemon restarted successfully"
`)

		case "save_only", "save":
			script.WriteString("echo \"Configuration saved to /etc/docker/daemon.json\"\n")

		default:
			script.WriteString("echo \"Configuration saved to /etc/docker/daemon.json\"\n")
		}

		out, err := storage.ExecuteRemoteScript(n.IP, script.String())
		if err != nil {
			slog.Error("failed to apply docker daemon config to node", "node_id", n.ID, "ip", n.IP, "err", err, "out", out)
			res.Error = fmt.Sprintf("%v: %s", err, strings.TrimSpace(out))
			res.Output = strings.TrimSpace(out)
		} else {
			res.Success = true
			res.Output = strings.TrimSpace(out)
			slog.Info("docker daemon config applied successfully to node", "node_id", n.ID, "ip", n.IP, "action", action)
		}

		results = append(results, res)
	}

	_ = formattedStr
	return results, nil
}
