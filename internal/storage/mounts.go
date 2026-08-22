package storage

import (
	"bufio"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/db"
)

// FstabPath returns the path to the system fstab file.
func FstabPath() string {
	if p := os.Getenv("GBNT_FSTAB_PATH"); p != "" {
		return p
	}
	if _, err := os.Stat("/host/etc/fstab"); err == nil {
		return "/host/etc/fstab"
	}
	if _, err := os.Stat("/etc/fstab"); err == nil {
		return "/etc/fstab"
	}
	home, _ := os.UserHomeDir()
	devPath := filepath.Join(home, ".gbnt", "fstab")
	_ = os.MkdirAll(filepath.Dir(devPath), 0755)
	if _, err := os.Stat(devPath); os.IsNotExist(err) {
		_ = os.WriteFile(devPath, []byte("# Gubernator local fstab emulation\n"), 0644)
	}
	return devPath
}

// CredentialsDir returns the secure directory where CIFS / S3 credential files are stored.
func CredentialsDir() string {
	if os.Geteuid() == 0 {
		return "/etc/gbnt/credentials"
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".gbnt", "credentials")
}

// CreateMountRequest defines parameters for adding a new network mount.
type CreateMountRequest struct {
	Name         string `json:"name"`
	Device       string `json:"device"`       // e.g. "192.168.1.50:/exports/contenedores", "//192.168.1.50/share", "s3fs#my-bucket"
	MountPoint   string `json:"mount_point"`  // e.g. "/var/contenedores", "/mnt/s3-models"
	FSType       string `json:"fs_type"`      // "nfs", "nfs4", "cifs", "fuse.s3fs", "rclone", "ext4", "glusterfs"
	Options      string `json:"options"`      // e.g. "rw,hard,intr,_netdev,rsize=1048576"
	Dump         int    `json:"dump"`
	Pass         int    `json:"pass"`
	TargetNode   string `json:"target_node"`  // "all" or specific Node ID
	AutoMount    bool   `json:"auto_mount"`
	Description  string `json:"description"`
	// Protocol-specific credentials
	Username     string `json:"username,omitempty"`
	Password     string `json:"password,omitempty"`
	Domain       string `json:"domain,omitempty"`
	S3Endpoint   string `json:"s3_endpoint,omitempty"`
	S3AccessKey  string `json:"s3_access_key,omitempty"`
	S3SecretKey  string `json:"s3_secret_key,omitempty"`
}

// TestMountResult holds diagnostics after testing a mount.
type TestMountResult struct {
	Success      bool   `json:"success"`
	LatencyMs    int64  `json:"latency_ms"`
	IsWritable   bool   `json:"is_writable"`
	TotalBytes   uint64 `json:"total_bytes"`
	FreeBytes    uint64 `json:"free_bytes"`
	ErrorMessage string `json:"error_message,omitempty"`
	Output       string `json:"output,omitempty"`
}

// ListStorageMounts retrieves all configured mounts and verifies live mount status.
func ListStorageMounts() ([]db.StorageMount, error) {
	var mounts []db.StorageMount
	if db.DB != nil {
		if err := db.DB.Order("created_at desc").Find(&mounts).Error; err != nil {
			return nil, err
		}
	}

	activeMounts := getActiveMountPoints()

	for i := range mounts {
		mp := filepath.Clean(mounts[i].MountPoint)
		if _, isMounted := activeMounts[mp]; isMounted {
			mounts[i].Status = "mounted"
		} else {
			if mounts[i].Status == "mounted" {
				mounts[i].Status = "unmounted"
			}
		}
	}

	return mounts, nil
}

// getActiveMountPoints parses /proc/mounts to find currently mounted target directories.
func getActiveMountPoints() map[string]string {
	active := make(map[string]string)
	f, err := os.Open("/proc/mounts")
	if err != nil {
		out, err := exec.Command("mount").Output()
		if err == nil {
			scanner := bufio.NewScanner(strings.NewReader(string(out)))
			for scanner.Scan() {
				fields := strings.Fields(scanner.Text())
				if len(fields) >= 3 && fields[1] == "on" {
					active[filepath.Clean(fields[2])] = fields[0]
				}
			}
		}
		return active
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) >= 2 {
			active[filepath.Clean(fields[1])] = fields[0]
		}
	}
	return active
}

