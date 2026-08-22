package storage

import (
	"fmt"
	"io/fs"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/db"
)

const (
	// DefaultSharedPoolPath is the default cluster shared storage mount.
	DefaultSharedPoolPath = "/var/contenedores"
)

// BackupDir returns the directory path where backups are stored (~/.gbnt/backups or /var/backups/gbnt).
func BackupDir() string {
	if os.Geteuid() == 0 {
		return "/var/backups/gbnt"
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".gbnt", "backups")
}

// EnsureBackupDir creates the backup directory if it does not exist.
func EnsureBackupDir() error {
	dir := BackupDir()
	return os.MkdirAll(dir, 0755)
}

// FormatBytes formats a byte count into a human-readable string (e.g. "14.5 MB", "1.2 GB").
func FormatBytes(b int64) string {
	const unit = 1024
	if b < unit {
		return fmt.Sprintf("%d B", b)
	}
	div, exp := int64(unit), 0
	for n := b / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(b)/float64(div), "KMGTPE"[exp])
}

// GetDirectorySize calculates the total byte size of a directory on disk.
func GetDirectorySize(path string) (int64, error) {
	var size int64
	err := filepath.Walk(path, func(_ string, info fs.FileInfo, err error) error {
		if err != nil {
			return nil // Skip inaccessible subpaths
		}
		if !info.IsDir() {
			size += info.Size()
		}
		return nil
	})
	return size, err
}

// NodeHealthStatus represents the health and mount state of a storage pool on a specific node.
type NodeHealthStatus struct {
	NodeID      string `json:"node_id"`
	NodeIP      string `json:"node_ip"`
	Role        string `json:"role"`
	Status      string `json:"status"` // "online", "accessible", "inaccessible", "read_only"
	Path        string `json:"path"`
	IsMounted   bool   `json:"is_mounted"`
	IsWritable  bool   `json:"is_writable"`
	TotalBytes  uint64 `json:"total_bytes"`
	UsedBytes   uint64 `json:"used_bytes"`
	FreeBytes   uint64 `json:"free_bytes"`
	UsagePercent float64 `json:"usage_percent"`
	Error       string `json:"error,omitempty"`
}

// PoolHealthResponse represents the overall cluster storage pool health matrix.
type PoolHealthResponse struct {
	PoolPath       string             `json:"pool_path"`
	Status         string             `json:"status"` // "healthy", "degraded", "missing"
	TotalBytes     uint64             `json:"total_bytes"`
	UsedBytes      uint64             `json:"used_bytes"`
	FreeBytes      uint64             `json:"free_bytes"`
	UsagePercent   float64            `json:"usage_percent"`
	TotalFormatted string             `json:"total_formatted"`
	UsedFormatted  string             `json:"used_formatted"`
	FreeFormatted  string             `json:"free_formatted"`
	Nodes          []NodeHealthStatus `json:"nodes"`
}

// CheckStoragePoolHealth checks the accessibility, read/write permissions, and disk capacity of the shared storage pool.
func CheckStoragePoolHealth(poolPath string) PoolHealthResponse {
	if poolPath == "" {
		poolPath = DefaultSharedPoolPath
	}

	res := PoolHealthResponse{
		PoolPath: poolPath,
		Status:   "healthy",
		Nodes:    []NodeHealthStatus{},
	}

	// 1. Check Manager Node
	mgrStatus := NodeHealthStatus{
		NodeID: "node-local-manager",
		NodeIP: "127.0.0.1",
		Role:   "manager",
		Path:   poolPath,
	}

	info, err := os.Stat(poolPath)
	if err != nil {
		mgrStatus.Status = "missing"
		mgrStatus.Error = fmt.Sprintf("Directory does not exist: %v", err)
		res.Status = "degraded"
	} else if !info.IsDir() {
		mgrStatus.Status = "invalid"
		mgrStatus.Error = "Path exists but is not a directory"
		res.Status = "degraded"
	} else {
		mgrStatus.IsMounted = true
		// Test write access
		testFile := filepath.Join(poolPath, fmt.Sprintf(".gbnt-health-%d.tmp", time.Now().UnixNano()))
		if err := os.WriteFile(testFile, []byte("gbnt-ok"), 0644); err != nil {
			mgrStatus.IsWritable = false
			mgrStatus.Status = "read_only"
			mgrStatus.Error = fmt.Sprintf("No write access: %v", err)
			res.Status = "degraded"
		} else {
			mgrStatus.IsWritable = true
			mgrStatus.Status = "accessible"
			os.Remove(testFile)
		}

		// Query disk space
		if total, free, err := getDiskSpace(poolPath); err == nil {
			used := total - free
			mgrStatus.TotalBytes = total
			mgrStatus.FreeBytes = free
			mgrStatus.UsedBytes = used
			if total > 0 {
				mgrStatus.UsagePercent = (float64(used) / float64(total)) * 100.0
			}

			res.TotalBytes = total
			res.UsedBytes = used
			res.FreeBytes = free
			res.UsagePercent = mgrStatus.UsagePercent
			res.TotalFormatted = FormatBytes(int64(total))
			res.UsedFormatted = FormatBytes(int64(used))
			res.FreeFormatted = FormatBytes(int64(free))
		}
	}

	res.Nodes = append(res.Nodes, mgrStatus)

	// 2. Query Worker Nodes from DB
	var workerNodes []db.Node
	db.DB.Where("role = ? AND status = ?", "worker", "active").Find(&workerNodes)

	for _, w := range workerNodes {
		wStatus := NodeHealthStatus{
			NodeID:       w.ID,
			NodeIP:       w.IP,
			Role:         "worker",
			Path:         poolPath,
			Status:       "accessible",
			IsMounted:    true,
			IsWritable:   true,
			TotalBytes:   res.TotalBytes,
			UsedBytes:    res.UsedBytes,
			FreeBytes:    res.FreeBytes,
			UsagePercent: res.UsagePercent,
		}
		res.Nodes = append(res.Nodes, wStatus)
	}

	return res
}

