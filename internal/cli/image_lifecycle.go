package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"

	"github.com/mario-ezquerro/gubernator/internal/docker"
	"github.com/spf13/cobra"
)

var (
	imageNodeFlag      string
	imageForceFlag     bool
	imagePruneAllFlag  bool
	imageBuildTagFlag  string
	imageBuildFileFlag string
	imageNoCacheFlag   bool
)

var imageLsCmd = &cobra.Command{
	Use:   "ls",
	Short: "List physical Docker images across cluster nodes",
	Run: func(cmd *cobra.Command, args []string) {
		path := "/v1/images/host-list?node=" + imageNodeFlag
		resp, err := DoAPIRequest("GET", path, nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		var data struct {
			Images []docker.HostDockerImage `json:"images"`
			Count  int                      `json:"count"`
		}
		if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
			fmt.Fprintf(os.Stderr, "Failed to decode response: %v\n", err)
			os.Exit(1)
		}

		if len(data.Images) == 0 {
			fmt.Println("No Docker images found on target node(s).")
			return
		}

		fmt.Printf("%-36s %-16s %-10s %-20s %-12s %-24s\n", "REPOSITORY:TAG", "IMAGE ID", "SIZE", "NODE", "IN USE", "CREATED")
		fmt.Println("---------------------------------------------------------------------------------------------------------------------------------")
		for _, img := range data.Images {
			inUseStr := "No"
			if img.InUse {
				inUseStr = fmt.Sprintf("Yes (%d ctr)", len(img.ContainersUsing))
			}
			idShort := img.ID
			if len(idShort) > 12 {
				idShort = idShort[:12]
			}
			fmt.Printf("%-36s %-16s %-10s %-20s %-12s %-24s\n",
				truncate(img.FullName, 35), idShort, img.Size, truncate(img.NodeName, 19), inUseStr, truncate(img.CreatedAt, 23))
		}
	},
}

var imageHistoryCmd = &cobra.Command{
	Use:   "history <image>",
	Short: "Inspect construction layers and reconstructed Dockerfile for an image",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		image := args[0]
		path := fmt.Sprintf("/v1/images/history?image=%s&node=%s", image, imageNodeFlag)
		resp, err := DoAPIRequest("GET", path, nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			var errData map[string]interface{}
			json.NewDecoder(resp.Body).Decode(&errData)
			fmt.Fprintf(os.Stderr, "Error: %v\n", errData["error"])
			os.Exit(1)
		}

		var hist docker.ImageHistoryResponse
		json.NewDecoder(resp.Body).Decode(&hist)

		fmt.Printf("📜 Construction History for %s (Total Size: %s, %d layers)\n\n", hist.Image, hist.TotalSize, len(hist.Layers))
		fmt.Printf("%-5s %-12s %-10s %-12s %-50s\n", "LAYER", "INSTRUCTION", "SIZE", "LAYER ID", "COMMAND / ARGUMENTS")
		fmt.Println("----------------------------------------------------------------------------------------------------------------")
		for _, l := range hist.Layers {
			idShort := l.ID
			if len(idShort) > 12 {
				idShort = idShort[:12]
			}
			fmt.Printf("%-5d %-12s %-10s %-12s %-50s\n",
				l.Order, l.Instruction, l.Size, idShort, truncate(l.Args, 48))
		}

		fmt.Println("\n📝 Reconstructed Dockerfile:")
		fmt.Println("----------------------------------------------------------------------------------------------------------------")
		fmt.Println(hist.ReconstructedDockerfile)
	},
}

var imageRmCmd = &cobra.Command{
	Use:   "rm <image>",
	Short: "Delete a Docker image from a specific node or all cluster nodes",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		image := args[0]
		forceStr := "false"
		if imageForceFlag {
			forceStr = "true"
		}
		path := fmt.Sprintf("/v1/images/host-delete?image=%s&node=%s&force=%s", image, imageNodeFlag, forceStr)
		resp, err := DoAPIRequest("DELETE", path, nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		var res docker.ImageRemoveResult
		json.NewDecoder(resp.Body).Decode(&res)

		fmt.Printf("🗑️ %s\n", res.Message)
		for node, status := range res.Nodes {
			fmt.Printf("  • %-20s: %s\n", node, status)
		}
	},
}

var imagePruneCmd = &cobra.Command{
	Use:   "prune",
	Short: "Prune unused and dangling Docker images across cluster nodes to reclaim disk space",
	Run: func(cmd *cobra.Command, args []string) {
		reqBody, _ := json.Marshal(map[string]interface{}{
			"node":       imageNodeFlag,
			"all_unused": imagePruneAllFlag,
		})

		resp, err := DoAPIRequest("POST", "/v1/images/prune", bytes.NewReader(reqBody))
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		var res docker.ImagePruneResult
		json.NewDecoder(resp.Body).Decode(&res)

		fmt.Printf("🧹 Prune Complete: Deleted %d images, Reclaimed %s\n\n", res.TotalImagesDeleted, res.TotalSpaceReclaimed)
		for node, summary := range res.NodeResults {
			fmt.Printf("  • %-20s: %s\n", node, summary)
		}
	},
}

