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

		fmt.Printf("%-36s %-25s %-15s %-10s %-20s %-12s %-10s\n", "ID", "NAME", "STACK", "SIZE", "CREATED AT", "ENCRYPTION", "STATUS")
		fmt.Println("-----------------------------------------------------------------------------------------------------------------------------")
		for _, b := range backups {
			sizeStr := storage.FormatBytes(b.SizeBytes)
			createdStr := b.CreatedAt.Format("2006-01-02 15:04:05")
			encStr := "Plain"
			if b.IsEncrypted {
				encStr = "🔒 AES-256"
			}
			fmt.Printf("%-36s %-25s %-15s %-10s %-20s %-12s %-10s\n", b.ID, b.Name, b.StackName, sizeStr, createdStr, encStr, b.Status)
		}
	},
}

var (
	backupCreatePause      bool
	backupCreateName       string
	backupCreateEncrypt    bool
	backupCreatePassphrase string
)

var backupCreateCmd = &cobra.Command{
	Use:   "create <stack_id_or_path>",
	Short: "Create a point-in-time compressed backup (optional AES-256-GCM encryption)",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		target := args[0]
		if backupCreateEncrypt && backupCreatePassphrase == "" {
			fmt.Fprintf(os.Stderr, "Error: --password is required when --encrypt is enabled (ENS mp.si.2)\n")
			os.Exit(1)
		}

		req := storage.CreateBackupRequest{
			Name:                 backupCreateName,
			StackID:              target,
			SourcePath:           target,
			PauseContainers:      backupCreatePause,
			Encrypted:            backupCreateEncrypt,
			EncryptionPassphrase: backupCreatePassphrase,
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
		fmt.Printf("   ID:         %s\n", b.ID)
		fmt.Printf("   Name:       %s\n", b.Name)
		fmt.Printf("   Size:       %s\n", storage.FormatBytes(b.SizeBytes))
		fmt.Printf("   SHA-256:    %s\n", b.SHA256)
		if b.IsEncrypted {
			fmt.Printf("   Encryption: 🔒 AES-256-GCM (ENS mp.si.2 / CCN-STIC)\n")
		}
		fmt.Printf("   File Path:  %s\n", b.FilePath)
	},
}

var (
	backupRestoreTarget     string
	backupRestorePassphrase string
)

var backupRestoreCmd = &cobra.Command{
	Use:   "restore <backup_id>",
	Short: "Restore a backup archive to original or custom target path",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		backupID := args[0]
		req := storage.RestoreBackupRequest{
			BackupID:             backupID,
			TargetPath:           backupRestoreTarget,
			EncryptionPassphrase: backupRestorePassphrase,
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

var (
	schedNameFlag       string
	schedCronFlag       string
	schedTypeFlag       string
	schedTargetFlag     string
	schedDestFlag       string
	schedRetentionFlag  int
	schedPauseFlag      bool
	schedEncryptFlag    bool
	schedPassphraseFlag string
)

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

		fmt.Printf("%-36s %-20s %-15s %-15s %-10s %-12s %-10s\n", "ID", "NAME", "CRON", "TARGET", "RETENTION", "ENCRYPTED", "ENABLED")
		fmt.Println("-----------------------------------------------------------------------------------------------------------------------------")
		for _, s := range schedules {
			enabledStr := "Yes"
			if !s.Enabled {
				enabledStr = "No"
			}
			encStr := "No"
			if s.Encrypted {
				encStr = "AES-256-GCM"
			}
			target := s.TargetName
			if target == "" {
				target = s.TargetID
			}
			fmt.Printf("%-36s %-20s %-15s %-15s %-10d %-12s %-10s\n", s.ID, s.Name, s.CronExpression, target, s.RetentionCount, encStr, enabledStr)
		}
	},
}

