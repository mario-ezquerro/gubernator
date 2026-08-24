package cli

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"text/tabwriter"

	"github.com/mario-ezquerro/gubernator/internal/storage"
	"github.com/spf13/cobra"
)

var glusterCmd = &cobra.Command{
	Use:   "gluster",
	Short: "Manage GlusterFS distributed cluster storage and multi-node replication",
	Long:  `Manage GlusterFS trusted storage pool peers, 3-way replicated volumes (Replica 3 / Arbiter), self-healing, and cluster-wide mount points.`,
}

// gbnt gluster status
var glusterStatusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show GlusterFS cluster health, daemon state, and topology diagnostics",
	Run: func(cmd *cobra.Command, args []string) {
		diag, err := storage.GetGlusterDiagnostics()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error querying GlusterFS diagnostics: %v\n", err)
			os.Exit(1)
		}

		fmt.Println("🏛️  GlusterFS Cluster Storage Diagnostics")
		fmt.Println(strings.Repeat("─", 50))
		daemonIcon := "🟢 Running"
		if !diag.DaemonRunning {
			daemonIcon = "🔴 Inactive (Start glusterd or run ansible/glusterfs.yml)"
		}
		fmt.Printf("Daemon Status:    %s\n", daemonIcon)
		if diag.Version != "" {
			fmt.Printf("Gluster Version:  %s\n", diag.Version)
		}
		fmt.Printf("Health Score:     %d/100\n", diag.HealthScore)
		fmt.Printf("Trusted Peers:    %d node(s)\n", diag.PeersCount)
		fmt.Printf("Volumes:          %d total (%d started)\n", diag.VolumesCount, diag.OnlineVolumes)

		if len(diag.Issues) > 0 {
			fmt.Println("\n⚠️  Warnings & Recommendations:")
			for _, iss := range diag.Issues {
				fmt.Printf("  • %s\n", iss)
			}
		}
	},
}

// gbnt gluster peer ls
var glusterPeerLsCmd = &cobra.Command{
	Use:   "peer-ls",
	Short: "List all nodes in the GlusterFS trusted storage pool",
	Aliases: []string{"peers"},
	Run: func(cmd *cobra.Command, args []string) {
		peers, err := storage.GetGlusterPeers()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error fetching peers: %v\n", err)
			os.Exit(1)
		}

		w := tabwriter.NewWriter(os.Stdout, 0, 0, 3, ' ', 0)
		fmt.Fprintln(w, "HOSTNAME\tSTATE\tCONNECTED\tLOCAL\tUUID")
		for _, p := range peers {
			conn := "YES"
			if !p.Connected {
				conn = "NO"
			}
			isLocal := "NO"
			if p.IsLocal {
				isLocal = "YES (Manager)"
			}
			uuid := p.UUID
			if uuid == "" {
				uuid = "-"
			}
			fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\n", p.Hostname, p.State, conn, isLocal, uuid)
		}
		w.Flush()
	},
}

// gbnt gluster peer probe <host>
var glusterPeerProbeCmd = &cobra.Command{
	Use:   "probe [host]",
	Short: "Probe a new node into the trusted storage pool",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		host := args[0]
		err := storage.ProbeGlusterPeer(host)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error probing peer %s: %v\n", host, err)
			os.Exit(1)
		}
		fmt.Printf("✓ Successfully probed peer: %s\n", host)
	},
}

// gbnt gluster peer detach <host>
var glusterPeerDetachCmd = &cobra.Command{
	Use:   "detach [host]",
	Short: "Remove a node from the trusted storage pool",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		host := args[0]
		err := storage.DetachGlusterPeer(host, false)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error detaching peer %s: %v\n", host, err)
			os.Exit(1)
		}
		fmt.Printf("✓ Successfully detached peer: %s\n", host)
	},
}

// Flags for volume create
var (
	glusterReplicaCount int
	glusterArbiterCount int
	glusterBricks       string
	glusterBrickDir     string
	glusterAutoMount    bool
	glusterMountPoint   string
)