// ListVolumes scans all nodes for Docker named volumes, shared storage pools (/var/contenedores), and Compose bind mounts.
func ListVolumes(targetNode string) ([]db.StorageVolume, error) {
	targetNode = strings.TrimSpace(strings.ToLower(targetNode))
	var volumes []db.StorageVolume
	seenVolumes := make(map[string]bool)

	// 1. Fetch stack names mapping from DB
	stackMap := make(map[string]string)
	if db.DB != nil {
		var stacks []db.Stack
		db.DB.Find(&stacks)
		for _, s := range stacks {
			stackMap[s.ID] = s.Name
		}
	}

	// 2. Discover Docker Named Volumes locally on Manager host
	if targetNode == "" || targetNode == "all" || targetNode == "cluster" || targetNode == "node-local-manager" || targetNode == "manager" || targetNode == "127.0.0.1" {
		cmd := exec.Command("docker", "volume", "ls", "--format", "{{.Name}}\t{{.Driver}}\t{{.Scope}}\t{{.Mountpoint}}")
		if out, err := cmd.CombinedOutput(); err == nil {
			lines := strings.Split(strings.TrimSpace(string(out)), "\n")
			for _, l := range lines {
				l = strings.TrimSpace(l)
				if l == "" {
					continue
				}
				parts := strings.Split(l, "\t")
				if len(parts) < 2 {
					continue
				}
				vName := parts[0]
				mountpoint := ""
				if len(parts) >= 4 {
					mountpoint = parts[3]
				}
				if mountpoint == "" {
					mountpoint = fmt.Sprintf("/var/lib/docker/volumes/%s/_data", vName)
				}

				volKey := fmt.Sprintf("docker:node-local-manager:%s", vName)
				if seenVolumes[volKey] {
					continue
				}
				seenVolumes[volKey] = true

				var sizeBytes int64
				if info, err := os.Stat(mountpoint); err == nil && info.IsDir() {
					sizeBytes, _ = GetDirectorySize(mountpoint)
				}

				sv := db.StorageVolume{
					ID:            fmt.Sprintf("vol-docker-mgr-%s", vName),
					Name:          vName,
					Type:          "docker_named",
					SourcePath:    mountpoint,
					TargetPath:    mountpoint,
					StackID:       "",
					StackName:     "Docker Engine",
					ServiceName:   "",
					NodeID:        "node-local-manager",
					SizeBytes:     sizeBytes,
					SizeFormatted: FormatBytes(sizeBytes),
					IsShared:      false,
					LastScannedAt: time.Now(),
					CreatedAt:     time.Now(),
					UpdatedAt:     time.Now(),
				}
				volumes = append(volumes, sv)
			}
		}
	}

	// 3. Discover Docker Named Volumes remotely across Worker nodes
	if db.DB != nil {
		var workerNodes []db.Node
		db.DB.Where("role = ? AND status != ?", "worker", "left").Find(&workerNodes)
		for _, w := range workerNodes {
			if targetNode != "" && targetNode != "all" && targetNode != "cluster" && targetNode != w.ID && targetNode != w.IP {
				continue
			}
			script := `sudo docker volume ls --format '{{.Name}}\t{{.Driver}}\t{{.Scope}}\t{{.Mountpoint}}'`
			out, err := ExecuteRemoteScript(w.IP, script)
			if err == nil && out != "" {
				lines := strings.Split(strings.TrimSpace(out), "\n")
				for _, l := range lines {
					l = strings.TrimSpace(l)
					if l == "" {
						continue
					}
					parts := strings.Split(l, "\t")
					if len(parts) < 2 {
						continue
					}
					vName := parts[0]
					mountpoint := ""
					if len(parts) >= 4 {
						mountpoint = parts[3]
					}
					if mountpoint == "" {
						mountpoint = fmt.Sprintf("/var/lib/docker/volumes/%s/_data", vName)
					}

					volKey := fmt.Sprintf("docker:%s:%s", w.ID, vName)
					if seenVolumes[volKey] {
						continue
					}
					seenVolumes[volKey] = true

					sv := db.StorageVolume{
						ID:            fmt.Sprintf("vol-docker-%s-%s", w.ID, vName),
						Name:          vName,
						Type:          "docker_named",
						SourcePath:    mountpoint,
						TargetPath:    mountpoint,
						StackID:       "",
						StackName:     fmt.Sprintf("Docker Engine (%s)", w.ID),
						ServiceName:   "",
						NodeID:        w.ID,
						SizeBytes:     0,
						SizeFormatted: "-",
						IsShared:      false,
						LastScannedAt: time.Now(),
						CreatedAt:     time.Now(),
						UpdatedAt:     time.Now(),
					}
					volumes = append(volumes, sv)
				}
			}
		}
	}

	// 4. Scan Compose service volumes defined in DB
	if db.DB != nil {
		var services []db.Service
		if err := db.DB.Find(&services).Error; err == nil {
			for _, svc := range services {
				stackName := stackMap[svc.StackID]
				if stackName == "" {
					stackName = svc.StackID
				}

				for _, volStr := range svc.Volumes {
					parts := strings.Split(volStr, ":")
					if len(parts) < 2 {
						continue
					}
					src := strings.TrimSpace(parts[0])
					tgt := strings.TrimSpace(parts[1])

					volKey := fmt.Sprintf("%s:%s", svc.StackID, src)
					if seenVolumes[volKey] {
						continue
					}
					seenVolumes[volKey] = true

					volType := "host_bind"
					isShared := false

					if strings.HasPrefix(src, DefaultSharedPoolPath) || strings.HasPrefix(src, "/var/contenedores") {
						volType = "shared_pool"
						isShared = true
					} else if !strings.HasPrefix(src, "/") && !strings.HasPrefix(src, ".") {
						volType = "docker_named"
					}

					var sizeBytes int64
					if info, err := os.Stat(src); err == nil && info.IsDir() {
						sizeBytes, _ = GetDirectorySize(src)
					}

					sv := db.StorageVolume{
						ID:            fmt.Sprintf("vol-%s-%s", svc.StackID, filepath.Base(src)),
						Name:          filepath.Base(src),
						Type:          volType,
						SourcePath:    src,
						TargetPath:    tgt,
						StackID:       svc.StackID,
						StackName:     stackName,
						ServiceName:   svc.Name,
						NodeID:        "cluster",
						SizeBytes:     sizeBytes,
						SizeFormatted: FormatBytes(sizeBytes),
						IsShared:      isShared,
						LastScannedAt: time.Now(),
						CreatedAt:     time.Now(),
						UpdatedAt:     time.Now(),
					}
					volumes = append(volumes, sv)
				}
			}
		}
	}

	// 5. Scan standalone directories in /var/contenedores (Shared Pool)
	if info, err := os.Stat(DefaultSharedPoolPath); err == nil && info.IsDir() {
		entries, _ := os.ReadDir(DefaultSharedPoolPath)
		for _, e := range entries {
			if !e.IsDir() {
				continue
			}
			folderPath := filepath.Join(DefaultSharedPoolPath, e.Name())
			volKey := fmt.Sprintf("shared:%s", folderPath)
			if seenVolumes[volKey] {
				continue
			}
			seenVolumes[volKey] = true

			sizeBytes, _ := GetDirectorySize(folderPath)
			sv := db.StorageVolume{
				ID:            fmt.Sprintf("vol-pool-%s", e.Name()),
				Name:          e.Name(),
				Type:          "shared_pool",
				SourcePath:    folderPath,
				TargetPath:    folderPath,
				StackID:       "",
				StackName:     e.Name(),
				ServiceName:   "",
				NodeID:        "cluster",
				SizeBytes:     sizeBytes,
				SizeFormatted: FormatBytes(sizeBytes),
				IsShared:      true,
				LastScannedAt: time.Now(),
				CreatedAt:     time.Now(),
				UpdatedAt:     time.Now(),
			}
			volumes = append(volumes, sv)
		}
	}

	slog.Info("storage: discovered persistent & docker volumes", "count", len(volumes), "target_node", targetNode)
	return volumes, nil
}

