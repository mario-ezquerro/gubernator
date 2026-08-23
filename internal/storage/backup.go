package storage

import (
	"archive/tar"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

// CreateBackupRequest defines the parameters for creating a new backup.
type CreateBackupRequest struct {
	Name            string `json:"name"`
	StackID         string `json:"stack_id"`
	VolumeName      string `json:"volume_name"`
	SourcePath      string `json:"source_path"`
	DestinationPath string `json:"destination_path"`
	PauseContainers bool   `json:"pause_containers"`
	IsScheduled     bool   `json:"is_scheduled"`
	ScheduleID      string `json:"schedule_id"`
}

// RestoreBackupRequest defines the parameters for restoring an existing backup.
type RestoreBackupRequest struct {
	BackupID   string `json:"backup_id"`
	TargetPath string `json:"target_path"` // If empty, restores over the original SourcePath
}

// ListBackups returns all backup records from the database.
func ListBackups() ([]db.Backup, error) {
	var backups []db.Backup
	if err := db.DB.Order("created_at desc").Find(&backups).Error; err != nil {
		return nil, err
	}
	for i := range backups {
		backups[i].SizeFormatted = FormatBytes(backups[i].SizeBytes)
	}
	return backups, nil
}

// CreateBackup creates a point-in-time compressed tar.gz archive of the specified path.
func CreateBackup(req CreateBackupRequest) (*db.Backup, error) {
	if err := EnsureBackupDir(); err != nil {
		return nil, fmt.Errorf("failed to ensure backup directory: %w", err)
	}

	// Resolve stack name
	stackName := req.StackID
	if req.StackID != "" {
		var stack db.Stack
		if err := db.DB.First(&stack, "id = ?", req.StackID).Error; err == nil && stack.Name != "" {
			stackName = stack.Name
		}
	}

	// Determine source path if only VolumeName or StackID was passed
	sourcePath := req.SourcePath
	if sourcePath == "" {
		if req.VolumeName != "" {
			if strings.HasPrefix(req.VolumeName, "/") {
				sourcePath = req.VolumeName
			} else {
				sharedPath := filepath.Join(DefaultSharedPoolPath, req.VolumeName)
				if info, err := os.Stat(sharedPath); err == nil && info.IsDir() {
					sourcePath = sharedPath
				} else {
					dockerVolPath := fmt.Sprintf("/var/lib/docker/volumes/%s/_data", req.VolumeName)
					if info, err := os.Stat(dockerVolPath); err == nil && info.IsDir() {
						sourcePath = dockerVolPath
					} else {
						sourcePath = sharedPath
					}
				}
			}
		} else if stackName != "" {
			if strings.HasPrefix(stackName, "/") {
				sourcePath = stackName
			} else {
				sourcePath = filepath.Join(DefaultSharedPoolPath, stackName)
			}
		} else {
			return nil, fmt.Errorf("source_path or stack_id must be specified")
		}
	}

	if _, err := os.Stat(sourcePath); os.IsNotExist(err) {
		if strings.HasPrefix(sourcePath, DefaultSharedPoolPath) {
			_ = EnsureDirectoryLocal(sourcePath, "0777")
		}
		if _, err2 := os.Stat(sourcePath); os.IsNotExist(err2) {
			return nil, fmt.Errorf("source path does not exist on disk: %s", sourcePath)
		}
	}

	// Determine target destination directory
	destDir := strings.TrimSpace(req.DestinationPath)
	if destDir == "" {
		destDir = BackupDir()
	}
	if err := EnsureDirectoryLocal(destDir, "0777"); err != nil {
		// If custom or /var/backups/gbnt fails even with sudo, fallback to BackupDir()
		fallbackDir := BackupDir()
		if fallbackDir != destDir {
			slog.Warn("storage: failed to create requested destDir, falling back to BackupDir", "destDir", destDir, "fallbackDir", fallbackDir, "err", err)
			if err2 := EnsureDirectoryLocal(fallbackDir, "0777"); err2 == nil {
				destDir = fallbackDir
			} else {
				return nil, fmt.Errorf("failed to create destination directory %s: %w", destDir, err)
			}
		} else {
			return nil, fmt.Errorf("failed to create destination directory %s: %w", destDir, err)
		}
	}

	// Generate filename and destination path
	backupID := uuid.New().String()
	timestamp := time.Now().Format("20060102-150405")
	cleanName := strings.ReplaceAll(strings.ToLower(req.Name), " ", "-")
	if cleanName == "" {
		cleanName = fmt.Sprintf("backup-%s-%s", filepath.Base(sourcePath), timestamp)
	}
	fileName := fmt.Sprintf("%s.tar.gz", cleanName)
	destFilePath := filepath.Join(destDir, fileName)

	// Collect containers associated with the stack to pause if requested
	var pausedContainerIDs []string
	if req.PauseContainers && req.StackID != "" {
		var services []db.Service
		db.DB.Where("stack_id = ?", req.StackID).Find(&services)
		var svcIDs []string
		for _, s := range services {
			svcIDs = append(svcIDs, s.ID)
		}
		if len(svcIDs) > 0 {
			var tasks []db.Task
			db.DB.Where("service_id IN ? AND status = ?", svcIDs, "running").Find(&tasks)
			for _, t := range tasks {
				target := t.ContainerName
				if target == "" {
					target = t.ID
				}
				if target != "" {
					slog.Info("backup: pausing container for consistency", "container", target)
					if err := exec.Command("docker", "pause", target).Run(); err == nil {
						pausedContainerIDs = append(pausedContainerIDs, target)
					}
				}
			}
		}
	}

	// Ensure unpausing containers on return
	defer func() {
		for _, cid := range pausedContainerIDs {
			slog.Info("backup: unpausing container", "container_id", cid)
			_ = exec.Command("docker", "unpause", cid).Run()
		}
	}()

	// Create tar.gz file
	outFile, err := os.Create(destFilePath)
	if err != nil {
		return nil, fmt.Errorf("failed to create backup file: %w", err)
	}
	defer outFile.Close()

	hasher := sha256.New()
	multiWriter := io.MultiWriter(outFile, hasher)

	gw := gzip.NewWriter(multiWriter)
	tw := tar.NewWriter(gw)

	// Walk source directory and add files to tar.gz
	err = filepath.Walk(sourcePath, func(path string, info os.FileInfo, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}

		relPath, err := filepath.Rel(sourcePath, path)
		if err != nil {
			return err
		}
		if relPath == "." {
			return nil
		}

		header, err := tar.FileInfoHeader(info, info.Name())
		if err != nil {
			return err
		}

		header.Name = filepath.ToSlash(relPath)
		if info.IsDir() {
			header.Name += "/"
		}

		if err := tw.WriteHeader(header); err != nil {
			return err
		}

		if info.Mode().IsRegular() {
			f, err := os.Open(path)
			if err != nil {
				return err
			}
			defer f.Close()

			if _, err := io.Copy(tw, f); err != nil {
				return err
			}
		}

		return nil
	})

	if err != nil {
		tw.Close()
		gw.Close()
		os.Remove(destFilePath)
		return nil, fmt.Errorf("failed during tar compression: %w", err)
	}

	if err := tw.Close(); err != nil {
		os.Remove(destFilePath)
		return nil, fmt.Errorf("failed to close tar writer: %w", err)
	}
	if err := gw.Close(); err != nil {
		os.Remove(destFilePath)
		return nil, fmt.Errorf("failed to close gzip writer: %w", err)
	}

	// Calculate final file stats
	fileInfo, err := os.Stat(destFilePath)
	if err != nil {
		return nil, fmt.Errorf("failed to stat created backup file: %w", err)
	}

	sizeBytes := fileInfo.Size()
	sha256Hex := hex.EncodeToString(hasher.Sum(nil))
	now := time.Now()

	bRecord := db.Backup{
		ID:            backupID,
		Name:          cleanName,
		StackID:       req.StackID,
		StackName:     stackName,
		VolumeName:    req.VolumeName,
		SourcePath:    sourcePath,
		FilePath:      destFilePath,
		SizeBytes:     sizeBytes,
		SizeFormatted: FormatBytes(sizeBytes),
		SHA256:        sha256Hex,
		Status:        "completed",
		IsScheduled:   req.IsScheduled,
		ScheduleID:    req.ScheduleID,
		CreatedAt:     now,
		CompletedAt:   &now,
	}

	if err := db.DB.Create(&bRecord).Error; err != nil {
		slog.Error("failed to save backup record in DB", "err", err)
		return nil, err
	}

	slog.Info("backup: successfully created archive", "name", bRecord.Name, "size", bRecord.SizeFormatted, "sha256", sha256Hex)
	return &bRecord, nil
}

