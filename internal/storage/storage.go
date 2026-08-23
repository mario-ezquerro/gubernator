package storage

import (
	"encoding/json"
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

	// 1. Fetch stack and node mapping from DB
	stackMap := make(map[string]string)
	nodeMap := make(map[string]db.Node)
	managerIP := db.GetManagerIP()
	if managerIP == "" {
		managerIP = "127.0.0.1"
	}
	managerHostname := "Manager"
	if h, err := os.Hostname(); err == nil && h != "" {
		managerHostname = h
	}

	if db.DB != nil {
		var stacks []db.Stack
		db.DB.Find(&stacks)
		for _, s := range stacks {
			stackMap[s.ID] = s.Name
		}
		var allNodes []db.Node
		db.DB.Find(&allNodes)
		for _, n := range allNodes {
			nodeMap[n.ID] = n
			nodeMap[n.IP] = n
		}
	}

	// 2. Discover Docker Named Volumes locally on Manager host
	if targetNode == "" || targetNode == "all" || targetNode == "cluster" || targetNode == "node-local-manager" || targetNode == "manager" || targetNode == "127.0.0.1" || targetNode == managerIP {
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
				driver := parts[1]
				if driver == "" {
					driver = "local"
				}
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
					Driver:        driver,
					SourcePath:    mountpoint,
					TargetPath:    mountpoint,
					StackID:       "",
					StackName:     "Docker Engine",
					ServiceName:   "",
					NodeID:        "node-local-manager",
					NodeIP:        managerIP,
					NodeHostname:  managerHostname,
					NodeRole:      "MANAGER",
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
			workerHostname := strings.TrimPrefix(w.ID, "node-")
			if targetNode != "" && targetNode != "all" && targetNode != "cluster" && targetNode != w.ID && targetNode != w.IP && targetNode != strings.ToLower(workerHostname) {
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
					driver := parts[1]
					if driver == "" {
						driver = "local"
					}
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
						Driver:        driver,
						SourcePath:    mountpoint,
						TargetPath:    mountpoint,
						StackID:       "",
						StackName:     fmt.Sprintf("Docker Engine (%s)", workerHostname),
						ServiceName:   "",
						NodeID:        w.ID,
						NodeIP:        w.IP,
						NodeHostname:  workerHostname,
						NodeRole:      "WORKER",
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
					nodeRole := "CLUSTER"
					nodeHost := "All Centurions"
					nodeIP := "cluster"

					if strings.HasPrefix(src, DefaultSharedPoolPath) || strings.HasPrefix(src, "/var/contenedores") {
						volType = "shared_pool"
						isShared = true
						nodeHost = "All Centurions (Shared Mesh)"
						nodeIP = "/var/contenedores"
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
						Driver:        "local",
						SourcePath:    src,
						TargetPath:    tgt,
						StackID:       svc.StackID,
						StackName:     stackName,
						ServiceName:   svc.Name,
						NodeID:        "cluster",
						NodeIP:        nodeIP,
						NodeHostname:  nodeHost,
						NodeRole:      nodeRole,
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
				Driver:        "glusterfs/shared",
				SourcePath:    folderPath,
				TargetPath:    folderPath,
				StackID:       "",
				StackName:     e.Name(),
				ServiceName:   "",
				NodeID:        "cluster",
				NodeIP:        "/var/contenedores",
				NodeHostname:  "All Centurions (Shared Mesh)",
				NodeRole:      "CLUSTER",
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

	// 6. Scan all registered StoragePool records from database
	if db.DB != nil {
		var pools []db.StoragePool
		db.DB.Find(&pools)
		for _, p := range pools {
			volKey := fmt.Sprintf("pool:%s", p.Path)
			if seenVolumes[volKey] {
				continue
			}
			seenVolumes[volKey] = true

			var sizeBytes int64
			if info, err := os.Stat(p.Path); err == nil && info.IsDir() {
				sizeBytes, _ = GetDirectorySize(p.Path)
			}
			sv := db.StorageVolume{
				ID:            fmt.Sprintf("vol-pool-%s", p.ID),
				Name:          p.Name,
				Type:          "shared_pool",
				Driver:        p.FSType,
				SourcePath:    p.Path,
				TargetPath:    p.Path,
				StackID:       "",
				StackName:     p.Name,
				ServiceName:   "",
				NodeID:        "cluster",
				NodeIP:        p.Path,
				NodeHostname:  "All Centurions (Shared Mesh)",
				NodeRole:      "CLUSTER",
				SizeBytes:     sizeBytes,
				SizeFormatted: FormatBytes(sizeBytes),
				IsShared:      true,
				LastScannedAt: time.Now(),
				CreatedAt:     p.CreatedAt,
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

	// Persist created directory to db.StoragePool so it permanently appears in discovery
	if db.DB != nil {
		poolName := filepath.Base(dirPath)
		var existing db.StoragePool
		if err := db.DB.First(&existing, "path = ?", dirPath).Error; err != nil {
			newPool := db.StoragePool{
				ID:        fmt.Sprintf("pool-%d", time.Now().UnixNano()),
				Name:      poolName,
				Path:      dirPath,
				FSType:    "posix",
				IsActive:  true,
				CreatedAt: time.Now(),
				UpdatedAt: time.Now(),
			}
			db.DB.Create(&newPool)
			slog.Info("storage: persisted new storage pool to database", "path", dirPath, "name", poolName)
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

	// Special handling for Docker Named Volumes paths (/var/lib/docker/volumes/<vol>/_data)
	if strings.HasPrefix(dirPath, "/var/lib/docker/volumes/") {
		parts := strings.Split(strings.TrimPrefix(dirPath, "/var/lib/docker/volumes/"), "/")
		if len(parts) > 0 && parts[0] != "" {
			volName := parts[0]
			subPath := ""
			if len(parts) > 1 && parts[1] == "_data" {
				subPath = strings.Join(parts[2:], "/")
			}
			volTarget := "/__vol_target"
			if subPath != "" {
				volTarget = fmt.Sprintf("/__vol_target/%s", subPath)
			}
			var out []byte
			var cmdErr error
			if IsLocalHost(targetIP) {
				cmd := exec.Command("docker", "run", "--rm", "-v", fmt.Sprintf("%s:/__vol_target:ro", volName), "alpine", "ls", "-la", volTarget)
				out, cmdErr = cmd.CombinedOutput()
			} else {
				remoteScript := fmt.Sprintf("sudo docker run --rm -v %s:/__vol_target:ro alpine ls -la %s", volName, volTarget)
				remoteOut, err := ExecuteRemoteScript(targetIP, remoteScript)
				out = []byte(remoteOut)
				cmdErr = err
			}
			if cmdErr == nil {
				lines := strings.Split(string(out), "\n")
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
		}
	}

	if IsLocalHost(targetIP) {
		info, err := os.Stat(dirPath)
		if err != nil {
			return nil, fmt.Errorf("path does not exist on local host: %w", err)
		}
		if !info.IsDir() {
			return nil, fmt.Errorf("path is not a directory")
		}

		dirEntries, err := os.ReadDir(dirPath)
		if err == nil {
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

		// Sudo fallback for protected paths (like /var/lib/docker/volumes)
		cmd := exec.Command("sudo", "ls", "-la", dirPath)
		out, cmdErr := cmd.CombinedOutput()
		if cmdErr != nil {
			return nil, fmt.Errorf("failed to read directory: %w", err)
		}
		lines := strings.Split(string(out), "\n")
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

// CreateDockerVolumeRequest represents the payload to create a new Docker volume.
type CreateDockerVolumeRequest struct {
	Name       string            `json:"name" binding:"required"`
	Driver     string            `json:"driver"`
	TargetNode string            `json:"target_node"`
	Labels     map[string]string `json:"labels"`
	DriverOpts map[string]string `json:"driver_opts"`
}

// CreateDockerVolume creates a Docker volume across all nodes or on a specific target host.
func CreateDockerVolume(req CreateDockerVolumeRequest) ([]string, error) {
	name := strings.TrimSpace(req.Name)
	if name == "" {
		return nil, fmt.Errorf("volume name is required")
	}

	driver := strings.TrimSpace(req.Driver)
	if driver == "" {
		driver = "local"
	}

	var cmdArgs []string
	cmdArgs = append(cmdArgs, "volume", "create", name)
	if driver != "" && driver != "local" {
		cmdArgs = append(cmdArgs, "--driver", driver)
	}
	for k, v := range req.DriverOpts {
		if k != "" {
			cmdArgs = append(cmdArgs, "--opt", fmt.Sprintf("%s=%s", k, v))
		}
	}
	for k, v := range req.Labels {
		if k != "" {
			cmdArgs = append(cmdArgs, "--label", fmt.Sprintf("%s=%s", k, v))
		}
	}

	ips := GetTargetHostIPs(req.TargetNode)
	if len(ips) == 0 {
		ips = []string{"127.0.0.1"}
	}

	var successfulNodes []string
	var errs []string

	for _, ip := range ips {
		if IsLocalHost(ip) {
			cmd := exec.Command("docker", cmdArgs...)
			out, err := cmd.CombinedOutput()
			if err != nil {
				errs = append(errs, fmt.Sprintf("manager (%s): %s", ip, strings.TrimSpace(string(out))))
			} else {
				successfulNodes = append(successfulNodes, fmt.Sprintf("Manager (%s)", ip))
				slog.Info("created docker volume locally", "name", name, "driver", driver)
			}
		} else {
			remoteCmd := fmt.Sprintf("sudo docker %s", strings.Join(cmdArgs, " "))
			out, err := ExecuteRemoteScript(ip, remoteCmd)
			if err != nil {
				errs = append(errs, fmt.Sprintf("worker (%s): %s", ip, out))
			} else {
				successfulNodes = append(successfulNodes, fmt.Sprintf("Centurion (%s)", ip))
				slog.Info("created docker volume remotely", "name", name, "ip", ip)
			}
		}
	}

	if len(successfulNodes) == 0 && len(errs) > 0 {
		return nil, fmt.Errorf("failed to create volume: %s", strings.Join(errs, "; "))
	}

	return successfulNodes, nil
}

// DeleteDockerVolume removes a Docker volume from the specified target node(s).
func DeleteDockerVolume(name, targetNode string, force bool) ([]string, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return nil, fmt.Errorf("volume name is required")
	}

	ips := GetTargetHostIPs(targetNode)
	if len(ips) == 0 {
		ips = []string{"127.0.0.1"}
	}

	var successfulNodes []string
	var errs []string

	for _, ip := range ips {
		if IsLocalHost(ip) {
			args := []string{"volume", "rm"}
			if force {
				args = append(args, "-f")
			}
			args = append(args, name)
			cmd := exec.Command("docker", args...)
			out, err := cmd.CombinedOutput()
			if err != nil {
				errs = append(errs, fmt.Sprintf("manager (%s): %s", ip, strings.TrimSpace(string(out))))
			} else {
				successfulNodes = append(successfulNodes, fmt.Sprintf("Manager (%s)", ip))
				slog.Info("deleted docker volume locally", "name", name)
			}
		} else {
			fFlag := ""
			if force {
				fFlag = "-f "
			}
			remoteCmd := fmt.Sprintf("sudo docker volume rm %s%s", fFlag, name)
			out, err := ExecuteRemoteScript(ip, remoteCmd)
			if err != nil {
				errs = append(errs, fmt.Sprintf("worker (%s): %s", ip, out))
			} else {
				successfulNodes = append(successfulNodes, fmt.Sprintf("Centurion (%s)", ip))
				slog.Info("deleted docker volume remotely", "name", name, "ip", ip)
			}
		}
	}

	if len(successfulNodes) == 0 && len(errs) > 0 {
		return nil, fmt.Errorf("failed to delete volume: %s", strings.Join(errs, "; "))
	}

	return successfulNodes, nil
}

// PruneDockerVolumes purges unused/dangling Docker volumes on specified target node(s).
func PruneDockerVolumes(targetNode string) (string, error) {
	ips := GetTargetHostIPs(targetNode)
	if len(ips) == 0 {
		ips = []string{"127.0.0.1"}
	}

	var summaries []string
	var errs []string

	for _, ip := range ips {
		if IsLocalHost(ip) {
			cmd := exec.Command("docker", "volume", "prune", "-f")
			out, err := cmd.CombinedOutput()
			trimmed := strings.TrimSpace(string(out))
			if err != nil {
				errs = append(errs, fmt.Sprintf("manager (%s): %s", ip, trimmed))
			} else {
				summaries = append(summaries, fmt.Sprintf("Manager (%s): %s", ip, trimmed))
				slog.Info("pruned docker volumes locally", "ip", ip)
			}
		} else {
			remoteCmd := "sudo docker volume prune -f"
			out, err := ExecuteRemoteScript(ip, remoteCmd)
			if err != nil {
				errs = append(errs, fmt.Sprintf("worker (%s): %s", ip, out))
			} else {
				summaries = append(summaries, fmt.Sprintf("Centurion (%s): %s", ip, out))
				slog.Info("pruned docker volumes remotely", "ip", ip)
			}
		}
	}

	if len(summaries) == 0 && len(errs) > 0 {
		return "", fmt.Errorf("failed to prune volumes: %s", strings.Join(errs, "; "))
	}

	return strings.Join(summaries, "\n\n"), nil
}

// InspectDockerVolume returns detailed metadata for a Docker volume from the specified host.
func InspectDockerVolume(name, targetNode string) (map[string]interface{}, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return nil, fmt.Errorf("volume name is required")
	}

	ips := GetTargetHostIPs(targetNode)
	targetIP := "127.0.0.1"
	if len(ips) > 0 {
		targetIP = ips[0]
	}

	var rawJSON string
	if IsLocalHost(targetIP) {
		cmd := exec.Command("docker", "volume", "inspect", name)
		out, err := cmd.CombinedOutput()
		if err != nil {
			return nil, fmt.Errorf("volume %s not found on manager: %s", name, strings.TrimSpace(string(out)))
		}
		rawJSON = string(out)
	} else {
		remoteCmd := fmt.Sprintf("sudo docker volume inspect %s", name)
		out, err := ExecuteRemoteScript(targetIP, remoteCmd)
		if err != nil {
			return nil, fmt.Errorf("volume %s not found on node %s: %s", name, targetIP, out)
		}
		rawJSON = out
	}

	var list []map[string]interface{}
	if err := json.Unmarshal([]byte(rawJSON), &list); err != nil || len(list) == 0 {
		// Fallback single object
		var single map[string]interface{}
		if err2 := json.Unmarshal([]byte(rawJSON), &single); err2 == nil {
			return single, nil
		}
		return nil, fmt.Errorf("failed to parse volume inspect output: %v", err)
	}

	return list[0], nil
}
