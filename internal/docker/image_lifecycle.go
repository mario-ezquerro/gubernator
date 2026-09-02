package docker

import (
	"fmt"
	"log/slog"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/mario-ezquerro/gubernator/internal/storage"
)

// HostDockerImage represents a physical Docker image stored on a cluster node.
type HostDockerImage struct {
	ID              string   `json:"id"`
	Repository      string   `json:"repository"`
	Tag             string   `json:"tag"`
	FullName        string   `json:"full_name"`
	Size            string   `json:"size"`
	SizeBytes       int64    `json:"size_bytes"`
	CreatedAt       string   `json:"created_at"`
	NodeID          string   `json:"node_id"`
	NodeName        string   `json:"node_name"`
	NodeIP          string   `json:"node_ip"`
	InUse           bool     `json:"in_use"`
	ContainersUsing []string `json:"containers_using"`
}

// ImageLayerInfo represents a single layer in the construction history of a Docker image.
type ImageLayerInfo struct {
	Order       int    `json:"order"`
	ID          string `json:"id"`
	CreatedBy   string `json:"created_by"`
	Instruction string `json:"instruction"` // RUN, ENV, COPY, EXPOSE, WORKDIR, FROM, etc.
	Args        string `json:"args"`
	Size        string `json:"size"`
	SizeBytes   int64  `json:"size_bytes"`
	CreatedAt   string `json:"created_at"`
	Comment     string `json:"comment"`
}

// ImageHistoryResponse is the full breakdown of an image's layers and reverse-engineered Dockerfile.
type ImageHistoryResponse struct {
	Image                  string           `json:"image"`
	ImageID                string           `json:"image_id"`
	NodeID                 string           `json:"node_id"`
	NodeName               string           `json:"node_name"`
	Layers                 []ImageLayerInfo `json:"layers"`
	ReconstructedDockerfile string           `json:"reconstructed_dockerfile"`
	TotalSizeBytes         int64            `json:"total_size_bytes"`
	TotalSize              string           `json:"total_size"`
}

// ImageRemoveResult represents the outcome of deleting an image from one or all cluster nodes.
type ImageRemoveResult struct {
	Image   string            `json:"image"`
	Success bool              `json:"success"`
	Message string            `json:"message"`
	Nodes   map[string]string `json:"nodes"` // NodeID -> status/error
}

// ImagePruneResult represents the outcome of running docker image prune across cluster nodes.
type ImagePruneResult struct {
	TotalImagesDeleted     int               `json:"total_images_deleted"`
	TotalSpaceReclaimed    string            `json:"total_space_reclaimed"`
	TotalSpaceReclaimedB   int64             `json:"total_space_reclaimed_bytes"`
	NodeResults            map[string]string `json:"node_results"` // NodeID -> summary
	Logs                   []string          `json:"logs"`
}

// ImageBuildRequest defines the parameters for building an image in The Imperial Forge.
type ImageBuildRequest struct {
	NodeID     string            `json:"node_id"`     // target host ID or "manager"
	Tag        string            `json:"tag"`         // e.g. "my-app:v1.0" or "postgres:16-custom"
	Dockerfile string            `json:"dockerfile"`  // raw Dockerfile string
	BuildArgs  map[string]string `json:"build_args"`  // ARG KEY=VAL
	NoCache    bool              `json:"no_cache"`
}

// ImageBuildResult captures the build execution logs and status.
type ImageBuildResult struct {
	Success   bool     `json:"success"`
	ImageTag  string   `json:"image_tag"`
	ImageID   string   `json:"image_id"`
	NodeID    string   `json:"node_id"`
	NodeName  string   `json:"node_name"`
	Duration  string   `json:"duration"`
	Logs      []string `json:"logs"`
	Error     string   `json:"error,omitempty"`
}