// RestoreBackup unpacks a backup tar.gz archive into the target destination directory.
func RestoreBackup(req RestoreBackupRequest) error {
	var b db.Backup
	if err := db.DB.First(&b, "id = ?", req.BackupID).Error; err != nil {
		return fmt.Errorf("backup not found: %w", err)
	}

	if _, err := os.Stat(b.FilePath); os.IsNotExist(err) {
		return fmt.Errorf("backup file not found on disk: %s", b.FilePath)
	}

	targetPath := req.TargetPath
	if targetPath == "" {
		targetPath = b.SourcePath
	}
	if targetPath == "" {
		return fmt.Errorf("target_path is required for restoration")
	}

	if err := EnsureDirectoryLocal(targetPath, "0777"); err != nil {
		return fmt.Errorf("failed to create target directory %s: %w", targetPath, err)
	}

	file, err := os.Open(b.FilePath)
	if err != nil {
		return fmt.Errorf("failed to open backup archive: %w", err)
	}
	defer file.Close()

	gr, err := gzip.NewReader(file)
	if err != nil {
		return fmt.Errorf("failed to create gzip reader: %w", err)
	}
	defer gr.Close()

	tr := tar.NewReader(gr)

	for {
		header, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("failed to read tar header: %w", err)
		}

		// Security: prevent zip-slip attacks
		cleanHeaderName := filepath.Clean(header.Name)
		if strings.HasPrefix(cleanHeaderName, "..") || strings.HasPrefix(cleanHeaderName, "/") {
			continue
		}

		destPath := filepath.Join(targetPath, cleanHeaderName)

		switch header.Typeflag {
		case tar.TypeDir:
			if err := EnsureDirectoryLocal(destPath, "0777"); err != nil {
				return err
			}
		case tar.TypeReg:
			if err := EnsureDirectoryLocal(filepath.Dir(destPath), "0777"); err != nil {
				return err
			}
			outFile, err := os.OpenFile(destPath, os.O_CREATE|os.O_RDWR|os.O_TRUNC, header.FileInfo().Mode())
			if err != nil {
				return err
			}
			if _, err := io.Copy(outFile, tr); err != nil {
				outFile.Close()
				return err
			}
			outFile.Close()
		}
	}

	slog.Info("backup: successfully restored archive", "backup_id", b.ID, "target_path", targetPath)
	return nil
}

// DeleteBackup deletes a backup archive from disk and removes its record from the database.
func DeleteBackup(backupID string) error {
	var b db.Backup
	if err := db.DB.First(&b, "id = ?", backupID).Error; err != nil {
		return fmt.Errorf("backup not found: %w", err)
	}

	if b.FilePath != "" {
		_ = os.Remove(b.FilePath)
	}

	return db.DB.Delete(&b).Error
}

// PruneRetainedBackups removes older backups for a schedule exceeding the retention count limit.
func PruneRetainedBackups(scheduleID string, retentionCount int) error {
	if retentionCount <= 0 {
		return nil
	}

	var backups []db.Backup
	if err := db.DB.Where("schedule_id = ?", scheduleID).Order("created_at desc").Find(&backups).Error; err != nil {
		return err
	}

	if len(backups) > retentionCount {
		toDelete := backups[retentionCount:]
		for _, b := range toDelete {
			slog.Info("backup: pruning old backup for retention policy", "name", b.Name, "id", b.ID)
			_ = DeleteBackup(b.ID)
		}
	}
	return nil
}