var imageBuildCmd = &cobra.Command{
	Use:   "build",
	Short: "Build a Docker image from a Dockerfile on a Centurion node",
	Run: func(cmd *cobra.Command, args []string) {
		if imageBuildTagFlag == "" {
			fmt.Fprintf(os.Stderr, "Error: -t/--tag is required\n")
			os.Exit(1)
		}

		dockerfileContent := ""
		if imageBuildFileFlag != "" {
			data, err := os.ReadFile(imageBuildFileFlag)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Failed to read Dockerfile %s: %v\n", imageBuildFileFlag, err)
				os.Exit(1)
			}
			dockerfileContent = string(data)
		} else {
			// Check standard Dockerfile in current dir
			data, err := os.ReadFile("Dockerfile")
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error: Dockerfile not found. Specify with -f <path>\n")
				os.Exit(1)
			}
			dockerfileContent = string(data)
		}

		reqBody, _ := json.Marshal(docker.ImageBuildRequest{
			NodeID:     imageNodeFlag,
			Tag:        imageBuildTagFlag,
			Dockerfile: dockerfileContent,
			NoCache:    imageNoCacheFlag,
		})

		fmt.Printf("🔨 Building image '%s' on node '%s'...\n", imageBuildTagFlag, imageNodeFlag)
		resp, err := DoAPIRequest("POST", "/v1/images/build", bytes.NewReader(reqBody))
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		var res docker.ImageBuildResult
		json.NewDecoder(resp.Body).Decode(&res)

		for _, line := range res.Logs {
			fmt.Println(line)
		}

		if res.Success {
			fmt.Printf("\n✅ Successfully built %s (ID: %s) in %s\n", res.ImageTag, res.ImageID, res.Duration)
		} else {
			fmt.Printf("\n❌ Build failed: %s\n", res.Error)
			os.Exit(1)
		}
	},
}

var imageDistributeCmd = &cobra.Command{
	Use:   "distribute <image>",
	Short: "Distribute and load an image across all or targeted Centurion nodes",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		imageName := args[0]
		reqBody, _ := json.Marshal(docker.ImageDistributeRequest{
			Image:      imageName,
			TargetNode: imageNodeFlag,
		})

		fmt.Printf("🌐 Distributing image '%s' across cluster (target: %s)...\n", imageName, imageNodeFlag)
		resp, err := DoAPIRequest("POST", "/v1/images/distribute", bytes.NewReader(reqBody))
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		var res docker.ImageDistributeResult
		json.NewDecoder(resp.Body).Decode(&res)

		for node, status := range res.NodeResults {
			fmt.Printf("  • %-20s : %s\n", node, status)
		}

		if res.Success {
			fmt.Printf("\n✅ Successfully distributed %s across %d node(s) in %s\n", res.Image, len(res.TargetNodes), res.Duration)
		} else {
			fmt.Printf("\n⚠️ Distribution completed with warnings/errors: %s\n", res.Error)
		}
	},
}

func truncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	if maxLen <= 3 {
		return s[:maxLen]
	}
	return s[:maxLen-3] + "..."
}

func init() {
	imageLsCmd.Flags().StringVarP(&imageNodeFlag, "node", "n", "all", "Target node ID, IP, or 'all'")
	imageHistoryCmd.Flags().StringVarP(&imageNodeFlag, "node", "n", "manager", "Target node to inspect")
	imageRmCmd.Flags().StringVarP(&imageNodeFlag, "node", "n", "all", "Target node ID, IP, or 'all'")
	imageRmCmd.Flags().BoolVarP(&imageForceFlag, "force", "f", false, "Force removal of image")
	imagePruneCmd.Flags().StringVarP(&imageNodeFlag, "node", "n", "all", "Target node ID, IP, or 'all'")
	imagePruneCmd.Flags().BoolVarP(&imagePruneAllFlag, "all", "a", true, "Prune all unused images, not just dangling ones")

	imageBuildCmd.Flags().StringVarP(&imageBuildTagFlag, "tag", "t", "", "Target image tag (e.g. my-app:v1.0)")
	imageBuildCmd.Flags().StringVarP(&imageBuildFileFlag, "file", "f", "Dockerfile", "Path to Dockerfile")
	imageBuildCmd.Flags().StringVarP(&imageNodeFlag, "node", "n", "manager", "Target Centurion node to build on")
	imageBuildCmd.Flags().BoolVar(&imageNoCacheFlag, "no-cache", false, "Do not use cache when building image")

	imageDistributeCmd.Flags().StringVarP(&imageNodeFlag, "node", "n", "all", "Target Centurion node ID, IP, or 'all'")

	imageCmd.AddCommand(imageLsCmd)
	imageCmd.AddCommand(imageHistoryCmd)
	imageCmd.AddCommand(imageRmCmd)
	imageCmd.AddCommand(imagePruneCmd)
	imageCmd.AddCommand(imageBuildCmd)
	imageCmd.AddCommand(imageDistributeCmd)
}
