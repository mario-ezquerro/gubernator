package autoscaler

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/mario-ezquerro/gubernator/internal/docker"
)

// Label constants for declarative Compose autoscaling
const (
	LabelEnable   = "gbnt.autoscaling.enable"
	LabelScope    = "gbnt.autoscaling.scope"    // "host" (local) or "cluster" (all)
	LabelMetric   = "gbnt.autoscaling.metric"   // "gpu" or "cpu"
	LabelTarget   = "gbnt.autoscaling.target"   // target percentage (e.g. "80")
	LabelMin      = "gbnt.autoscaling.min"      // min replicas (e.g. "1")
	LabelMax      = "gbnt.autoscaling.max"      // max replicas (e.g. "5")
	LabelCooldown = "gbnt.autoscaling.cooldown" // cooldown duration (e.g. "60s")
)

// AutoscalePolicy represents parsed autoscaling configuration for a service.
type AutoscalePolicy struct {
	Enabled        bool          `json:"enabled"`
	Scope          string        `json:"scope"`            // "host" or "cluster"
	Metric         string        `json:"metric"`           // "gpu" or "cpu"
	Target         float64       `json:"target"`           // default 80.0
	Min            int           `json:"min"`              // default 1
	Max            int           `json:"max"`              // default 5
	Cooldown       time.Duration `json:"cooldown"`         // default 60s
	PinnedHost     string        `json:"pinned_host"`      // pinned hostname or node ID if affinity locked
	SingleHostOnly bool          `json:"single_host_only"` // true if constrained to single host
}

// ScaleEventInfo holds details of the latest scaling activity.
type ScaleEventInfo struct {
	ServiceID    string    `json:"service_id"`
	ServiceName  string    `json:"service_name"`
	Metric       string    `json:"metric"`
	CurrentVal   float64   `json:"current_val"`
	TargetVal    float64   `json:"target_val"`
	OldReplicas  int       `json:"old_replicas"`
	NewReplicas  int       `json:"new_replicas"`
	Scope        string    `json:"scope"`
	Reason       string    `json:"reason"`
	Timestamp    time.Time `json:"timestamp"`
}

var (
	cooldownMu      sync.RWMutex
	lastScaleEvents = make(map[string]time.Time)

	historyMu       sync.RWMutex
	scalingHistory  = make([]ScaleEventInfo, 0, 50)
)

// ParseAutoscalePolicy parses service placement/labels constraints into an AutoscalePolicy,
// rigorously evaluating placement strategies (single-host vs spread/multi-host) and host affinity.
func ParseAutoscalePolicy(constraints []string) *AutoscalePolicy {
	policy := &AutoscalePolicy{
		Enabled:  false,
		Scope:    "host",
		Metric:   "cpu",
		Target:   80.0,
		Min:      1,
		Max:      5,
		Cooldown: 60 * time.Second,
	}

	var explicitScope bool
	var placementStrategy string

	for _, c := range constraints {
		// Check "==" operator for deploy placement constraints
		if parts := strings.Split(c, "=="); len(parts) == 2 {
			left := strings.ToLower(strings.TrimSpace(parts[0]))
			val := strings.TrimSpace(parts[1])
			if left == "node.hostname" || left == "gbnt.node.hostname" || left == "node.id" || left == "gbnt.node.id" {
				policy.PinnedHost = val
				policy.SingleHostOnly = true
			}
			continue
		}

		parts := strings.SplitN(c, "=", 2)
		if len(parts) != 2 {
			parts = strings.SplitN(c, ":", 2)
		}
		if len(parts) != 2 {
			continue
		}
		key := strings.ToLower(strings.TrimSpace(parts[0]))
		val := strings.ToLower(strings.TrimSpace(parts[1]))

		switch key {
		case LabelEnable:
			policy.Enabled = (val == "true" || val == "1" || val == "yes")
		case LabelScope:
			explicitScope = true
			if val == "cluster" || val == "all" || val == "multi-host" {
				policy.Scope = "cluster"
			} else {
				policy.Scope = "host"
			}
		case "gbnt.placement.strategy":
			placementStrategy = val
		case LabelMetric:
			if strings.Contains(val, "gpu") || strings.Contains(val, "cuda") || strings.Contains(val, "nvidia") {
				policy.Metric = "gpu"
			} else {
				policy.Metric = "cpu"
			}
		case LabelTarget:
			if t, err := strconv.ParseFloat(val, 64); err == nil && t > 0 {
				policy.Target = t
			}
		case LabelMin:
			if m, err := strconv.Atoi(val); err == nil && m >= 1 {
				policy.Min = m
			}
		case LabelMax:
			if m, err := strconv.Atoi(val); err == nil && m >= 1 {
				policy.Max = m
			}
		case LabelCooldown:
			if d, err := time.ParseDuration(val); err == nil && d > 0 {
				policy.Cooldown = d
			}
		}
	}

	// Affinity and placement strategy overrides:
	// 1. If explicit single-host placement strategy or pinned to a specific host, force host scope
	if placementStrategy == "single-host" || policy.PinnedHost != "" {
		policy.Scope = "host"
		policy.SingleHostOnly = true
	} else if (placementStrategy == "spread" || placementStrategy == "multi-host") && !explicitScope {
		// If placement strategy indicates spread/multi-host and scope wasn't explicitly pinned to host, default to cluster
		policy.Scope = "cluster"
	}

	if policy.Min > policy.Max {
		policy.Max = policy.Min
	}

	return policy
}