// ListClusterHostImages queries physical Docker images on the specified node or across all cluster nodes.
func ListClusterHostImages(targetNode string) ([]HostDockerImage, error) {
	nodes := resolveNodes(targetNode)
	if len(nodes) == 0 {
		return nil, fmt.Errorf("no target nodes found")
	}

	allImages := make([]HostDockerImage, 0)

	for _, n := range nodes {
		script := `
docker images --format '{{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}' 2>/dev/null
echo "---DIVIDER---"
docker ps -a --format '{{.Image}}\t{{.Names}}' 2>/dev/null
`
		out, err := storage.ExecuteRemoteScript(n.IP, script)
		if err != nil {
			slog.Warn("failed to query docker images on node", "node_id", n.ID, "ip", n.IP, "err", err)
			continue
		}

		parts := strings.Split(out, "---DIVIDER---")
		imagesPart := strings.TrimSpace(parts[0])
		containersPart := ""
		if len(parts) > 1 {
			containersPart = strings.TrimSpace(parts[1])
		}

		// Map image -> list of container names using it
		inUseMap := make(map[string][]string)
		for _, line := range strings.Split(containersPart, "\n") {
			line = strings.TrimSpace(line)
			if line == "" {
				continue
			}
			f := strings.Split(line, "\t")
			if len(f) >= 2 {
				img := strings.TrimSpace(f[0])
				ctr := strings.TrimSpace(f[1])
				inUseMap[img] = append(inUseMap[img], ctr)
			}
		}

		for _, line := range strings.Split(imagesPart, "\n") {
			line = strings.TrimSpace(line)
			if line == "" {
				continue
			}
			fields := strings.Split(line, "\t")
			if len(fields) < 4 {
				continue
			}

			id := strings.TrimSpace(fields[0])
			repo := strings.TrimSpace(fields[1])
			tag := strings.TrimSpace(fields[2])
			sizeStr := strings.TrimSpace(fields[3])
			createdAt := ""
			if len(fields) >= 5 {
				createdAt = strings.TrimSpace(fields[4])
			}

			fullName := repo
			if tag != "" && tag != "<none>" {
				fullName = repo + ":" + tag
			} else if repo == "<none>" {
				fullName = "<dangling:" + id[:min(12, len(id))] + ">"
			}

			// Check in-use status
			usingContainers := inUseMap[fullName]
			if len(usingContainers) == 0 && tag != "" && tag != "<none>" {
				usingContainers = inUseMap[repo]
			}
			if len(usingContainers) == 0 {
				usingContainers = inUseMap[id]
			}

			sizeBytes := parseSizeToBytes(sizeStr)

			allImages = append(allImages, HostDockerImage{
				ID:              id,
				Repository:      repo,
				Tag:             tag,
				FullName:        fullName,
				Size:            sizeStr,
				SizeBytes:       sizeBytes,
				CreatedAt:       createdAt,
				NodeID:          n.ID,
				NodeName:        nodeDisplayName(n),
				NodeIP:          n.IP,
				InUse:           len(usingContainers) > 0,
				ContainersUsing: usingContainers,
			})
		}
	}

	return allImages, nil
}