// gbnt gluster volume ls
var glusterVolumeLsCmd = &cobra.Command{
	Use:   "ls",
	Short: "List all GlusterFS distributed and replicated volumes",
	Aliases: []string{"volume-ls", "vols"},
	Run: func(cmd *cobra.Command, args []string) {
		vols, err := storage.GetGlusterVolumes()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error fetching volumes: %v\n", err)
			os.Exit(1)
		}

		w := tabwriter.NewWriter(os.Stdout, 0, 0, 3, ' ', 0)
		fmt.Fprintln(w, "VOLUME NAME\tTYPE\tSTATUS\tREPLICAS\tBRICKS\tMOUNT POINT\tCAPACITY")
		for _, v := range vols {
			repl := fmt.Sprintf("Replica %d", v.ReplicaCount)
			if v.ArbiterCount > 0 {
				repl += " (Arbiter 1)"
			}
			mnt := "-"
			if v.IsMounted {
				mnt = v.MountPoint
				if mnt == "" {
					mnt = "/var/contenedores"
				}
			}
			capStr := "-"
			if v.CapacityTotal > 0 {
				capStr = fmt.Sprintf("%.1f%% (%s / %s)", v.CapacityPercent, storage.FormatBytes(v.CapacityUsed), storage.FormatBytes(v.CapacityTotal))
			}
			fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%d\t%s\t%s\n", v.Name, v.Type, v.Status, repl, v.NumBricks, mnt, capStr)
		}
		w.Flush()
	},
}

// gbnt gluster volume create <name>
var glusterVolumeCreateCmd = &cobra.Command{
	Use:   "create [name]",
	Short: "Create a new replicated GlusterFS cluster volume",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		name := args[0]
		var brickList []string
		if glusterBricks != "" {
			for _, b := range strings.Split(glusterBricks, ",") {
				b = strings.TrimSpace(b)
				if b != "" {
					brickList = append(brickList, b)
				}
			}
		}

		req := storage.GlusterVolumeCreateRequest{
			Name:         name,
			ReplicaCount: glusterReplicaCount,
			ArbiterCount: glusterArbiterCount,
			Bricks:       brickList,
			BrickDir:     glusterBrickDir,
			AutoMount:    glusterAutoMount,
			MountPoint:   glusterMountPoint,
			Force:        true,
		}

		err := storage.CreateGlusterVolume(req)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error creating volume %s: %v\n", name, err)
			os.Exit(1)
		}

		fmt.Printf("✓ Successfully created and optimized GlusterFS volume '%s'\n", name)
		if glusterAutoMount {
			fmt.Printf("✓ Auto-mounted to %s across cluster nodes\n", glusterMountPoint)
		}
	},
}

// gbnt gluster volume start <name>
var glusterVolumeStartCmd = &cobra.Command{
	Use:   "start [name]",
	Short: "Start a GlusterFS volume",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		name := args[0]
		err := storage.StartGlusterVolume(name)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error starting volume %s: %v\n", name, err)
			os.Exit(1)
		}
		fmt.Printf("✓ Volume '%s' started successfully\n", name)
	},
}

// gbnt gluster volume stop <name>
var glusterVolumeStopCmd = &cobra.Command{
	Use:   "stop [name]",
	Short: "Stop an active GlusterFS volume",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		name := args[0]
		err := storage.StopGlusterVolume(name, true)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error stopping volume %s: %v\n", name, err)
			os.Exit(1)
		}
		fmt.Printf("✓ Volume '%s' stopped\n", name)
	},
}

// gbnt gluster volume rm <name>
var glusterVolumeRmCmd = &cobra.Command{
	Use:   "rm [name]",
	Short: "Delete a GlusterFS volume",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		name := args[0]
		err := storage.DeleteGlusterVolume(name)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error deleting volume %s: %v\n", name, err)
			os.Exit(1)
		}
		fmt.Printf("✓ Volume '%s' deleted\n", name)
	},
}

// gbnt gluster volume heal <name>
var glusterVolumeHealCmd = &cobra.Command{
	Use:   "heal [name]",
	Short: "Show self-heal statistics or trigger manual self-healing",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		name := args[0]
		report, err := storage.GetGlusterHealReport(name)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error querying heal status: %v\n", err)
			os.Exit(1)
		}

		fmt.Printf("🏥  Self-Heal Status for Volume '%s'\n", name)
		fmt.Println(strings.Repeat("─", 50))
		fmt.Printf("Summary:          %s\n", report.StatusSummary)
		fmt.Printf("Pending Entries:  %d\n", report.TotalPending)
		fmt.Printf("Split-Brain:      %s\n", strconv.FormatBool(report.InSplitBrain))
		if len(report.BricksHealInfo) > 0 {
			fmt.Println("\nBrick Diagnostics:")
			for _, b := range report.BricksHealInfo {
				fmt.Printf("  • %s: %d pending (%s)\n", b.BrickSpec, b.NumberOfEntries, b.Status)
			}
		}
	},
}

