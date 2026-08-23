package storage

import (
	"log/slog"
	"strings"
	"sync"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/robfig/cron/v3"
)

var (
	cronRunner *cron.Cron
	cronMutex  sync.Mutex
)

// StartBackupScheduler starts the background cron engine for automated backup policies.
func StartBackupScheduler() {
	// Initial sync of all enabled schedules
	SyncSchedules()

	// Periodically sync schedules every 5 minutes to detect newly added or edited policies
	go func() {
		ticker := time.NewTicker(5 * time.Minute)
		for range ticker.C {
			SyncSchedules()
		}
	}()

	slog.Info("storage: backup scheduler daemon started")
}

// SyncSchedules reads all enabled BackupSchedule records from SQLite and registers their cron jobs.
func SyncSchedules() {
	cronMutex.Lock()
	defer cronMutex.Unlock()

	if cronRunner == nil {
		return
	}

	// Stop and recreate runner to cleanly refresh entries
	cronRunner.Stop()
	cronRunner = cron.New()

	var schedules []db.BackupSchedule
	if err := db.DB.Where("enabled = ?", true).Find(&schedules).Error; err != nil {
		slog.Error("storage: failed to fetch backup schedules", "err", err)
		return
	}

	for _, s := range schedules {
		sched := s // Capture loop variable
		_, err := cronRunner.AddFunc(sched.CronExpression, func() {
			ExecuteScheduledBackup(sched)
		})
		if err != nil {
			slog.Warn("storage: invalid cron expression for schedule", "name", sched.Name, "cron", sched.CronExpression, "err", err)
		} else {
			slog.Info("storage: registered backup schedule", "name", sched.Name, "cron", sched.CronExpression)
		}
	}

	cronRunner.Start()
}

// ExecuteScheduledBackup executes a backup for a given schedule and applies retention pruning.
func ExecuteScheduledBackup(s db.BackupSchedule) {
	slog.Info("storage: executing scheduled backup", "schedule_id", s.ID, "name", s.Name)
	now := time.Now()
	sourcePath := ""
	stackID := s.TargetID
	volumeName := s.TargetName

	if s.TargetType == "path" || strings.HasPrefix(s.TargetID, "/") {
		sourcePath = s.TargetID
		stackID = ""
		volumeName = ""
	} else if s.TargetType == "volume" {
		volumeName = s.TargetID
		stackID = ""
		if strings.HasPrefix(s.TargetName, "/") {
			sourcePath = s.TargetName
		}
	} else if s.TargetType == "stack" {
		stackID = s.TargetID
		volumeName = s.TargetName
	}

	req := CreateBackupRequest{
		Name:            s.Name,
		StackID:         stackID,
		VolumeName:      volumeName,
		SourcePath:      sourcePath,
		DestinationPath: s.DestinationPath,
		PauseContainers: s.PauseContainers,
		IsScheduled:     true,
		ScheduleID:      s.ID,
	}

	backup, err := CreateBackup(req)
	if err != nil {
		slog.Error("storage: scheduled backup failed", "schedule_id", s.ID, "err", err)
		return
	}

	// Update schedule's LastRunAt in DB
	db.DB.Model(&db.BackupSchedule{}).Where("id = ?", s.ID).Update("last_run_at", now)

	// Apply retention policy
	if s.RetentionCount > 0 {
		_ = PruneRetainedBackups(s.ID, s.RetentionCount)
	}

	slog.Info("storage: scheduled backup completed successfully", "backup_id", backup.ID, "size", backup.SizeFormatted)
}