// InspectImageHistory inspects the layer history of an image and generates a reconstructed Dockerfile.
func InspectImageHistory(targetNode, image string) (*ImageHistoryResponse, error) {
	if image == "" {
		return nil, fmt.Errorf("image parameter is required")
	}

	nodes := resolveNodes(targetNode)
	if len(nodes) == 0 {
		return nil, fmt.Errorf("node not found")
	}
	target := nodes[0]

	script := fmt.Sprintf(`docker history --no-trunc --format '{{.ID}}\t{{.Size}}\t{{.CreatedAt}}\t{{.Comment}}\t{{.CreatedBy}}' %s 2>/dev/null`, image)
	out, err := storage.ExecuteRemoteScript(target.IP, script)
	targetName := nodeDisplayName(target)
	if err != nil || strings.TrimSpace(out) == "" {
		return nil, fmt.Errorf("failed to inspect history for image %s on node %s: %w", image, targetName, err)
	}

	lines := strings.Split(strings.TrimSpace(out), "\n")
	layers := make([]ImageLayerInfo, 0)
	var totalSizeBytes int64

	// docker history prints top layer first; reverse to get chronological (bottom-up) order
	for i, j := 0, len(lines)-1; i < j; i, j = i+1, j-1 {
		lines[i], lines[j] = lines[j], lines[i]
	}

	var dockerfileBuilder strings.Builder
	dockerfileBuilder.WriteString(fmt.Sprintf("# Reconstructed Dockerfile for %s\n", image))
	dockerfileBuilder.WriteString(fmt.Sprintf("# Inspected on node: %s (%s) at %s\n\n", targetName, target.IP, time.Now().Format(time.RFC3339)))

	for idx, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		fields := strings.SplitN(line, "\t", 5)
		if len(fields) < 5 {
			continue
		}

		layerID := strings.TrimSpace(fields[0])
		sizeStr := strings.TrimSpace(fields[1])
		createdAt := strings.TrimSpace(fields[2])
		comment := strings.TrimSpace(fields[3])
		createdBy := strings.TrimSpace(fields[4])

		sizeBytes := parseSizeToBytes(sizeStr)
		totalSizeBytes += sizeBytes

		instr, args := parseCreatedByInstruction(createdBy)

		layer := ImageLayerInfo{
			Order:       idx + 1,
			ID:          layerID,
			CreatedBy:   createdBy,
			Instruction: instr,
			Args:        args,
			Size:        sizeStr,
			SizeBytes:   sizeBytes,
			CreatedAt:   createdAt,
			Comment:     comment,
		}
		layers = append(layers, layer)

		// Format into clean Dockerfile lines
		if instr != "" && args != "" {
			dockerfileBuilder.WriteString(fmt.Sprintf("%-10s %s\n", instr, args))
		} else if strings.TrimSpace(createdBy) != "" {
			dockerfileBuilder.WriteString(fmt.Sprintf("# Layer %d (%s):\n# %s\n", idx+1, sizeStr, createdBy))
		}
	}

	return &ImageHistoryResponse{
		Image:                   image,
		ImageID:                 image,
		NodeID:                  target.ID,
		NodeName:                targetName,
		Layers:                  layers,
		ReconstructedDockerfile: dockerfileBuilder.String(),
		TotalSizeBytes:          totalSizeBytes,
		TotalSize:               formatBytes(totalSizeBytes),
	}, nil
}

// RemoveHostImage removes a Docker image from a specific node or all cluster nodes.
func RemoveHostImage(targetNode, image string, force bool) (*ImageRemoveResult, error) {
	if image == "" {
		return nil, fmt.Errorf("image parameter is required")
	}

	nodes := resolveNodes(targetNode)
	if len(nodes) == 0 {
		return nil, fmt.Errorf("no target nodes found")
	}

	forceFlag := ""
	if force {
		forceFlag = "-f"
	}

	results := make(map[string]string)
	allSuccess := true

	for _, n := range nodes {
		cmd := fmt.Sprintf("docker rmi %s %s 2>&1", forceFlag, image)
		out, err := storage.ExecuteRemoteScript(n.IP, cmd)
		nName := nodeDisplayName(n)
		if err != nil {
			allSuccess = false
			results[nName] = fmt.Sprintf("Failed: %s", out)
		} else {
			results[nName] = "Deleted successfully"
		}
	}

	return &ImageRemoveResult{
		Image:   image,
		Success: allSuccess,
		Message: fmt.Sprintf("Processed image removal across %d node(s)", len(nodes)),
		Nodes:   results,
	}, nil
}