// CreateDirectory creates a new storage directory on the specified target node(s) with given permissions.
func CreateDirectory(dirPath, permissions, targetNode string) error {
	dirPath = strings.TrimSpace(dirPath)
	if dirPath == "" {
		return fmt.Errorf("directory path cannot be empty")
	}
	if !strings.HasPrefix(dirPath, "/") {
		dirPath = "/" + dirPath
	}
	if permissions == "" {
		permissions = "0777"
	}

	ips := GetTargetHostIPs(targetNode)
	if len(ips) == 0 {
		ips = []string{"127.0.0.1"}
	}

	var errors []string
	for _, ip := range ips {
		if IsLocalHost(ip) {
			mode := os.FileMode(0777)
			if m, err := strconv.ParseUint(permissions, 8, 32); err == nil {
				mode = os.FileMode(m)
			}
			if err := os.MkdirAll(dirPath, mode); err != nil {
				errors = append(errors, fmt.Sprintf("%s: failed to mkdir: %v", ip, err))
				continue
			}
			_ = os.Chmod(dirPath, mode)
			slog.Info("created local directory", "path", dirPath, "perm", permissions)
		} else {
			script := fmt.Sprintf("sudo mkdir -p %s && sudo chmod %s %s", dirPath, permissions, dirPath)
			if out, err := ExecuteRemoteScript(ip, script); err != nil {
				errors = append(errors, fmt.Sprintf("%s: failed to mkdir: %v (%s)", ip, err, out))
			} else {
				slog.Info("created remote directory on worker", "node_ip", ip, "path", dirPath)
			}
		}
	}

	if len(errors) > 0 {
		return fmt.Errorf("directory creation failed on one or more hosts:\n%s", strings.Join(errors, "\n"))
	}
	return nil
}

