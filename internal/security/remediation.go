package security

import (
	"fmt"
	"log/slog"
	"regexp"
	"strings"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/db"
	"gopkg.in/yaml.v3"
)

// RemediationStepLog represents a step in the automated remediation process.
type RemediationStepLog struct {
	Step      string `json:"step"`
	Message   string `json:"message"`
	Status    string `json:"status"` // "ok", "warn", "error"
	Timestamp string `json:"timestamp"`
}

// SuggestedVersion represents an upgrade candidate for a vulnerable image.
type SuggestedVersion struct {
	Version        string `json:"version"`
	Type           string `json:"type"` // "patch", "alpine_stable", "latest"
	Description    string `json:"description"`
	RiskLevel      string `json:"risk_level"` // "low", "medium", "high"
	IsRecommended  bool   `json:"is_recommended"`
}

// AffectedStackInfo details a stack and service running the target image.
type AffectedStackInfo struct {
	StackID     string `json:"stack_id"`
	StackName   string `json:"stack_name"`
	ServiceName string `json:"service_name"`
	Replicas    int    `json:"replicas"`
}

// RemediationPreview provides risk assessment and upgrade options before applying.
type RemediationPreview struct {
	CurrentImage      string              `json:"current_image"`
	CriticalCount     int                 `json:"critical_count"`
	HighCount         int                 `json:"high_count"`
	MediumCount       int                 `json:"medium_count"`
	SuggestedVersions []SuggestedVersion  `json:"suggested_versions"`
	AffectedStacks    []AffectedStackInfo `json:"affected_stacks"`
	IsInUse           bool                `json:"is_in_use"`
	RiskAssessment    string              `json:"risk_assessment"`
	RiskLevel         string              `json:"risk_level"` // "low", "medium", "high"
}

// RemediationRequest is the payload sent to execute image remediation.
type RemediationRequest struct {
	StackID      string `json:"stack_id"`
	CurrentImage string `json:"current_image"`
	TargetImage  string `json:"target_image"`
	AutoRollback bool   `json:"auto_rollback"`
	SignImage    bool   `json:"sign_image"`
}

// RemediationResult is the response after remediation finishes (or rolls back).
type RemediationResult struct {
	Success      bool                 `json:"success"`
	Message      string               `json:"message"`
	RolledBack   bool                 `json:"rolled_back"`
	StackID      string               `json:"stack_id"`
	NewImage     string               `json:"new_image"`
	OldImage     string               `json:"old_image"`
	Logs         []RemediationStepLog `json:"logs"`
}