// CreateStorageMount validates, writes fstab entry, and attempts live mounting.
func CreateStorageMount(req CreateMountRequest) (*db.StorageMount, error) {
	if req.Device == "" {
		return nil, fmt.Errorf("remote device/share cannot be empty")
	}
	if req.MountPoint == "" {
		req.MountPoint = DefaultSharedPoolPath
	}
	if req.Name == "" {
		req.Name = fmt.Sprintf("mount-%s", filepath.Base(req.MountPoint))
	}
	if req.FSType == "" {
		req.FSType = "nfs"
	}
	if req.TargetNode == "" {
		req.TargetNode = "all"
	}

	// Format options & handle credentials
	options := req.Options
	if options == "" {
		switch req.FSType {
		case "nfs", "nfs4":
			options = "rw,hard,intr,noatime,rsize=1048576,wsize=1048576,_netdev"
		case "cifs":
			options = "rw,_netdev,uid=1000,gid=1000"
		case "fuse.s3fs", "s3fs":
			options = "_netdev,allow_other,use_cache=/tmp,uid=1000,gid=1000"
		default:
			options = "defaults,_netdev"
		}
	}

	mountID := fmt.Sprintf("mnt-%d", time.Now().UnixNano()%100000000)
	var credPath string

	// Handle CIFS / Samba credentials file
	if req.FSType == "cifs" && req.Username != "" {
		credDir := CredentialsDir()
		_ = os.MkdirAll(credDir, 0700)
		credPath = filepath.Join(credDir, fmt.Sprintf("%s.cred", mountID))
		credContent := fmt.Sprintf("username=%s\npassword=%s\n", req.Username, req.Password)
		if req.Domain != "" {
			credContent += fmt.Sprintf("domain=%s\n", req.Domain)
		}
		if err := os.WriteFile(credPath, []byte(credContent), 0600); err != nil {
			slog.Warn("failed to write credentials file", "err", err)
		} else {
			options += fmt.Sprintf(",credentials=%s", credPath)
		}
	}

	// Handle S3 Credentials
	if (req.FSType == "fuse.s3fs" || req.FSType == "s3fs") && req.S3AccessKey != "" {
		credDir := CredentialsDir()
		_ = os.MkdirAll(credDir, 0700)
		credPath = filepath.Join(credDir, fmt.Sprintf("%s.passwd-s3fs", mountID))
		credContent := fmt.Sprintf("%s:%s\n", req.S3AccessKey, req.S3SecretKey)
		if err := os.WriteFile(credPath, []byte(credContent), 0600); err == nil {
			options += fmt.Sprintf(",passwd_file=%s", credPath)
			if req.S3Endpoint != "" {
				options += fmt.Sprintf(",url=%s", req.S3Endpoint)
			}
		}
	}

	// Ensure destination directory exists on host
	_ = os.MkdirAll(req.MountPoint, 0755)

	mountEntry := db.StorageMount{
		ID:              mountID,
		Name:            req.Name,
		Device:          req.Device,
		MountPoint:      req.MountPoint,
		FSType:          req.FSType,
		Options:         options,
		Dump:            req.Dump,
		Pass:            req.Pass,
		TargetNode:      req.TargetNode,
		CredentialsFile: credPath,
		AutoMount:       req.AutoMount,
		Status:          "unmounted",
		IsActive:        true,
		Description:     req.Description,
		CreatedAt:       time.Now(),
		UpdatedAt:       time.Now(),
	}

	// Apply mount across target node(s)
	ips := GetTargetHostIPs(req.TargetNode)
	var syncErrs []string
	for _, ip := range ips {
		if err := SyncMountToTargetNode(mountEntry, ip); err != nil {
			syncErrs = append(syncErrs, fmt.Sprintf("%s: %v", ip, err))
		}
	}

	if len(syncErrs) > 0 {
		mountEntry.Status = "error"
		if len(syncErrs) < len(ips) {
			mountEntry.Status = "degraded"
		}
		mountEntry.ErrorMessage = strings.Join(syncErrs, "; ")
	} else {
		mountEntry.Status = "mounted"
		mountEntry.ErrorMessage = ""
	}

	if db.DB != nil {
		if err := db.DB.Create(&mountEntry).Error; err != nil {
			return nil, fmt.Errorf("failed to save mount to database: %w", err)
		}
	}

	return &mountEntry, nil
}