// gbnt gluster mount <name>
var glusterMountCmd = &cobra.Command{
	Use:   "mount [name]",
	Short: "Auto-mount GlusterFS volume to /var/contenedores across cluster hosts",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		name := args[0]
		target := glusterMountPoint
		if target == "" {
			target = "/var/contenedores"
		}
		err := storage.MountGlusterToCluster(name, target, nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error auto-mounting volume: %v\n", err)
			os.Exit(1)
		}
		fmt.Printf("✓ Registered GlusterFS volume '%s' mounted on %s across cluster\n", name, target)
	},
}

// gbnt gluster volume option <name> <key> [value] [--reset]
var glusterOptionReset bool

var glusterVolumeOptionCmd = &cobra.Command{
	Use:   "option [volume-name] [key] [value]",
	Short: "Configure or reset volume tuning, network isolation (auth.allow), and performance options",
	Long:  `Set or reset options like auth.allow, auth.reject, network.ping-timeout, and performance.write-behind on a GlusterFS volume.`,
	Args:  cobra.RangeArgs(2, 3),
	Run: func(cmd *cobra.Command, args []string) {
		volName := args[0]
		key := args[1]

		if glusterOptionReset {
			err := storage.ResetGlusterVolumeOption(volName, key)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error resetting option %s on %s: %v\n", key, volName, err)
				os.Exit(1)
			}
			fmt.Printf("✓ Option '%s' reset to default on volume '%s'\n", key, volName)
			return
		}

		if len(args) < 3 {
			fmt.Fprintln(os.Stderr, "Error: value required when setting an option (e.g. gbnt gluster volume option gv_contenedores auth.allow '10.10.100.*')")
			os.Exit(1)
		}
		val := args[2]

		err := storage.SetGlusterVolumeOption(volName, key, val)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error setting option %s=%s on %s: %v\n", key, val, volName, err)
			os.Exit(1)
		}
		fmt.Printf("✓ Successfully configured '%s=%s' on volume '%s'\n", key, val, volName)
	},
}

func init() {
	// Flags for volume create
	glusterVolumeCreateCmd.Flags().IntVarP(&glusterReplicaCount, "replica", "r", 3, "Replica count (default: 3 for 3-way mirror)")
	glusterVolumeCreateCmd.Flags().IntVarP(&glusterArbiterCount, "arbiter", "a", 0, "Arbiter count (e.g. 1)")
	glusterVolumeCreateCmd.Flags().StringVarP(&glusterBricks, "bricks", "b", "", "Comma-separated list of brick specs (e.g. host1:/data/b1,host2:/data/b1,host3:/data/b1)")
	glusterVolumeCreateCmd.Flags().StringVarP(&glusterBrickDir, "brick-dir", "d", "/data/glusterfs/brick1", "Directory on nodes to store volume bricks")
	glusterVolumeCreateCmd.Flags().BoolVarP(&glusterAutoMount, "auto-mount", "m", true, "Auto-mount to /var/contenedores across cluster")
	glusterVolumeCreateCmd.Flags().StringVarP(&glusterMountPoint, "mount-point", "p", "/var/contenedores", "Target mount point for containers")

	glusterMountCmd.Flags().StringVarP(&glusterMountPoint, "target", "t", "/var/contenedores", "Target mount point on cluster nodes")
	glusterVolumeOptionCmd.Flags().BoolVar(&glusterOptionReset, "reset", false, "Reset the specified option to its default value")

	// Assemble subcommands
	glusterCmd.AddCommand(glusterStatusCmd)
	glusterCmd.AddCommand(glusterPeerLsCmd)
	glusterCmd.AddCommand(glusterPeerProbeCmd)
	glusterCmd.AddCommand(glusterPeerDetachCmd)
	glusterCmd.AddCommand(glusterVolumeLsCmd)
	glusterCmd.AddCommand(glusterVolumeCreateCmd)
	glusterCmd.AddCommand(glusterVolumeStartCmd)
	glusterCmd.AddCommand(glusterVolumeStopCmd)
	glusterCmd.AddCommand(glusterVolumeRmCmd)
	glusterCmd.AddCommand(glusterVolumeHealCmd)
	glusterCmd.AddCommand(glusterVolumeOptionCmd)
	glusterCmd.AddCommand(glusterMountCmd)
}