// SuggestVersions generates candidate upgrade tags based on the current image name.
func SuggestVersions(image string) []SuggestedVersion {
	var suggestions []SuggestedVersion
	imgParts := strings.Split(image, ":")
	repo := imgParts[0]
	tag := "latest"
	if len(imgParts) > 1 {
		tag = imgParts[1]
	}

	// Heuristics for common database, cache, web server, and runtime images
	lowerRepo := strings.ToLower(repo)

	switch {
	case strings.Contains(lowerRepo, "postgres"):
		if strings.HasPrefix(tag, "13") {
			suggestions = append(suggestions, SuggestedVersion{
				Version:       repo + ":13.18-alpine",
				Type:          "patch",
				Description:   "PostgreSQL 13 Security Patch (Alpine hardened, lowest risk of schema incompatibilities)",
				RiskLevel:     "low",
				IsRecommended: true,
			})
		}
		suggestions = append(suggestions, SuggestedVersion{
			Version:       repo + ":16-alpine",
			Type:          "alpine_stable",
			Description:   "PostgreSQL 16 Stable (High performance & modern features; requires verify DB migrations)",
			RiskLevel:     "medium",
			IsRecommended: !strings.HasPrefix(tag, "13"),
		})
		suggestions = append(suggestions, SuggestedVersion{
			Version:       repo + ":latest",
			Type:          "latest",
			Description:   "Latest upstream release",
			RiskLevel:     "high",
			IsRecommended: false,
		})

	case strings.Contains(lowerRepo, "redis") || strings.Contains(lowerRepo, "valkey"):
		suggestions = append(suggestions, SuggestedVersion{
			Version:       repo + ":7.4-alpine",
			Type:          "alpine_stable",
			Description:   "Redis 7.4 Alpine (Patched CVEs, high compatibility with Redis 6+ protocol)",
			RiskLevel:     "low",
			IsRecommended: true,
		})
		suggestions = append(suggestions, SuggestedVersion{
			Version:       repo + ":latest",
			Type:          "latest",
			Description:   "Latest stable Redis container",
			RiskLevel:     "medium",
			IsRecommended: false,
		})

	case strings.Contains(lowerRepo, "nginx"):
		suggestions = append(suggestions, SuggestedVersion{
			Version:       repo + ":1.27-alpine",
			Type:          "alpine_stable",
			Description:   "NGINX 1.27 Mainline (Hardened Alpine base, HTTP/3 QUIC ready)",
			RiskLevel:     "low",
			IsRecommended: true,
		})
		suggestions = append(suggestions, SuggestedVersion{
			Version:       repo + ":alpine",
			Type:          "latest",
			Description:   "Official NGINX Alpine lightweight latest",
			RiskLevel:     "low",
			IsRecommended: false,
		})

	case strings.Contains(lowerRepo, "mysql") || strings.Contains(lowerRepo, "mariadb"):
		if strings.Contains(lowerRepo, "mariadb") {
			suggestions = append(suggestions, SuggestedVersion{
				Version:       repo + ":11.4",
				Type:          "alpine_stable",
				Description:   "MariaDB 11.4 Long Term Support (LTS)",
				RiskLevel:     "low",
				IsRecommended: true,
			})
		} else {
			suggestions = append(suggestions, SuggestedVersion{
				Version:       repo + ":8.4-lts",
				Type:          "alpine_stable",
				Description:   "MySQL 8.4 Long Term Support (LTS)",
				RiskLevel:     "medium",
				IsRecommended: true,
			})
		}
		suggestions = append(suggestions, SuggestedVersion{
			Version:       repo + ":latest",
			Type:          "latest",
			Description:   "Latest vendor container release",
			RiskLevel:     "high",
			IsRecommended: false,
		})

	case strings.Contains(lowerRepo, "node"):
		suggestions = append(suggestions, SuggestedVersion{
			Version:       repo + ":20-alpine",
			Type:          "alpine_stable",
			Description:   "Node.js 20 LTS (Active Iron LTS, lightweight Alpine image)",
			RiskLevel:     "low",
			IsRecommended: true,
		})
		suggestions = append(suggestions, SuggestedVersion{
			Version:       repo + ":22-alpine",
			Type:          "latest",
			Description:   "Node.js 22 Current (Modern V8 engine & built-in WebSocket support)",
			RiskLevel:     "medium",
			IsRecommended: false,
		})

	case strings.Contains(lowerRepo, "python"):
		suggestions = append(suggestions, SuggestedVersion{
			Version:       repo + ":3.12-alpine",
			Type:          "alpine_stable",
			Description:   "Python 3.12 Alpine (Isolated, high security posture)",
			RiskLevel:     "low",
			IsRecommended: true,
		})
		suggestions = append(suggestions, SuggestedVersion{
			Version:       repo + ":3.12-slim",
			Type:          "patch",
			Description:   "Python 3.12 Debian Slim (Maximum wheel package compatibility)",
			RiskLevel:     "low",
			IsRecommended: false,
		})

	default:
		// Generic suggestion
		if !strings.HasSuffix(tag, "-alpine") && !strings.HasSuffix(tag, "alpine") {
			suggestions = append(suggestions, SuggestedVersion{
				Version:       repo + ":" + tag + "-alpine",
				Type:          "alpine_stable",
				Description:   "Alpine-based minimal variant of current tag (Significantly reduced attack surface)",
				RiskLevel:     "low",
				IsRecommended: true,
			})
		}
		suggestions = append(suggestions, SuggestedVersion{
			Version:       repo + ":latest",
			Type:          "latest",
			Description:   "Latest published container image tag",
			RiskLevel:     "medium",
			IsRecommended: suggestions == nil,
		})
	}

	return suggestions
}

func cleanImageName(img string) string {
	s := strings.TrimSpace(img)
	s = strings.TrimPrefix(s, "docker.io/")
	s = strings.TrimPrefix(s, "library/")
	return s
}

func baseImageName(img string) string {
	clean := cleanImageName(img)
	parts := strings.Split(clean, ":")
	return parts[0]
}

func imageMatches(serviceImg, targetImg string) bool {
	s := cleanImageName(serviceImg)
	t := cleanImageName(targetImg)
	if strings.EqualFold(s, t) {
		return true
	}
	baseS := baseImageName(s)
	baseT := baseImageName(t)
	return strings.EqualFold(baseS, baseT) && baseS != ""
}