// MountStorageEntry executes mount for a registered mount on target nodes.
func MountStorageEntry(id string, targetNodeOverride ...string) error {
	var m db.StorageMount
	if db.DB != nil {
		if err := db.DB.First(&m, "id = ?", id).Error; err != nil {
			return fmt.Errorf("mount not found: %w", err)
		}
	}

	target := m.TargetNode
	if len(targetNodeOverride) > 0 && targetNodeOverride[0] != "" {
		target = targetNodeOverride[0]
	}

	ips := GetTargetHostIPs(target)
	var errs []string
	for _, ip := range ips {
		if err := SyncMountToTargetNode(m, ip); err != nil {
			errs = append(errs, fmt.Sprintf("%s: %v", ip, err))
		}
	}

	if len(errs) > 0 {
		m.Status = "error"
		m.ErrorMessage = strings.Join(errs, "; ")
		if db.DB != nil {
			db.DB.Save(&m)
		}
		return fmt.Errorf("mount failed on some hosts: %s", strings.Join(errs, "; "))
	}

	m.Status = "mounted"
	m.ErrorMessage = ""
	if db.DB != nil {
		db.DB.Save(&m)
	}
	return nil
}

// UnmountStorageEntry executes umount for a registered mount on target nodes.
func UnmountStorageEntry(id string, targetNodeOverride ...string) error {
	var m db.StorageMount
	if db.DB != nil {
		if err := db.DB.First(&m, "id = ?", id).Error; err != nil {
			return fmt.Errorf("mount not found: %w", err)
		}
	}

	target := m.TargetNode
	if len(targetNodeOverride) > 0 && targetNodeOverride[0] != "" {
		target = targetNodeOverride[0]
	}

	ips := GetTargetHostIPs(target)
	for _, ip := range ips {
		_ = UnmountFromTargetNode(m.MountPoint, ip)
	}

	m.Status = "unmounted"
	m.ErrorMessage = ""
	if db.DB != nil {
		db.DB.Save(&m)
	}
	return nil
}

// DeleteStorageMount unmounts, removes fstab entry, and deletes from DB on target nodes.
func DeleteStorageMount(id string) error {
	var m db.StorageMount
	if db.DB != nil {
		if err := db.DB.First(&m, "id = ?", id).Error; err != nil {
			return fmt.Errorf("mount not found: %w", err)
		}
	}

	ips := GetTargetHostIPs(m.TargetNode)
	for _, ip := range ips {
		_ = DeleteMountFromTargetNode(m, ip)
	}

	if db.DB != nil {
		return db.DB.Delete(&m).Error
	}
	return nil
}

// MountAllStorageEntries executes `mount -a` across target nodes.
func MountAllStorageEntries(targetNode ...string) (string, error) {
	target := "all"
	if len(targetNode) > 0 && targetNode[0] != "" {
		target = targetNode[0]
	}

	ips := GetTargetHostIPs(target)
	var combinedOutput []string
	var errs []string
	for _, ip := range ips {
		out, err := MountAllOnTargetNode(ip)
		if err != nil {
			errs = append(errs, fmt.Sprintf("[%s error]: %v (%s)", ip, err, out))
		}
		if out != "" {
			combinedOutput = append(combinedOutput, fmt.Sprintf("[%s]: %s", ip, out))
		} else {
			combinedOutput = append(combinedOutput, fmt.Sprintf("[%s]: OK", ip))
		}
	}

	resultStr := strings.Join(combinedOutput, "\n")
	if len(errs) > 0 {
		return resultStr, fmt.Errorf("mount -a had errors on some nodes: %s", strings.Join(errs, "; "))
	}
	return resultStr, nil
}