// CanScale checks whether the cooldown period has elapsed since the last scaling event.
func CanScale(serviceID string, cooldown time.Duration) bool {
	cooldownMu.RLock()
	last, exists := lastScaleEvents[serviceID]
	cooldownMu.RUnlock()
	if !exists {
		return true
	}
	return time.Since(last) >= cooldown
}

// RecordScaleEvent records a scaling timestamp and history entry.
func RecordScaleEvent(event ScaleEventInfo) {
	cooldownMu.Lock()
	lastScaleEvents[event.ServiceID] = event.Timestamp
	cooldownMu.Unlock()

	historyMu.Lock()
	if len(scalingHistory) >= 50 {
		scalingHistory = scalingHistory[1:]
	}
	scalingHistory = append(scalingHistory, event)
	historyMu.Unlock()
}

// GetScalingHistory returns recent scaling events.
func GetScalingHistory() []ScaleEventInfo {
	historyMu.RLock()
	defer historyMu.RUnlock()
	res := make([]ScaleEventInfo, len(scalingHistory))
	copy(res, scalingHistory)
	return res
}

// EvaluateAndAutoscale evaluates all services across stacks and executes auto-scaling.
func EvaluateAndAutoscale() (scaledCount int) {
	var services []db.Service
	if err := db.DB.Find(&services).Error; err != nil {
		return 0
	}

	for _, svc := range services {
		policy := ParseAutoscalePolicy(svc.Constraints)
		if !policy.Enabled {
			continue
		}

		if !CanScale(svc.ID, policy.Cooldown) {
			continue
		}

		// Fetch all tasks for this service
		var tasks []db.Task
		if err := db.DB.Where("service_id = ?", svc.ID).Find(&tasks).Error; err != nil || len(tasks) == 0 {
			continue
		}

		runningTasks := make([]db.Task, 0, len(tasks))
		for _, t := range tasks {
			if t.Status == "running" {
				runningTasks = append(runningTasks, t)
			}
		}
		if len(runningTasks) == 0 {
			continue
		}

		// Calculate current utilization metric
		currentVal := ResolveCurrentMetric(&svc, runningTasks, policy.Metric)
		desired := svc.DesiredReplicas
		if desired <= 0 {
			desired = 1
		}

		// Scaling decision
		if currentVal >= policy.Target && desired < policy.Max {
			newReplicas := desired + 1
			slog.Info("autoscaler: scaling up",
				"service", svc.Name,
				"metric", policy.Metric,
				"current_val", fmt.Sprintf("%.1f%%", currentVal),
				"target", fmt.Sprintf("%.1f%%", policy.Target),
				"from", desired,
				"to", newReplicas,
				"scope", policy.Scope,
			)

			if err := ExecuteScaleUp(&svc, runningTasks, policy, newReplicas); err == nil {
				scaledCount++
				RecordScaleEvent(ScaleEventInfo{
					ServiceID:   svc.ID,
					ServiceName: svc.Name,
					Metric:      policy.Metric,
					CurrentVal:  currentVal,
					TargetVal:   policy.Target,
					OldReplicas: desired,
					NewReplicas: newReplicas,
					Scope:       policy.Scope,
					Reason:      fmt.Sprintf("%s utilization %.1f%% exceeded target %.1f%%", strings.ToUpper(policy.Metric), currentVal, policy.Target),
					Timestamp:   time.Now(),
				})
			}
		} else if currentVal < (policy.Target*0.4) && desired > policy.Min {
			// Scale down threshold: less than 40% of target
			newReplicas := desired - 1
			slog.Info("autoscaler: scaling down",
				"service", svc.Name,
				"metric", policy.Metric,
				"current_val", fmt.Sprintf("%.1f%%", currentVal),
				"target", fmt.Sprintf("%.1f%%", policy.Target),
				"from", desired,
				"to", newReplicas,
				"scope", policy.Scope,
			)

			if err := ExecuteScaleDown(&svc, tasks, newReplicas); err == nil {
				scaledCount++
				RecordScaleEvent(ScaleEventInfo{
					ServiceID:   svc.ID,
					ServiceName: svc.Name,
					Metric:      policy.Metric,
					CurrentVal:  currentVal,
					TargetVal:   policy.Target,
					OldReplicas: desired,
					NewReplicas: newReplicas,
					Scope:       policy.Scope,
					Reason:      fmt.Sprintf("%s utilization %.1f%% below scale-down threshold %.1f%%", strings.ToUpper(policy.Metric), currentVal, policy.Target*0.4),
					Timestamp:   time.Now(),
				})
			}
		}
	}

	return scaledCount
}