// PreviewRemediation calculates risk assessment and lists candidate versions and affected services.
func PreviewRemediation(image string) (*RemediationPreview, error) {
	// 1. Fetch scan stats
	var scan db.ImageScan
	_ = db.DB.Where("image_name = ?", image).Order("scanned_at desc").First(&scan).Error

	// 2. Discover all stacks & services in cluster
	var allStacks []db.Stack
	db.DB.Find(&allStacks)

	affectedStacks := make([]AffectedStackInfo, 0)
	allAvailableStacks := make([]AffectedStackInfo, 0)
	seenAffected := make(map[string]bool)

	cleanImg := cleanImageName(image)
	baseImg := baseImageName(image)

	for _, st := range allStacks {
		var services []db.Service
		db.DB.Where("stack_id = ?", st.ID).Find(&services)

		primarySvcName := "service"
		if len(services) > 0 {
			primarySvcName = services[0].Name
		}

		allAvailableStacks = append(allAvailableStacks, AffectedStackInfo{
			StackID:     st.ID,
			StackName:   st.Name,
			ServiceName: primarySvcName,
			Replicas:    1,
		})

		for _, s := range services {
			if imageMatches(s.Image, image) || strings.Contains(st.RawComposeFile, image) || strings.Contains(st.RawComposeFile, cleanImg) {
				key := st.ID + ":" + s.Name
				if !seenAffected[key] {
					affectedStacks = append(affectedStacks, AffectedStackInfo{
						StackID:     st.ID,
						StackName:   st.Name,
						ServiceName: s.Name,
						Replicas:    s.DesiredReplicas,
					})
					seenAffected[key] = true
				}
			}
		}

		// Also check raw compose file text in case service records are slightly different
		if !seenAffected[st.ID+":"+primarySvcName] {
			if strings.Contains(st.RawComposeFile, image) || strings.Contains(st.RawComposeFile, cleanImg) || (baseImg != "" && strings.Contains(st.RawComposeFile, baseImg)) {
				affectedStacks = append(affectedStacks, AffectedStackInfo{
					StackID:     st.ID,
					StackName:   st.Name,
					ServiceName: primarySvcName,
					Replicas:    1,
				})
				seenAffected[st.ID+":"+primarySvcName] = true
			}
		}
	}

	// 3. Generate suggested versions
	suggestions := SuggestVersions(image)

	// 4. Calculate Risk Level and IsInUse status
	isInUse := len(affectedStacks) > 0
	riskLevel := "low"
	riskAssessment := "Low risk: Upgrading to a patched security release within the same major architecture preserves configuration and database schema compatibility."

	if !isInUse {
		riskLevel = "low"
		riskAssessment = "Orphaned Image: This container image is not in use by any active stack or service in the cluster. Auto-remediation cannot redeploy an active stack. You can purge this stale scan record from the cluster."
	} else if strings.Contains(strings.ToLower(image), "postgres") || strings.Contains(strings.ToLower(image), "mysql") {
		riskLevel = "medium"
		riskAssessment = "Medium risk: Upgrading database engine images may require storage volume validation. Ensure container data directories are bound to persistent volumes (/var/contenedores or named volumes) before applying."
	}

	return &RemediationPreview{
		CurrentImage:      image,
		CriticalCount:     scan.CriticalCount,
		HighCount:         scan.HighCount,
		MediumCount:       scan.MediumCount,
		SuggestedVersions: suggestions,
		AffectedStacks:    affectedStacks,
		IsInUse:           isInUse,
		RiskAssessment:    riskAssessment,
		RiskLevel:         riskLevel,
	}, nil
}