var backupScheduleAddCmd = &cobra.Command{
	Use:   "add --name <name> --cron <cron> [--target <target>] [--type <stack|volume|path>]",
	Short: "Create or update an automated periodic backup schedule",
	Run: func(cmd *cobra.Command, args []string) {
		if schedNameFlag == "" {
			fmt.Fprintln(os.Stderr, "Error: --name is required")
			os.Exit(1)
		}
		if schedCronFlag == "" {
			fmt.Fprintln(os.Stderr, "Error: --cron expression is required (e.g. '0 3 * * *')")
			os.Exit(1)
		}
		if schedTargetFlag == "" {
			schedTargetFlag = "all"
		}
		if schedDestFlag == "" {
			schedDestFlag = "/var/backups/gbnt"
		}

		payload := map[string]interface{}{
			"name":                  schedNameFlag,
			"cron_expression":       schedCronFlag,
			"target_type":           schedTypeFlag,
			"target_id":             schedTargetFlag,
			"target_name":           schedTargetFlag,
			"destination_path":      schedDestFlag,
			"retention_count":       schedRetentionFlag,
			"pause_containers":      schedPauseFlag,
			"enabled":               true,
			"encrypted":             schedEncryptFlag,
			"encryption_passphrase": schedPassphraseFlag,
		}

		reqBytes, _ := json.Marshal(payload)
		resp, err := DoAPIRequest("POST", "/v1/backup/schedules", bytes.NewBuffer(reqBytes))
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			fmt.Fprintf(os.Stderr, "Failed to create schedule: %s\n", string(body))
			os.Exit(1)
		}

		encMsg := "No"
		if schedEncryptFlag {
			encMsg = "Yes (AES-256-GCM authenticated)"
		}
		fmt.Printf("✅ Backup schedule '%s' registered successfully!\n", schedNameFlag)
		fmt.Printf("  • Cron Expression: %s\n", schedCronFlag)
		fmt.Printf("  • Target:          %s (%s)\n", schedTargetFlag, schedTypeFlag)
		fmt.Printf("  • Retention:       Keep last %d copies\n", schedRetentionFlag)
		fmt.Printf("  • Encrypted:       %s\n", encMsg)
		fmt.Printf("  • Destination:     %s\n", schedDestFlag)
	},
}

var backupScheduleRmCmd = &cobra.Command{
	Use:   "rm <schedule-id>",
	Short: "Delete an automated backup schedule",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		id := args[0]
		resp, err := DoAPIRequest("DELETE", "/v1/backup/schedules/"+id, nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			fmt.Fprintf(os.Stderr, "Failed to delete schedule: %s\n", string(body))
			os.Exit(1)
		}

		fmt.Printf("✅ Backup schedule '%s' deleted successfully.\n", id)
	},
}

func init() {
	volumeCmd.AddCommand(volumeLsCmd)

	backupCreateCmd.Flags().BoolVarP(&backupCreatePause, "pause", "p", true, "Pause containers during backup for database consistency")
	backupCreateCmd.Flags().StringVarP(&backupCreateName, "name", "n", "", "Custom backup name")
	backupCreateCmd.Flags().BoolVarP(&backupCreateEncrypt, "encrypt", "e", false, "Encrypt backup archive with AES-256-GCM (ENS mp.si.2)")
	backupCreateCmd.Flags().StringVar(&backupCreatePassphrase, "password", "", "Passphrase for AES-256-GCM encryption")

	backupRestoreCmd.Flags().StringVarP(&backupRestoreTarget, "target", "t", "", "Custom destination path (defaults to original source path)")
	backupRestoreCmd.Flags().StringVar(&backupRestorePassphrase, "password", "", "Passphrase for decrypting AES-256-GCM backup")

	backupScheduleAddCmd.Flags().StringVarP(&schedNameFlag, "name", "n", "", "Schedule name (required)")
	backupScheduleAddCmd.Flags().StringVarP(&schedCronFlag, "cron", "c", "0 3 * * *", "Cron expression (e.g. '0 3 * * *')")
	backupScheduleAddCmd.Flags().StringVarP(&schedTypeFlag, "type", "t", "stack", "Target type ('stack', 'volume', 'path')")
	backupScheduleAddCmd.Flags().StringVar(&schedTargetFlag, "target", "all", "Target Stack ID, Volume Name, or directory path")
	backupScheduleAddCmd.Flags().StringVarP(&schedDestFlag, "dest", "d", "/var/backups/gbnt", "Destination folder on host")
	backupScheduleAddCmd.Flags().IntVarP(&schedRetentionFlag, "retention", "r", 7, "Number of backups to retain")
	backupScheduleAddCmd.Flags().BoolVarP(&schedPauseFlag, "pause", "p", true, "Pause containers during backup")
	backupScheduleAddCmd.Flags().BoolVarP(&schedEncryptFlag, "encrypt", "e", false, "Encrypt backup archives with AES-256-GCM (ENS mp.si.2 / op.exp.10)")
	backupScheduleAddCmd.Flags().StringVar(&schedPassphraseFlag, "password", "", "Passphrase for AES-256-GCM encryption")

	backupScheduleCmd.AddCommand(backupScheduleLsCmd)
	backupScheduleCmd.AddCommand(backupScheduleAddCmd)
	backupScheduleCmd.AddCommand(backupScheduleRmCmd)

	backupCmd.AddCommand(backupLsCmd)
	backupCmd.AddCommand(backupCreateCmd)
	backupCmd.AddCommand(backupRestoreCmd)
	backupCmd.AddCommand(backupScheduleCmd)

	rootCmd.AddCommand(volumeCmd)
	rootCmd.AddCommand(backupCmd)
}