// PruneHostImages prunes unused and dangling images across selected or all nodes.
func PruneHostImages(targetNode string, allUnused bool) (*ImagePruneResult, error) {
	nodes := resolveNodes(targetNode)
	if len(nodes) == 0 {
		return nil, fmt.Errorf("no target nodes found")
	}

	allFlag := ""
	if allUnused {
		allFlag = "-a"
	}

	results := make(map[string]string)
	logs := make([]string, 0)
	var totalDeleted int
	var totalReclaimedBytes int64

	reSpace := regexp.MustCompile(`Total reclaimed space:\s*([0-9.]+\s*[kMGTP]?B)`)
	reDeleted := regexp.MustCompile(`Deleted:\s*sha256:`)

	for _, n := range nodes {
		cmd := fmt.Sprintf("docker image prune %s -f 2>&1", allFlag)
		out, err := storage.ExecuteRemoteScript(n.IP, cmd)
		nName := nodeDisplayName(n)
		if err != nil {
			results[nName] = fmt.Sprintf("Error: %s", out)
			logs = append(logs, fmt.Sprintf("[%s] Prune failed: %v", nName, err))
			continue
		}

		deletedCount := len(reDeleted.FindAllString(out, -1))
		totalDeleted += deletedCount

		reclaimedStr := "0 B"
		if matches := reSpace.FindStringSubmatch(out); len(matches) > 1 {
			reclaimedStr = matches[1]
			totalReclaimedBytes += parseSizeToBytes(reclaimedStr)
		}

		summary := fmt.Sprintf("Deleted %d images, reclaimed %s", deletedCount, reclaimedStr)
		results[nName] = summary
		logs = append(logs, fmt.Sprintf("[%s] %s", nName, summary))
	}

	return &ImagePruneResult{
		TotalImagesDeleted:   totalDeleted,
		TotalSpaceReclaimed:  formatBytes(totalReclaimedBytes),
		TotalSpaceReclaimedB: totalReclaimedBytes,
		NodeResults:          results,
		Logs:                 logs,
	}, nil
}

// BuildHostImage builds a Docker image on the specified Centurion node using the provided Dockerfile.
func BuildHostImage(req ImageBuildRequest) (*ImageBuildResult, error) {
	if strings.TrimSpace(req.Tag) == "" {
		return nil, fmt.Errorf("target image tag is required")
	}
	if strings.TrimSpace(req.Dockerfile) == "" {
		return nil, fmt.Errorf("dockerfile content cannot be empty")
	}

	nodes := resolveNodes(req.NodeID)
	if len(nodes) == 0 {
		return nil, fmt.Errorf("target build node not found")
	}
	target := nodes[0]

	startTime := time.Now()
	buildID := fmt.Sprintf("gbnt-build-%d", time.Now().UnixNano())
	remoteWorkDir := filepath.Join("/tmp", buildID)

	// Prepare build command args
	buildArgsStr := ""
	for k, v := range req.BuildArgs {
		buildArgsStr += fmt.Sprintf(" --build-arg %s=%s", k, v)
	}
	noCacheFlag := ""
	if req.NoCache {
		noCacheFlag = " --no-cache"
	}

	// Escape Dockerfile content for shell script heredoc
	safeDockerfile := strings.ReplaceAll(req.Dockerfile, "$", "\\$")
	safeDockerfile = strings.ReplaceAll(safeDockerfile, "`", "\\`")

	script := fmt.Sprintf(`
mkdir -p %s && cd %s || exit 1
cat <<'EOF_DOCKERFILE' > Dockerfile
%s
EOF_DOCKERFILE
docker build -t %s%s%s . 2>&1
BUILD_STATUS=$?
cd /tmp && rm -rf %s
exit $BUILD_STATUS
`, remoteWorkDir, remoteWorkDir, safeDockerfile, req.Tag, buildArgsStr, noCacheFlag, remoteWorkDir)

	out, err := storage.ExecuteRemoteScript(target.IP, script)
	duration := time.Since(startTime).Round(time.Millisecond).String()

	logLines := strings.Split(strings.TrimSpace(out), "\n")

	// Extract built Image ID if successful
	reImgID := regexp.MustCompile(`Successfully built\s+([a-f0-9]+)|writing image sha256:([a-f0-9]+)`)
	imageID := ""
	if match := reImgID.FindStringSubmatch(out); len(match) > 1 {
		for _, m := range match[1:] {
			if m != "" {
				imageID = m
				break
			}
		}
	}
	if imageID == "" {
		imageID = req.Tag
	}

	success := err == nil
	errMsg := ""
	if err != nil {
		errMsg = err.Error()
	}

	return &ImageBuildResult{
		Success:  success,
		ImageTag: req.Tag,
		ImageID:  imageID,
		NodeID:   target.ID,
		NodeName: nodeDisplayName(target),
		Duration: duration,
		Logs:     logLines,
		Error:    errMsg,
	}, nil
}