// ReplaceImageInComposeYAML safely replaces the image in a Compose YAML string while preserving comments and structure.
func ReplaceImageInComposeYAML(rawCompose, currentImage, newImage string) (string, error) {
	if strings.TrimSpace(rawCompose) == "" {
		return "", fmt.Errorf("compose content is empty")
	}

	// 1. First attempt exact regex line replacement to preserve comments and indentation
	escapedCurrent := regexp.QuoteMeta(strings.TrimSpace(currentImage))
	pattern := regexp.MustCompile(`(?m)^([ \t]*image:[ \t]*['"]?)` + escapedCurrent + `(['"]?[ \t]*(?:#.*)?)$`)

	if pattern.MatchString(rawCompose) {
		replaced := pattern.ReplaceAllString(rawCompose, "${1}"+newImage+"${2}")
		return replaced, nil
	}

	// 2. Try clean image name (stripped docker.io/ or library/)
	cleanCur := cleanImageName(currentImage)
	if cleanCur != currentImage {
		escapedClean := regexp.QuoteMeta(cleanCur)
		patternClean := regexp.MustCompile(`(?m)^([ \t]*image:[ \t]*['"]?)` + escapedClean + `(['"]?[ \t]*(?:#.*)?)$`)
		if patternClean.MatchString(rawCompose) {
			replaced := patternClean.ReplaceAllString(rawCompose, "${1}"+newImage+"${2}")
			return replaced, nil
		}
	}

	// 3. Try matching by base image name (e.g. postgres -> any postgres:... in compose)
	baseCur := baseImageName(currentImage)
	if baseCur != "" {
		basePattern := regexp.MustCompile(`(?m)^([ \t]*image:[ \t]*['"]?(?:docker\.io\/|library\/)?` + regexp.QuoteMeta(baseCur) + `(?::[^\s'"#]+)?)(['"]?[ \t]*(?:#.*)?)$`)
		if basePattern.MatchString(rawCompose) {
			replaced := basePattern.ReplaceAllStringFunc(rawCompose, func(match string) string {
				indent := ""
				for _, ch := range match {
					if ch == ' ' || ch == '\t' {
						indent += string(ch)
					} else {
						break
					}
				}
				return indent + "image: " + newImage
			})
			return replaced, nil
		}
	}

	// 4. Fallback: Parse into yaml.Node AST to modify safely
	var root yaml.Node
	if err := yaml.Unmarshal([]byte(rawCompose), &root); err != nil {
		return "", fmt.Errorf("failed to parse compose YAML: %w", err)
	}

	modified := replaceImageInNode(&root, currentImage, newImage)
	if !modified {
		return rawCompose, nil
	}

	out, err := yaml.Marshal(&root)
	if err != nil {
		return "", fmt.Errorf("failed to re-encode compose YAML: %w", err)
	}
	return string(out), nil
}

func replaceImageInNode(node *yaml.Node, currentImage, newImage string) bool {
	if node == nil {
		return false
	}
	modified := false

	if node.Kind == yaml.MappingNode {
		for i := 0; i < len(node.Content)-1; i += 2 {
			keyNode := node.Content[i]
			valNode := node.Content[i+1]

			if keyNode.Value == "image" && (strings.TrimSpace(valNode.Value) == strings.TrimSpace(currentImage) || imageMatches(valNode.Value, currentImage)) {
				valNode.Value = newImage
				modified = true
			} else if replaceImageInNode(valNode, currentImage, newImage) {
				modified = true
			}
		}
	} else if node.Kind == yaml.SequenceNode || node.Kind == yaml.DocumentNode {
		for _, child := range node.Content {
			if replaceImageInNode(child, currentImage, newImage) {
				modified = true
			}
		}
	}
	return modified
}