// TestMountConnection tests a mount in a temporary directory and validates R/W permissions.
func TestMountConnection(req CreateMountRequest) TestMountResult {
	start := time.Now()
	res := TestMountResult{Success: false}

	tempDir := filepath.Join(os.TempDir(), fmt.Sprintf("gbnt-test-mount-%d", time.Now().UnixNano()))
	if err := os.MkdirAll(tempDir, 0755); err != nil {
		res.ErrorMessage = fmt.Sprintf("failed to create temp dir: %v", err)
		return res
	}
	defer func() {
		_ = exec.Command("umount", "-l", tempDir).Run()
		_ = os.RemoveAll(tempDir)
	}()

	options := req.Options
	if options == "" {
		options = "rw,_netdev"
	}

	// Format mount command
	var cmd *exec.Cmd
	if req.FSType == "nfs" || req.FSType == "nfs4" {
		cmd = exec.Command("mount", "-t", req.FSType, "-o", options, req.Device, tempDir)
	} else if req.FSType == "cifs" {
		if req.Username != "" {
			options += fmt.Sprintf(",username=%s,password=%s", req.Username, req.Password)
			if req.Domain != "" {
				options += fmt.Sprintf(",domain=%s", req.Domain)
			}
		}
		cmd = exec.Command("mount", "-t", "cifs", "-o", options, req.Device, tempDir)
	} else {
		cmd = exec.Command("mount", "-t", req.FSType, "-o", options, req.Device, tempDir)
	}

	out, err := cmd.CombinedOutput()
	res.LatencyMs = time.Since(start).Milliseconds()
	res.Output = strings.TrimSpace(string(out))

	if err != nil {
		res.ErrorMessage = fmt.Sprintf("mount test failed: %v (%s)", err, res.Output)
		return res
	}

	res.Success = true

	// Test write access
	probeFile := filepath.Join(tempDir, fmt.Sprintf(".gbnt-rw-probe-%d.tmp", time.Now().UnixNano()))
	if err := os.WriteFile(probeFile, []byte("gubernator-ok"), 0644); err == nil {
		res.IsWritable = true
		_ = os.Remove(probeFile)
	} else {
		res.IsWritable = false
	}

	// Query disk space
	if total, free, err := getDiskSpace(tempDir); err == nil {
		res.TotalBytes = total
		res.FreeBytes = free
	}

	return res
}

// GetRawFstab returns the current content of the fstab file.
func GetRawFstab() (string, error) {
	data, err := os.ReadFile(FstabPath())
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// appendFstabEntry appends a managed entry to /etc/fstab with backup.
func appendFstabEntry(m db.StorageMount) error {
	path := FstabPath()
	data, err := os.ReadFile(path)
	if err != nil && !os.IsNotExist(err) {
		return err
	}

	// Create backup
	if len(data) > 0 {
		backupPath := fmt.Sprintf("%s.bak.%d", path, time.Now().Unix())
		_ = os.WriteFile(backupPath, data, 0644)
	}

	content := string(data)
	tagStart := fmt.Sprintf("# BEGIN GBNT MOUNT %s", m.ID)
	tagEnd := fmt.Sprintf("# END GBNT MOUNT %s", m.ID)

	line := fmt.Sprintf("%s\t%s\t%s\t%s\t%d\t%d", m.Device, m.MountPoint, m.FSType, m.Options, m.Dump, m.Pass)
	block := fmt.Sprintf("\n%s (%s)\n%s\n%s\n", tagStart, m.Name, line, tagEnd)

	// Check if block exists and replace, else append
	if strings.Contains(content, tagStart) {
		startIdx := strings.Index(content, tagStart)
		endIdx := strings.Index(content, tagEnd)
		if startIdx != -1 && endIdx != -1 {
			endIdx += len(tagEnd)
			content = content[:startIdx] + block + content[endIdx:]
			return os.WriteFile(path, []byte(content), 0644)
		}
	}

	content = strings.TrimRight(content, "\n") + "\n" + block
	return os.WriteFile(path, []byte(content), 0644)
}

// removeFstabEntry removes a marked entry from /etc/fstab.
func removeFstabEntry(id string) error {
	path := FstabPath()
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}

	content := string(data)
	tagStart := fmt.Sprintf("# BEGIN GBNT MOUNT %s", id)
	tagEnd := fmt.Sprintf("# END GBNT MOUNT %s", id)

	startIdx := strings.Index(content, tagStart)
	endIdx := strings.Index(content, tagEnd)
	if startIdx != -1 && endIdx != -1 {
		endIdx += len(tagEnd)
		// Clean up line
		content = content[:startIdx] + content[endIdx:]
		content = strings.TrimSpace(content) + "\n"
		return os.WriteFile(path, []byte(content), 0644)
	}

	return nil
}
