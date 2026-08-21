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

var mountCmd = &cobra.Command{
	Use:   "mount",
	Short: "Manage network filesystems (NFS, S3, Samba) and /etc/fstab",
}

var mountLsCmd = &cobra.Command{
	Use:   "ls",
	Short: "List all managed and detected network storage mounts",
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := DoAPIRequest("GET", "/v1/storage/mounts", nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			fmt.Fprintf(os.Stderr, "Failed to list mounts: %s\n", string(body))
			os.Exit(1)
		}

		var res struct {
			Mounts []db.StorageMount `json:"mounts"`
		}
		if err := json.NewDecoder(resp.Body).Decode(&res); err != nil {
			fmt.Fprintf(os.Stderr, "Failed to parse response: %v\n", err)
			os.Exit(1)
		}

		if len(res.Mounts) == 0 {
			fmt.Println("No network storage mounts configured.")
			return
		}

		fmt.Printf("%-12s %-10s %-30s %-25s %-12s %-10s\n", "ID", "TYPE", "REMOTE DEVICE", "MOUNT POINT", "STATUS", "AUTO-MOUNT")
		fmt.Println("---------------------------------------------------------------------------------------------------------")
		for _, m := range res.Mounts {
			autoStr := "No"
			if m.AutoMount {
				autoStr = "Yes"
			}
			fmt.Printf("%-12s %-10s %-30s %-25s %-12s %-10s\n", m.ID, m.FSType, m.Device, m.MountPoint, m.Status, autoStr)
		}
	},
}

var (
	mountNameFlag        string
	mountTypeFlag        string
	mountDeviceFlag      string
	mountPointFlag       string
	mountOptionsFlag     string
	mountAutoFlag        bool
	mountUsernameFlag    string
	mountPasswordFlag    string
	mountDomainFlag      string
	mountS3EndpointFlag  string
	mountS3AccessKeyFlag string
	mountS3SecretKeyFlag string
)

var mountAddCmd = &cobra.Command{
	Use:   "add",
	Short: "Add and mount a new network filesystem (NFS, S3, Samba)",
	Run: func(cmd *cobra.Command, args []string) {
		req := storage.CreateMountRequest{
			Name:        mountNameFlag,
			FSType:      mountTypeFlag,
			Device:      mountDeviceFlag,
			MountPoint:  mountPointFlag,
			Options:     mountOptionsFlag,
			AutoMount:   mountAutoFlag,
			Username:    mountUsernameFlag,
			Password:    mountPasswordFlag,
			Domain:      mountDomainFlag,
			S3Endpoint:  mountS3EndpointFlag,
			S3AccessKey: mountS3AccessKeyFlag,
			S3SecretKey: mountS3SecretKeyFlag,
		}

		bodyBytes, _ := json.Marshal(req)
		resp, err := DoAPIRequest("POST", "/v1/storage/mounts", bytes.NewReader(bodyBytes))
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		body, _ := io.ReadAll(resp.Body)
		if resp.StatusCode != http.StatusOK {
			fmt.Fprintf(os.Stderr, "Failed to create mount: %s\n", string(body))
			os.Exit(1)
		}

		fmt.Println("✅ Network storage mount configured successfully!")
		fmt.Printf("Device: %s -> MountPoint: %s (%s)\n", req.Device, req.MountPoint, req.FSType)
	},
}

var mountRmCmd = &cobra.Command{
	Use:   "rm <id>",
	Short: "Unmount and remove a network storage mount from /etc/fstab",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		id := args[0]
		resp, err := DoAPIRequest("DELETE", fmt.Sprintf("/v1/storage/mounts/%s", id), nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			fmt.Fprintf(os.Stderr, "Failed to delete mount: %s\n", string(body))
			os.Exit(1)
		}

		fmt.Printf("✅ Mount %s removed successfully.\n", id)
	},
}

var mountMountCmd = &cobra.Command{
	Use:   "mount <id>",
	Short: "Mount a configured network storage entry",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		id := args[0]
		resp, err := DoAPIRequest("POST", fmt.Sprintf("/v1/storage/mounts/%s/mount", id), nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			fmt.Fprintf(os.Stderr, "Failed to mount: %s\n", string(body))
			os.Exit(1)
		}

		fmt.Printf("✅ Mount %s mounted successfully.\n", id)
	},
}

var mountUnmountCmd = &cobra.Command{
	Use:   "unmount <id>",
	Short: "Unmount a configured network storage entry",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		id := args[0]
		resp, err := DoAPIRequest("POST", fmt.Sprintf("/v1/storage/mounts/%s/unmount", id), nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			fmt.Fprintf(os.Stderr, "Failed to unmount: %s\n", string(body))
			os.Exit(1)
		}

		fmt.Printf("✅ Mount %s unmounted successfully.\n", id)
	},
}

var mountFstabCmd = &cobra.Command{
	Use:   "fstab",
	Short: "Display the raw host /etc/fstab configuration",
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := DoAPIRequest("GET", "/v1/storage/fstab/raw", nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		var res struct {
			Path string `json:"path"`
			Raw  string `json:"raw"`
		}
		if err := json.NewDecoder(resp.Body).Decode(&res); err != nil {
			fmt.Fprintf(os.Stderr, "Failed to parse response: %v\n", err)
			os.Exit(1)
		}

		fmt.Printf("📄 Host fstab: %s\n", res.Path)
		fmt.Println("---------------------------------------------------------------------------------------------------------")
		fmt.Println(res.Raw)
	},
}

func init() {
	mountAddCmd.Flags().StringVarP(&mountNameFlag, "name", "n", "", "Descriptive mount name")
	mountAddCmd.Flags().StringVarP(&mountTypeFlag, "type", "t", "nfs", "Filesystem type (nfs, cifs, fuse.s3fs, ext4)")
	mountAddCmd.Flags().StringVarP(&mountDeviceFlag, "device", "d", "", "Remote server share or bucket (e.g. 192.168.1.50:/share)")
	mountAddCmd.Flags().StringVarP(&mountPointFlag, "target", "m", "/var/contenedores", "Local mount destination path")
	mountAddCmd.Flags().StringVarP(&mountOptionsFlag, "options", "o", "", "Mount options string")
	mountAddCmd.Flags().BoolVar(&mountAutoFlag, "auto", true, "Automatically mount on system boot via /etc/fstab")
	mountAddCmd.Flags().StringVar(&mountUsernameFlag, "user", "", "Username for Samba/CIFS authentication")
	mountAddCmd.Flags().StringVar(&mountPasswordFlag, "password", "", "Password for Samba/CIFS authentication")
	mountAddCmd.Flags().StringVar(&mountDomainFlag, "domain", "", "Workgroup/Domain for Samba/CIFS")
	mountAddCmd.Flags().StringVar(&mountS3EndpointFlag, "s3-endpoint", "", "S3 API endpoint URL (AWS, MinIO, Wasabi, Cloudflare R2)")
	mountAddCmd.Flags().StringVar(&mountS3AccessKeyFlag, "s3-access-key", "", "S3 Access Key ID")
	mountAddCmd.Flags().StringVar(&mountS3SecretKeyFlag, "s3-secret-key", "", "S3 Secret Access Key")
	_ = mountAddCmd.MarkFlagRequired("device")

	mountCmd.AddCommand(mountLsCmd)
	mountCmd.AddCommand(mountAddCmd)
	mountCmd.AddCommand(mountRmCmd)
	mountCmd.AddCommand(mountMountCmd)
	mountCmd.AddCommand(mountUnmountCmd)
	mountCmd.AddCommand(mountFstabCmd)

	rootCmd.AddCommand(mountCmd)
}
