package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"

	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/mario-ezquerro/gubernator/internal/storage"
	"github.com/spf13/cobra"
)

// Volume command group
var volumeCmd = &cobra.Command{
	Use:   "volume",
	Short: "Manage persistent cluster storage volumes and shared pools",
}

var volumeLsCmd = &cobra.Command{
	Use:   "ls",
	Short: "List all persistent volumes and bind mounts",
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := DoAPIRequest("GET", "/v1/storage/volumes", nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			fmt.Fprintf(os.Stderr, "Failed to list volumes: %s\n", string(body))
			os.Exit(1)
		}

		var vols []db.StorageVolume
		if err := json.NewDecoder(resp.Body).Decode(&vols); err != nil {
			fmt.Fprintf(os.Stderr, "Failed to parse response: %v\n", err)
			os.Exit(1)
		}

		if len(vols) == 0 {
			fmt.Println("No persistent volumes or bind mounts found.")
			return
		}

		fmt.Printf("%-20s %-15s %-15s %-10s %-30s %-10s\n", "NAME", "STACK", "TYPE", "SIZE", "SOURCE PATH", "SHARED")
		fmt.Println("---------------------------------------------------------------------------------------------------------")
		for _, v := range vols {
			sharedStr := "No"
			if v.IsShared {
				sharedStr = "Yes"
			}
			sizeStr := storage.FormatBytes(v.SizeBytes)
			fmt.Printf("%-20s %-15s %-15s %-10s %-30s %-10s\n", v.Name, v.StackName, v.Type, sizeStr, v.SourcePath, sharedStr)
		}
	},
}

// Backup command group
var backupCmd = &cobra.Command{
	Use:   "backup",
	Short: "Manage compressed point-in-time backups and snapshots",
}

var backupLsCmd = &cobra.Command{
	Use:   "ls",
	Short: "List all backups",
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := DoAPIRequest("GET", "/v1/backup/ls", nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			fmt.Fprintf(os.Stderr, "Failed to list backups: %s\n", string(body))
			os.Exit(1)
		}

		var backups []db.Backup
		if err := json.NewDecoder(resp.Body).Decode(&backups); err != nil {
			fmt.Fprintf(os.Stderr, "Failed to parse response: %v\n", err)
			os.Exit(1)
		}

		if len(backups) == 0 {
			fmt.Println("No backups found.")
			return
		}

		fmt.Printf("%-36s %-25s %-15s %-10s %-20s %-10s\n", "ID", "NAME", "STACK", "SIZE", "CREATED AT", "STATUS")
		fmt.Println("----------------------------------------------------------------------------------------------------------------")
		for _, b := range backups {
			sizeStr := storage.FormatBytes(b.SizeBytes)
			createdStr := b.CreatedAt.Format("2006-01-02 15:04:05")
			fmt.Printf("%-36s %-25s %-15s %-10s %-20s %-10s\n", b.ID, b.Name, b.StackName, sizeStr, createdStr, b.Status)
		}
	},
}

var (
	backupCreatePause bool
	backupCreateName  string
)

var backupCreateCmd = &cobra.Command{
	Use:   "create <stack_id_or_path>",
	Short: "Create a point-in-time compressed backup",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		target := args[0]
		req := storage.CreateBackupRequest{
			Name:            backupCreateName,
			StackID:         target,
			SourcePath:      target,
			PauseContainers: backupCreatePause,
		}

		reqBytes, _ := json.Marshal(req)
		resp, err := DoAPIRequest("POST", "/v1/backup/create", bytes.NewBuffer(reqBytes))
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			fmt.Fprintf(os.Stderr, "Failed to create backup: %s\n", string(body))
			os.Exit(1)
		}

		var b db.Backup
		if err := json.NewDecoder(resp.Body).Decode(&b); err != nil {
			fmt.Fprintf(os.Stderr, "Failed to parse response: %v\n", err)
			os.Exit(1)
		}

		fmt.Printf("✅ Backup successfully created:\n")
		fmt.Printf("   ID:        %s\n", b.ID)
		fmt.Printf("   Name:      %s\n", b.Name)
		fmt.Printf("   Size:      %s\n", storage.FormatBytes(b.SizeBytes))
		fmt.Printf("   SHA-256:   %s\n", b.SHA256)
		fmt.Printf("   File Path: %s\n", b.FilePath)
	},
}

var backupRestoreTarget string

var backupRestoreCmd = &cobra.Command{
	Use:   "restore <backup_id>",
	Short: "Restore a backup archive to original or custom target path",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		backupID := args[0]
		req := storage.RestoreBackupRequest{
			BackupID:   backupID,
			TargetPath: backupRestoreTarget,
		}

		reqBytes, _ := json.Marshal(req)
		resp, err := DoAPIRequest("POST", "/v1/backup/restore", bytes.NewBuffer(reqBytes))
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			fmt.Fprintf(os.Stderr, "Failed to restore backup: %s\n", string(body))
			os.Exit(1)
		}

		fmt.Printf("✅ Backup %s restored successfully.\n", backupID)
	},
}

var backupScheduleCmd = &cobra.Command{
	Use:   "schedule",
	Short: "Manage automated backup schedules and retention policies",
}

var backupScheduleLsCmd = &cobra.Command{
	Use:   "ls",
	Short: "List all backup schedules",
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := DoAPIRequest("GET", "/v1/backup/schedules", nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			fmt.Fprintf(os.Stderr, "Failed to list schedules: %s\n", string(body))
			os.Exit(1)
		}

		var schedules []db.BackupSchedule
		if err := json.NewDecoder(resp.Body).Decode(&schedules); err != nil {
			fmt.Fprintf(os.Stderr, "Failed to parse response: %v\n", err)
			os.Exit(1)
		}

		if len(schedules) == 0 {
			fmt.Println("No backup schedules configured.")
			return
		}

		fmt.Printf("%-20s %-15s %-15s %-10s %-10s\n", "NAME", "CRON", "TARGET", "RETENTION", "ENABLED")
		fmt.Println("-----------------------------------------------------------------------------")
		for _, s := range schedules {
			enabledStr := "Yes"
			if !s.Enabled {
				enabledStr = "No"
			}
			fmt.Printf("%-20s %-15s %-15s %-10d %-10s\n", s.Name, s.CronExpression, s.TargetName, s.RetentionCount, enabledStr)
		}
	},
}

func init() {
	volumeCmd.AddCommand(volumeLsCmd)

	backupCreateCmd.Flags().BoolVarP(&backupCreatePause, "pause", "p", true, "Pause containers during backup for database consistency")
	backupCreateCmd.Flags().StringVarP(&backupCreateName, "name", "n", "", "Custom backup name")

	backupRestoreCmd.Flags().StringVarP(&backupRestoreTarget, "target", "t", "", "Custom destination path (defaults to original source path)")

	backupScheduleCmd.AddCommand(backupScheduleLsCmd)

	backupCmd.AddCommand(backupLsCmd)
	backupCmd.AddCommand(backupCreateCmd)
	backupCmd.AddCommand(backupRestoreCmd)
	backupCmd.AddCommand(backupScheduleCmd)

	rootCmd.AddCommand(volumeCmd)
	rootCmd.AddCommand(backupCmd)
}