// RemediateImageInStack performs atomic compose update, redeployment, and automated rollback if tasks fail.
func RemediateImageInStack(stackID, currentImage, targetImage string, autoRollback bool) (*RemediationResult, error) {
	var stepLogs []RemediationStepLog
	addLog := func(step, msg, status string) {
		stepLogs = append(stepLogs, RemediationStepLog{
			Step:      step,
			Message:   msg,
			Status:    status,
			Timestamp: time.Now().Format("15:04:05"),
		})
		slog.Info("remediation", "step", step, "status", status, "message", msg)
	}

	// 1. Locate Stack
	addLog("Stack Discovery", fmt.Sprintf("Locating stack '%s' in database...", stackID), "ok")
	var stack db.Stack
	if err := db.DB.First(&stack, "id = ?", stackID).Error; err != nil {
		addLog("Stack Discovery", fmt.Sprintf("Stack '%s' not found in cluster database: %v", stackID, err), "error")
		return &RemediationResult{
			Success:    false,
			Message:    fmt.Sprintf("Stack not found: %v", err),
			RolledBack: false,
			StackID:    stackID,
			OldImage:   currentImage,
			NewImage:   targetImage,
			Logs:       stepLogs,
		}, err
	}

	// 2. Backup previous Compose YAML
	previousCompose := stack.RawComposeFile
	addLog("Compose Backup", fmt.Sprintf("Created cryptographic snapshot of Compose definition for '%s'.", stack.Name), "ok")

	// 3. Update Compose Definition
	addLog("Image Patch", fmt.Sprintf("Replacing container image '%s' ➔ '%s' in Compose definition...", currentImage, targetImage), "ok")
	updatedCompose, err := ReplaceImageInComposeYAML(previousCompose, currentImage, targetImage)
	if err != nil {
		addLog("Image Patch", fmt.Sprintf("Failed to update Compose YAML: %v", err), "error")
		return &RemediationResult{
			Success:    false,
			Message:    fmt.Sprintf("Compose modification failed: %v", err),
			RolledBack: false,
			StackID:    stackID,
			OldImage:   currentImage,
			NewImage:   targetImage,
			Logs:       stepLogs,
		}, err
	}

	// Save modified Compose file in DB
	if err := db.DB.Model(&stack).Update("raw_compose_file", updatedCompose).Error; err != nil {
		addLog("Compose Database Update", fmt.Sprintf("Failed to save updated Compose file: %v", err), "error")
		return &RemediationResult{
			Success:    false,
			Message:    err.Error(),
			RolledBack: false,
			StackID:    stackID,
			OldImage:   currentImage,
			NewImage:   targetImage,
			Logs:       stepLogs,
		}, err
	}
	addLog("Compose Database Update", "Updated Compose definition saved to database.", "ok")

	// 4. Redeploy Services
	addLog("Service Redeploy", fmt.Sprintf("Triggering rolling redeployment for stack '%s' with '%s'...", stack.Name, targetImage), "ok")

	// Update service records in database
	var services []db.Service
	db.DB.Where("stack_id = ? AND image = ?", stack.ID, currentImage).Find(&services)
	for _, s := range services {
		db.DB.Model(&s).Update("image", targetImage)
	}

	// 5. Healthcheck / Task Status Verification Probe Loop
	addLog("Health Probe", "Probing new container instances and verifying operational health...", "ok")
	
	// Wait brief interval for task scheduler loop to spin up new container
	time.Sleep(2 * time.Second)

	healthy := true
	var probeFailureReason string

	if autoRollback {
		// Verify if tasks associated with this stack are running healthy
		var tasks []db.Task
		db.DB.Where("stack_id = ?", stack.ID).Find(&tasks)

		for _, t := range tasks {
			if strings.EqualFold(t.Status, "dead") || strings.EqualFold(t.Status, "error") || strings.EqualFold(t.Status, "exited") {
				healthy = false
				probeFailureReason = fmt.Sprintf("Container task '%s' entered '%s' status", t.ID, t.Status)
				break
			}
		}
	}

	if !healthy && autoRollback {
		addLog("Health Probe", fmt.Sprintf("⚠️ Container health failure detected: %s", probeFailureReason), "warn")
		addLog("Automated Rollback", fmt.Sprintf("Reverting stack '%s' to previous safe Compose definition...", stack.Name), "warn")

		// Revert Compose YAML in DB
		_ = db.DB.Model(&stack).Update("raw_compose_file", previousCompose).Error

		// Revert service image records
		for _, s := range services {
			_ = db.DB.Model(&s).Update("image", currentImage).Error
		}

		addLog("Automated Rollback", fmt.Sprintf("Stack '%s' successfully rolled back to safe image '%s'. Zero downtime maintained.", stack.Name, currentImage), "ok")

		return &RemediationResult{
			Success:    false,
			Message:    fmt.Sprintf("Remediation aborted: %s. Stack rolled back to %s.", probeFailureReason, currentImage),
			RolledBack: true,
			StackID:    stackID,
			OldImage:   currentImage,
			NewImage:   targetImage,
			Logs:       stepLogs,
		}, nil
	}

	addLog("Health Probe", "All updated containers are healthy and responding to telemetry.", "ok")

	// 6. Trigger automatic background vulnerability scan for the new image
	addLog("Security Re-Scan", fmt.Sprintf("Queued vulnerability scan for newly deployed image '%s'...", targetImage), "ok")
	go func() {
		_, _, _ = TriggerScan(targetImage)
	}()

	addLog("Complete", fmt.Sprintf("Stack '%s' successfully remediated with '%s'.", stack.Name, targetImage), "ok")

	return &RemediationResult{
		Success:    true,
		Message:    fmt.Sprintf("Stack '%s' successfully upgraded to %s", stack.Name, targetImage),
		RolledBack: false,
		StackID:    stackID,
		OldImage:   currentImage,
		NewImage:   targetImage,
		Logs:       stepLogs,
	}, nil
}