// ── Helper Functions ──────────────────────────────────────────────────────────

func nodeDisplayName(n db.Node) string {
	if n.Labels != nil && n.Labels["gbnt.node.hostname"] != "" {
		return n.Labels["gbnt.node.hostname"]
	}
	if n.ID != "" {
		return n.ID
	}
	return n.IP
}

func resolveNodes(targetNode string) []db.Node {
	if db.DB == nil {
		return []db.Node{{ID: "manager", IP: "127.0.0.1", Role: "manager"}}
	}

	targetNode = strings.TrimSpace(strings.ToLower(targetNode))

	if targetNode == "" || targetNode == "all" || targetNode == "all-nodes" {
		var all []db.Node
		db.DB.Find(&all)
		if len(all) == 0 {
			all = append(all, db.Node{ID: "manager", IP: "127.0.0.1", Role: "manager"})
		}
		return all
	}

	if targetNode == "manager" || targetNode == "local" {
		var mgr db.Node
		if err := db.DB.Where("role = 'manager'").First(&mgr).Error; err == nil && mgr.IP != "" {
			return []db.Node{mgr}
		}
		return []db.Node{{ID: "manager", IP: "127.0.0.1", Role: "manager"}}
	}

	var node db.Node
	if err := db.DB.Where("id = ? OR ip = ?", targetNode, targetNode).First(&node).Error; err == nil && node.IP != "" {
		return []db.Node{node}
	}

	return []db.Node{{ID: targetNode, IP: targetNode, Role: "worker"}}
}

// parseCreatedByInstruction extracts Dockerfile instructions from docker history output.
func parseCreatedByInstruction(raw string) (instruction, args string) {
	raw = strings.TrimSpace(raw)
	raw = strings.TrimPrefix(raw, "/bin/sh -c ")
	if strings.HasPrefix(raw, "#(nop)") {
		raw = strings.TrimPrefix(raw, "#(nop)")
	}
	raw = strings.TrimSpace(raw)

	keywords := []string{"FROM", "RUN", "CMD", "LABEL", "MAINTAINER", "EXPOSE", "ENV", "ADD", "COPY", "ENTRYPOINT", "VOLUME", "USER", "WORKDIR", "ARG", "ONBUILD", "STOPSIGNAL", "HEALTHCHECK", "SHELL"}

	for _, kw := range keywords {
		prefix := kw + " "
		if strings.HasPrefix(strings.ToUpper(raw), prefix) {
			return kw, strings.TrimSpace(raw[len(prefix):])
		}
	}

	// Default fallback to RUN
	if len(raw) > 0 {
		return "RUN", raw
	}

	return "", ""
}

func parseSizeToBytes(s string) int64 {
	s = strings.TrimSpace(strings.ToUpper(s))
	if s == "" || s == "0B" || s == "0" {
		return 0
	}

	multiplier := int64(1)
	if strings.HasSuffix(s, "KB") || strings.HasSuffix(s, "K") {
		multiplier = 1024
		s = strings.TrimSuffix(strings.TrimSuffix(s, "KB"), "K")
	} else if strings.HasSuffix(s, "MB") || strings.HasSuffix(s, "M") {
		multiplier = 1024 * 1024
		s = strings.TrimSuffix(strings.TrimSuffix(s, "MB"), "M")
	} else if strings.HasSuffix(s, "GB") || strings.HasSuffix(s, "G") {
		multiplier = 1024 * 1024 * 1024
		s = strings.TrimSuffix(strings.TrimSuffix(s, "GB"), "G")
	} else if strings.HasSuffix(s, "TB") || strings.HasSuffix(s, "T") {
		multiplier = 1024 * 1024 * 1024 * 1024
		s = strings.TrimSuffix(strings.TrimSuffix(s, "TB"), "T")
	} else if strings.HasSuffix(s, "B") {
		s = strings.TrimSuffix(s, "B")
	}

	val, err := strconv.ParseFloat(strings.TrimSpace(s), 64)
	if err != nil {
		return 0
	}
	return int64(val * float64(multiplier))
}

func formatBytes(b int64) string {
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

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