// ResolveCurrentMetric resolves the average utilization percentage for the given metric (CPU or GPU).
func ResolveCurrentMetric(svc *db.Service, runningTasks []db.Task, metric string) float64 {
	if metric == "gpu" {
		return resolveGPUMetric(svc, runningTasks)
	}
	return resolveCPUMetric(runningTasks)
}

func resolveCPUMetric(runningTasks []db.Task) float64 {
	if len(runningTasks) == 0 {
		return 0.0
	}
	var totalCPU float64
	var counted int
	for _, t := range runningTasks {
		if t.CpuPercent > 0 {
			totalCPU += t.CpuPercent
			counted++
		}
	}
	if counted > 0 {
		return totalCPU / float64(counted)
	}

	// Direct query from Prometheus as fallback
	query := `avg(rate(container_cpu_usage_seconds_total{container!=""}[1m])) * 100`
	if val := queryPrometheusScalar(query); val > 0 {
		return val
	}

	return 0.0
}

func resolveGPUMetric(svc *db.Service, runningTasks []db.Task) float64 {
	// 1. Query Prometheus for container or node GPU metrics (cAdvisor / DCGM)
	queries := []string{
		fmt.Sprintf(`avg(container_gpu_utilization{container=~".*%s.*"})`, svc.Name),
		`avg(DCGM_FI_DEV_GPU_UTIL)`,
		`avg(nvidia_smi_utilization_gpu_ratio) * 100`,
	}

	for _, q := range queries {
		if val := queryPrometheusScalar(q); val > 0 {
			return val
		}
	}

	// 2. Hardware heuristic: If task is running on GPU node and CPU is high, estimate GPU load proportionally
	var onGPUNode bool
	var activeNodes []db.Node
	db.DB.Find(&activeNodes)
	nodeMap := make(map[string]db.Node)
	for _, n := range activeNodes {
		nodeMap[n.ID] = n
	}

	for _, t := range runningTasks {
		if n, ok := nodeMap[t.NodeID]; ok && docker.NodeHasGPU(n) {
			onGPUNode = true
			break
		}
	}

	if onGPUNode {
		cpuVal := resolveCPUMetric(runningTasks)
		return cpuVal * 1.1
	}

	return 0.0
}

