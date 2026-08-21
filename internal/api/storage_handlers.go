package api

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/mario-ezquerro/gubernator/internal/storage"
)

// StorageVolumesHandler returns all persistent volumes and bind mounts in the cluster.
func StorageVolumesHandler(c *gin.Context) {
	vols, err := storage.ListVolumes()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, vols)
}

// StoragePoolsHealthHandler returns the health check matrix and capacity of the shared storage pool.
func StoragePoolsHealthHandler(c *gin.Context) {
	poolPath := c.DefaultQuery("path", storage.DefaultSharedPoolPath)
	res := storage.CheckStoragePoolHealth(poolPath)
	c.JSON(http.StatusOK, res)
}

// BackupListHandler returns all backups.
func BackupListHandler(c *gin.Context) {
	backups, err := storage.ListBackups()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, backups)
}

// BackupCreateHandler triggers the creation of a new backup.
func BackupCreateHandler(c *gin.Context) {
	var req storage.CreateBackupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	b, err := storage.CreateBackup(req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, b)
}

// BackupRestoreHandler restores a backup archive.
func BackupRestoreHandler(c *gin.Context) {
	var req storage.RestoreBackupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := storage.RestoreBackup(req); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Backup restored successfully"})
}

// BackupDeleteHandler deletes a backup.
func BackupDeleteHandler(c *gin.Context) {
	id := c.Param("id")
	if err := storage.DeleteBackup(id); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Backup deleted successfully"})
}

// BackupSchedulesListHandler returns all backup schedules.
func BackupSchedulesListHandler(c *gin.Context) {
	var schedules []db.BackupSchedule
	if err := db.DB.Order("created_at desc").Find(&schedules).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, schedules)
}

// BackupScheduleSaveHandler creates or updates a backup schedule.
func BackupScheduleSaveHandler(c *gin.Context) {
	var req db.BackupSchedule
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.ID == "" {
		req.ID = uuid.New().String()
		req.CreatedAt = time.Now()
		req.UpdatedAt = time.Now()
		if err := db.DB.Create(&req).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	} else {
		req.UpdatedAt = time.Now()
		if err := db.DB.Save(&req).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	storage.SyncSchedules()
	c.JSON(http.StatusOK, req)
}

// BackupScheduleDeleteHandler deletes a backup schedule.
func BackupScheduleDeleteHandler(c *gin.Context) {
	id := c.Param("id")
	if err := db.DB.Delete(&db.BackupSchedule{}, "id = ?", id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	storage.SyncSchedules()
	c.JSON(http.StatusOK, gin.H{"message": "Schedule deleted successfully"})
}

// StorageMountsListHandler returns all configured and detected fstab mounts.
func StorageMountsListHandler(c *gin.Context) {
	mounts, err := storage.ListStorageMounts()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"mounts": mounts,
		"total":  len(mounts),
	})
}

// StorageMountCreateHandler creates and mounts a network storage entry.
func StorageMountCreateHandler(c *gin.Context) {
	var req storage.CreateMountRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	m, err := storage.CreateStorageMount(req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Mount created successfully",
		"mount":   m,
	})
}

// StorageMountTestHandler tests network connection and R/W access for a mount.
func StorageMountTestHandler(c *gin.Context) {
	var req storage.CreateMountRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	res := storage.TestMountConnection(req)
	c.JSON(http.StatusOK, res)
}

// StorageMountActionHandler mounts an existing entry.
func StorageMountActionHandler(c *gin.Context) {
	id := c.Param("id")
	if err := storage.MountStorageEntry(id); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Mounted successfully"})
}

// StorageUnmountActionHandler unmounts an existing entry.
func StorageUnmountActionHandler(c *gin.Context) {
	id := c.Param("id")
	if err := storage.UnmountStorageEntry(id); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Unmounted successfully"})
}

// StorageMountDeleteHandler deletes a mount and cleans up fstab.
func StorageMountDeleteHandler(c *gin.Context) {
	id := c.Param("id")
	if err := storage.DeleteStorageMount(id); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Mount deleted successfully"})
}

// StorageMountAllHandler executes mount -a.
func StorageMountAllHandler(c *gin.Context) {
	out, err := storage.MountAllStorageEntries()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error(), "output": out})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "mount -a executed successfully", "output": out})
}

// StorageFstabRawHandler returns raw /etc/fstab contents.
func StorageFstabRawHandler(c *gin.Context) {
	raw, err := storage.GetRawFstab()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"path": storage.FstabPath(),
		"raw":  raw,
	})
}