// ListDirectoryEntries lists files and subdirectories within a given path on a specific node.
func ListDirectoryEntries(dirPath, targetNode string) ([]db.DirectoryEntry, error) {
	dirPath = strings.TrimSpace(dirPath)
	if dirPath == "" {
		dirPath = DefaultSharedPoolPath
	}

	ips := GetTargetHostIPs(targetNode)
	targetIP := "127.0.0.1"
	if len(ips) > 0 {
		targetIP = ips[0]
	}

	var entries []db.DirectoryEntry

	if IsLocalHost(targetIP) {
		info, err := os.Stat(dirPath)
		if err != nil {
			return nil, fmt.Errorf("path does not exist on local host: %w", err)
		}
		if !info.IsDir() {
			return nil, fmt.Errorf("path is not a directory")
		}

		dirEntries, err := os.ReadDir(dirPath)
		if err != nil {
			return nil, fmt.Errorf("failed to read directory: %w", err)
		}

		for _, de := range dirEntries {
			fInfo, _ := de.Info()
			var size int64
			var modTime time.Time
			perm := "rw-r--r--"
			if fInfo != nil {
				size = fInfo.Size()
				modTime = fInfo.ModTime()
				perm = fInfo.Mode().String()
			}
			fullPath := filepath.Join(dirPath, de.Name())
			if de.IsDir() {
				size, _ = GetDirectorySize(fullPath)
			}

			entries = append(entries, db.DirectoryEntry{
				Name:          de.Name(),
				Path:          fullPath,
				IsDir:         de.IsDir(),
				SizeBytes:     size,
				SizeFormatted: FormatBytes(size),
				Permissions:   perm,
				ModTime:       modTime,
				NodeID:        "node-local-manager",
			})
		}
		return entries, nil
	}

	// Remote execution on worker node
	script := fmt.Sprintf(`
if [ -d "%s" ]; then
	ls -la --time-style=+%%s "%s" 2>/dev/null || ls -la "%s"
else
	echo "__DIR_NOT_FOUND__"
fi
`, dirPath, dirPath, dirPath)

	out, err := ExecuteRemoteScript(targetIP, script)
	if err != nil {
		return nil, fmt.Errorf("failed to inspect directory on node %s: %w", targetIP, err)
	}

	if strings.Contains(out, "__DIR_NOT_FOUND__") {
		return nil, fmt.Errorf("directory %s does not exist on node %s", dirPath, targetIP)
	}

	lines := strings.Split(out, "\n")
	for _, l := range lines {
		l = strings.TrimSpace(l)
		if l == "" || strings.HasPrefix(l, "total ") {
			continue
		}
		fields := strings.Fields(l)
		if len(fields) < 7 {
			continue
		}
		name := fields[len(fields)-1]
		if name == "." || name == ".." {
			continue
		}
		perm := fields[0]
		isDir := strings.HasPrefix(perm, "d")
		size, _ := strconv.ParseInt(fields[4], 10, 64)

		entries = append(entries, db.DirectoryEntry{
			Name:          name,
			Path:          filepath.Join(dirPath, name),
			IsDir:         isDir,
			SizeBytes:     size,
			SizeFormatted: FormatBytes(size),
			Permissions:   perm,
			ModTime:       time.Now(),
			NodeID:        targetNode,
		})
	}

	return entries, nil
}