func queryPrometheusScalar(query string) float64 {
	client := http.Client{Timeout: 800 * time.Millisecond}
	endpoints := []string{
		"http://localhost:9090/api/v1/query?query=" + url.QueryEscape(query),
		"http://gbnt-monitor-prometheus:9090/api/v1/query?query=" + url.QueryEscape(query),
		"http://127.0.0.1:9090/api/v1/query?query=" + url.QueryEscape(query),
	}

	for _, ep := range endpoints {
		resp, err := client.Get(ep)
		if err != nil || resp.StatusCode != http.StatusOK {
			if resp != nil {
				resp.Body.Close()
			}
			continue
		}
		defer resp.Body.Close()

		var result struct {
			Data struct {
				Result []struct {
					Value []interface{} `json:"value"`
				} `json:"result"`
			} `json:"data"`
		}

		if err := json.NewDecoder(resp.Body).Decode(&result); err == nil && len(result.Data.Result) > 0 {
			valSlice := result.Data.Result[0].Value
			if len(valSlice) >= 2 {
				switch v := valSlice[1].(type) {
				case string:
					if parsed, err := strconv.ParseFloat(v, 64); err == nil {
						return parsed
					}
				case float64:
					return v
				}
			}
		}
	}
	return 0.0
}

// ExecuteScaleUp schedules a new replica honoring scope and hardware affinity.
func ExecuteScaleUp(svc *db.Service, runningTasks []db.Task, policy *AutoscalePolicy, newReplicas int) error {
	var targetNodeID string

	// 1. If scope is "host" or policy is SingleHostOnly, constrain to target host
	if policy.Scope == "host" || policy.SingleHostOnly {
		if policy.PinnedHost != "" {
			// Find node matching pinned host
			var n db.Node
			if err := db.DB.Where("id = ? OR ip = ?", policy.PinnedHost, policy.PinnedHost).First(&n).Error; err == nil {
				targetNodeID = n.ID
			} else if len(runningTasks) > 0 {
				targetNodeID = runningTasks[0].NodeID
			}
		} else if len(runningTasks) > 0 {
			targetNodeID = runningTasks[0].NodeID
		} else if svc.StackID != "" {
			var stack db.Stack
			if err := db.DB.Where("id = ?", svc.StackID).First(&stack).Error; err == nil && stack.NodeID != "" && stack.NodeID != "multi-host" {
				targetNodeID = stack.NodeID
			}
		}
	} else {
		// 2. Scope is "cluster": check if parent stack was deployed as single-host atomic unit
		if svc.StackID != "" {
			var stack db.Stack
			if err := db.DB.Where("id = ?", svc.StackID).First(&stack).Error; err == nil && stack.NodeID != "" && stack.NodeID != "multi-host" {
				// Stack was scheduled to a single node. If service doesn't have explicit spread label, scale on stack node
				hasExplicitSpread := false
				for _, c := range svc.Constraints {
					if strings.Contains(c, "gbnt.placement.strategy=spread") || strings.Contains(c, "gbnt.placement.strategy=multi-host") {
						hasExplicitSpread = true
						break
					}
				}
				if !hasExplicitSpread {
					targetNodeID = stack.NodeID
				}
			}
		}

		if targetNodeID == "" {
			// Select optimal node respecting hardware/GPU affinity and constraints
			targetNodeID = selectTargetNodeForScale(svc, policy, runningTasks)
		}
	}

	if targetNodeID == "" {
		return fmt.Errorf("no suitable node found for scale up (metric: %s, scope: %s)", policy.Metric, policy.Scope)
	}

	// Update DesiredReplicas in database
	svc.DesiredReplicas = newReplicas
	if err := db.DB.Model(svc).Update("desired_replicas", newReplicas).Error; err != nil {
		return err
	}

	// Schedule the new pending task
	task := db.Task{
		ID:        uuid.New().String(),
		ServiceID: svc.ID,
		NodeID:    targetNodeID,
		Status:    "pending",
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	if err := db.DB.Create(&task).Error; err != nil {
		return err
	}

	slog.Info("autoscaler: scheduled new task", "task_id", task.ID[:8], "service", svc.Name, "target_node", targetNodeID)
	return nil
}

// selectTargetNodeForScale picks an active node matching GPU affinity and placement constraints.
func selectTargetNodeForScale(svc *db.Service, policy *AutoscalePolicy, runningTasks []db.Task) string {
	var activeNodes []db.Node
	if err := db.DB.Where("status = ?", "active").Find(&activeNodes).Error; err != nil || len(activeNodes) == 0 {
		return ""
	}

	// Count existing task distribution
	taskCountByNode := make(map[string]int)
	for _, t := range runningTasks {
		taskCountByNode[t.NodeID]++
	}

	// Filter nodes based on hardware affinity (GPU, arch, placement)
	candidateNodes := make([]db.Node, 0)
	for _, node := range activeNodes {
		// If metric is GPU or service has GPU constraint, node MUST have GPU
		if policy.Metric == "gpu" || hasGPUConstraint(svc.Constraints) {
			if !docker.NodeHasGPU(node) {
				continue // Skip nodes without GPU hardware
			}
		}

		// Check service placement constraints (e.g. node.role == worker, node.hostname == ...)
		if !matchesConstraints(node, svc.Constraints) {
			continue
		}

		candidateNodes = append(candidateNodes, node)
	}

	if len(candidateNodes) == 0 {
		// Fallback: if metric is GPU but no other GPU node exists, use existing host if it has GPU
		if len(runningTasks) > 0 {
			return runningTasks[0].NodeID
		}
		return ""
	}

	// Pick candidate with least number of replicas (spread)
	bestNode := candidateNodes[0].ID
	minTasks := taskCountByNode[bestNode]
	for _, n := range candidateNodes[1:] {
		cnt := taskCountByNode[n.ID]
		if cnt < minTasks {
			minTasks = cnt
			bestNode = n.ID
		}
	}

	return bestNode
}

func hasGPUConstraint(constraints []string) bool {
	for _, c := range constraints {
		cl := strings.ToLower(c)
		if strings.Contains(cl, "gpu") || strings.Contains(cl, "nvidia") || strings.Contains(cl, "cuda") {
			return true
		}
	}
	return false
}

func matchesConstraints(node db.Node, constraints []string) bool {
	for _, constraint := range constraints {
		parts := strings.Split(constraint, "==")
		if len(parts) == 2 {
			leftSide := strings.TrimSpace(parts[0])
			val := strings.TrimSpace(parts[1])

			// Support node.role == worker / node.role == manager directly
			if leftSide == "node.role" || leftSide == "node.labels.node.role" || leftSide == "node.labels.gbnt.node.role" || leftSide == "gbnt.node.role" {
				if !strings.EqualFold(node.Role, val) && !strings.EqualFold(node.Labels["gbnt.node.role"], val) {
					return false
				}
				continue
			}

			// Support node.hostname == ... or node.id == ...
			if leftSide == "node.hostname" || leftSide == "gbnt.node.hostname" || leftSide == "node.labels.gbnt.node.hostname" || leftSide == "node.id" || leftSide == "gbnt.node.id" {
				if !strings.EqualFold(node.Labels["gbnt.node.hostname"], val) && !strings.EqualFold(node.ID, val) && !strings.EqualFold(node.IP, val) {
					return false
				}
				continue
			}

			if !strings.HasPrefix(leftSide, "node.labels.") && !strings.HasPrefix(leftSide, "gbnt.node.") {
				// Skip non-node-placement constraints
				continue
			}

			key := strings.TrimPrefix(leftSide, "node.labels.")
			nodeVal, exists := node.Labels[key]
			if !exists {
				if strings.HasPrefix(key, "gbnt.node.") {
					nodeVal, exists = node.Labels[strings.TrimPrefix(key, "gbnt.node.")]
				} else {
					nodeVal, exists = node.Labels["gbnt.node."+key]
				}
			}
			if !exists || !strings.EqualFold(nodeVal, val) {
				return false
			}
		}
	}
	return true
}

// ExecuteScaleDown stops the newest task and decrements DesiredReplicas.
func ExecuteScaleDown(svc *db.Service, tasks []db.Task, newReplicas int) error {
	// Find newest task
	var newestTask *db.Task
	for i := range tasks {
		if tasks[i].Status == "running" || tasks[i].Status == "pending" {
			if newestTask == nil || tasks[i].CreatedAt.After(newestTask.CreatedAt) {
				newestTask = &tasks[i]
			}
		}
	}

	if newestTask != nil {
		if newestTask.ContainerName != "" {
			_ = docker.RemoveContainerOnNode(newestTask.NodeID, newestTask.ContainerName)
		}
		db.DB.Delete(newestTask)
	}

	svc.DesiredReplicas = newReplicas
	return db.DB.Model(svc).Update("desired_replicas", newReplicas).Error
}
