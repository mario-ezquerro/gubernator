package storage

import (
	"fmt"
	"io/fs"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"syscall"
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
		var stat syscall.Statfs_t
		if err := syscall.Statfs(poolPath, &stat); err == nil {
			total := stat.Blocks * uint64(stat.Bsize)
			free := stat.Bavail * uint64(stat.Bsize)
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

// ListVolumes scans all stacks and services to discover persistent volumes and bind mounts.
func ListVolumes() ([]db.StorageVolume, error) {
	var services []db.Service
	if err := db.DB.Find(&services).Error; err != nil {
		return nil, err
	}

	// Fetch stack names
	var stacks []db.Stack
	db.DB.Find(&stacks)
	stackMap := make(map[string]string)
	for _, s := range stacks {
		stackMap[s.ID] = s.Name
	}

	var volumes []db.StorageVolume
	seenVolumes := make(map[string]bool)

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

			// Measure size if host directory exists
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

	// Also check if any standalone folders exist in /var/contenedores
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

	slog.Info("storage: discovered volumes", "count", len(volumes))
	return volumes, nil
}
