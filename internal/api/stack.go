package api

import (
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/mario-ezquerro/gubernator/internal/aqueducts"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/mario-ezquerro/gubernator/internal/examples"
	"github.com/mario-ezquerro/gubernator/internal/slo"
	"gopkg.in/yaml.v3"
)

func init() {
	examples.DeployStackFn = DeployStackRaw
}

// EnvSlice handles both sequence/list (e.g. ["FOO=bar"]) and map (e.g. FOO: bar) formats for environment variables in YAML.
type EnvSlice []string

func (e *EnvSlice) UnmarshalYAML(value *yaml.Node) error {
	if value.Kind == yaml.SequenceNode {
		var list []string
		if err := value.Decode(&list); err != nil {
			return err
		}
		*e = list
		return nil
	}

	if value.Kind == yaml.MappingNode {
		var m map[string]string
		if err := value.Decode(&m); err != nil {
			return err
		}
		list := make([]string, 0, len(m))
		for k, v := range m {
			list = append(list, fmt.Sprintf("%s=%s", k, v))
		}
		*e = list
		return nil
	}

	return fmt.Errorf("invalid environment format: must be a list or map")
}

// LabelsMap handles both sequence/list (e.g. ["gbnt.slo.enable=true"]) and map (e.g. gbnt.slo.enable: "true") formats for labels in YAML.
type LabelsMap map[string]string

func (l *LabelsMap) UnmarshalYAML(value *yaml.Node) error {
	*l = make(map[string]string)
	if value.Kind == yaml.SequenceNode {
		var list []string
		if err := value.Decode(&list); err != nil {
			return err
		}
		for _, item := range list {
			parts := strings.SplitN(item, "=", 2)
			if len(parts) == 2 {
				(*l)[strings.TrimSpace(parts[0])] = strings.TrimSpace(parts[1])
			} else if len(parts) == 1 {
				(*l)[strings.TrimSpace(parts[0])] = "true"
			}
		}
		return nil
	}

	if value.Kind == yaml.MappingNode {
		var mAny map[string]interface{}
		if err := value.Decode(&mAny); err == nil {
			for k, val := range mAny {
				(*l)[strings.TrimSpace(k)] = fmt.Sprintf("%v", val)
			}
			return nil
		}
		return nil
	}

	return fmt.Errorf("invalid labels format: must be a list or map")
}

// CommandVal handles both scalar string (e.g. "caddy run") and sequence list (e.g. ["caddy", "run"]) formats for command in YAML.
type CommandVal string

func (c *CommandVal) UnmarshalYAML(value *yaml.Node) error {
	if value.Kind == yaml.ScalarNode {
		*c = CommandVal(value.Value)
		return nil
	}
	if value.Kind == yaml.SequenceNode {
		var list []string
		if err := value.Decode(&list); err != nil {
			return err
		}
		*c = CommandVal(strings.Join(list, " "))
		return nil
	}
	return nil
}

// FlexString handles both scalar strings ("1.0", "2G") and numbers (1.0, 2, 512) in YAML.
type FlexString string

func (f *FlexString) UnmarshalYAML(value *yaml.Node) error {
	if value.Kind == yaml.ScalarNode {
		*f = FlexString(value.Value)
		return nil
	}
	return nil
}

type ComposeFile struct {
	Name     string                    `yaml:"name"` // Top-level name in compose file
	Services map[string]ComposeService `yaml:"services"`
}

// PlacementPreference captures Docker Compose deploy.placement.preferences entries (e.g. spread: node.id).
type PlacementPreference struct {
	Spread string `yaml:"spread"`
}

// PlacementPreferences handles unmarshaling of placement preferences from YAML sequences or mappings.
type PlacementPreferences []PlacementPreference

func (p *PlacementPreferences) UnmarshalYAML(value *yaml.Node) error {
	if value.Kind == yaml.SequenceNode {
		var list []map[string]string
		if err := value.Decode(&list); err == nil {
			var prefs []PlacementPreference
			for _, m := range list {
				if s, ok := m["spread"]; ok {
					prefs = append(prefs, PlacementPreference{Spread: s})
				}
			}
			*p = prefs
			return nil
		}
	} else if value.Kind == yaml.MappingNode {
		var m map[string]string
		if err := value.Decode(&m); err == nil {
			if s, ok := m["spread"]; ok {
				*p = []PlacementPreference{{Spread: s}}
				return nil
			}
		}
	}
	return nil
}

// ComposeService maps a docker-compose service definition, capturing all
// fields needed to run a container: image, replicas, ports, env, volumes, command, placement.
type ComposeService struct {
	Image          string            `yaml:"image"`
	Ports          []string          `yaml:"ports"`       // e.g. ["8080:80"]
	Environment    EnvSlice          `yaml:"environment"` // handles both list and map formats
	EnvMap         map[string]string `yaml:"environment_map,omitempty"`
	Volumes        []string          `yaml:"volumes"` // e.g. ["./data:/app/data"]
	Command        CommandVal        `yaml:"command"` // handles both string and list formats
	Labels         LabelsMap         `yaml:"labels"`  // handles service labels (e.g. gbnt.slo.*)
	Cpus           FlexString        `yaml:"cpus"`
	MemLimit       FlexString        `yaml:"mem_limit"`
	MemReservation FlexString        `yaml:"mem_reservation"`
	Deploy         struct {
		Replicas  int       `yaml:"replicas"`
		Labels    LabelsMap `yaml:"labels"`
		Placement struct {
			Constraints []string             `yaml:"constraints"`
			Preferences PlacementPreferences `yaml:"preferences"`
		} `yaml:"placement"`
		Resources struct {
			Limits struct {
				Cpus   FlexString `yaml:"cpus"`
				Memory FlexString `yaml:"memory"`
			} `yaml:"limits"`
			Reservations struct {
				Cpus   FlexString `yaml:"cpus"`
				Memory FlexString `yaml:"memory"`
			} `yaml:"reservations"`
		} `yaml:"resources"`
	} `yaml:"deploy"`
}

type StackDeployRequest struct {
	Name       string `json:"name"` // Optional if provided in compose file
	ComposeRaw string `json:"compose_raw" binding:"required"`
	TargetNode string `json:"target_node"`
}

// @Summary Deploy a Stack
// @Description Parse a docker-compose yaml and schedule tasks to nodes
// @Tags stack
// @Accept json
// @Produce json
// @Param request body StackDeployRequest true "Stack Deploy Request"
// @Success 200 {object} map[string]string
// @Failure 400 {object} map[string]string
// @Router /v1/stack/deploy [post]
func StackDeployHandler(c *gin.Context) {
	var req StackDeployRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	stack, err := DeployStackRaw(req.Name, req.ComposeRaw, req.TargetNode)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":  "Stack deployed successfully",
		"stack_id": stack.ID,
		"name":     stack.Name,
	})
}

// @Summary Save Stack Definition (Draft / Without Deploying)
// @Description Save or update stack compose definition in database and server files without deploying containers
// @Tags stacks
// @Accept json
// @Produce json
// @Param request body StackDeployRequest true "Stack Save Request"
// @Success 200 {object} map[string]interface{}
// @Router /v1/stack/save [post]
func StackSaveHandler(c *gin.Context) {
	var req StackDeployRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	stack, err := SaveStackRaw(req.Name, req.ComposeRaw, req.TargetNode)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":  "Stack saved successfully (draft mode, containers not deployed)",
		"stack_id": stack.ID,
		"name":     stack.Name,
		"status":   "saved",
	})
}

// SaveStackRaw parses compose YAML, creates or updates the db.Stack and db.Service records,
// saves the .yml file on the server, but DOES NOT schedule or launch containers.
func SaveStackRaw(reqName, composeRawInput, targetNode string) (*db.Stack, error) {
	stackName := strings.TrimSpace(reqName)

	var tempCompose ComposeFile
	if err := yaml.Unmarshal([]byte(composeRawInput), &tempCompose); err == nil {
		extractedName := ""
		for _, srv := range tempCompose.Services {
			for _, constraint := range srv.Deploy.Placement.Constraints {
				parts := strings.Split(constraint, "==")
				if len(parts) == 2 && strings.TrimSpace(parts[0]) == "stack.name" {
					extractedName = strings.TrimSpace(parts[1])
					break
				}
			}
			if extractedName != "" {
				break
			}
		}
		if extractedName != "" {
			stackName = extractedName
		} else if stackName == "" && tempCompose.Name != "" {
			stackName = tempCompose.Name
		}
	}

	if stackName == "" {
		return nil, fmt.Errorf("stack name must be provided or defined in compose file as 'name: <name>' or 'stack.name == <name>' constraint")
	}

	composeRaw := strings.ReplaceAll(composeRawInput, "{{stack.name}}", stackName)

	var compose ComposeFile
	if err := yaml.Unmarshal([]byte(composeRaw), &compose); err != nil {
		return nil, fmt.Errorf("failed to parse compose YAML: %w", err)
	}

	var stack db.Stack
	isNew := true
	if err := db.DB.Where("name = ?", stackName).First(&stack).Error; err == nil {
		isNew = false
	}

	if isNew {
		stackID := uuid.New().String()
		nodeID := ""
		if targetNode != "" && targetNode != "auto" {
			nodeID = targetNode
		}
		stack = db.Stack{
			ID:             stackID,
			Name:           stackName,
			RawComposeFile: composeRaw,
			NodeID:         nodeID,
		}
		if err := db.DB.Create(&stack).Error; err != nil {
			return nil, fmt.Errorf("failed to save stack: %w", err)
		}
	} else {
		stack.Name = stackName
		stack.RawComposeFile = composeRaw
		if targetNode != "" && targetNode != "auto" {
			stack.NodeID = targetNode
		}
		db.DB.Save(&stack)
	}

	var existingTasks []db.Task
	db.DB.Joins("JOIN services ON services.id = tasks.service_id").Where("services.stack_id = ?", stack.ID).Find(&existingTasks)

	if len(existingTasks) == 0 {
		db.DB.Where("stack_id = ?", stack.ID).Delete(&db.Service{})

		for srvName, srvDef := range compose.Services {
			replicas := srvDef.Deploy.Replicas
			if replicas == 0 {
				replicas = 1
			}

			constraints := append([]string{}, srvDef.Deploy.Placement.Constraints...)
			for k, v := range srvDef.Labels {
				constraints = append(constraints, fmt.Sprintf("%s=%s", k, v))
			}
			for k, v := range srvDef.Deploy.Labels {
				constraints = append(constraints, fmt.Sprintf("%s=%s", k, v))
			}

			cpuLimit := string(srvDef.Deploy.Resources.Limits.Cpus)
			if cpuLimit == "" {
				cpuLimit = string(srvDef.Cpus)
			}
			memLimit := string(srvDef.Deploy.Resources.Limits.Memory)
			if memLimit == "" {
				memLimit = string(srvDef.MemLimit)
			}
			cpuRes := string(srvDef.Deploy.Resources.Reservations.Cpus)
			memRes := string(srvDef.Deploy.Resources.Reservations.Memory)

			service := db.Service{
				ID:                uuid.New().String(),
				StackID:           stack.ID,
				Name:              srvName,
				Image:             srvDef.Image,
				DesiredReplicas:   replicas,
				Constraints:       constraints,
				Ports:             srvDef.Ports,
				Env:               []string(srvDef.Environment),
				Volumes:           srvDef.Volumes,
				Command:           string(srvDef.Command),
				CpuLimit:          cpuLimit,
				MemoryLimit:       memLimit,
				CpuReservation:    cpuRes,
				MemoryReservation: memRes,
			}
			db.DB.Create(&service)
		}
	}

	stacksDir := examples.DefaultServerStacksDir()
	if err := os.MkdirAll(stacksDir, 0755); err == nil {
		filePath := filepath.Join(stacksDir, fmt.Sprintf("%s.yml", stackName))
		_ = os.WriteFile(filePath, []byte(composeRaw), 0644)
	}

	return &stack, nil
}



// isMultiHostStack determines whether a Docker Compose stack should have its services
// and replicas distributed across multiple Centurion cluster nodes (multi-host)
// rather than scheduled atomically to a single host.
func isMultiHostStack(compose *ComposeFile, requestedTargetNode string) bool {
	// If user explicitly picked "multi-host" or "spread" from UI or CLI
	if strings.EqualFold(requestedTargetNode, "multi-host") || strings.EqualFold(requestedTargetNode, "spread") {
		return true
	}

	// If user explicitly targeted a single host (e.g. "gbnt-worker1"), honor atomic placement
	if requestedTargetNode != "" && requestedTargetNode != "auto" {
		return false
	}

	var hasExplicitSpread bool
	nodeConstraintsByService := make(map[string][]string)

	for srvName, srv := range compose.Services {
		// 1. Check deploy.placement.preferences for spread
		for _, pref := range srv.Deploy.Placement.Preferences {
			if pref.Spread != "" {
				hasExplicitSpread = true
			}
		}

		// 2. Check labels for placement strategy
		for k, v := range srv.Labels {
			if k == "gbnt.placement.strategy" && (v == "spread" || v == "multi-host") {
				hasExplicitSpread = true
			}
		}
		for k, v := range srv.Deploy.Labels {
			if k == "gbnt.placement.strategy" && (v == "spread" || v == "multi-host") {
				hasExplicitSpread = true
			}
		}

		// 3. Check if service has multiple replicas AND caddy load balancing configured
		if srv.Deploy.Replicas > 1 {
			for k := range srv.Labels {
				if strings.HasPrefix(k, "gbnt.caddy.lb") || k == "ingress.lb" {
					hasExplicitSpread = true
				}
			}
		}

		// 4. Collect node targeting constraints per service
		for _, c := range srv.Deploy.Placement.Constraints {
			parts := strings.Split(c, "==")
			if len(parts) == 2 {
				leftSide := strings.TrimSpace(parts[0])
				val := strings.TrimSpace(parts[1])
				if leftSide == "node.hostname" || leftSide == "node.id" || leftSide == "gbnt.node.hostname" || leftSide == "gbnt.node.id" {
					nodeConstraintsByService[srvName] = append(nodeConstraintsByService[srvName], val)
				}
			}
		}
	}

	if hasExplicitSpread {
		return true
	}

	// If different services explicitly target different nodes (e.g. srv1 -> worker1, srv2 -> worker2)
	var firstTarget string
	for _, targets := range nodeConstraintsByService {
		for _, t := range targets {
			if firstTarget == "" {
				firstTarget = t
			} else if !strings.EqualFold(firstTarget, t) {
				return true // Distinct host targets across services in the same stack!
			}
		}
	}

	return false
}

// DeployStackRaw parses compose YAML and schedules services across cluster nodes.
func DeployStackRaw(stackName string, composeRawInput string, targetNode string) (*db.Stack, error) {
	if strings.TrimSpace(composeRawInput) == "" {
		return nil, fmt.Errorf("empty compose file")
	}

	// Auto-generate stack name or infer from constraints/name
	if strings.TrimSpace(stackName) == "" {
		var tempCompose ComposeFile
		if err := yaml.Unmarshal([]byte(composeRawInput), &tempCompose); err == nil {
			for _, srv := range tempCompose.Services {
				for _, constraint := range srv.Deploy.Placement.Constraints {
					parts := strings.Split(constraint, "==")
					if len(parts) == 2 && strings.TrimSpace(parts[0]) == "stack.name" {
						stackName = strings.TrimSpace(parts[1])
						break
					}
				}
				if stackName != "" {
					break
				}
			}
			if stackName == "" && tempCompose.Name != "" {
				stackName = tempCompose.Name
			}
		}
		if stackName == "" {
			stackName = "stack-" + uuid.New().String()[:8]
		}
	}

	// Replace placeholders like {{stack.name}} with the actual stack name
	composeRaw := strings.ReplaceAll(composeRawInput, "{{stack.name}}", stackName)

	// Parse YAML for actual deployment
	var compose ComposeFile
	if err := yaml.Unmarshal([]byte(composeRaw), &compose); err != nil {
		return nil, fmt.Errorf("failed to parse compose YAML: %w", err)
	}

	// Clean up existing stack with the same name if redeploying
	var existingStack db.Stack
	if err := db.DB.Where("name = ?", stackName).First(&existingStack).Error; err == nil {
		slog.Info("redeploying existing stack, stopping previous containers", "name", stackName, "old_id", existingStack.ID)
		StopStackContainers(existingStack.ID)

		var oldServices []db.Service
		db.DB.Where("stack_id = ?", existingStack.ID).Find(&oldServices)
		for _, s := range oldServices {
			db.DB.Where("service_id = ?", s.ID).Delete(&db.Task{})
		}
		db.DB.Where("stack_id = ?", existingStack.ID).Delete(&db.Service{})
		db.DB.Where("id = ?", existingStack.ID).Delete(&db.Stack{})
	}

	// Determine if this stack requires Multi-Host Service Placement
	multiHost := isMultiHostStack(&compose, targetNode)

	var selectedNode *db.Node
	var stackNodeID string

	if multiHost {
		stackNodeID = "multi-host"
		slog.Info("scheduling stack in multi-host distributed mode", "stack", stackName)
	} else {
		// 1. Collect all constraints across all services to schedule the Stack as an atomic unit
		var allStackConstraints []string
		for _, srvDef := range compose.Services {
			allStackConstraints = append(allStackConstraints, srvDef.Deploy.Placement.Constraints...)
		}

		// 2. Select the optimal node for the ENTIRE Stack (balances stacks across hosts)
		var err error
		selectedNode, err = SelectOptimalNodeForStack(allStackConstraints, targetNode)
		if err != nil {
			return nil, fmt.Errorf("stack scheduling failed: %w", err)
		}
		stackNodeID = selectedNode.ID
		slog.Info("scheduled stack atomically to host", "stack", stackName, "node_id", selectedNode.ID, "node_ip", selectedNode.IP, "role", selectedNode.Role)
	}

	// Create Stack record
	stackID := uuid.New().String()
	stack := db.Stack{
		ID:             stackID,
		Name:           stackName,
		RawComposeFile: composeRaw,
		NodeID:         stackNodeID,
	}
	db.DB.Create(&stack)

	// Process Services
	for srvName, srvDef := range compose.Services {
		replicas := srvDef.Deploy.Replicas
		if replicas == 0 {
			replicas = 1 // default
		}

		constraints := append([]string{}, srvDef.Deploy.Placement.Constraints...)
		for k, v := range srvDef.Labels {
			constraints = append(constraints, fmt.Sprintf("%s=%s", k, v))
		}
		for k, v := range srvDef.Deploy.Labels {
			constraints = append(constraints, fmt.Sprintf("%s=%s", k, v))
		}

		slog.Info("parsed compose service labels", "name", srvName, "labels", srvDef.Labels, "deploy_labels", srvDef.Deploy.Labels, "constraints", constraints)

		cpuLimit := string(srvDef.Deploy.Resources.Limits.Cpus)
		if cpuLimit == "" {
			cpuLimit = string(srvDef.Cpus)
		}
		memLimit := string(srvDef.Deploy.Resources.Limits.Memory)
		if memLimit == "" {
			memLimit = string(srvDef.MemLimit)
		}
		cpuRes := string(srvDef.Deploy.Resources.Reservations.Cpus)
		memRes := string(srvDef.Deploy.Resources.Reservations.Memory)
		if memRes == "" {
			memRes = string(srvDef.MemReservation)
		}

		service := db.Service{
			ID:                uuid.New().String(),
			StackID:           stackID,
			Name:              srvName,
			Image:             srvDef.Image,
			DesiredReplicas:   replicas,
			Constraints:       constraints,
			Ports:             srvDef.Ports,
			Env:               []string(srvDef.Environment),
			Volumes:           srvDef.Volumes,
			Command:           string(srvDef.Command),
			CpuLimit:          cpuLimit,
			MemoryLimit:       memLimit,
			CpuReservation:    cpuRes,
			MemoryReservation: memRes,
		}
		db.DB.Create(&service)

		if multiHost {
			// Multi-Host placement: evaluate service-specific constraints & spread
			serviceTargetNode := "auto"
			serviceSpread := false

			for _, pref := range srvDef.Deploy.Placement.Preferences {
				if pref.Spread != "" {
					serviceSpread = true
				}
			}
			if srvDef.Labels["gbnt.placement.strategy"] == "spread" || srvDef.Deploy.Labels["gbnt.placement.strategy"] == "spread" {
				serviceSpread = true
			}
			if replicas > 1 {
				serviceSpread = true
			}

			// Check if service targets a specific node
			for _, c := range constraints {
				parts := strings.Split(c, "==")
				if len(parts) == 2 {
					leftSide := strings.TrimSpace(parts[0])
					val := strings.TrimSpace(parts[1])
					if leftSide == "node.hostname" || leftSide == "node.id" || leftSide == "gbnt.node.hostname" || leftSide == "gbnt.node.id" {
						serviceTargetNode = val
						serviceSpread = false
						break
					}
				}
			}

			ScheduleServiceWithSpread(&service, serviceTargetNode, serviceSpread)
		} else {
			// Single-host atomic placement
			ScheduleService(&service, selectedNode.ID)
		}
	}

	// Trigger generation of Prometheus SLO rules
	_ = slo.SyncSLORulesToPrometheus(db.DB)

	stacksDir := examples.DefaultServerStacksDir()
	if err := os.MkdirAll(stacksDir, 0755); err == nil {
		filePath := filepath.Join(stacksDir, fmt.Sprintf("%s.yml", stackName))
		_ = os.WriteFile(filePath, []byte(composeRaw), 0644)
	}

	return &stack, nil
}

// SelectOptimalNodeForStack selects a single host node for an entire Docker Compose stack.
// Gubernator balances STACKS across cluster nodes (not individual containers).
// All containers belonging to the same stack run together on this single host.
func SelectOptimalNodeForStack(constraints []string, targetNode string) (*db.Node, error) {
	// 1. Explicit target node requested (e.g. from UI dropdown or CLI flag)
	if targetNode != "" && targetNode != "auto" {
		var n db.Node
		if err := db.DB.First(&n, "id = ? OR ip = ?", targetNode, targetNode).Error; err == nil {
			if n.Status == "active" || n.Status == "ready" {
				return &n, nil
			}
			return nil, fmt.Errorf("requested node %s is not active (status: %s)", targetNode, n.Status)
		}
		return nil, fmt.Errorf("requested node %s not found in cluster", targetNode)
	}

	// 2. Query all healthy candidate nodes (excluding drain, pause, maintenance)
	var allNodes []db.Node
	if err := db.DB.Where("status IN ?", []string{"active", "ready"}).Find(&allNodes).Error; err != nil || len(allNodes) == 0 {
		return nil, fmt.Errorf("no active or ready cluster nodes available for scheduling")
	}

	// 3. Count active STACKS and tasks per candidate node to balance stacks across hosts
	type nodeWithStackLoad struct {
		node       db.Node
		stackCount int64
		taskCount  int64
	}
	var workerLoads []nodeWithStackLoad
	var managerLoads []nodeWithStackLoad

	for _, n := range allNodes {
		var stackCount int64
		db.DB.Model(&db.Stack{}).Where("node_id = ?", n.ID).Count(&stackCount)

		var taskCount int64
		db.DB.Model(&db.Task{}).Where("node_id = ? AND status IN ?", n.ID, []string{"running", "pending", "pulling", "starting"}).Count(&taskCount)

		nl := nodeWithStackLoad{
			node:       n,
			stackCount: stackCount,
			taskCount:  taskCount,
		}

		if strings.ToLower(n.Role) == "manager" {
			managerLoads = append(managerLoads, nl)
		} else {
			workerLoads = append(workerLoads, nl)
		}
	}

	// Sort workers ascending by active stack count (least stacks first), then by task count
	sort.SliceStable(workerLoads, func(a, b int) bool {
		if workerLoads[a].stackCount != workerLoads[b].stackCount {
			return workerLoads[a].stackCount < workerLoads[b].stackCount
		}
		return workerLoads[a].taskCount < workerLoads[b].taskCount
	})

	// Sort managers ascending
	sort.SliceStable(managerLoads, func(a, b int) bool {
		if managerLoads[a].stackCount != managerLoads[b].stackCount {
			return managerLoads[a].stackCount < managerLoads[b].stackCount
		}
		return managerLoads[a].taskCount < managerLoads[b].taskCount
	})

	// Workers ALWAYS prioritized over Manager
	var orderedNodes []db.Node
	for _, wl := range workerLoads {
		orderedNodes = append(orderedNodes, wl.node)
	}
	for _, ml := range managerLoads {
		orderedNodes = append(orderedNodes, ml.node)
	}

	// 4. Constraint matching with Worker-First priority and Least-Loaded Stack Spread
	for _, node := range orderedNodes {
		matchesAll := true
		for _, constraint := range constraints {
			parts := strings.Split(constraint, "==")
			if len(parts) == 2 {
				leftSide := strings.TrimSpace(parts[0])
				val := strings.TrimSpace(parts[1])

				// Support node.role == worker / node.role == manager
				if leftSide == "node.role" || leftSide == "node.labels.node.role" || leftSide == "node.labels.gbnt.node.role" || leftSide == "gbnt.node.role" {
					if !strings.EqualFold(node.Role, val) && !strings.EqualFold(node.Labels["gbnt.node.role"], val) {
						matchesAll = false
						break
					}
					continue
				}

				// Support node.hostname == gbnt-worker1 or node.id == ...
				if leftSide == "node.hostname" || leftSide == "gbnt.node.hostname" || leftSide == "node.labels.gbnt.node.hostname" {
					if !strings.EqualFold(node.Labels["gbnt.node.hostname"], val) && !strings.EqualFold(node.ID, val) {
						matchesAll = false
						break
					}
					continue
				}

				if !strings.HasPrefix(leftSide, "node.labels.") && !strings.HasPrefix(leftSide, "gbnt.node.") {
					// Skip non-node-placement constraints (like ingress.host, stack.name, gbnt.caddy.port)
					continue
				}

				key := strings.TrimPrefix(leftSide, "node.labels.")
				if nodeVal, exists := node.Labels[key]; !exists || nodeVal != val {
					matchesAll = false
					break
				}
			}
		}

		if matchesAll {
			return &node, nil
		}
	}

	return nil, fmt.Errorf("no active cluster node matches all stack placement constraints: %v", constraints)
}

// MigrateStack moves an entire stack atomically from its current host to targetNodeID.
func MigrateStack(stackID string, targetNodeID string) (*db.Stack, error) {
	var stack db.Stack
	if err := db.DB.Where("id = ? OR name = ?", stackID, stackID).First(&stack).Error; err != nil {
		return nil, fmt.Errorf("stack not found: %s", stackID)
	}

	var targetNode *db.Node
	if targetNodeID == "" || targetNodeID == "auto" {
		// Pick an optimal active node other than the current node
		var services []db.Service
		db.DB.Where("stack_id = ?", stack.ID).Find(&services)
		var constraints []string
		for _, s := range services {
			constraints = append(constraints, s.Constraints...)
		}
		var err error
		targetNode, err = SelectOptimalNodeForStack(constraints, "auto")
		if err != nil {
			return nil, fmt.Errorf("auto-migration failed: %w", err)
		}
	} else {
		var n db.Node
		if err := db.DB.First(&n, "id = ? OR ip = ?", targetNodeID, targetNodeID).Error; err != nil {
			return nil, fmt.Errorf("target node %s not found", targetNodeID)
		}
		if n.Status != "active" && n.Status != "ready" {
			return nil, fmt.Errorf("target node %s is not active (status: %s)", n.ID, n.Status)
		}
		targetNode = &n
	}

	slog.Info("migrating stack atomically to target node", "stack", stack.Name, "old_node", stack.NodeID, "new_node", targetNode.ID)

	// 1. Stop and remove all existing containers/tasks for this stack
	StopStackContainers(stack.ID)

	// 2. Update stack.NodeID in DB
	stack.NodeID = targetNode.ID
	db.DB.Model(&stack).Update("node_id", targetNode.ID)

	// 3. Reschedule all services onto targetNode.ID
	var services []db.Service
	db.DB.Where("stack_id = ?", stack.ID).Find(&services)
	for _, svc := range services {
		db.DB.Where("service_id = ?", svc.ID).Delete(&db.Task{})
		ScheduleService(&svc, targetNode.ID)
	}

	// 4. Regenerate DNS & Caddy routes
	go aqueducts.GenerateHostsFile()
	go aqueducts.GenerateCaddyfile()

	return &stack, nil
}

// StackMigrateHandler migrates an entire stack atomically to a new host via REST API.
func StackMigrateHandler(c *gin.Context) {
	id := c.Param("id")
	var req struct {
		TargetNode string `json:"target_node"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request body"})
		return
	}

	stack, err := MigrateStack(id, req.TargetNode)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":      "migrated",
		"stack_id":    stack.ID,
		"stack_name":  stack.Name,
		"target_node": stack.NodeID,
	})
}

// ScheduleService assigns desired replicas of a service to cluster nodes.
func ScheduleService(service *db.Service, targetNode string) {
	ScheduleServiceWithSpread(service, targetNode, false)
}

// ScheduleServiceWithSpread assigns desired replicas of a service to cluster nodes,
// supporting anti-affinity spread across distinct Centurion nodes.
func ScheduleServiceWithSpread(service *db.Service, targetNode string, spread bool) {
	assignedNodeIDs := make(map[string]int)
	for i := 0; i < service.DesiredReplicas; i++ {
		ScheduleSingleReplicaWithSpread(service, targetNode, spread, assignedNodeIDs)
	}
}

// ScheduleSingleReplica assigns one replica of a service to the optimal cluster node.
func ScheduleSingleReplica(service *db.Service, targetNode string) *db.Task {
	return ScheduleSingleReplicaWithSpread(service, targetNode, false, make(map[string]int))
}

// ScheduleSingleReplicaWithSpread assigns one replica of a service to a cluster node,
// respecting hardware affinity (GPU, arch, role), host constraints, and anti-affinity spread.
func ScheduleSingleReplicaWithSpread(service *db.Service, targetNode string, spread bool, assignedNodeIDs map[string]int) *db.Task {
	var selectedNode *db.Node

	if targetNode != "" && targetNode != "auto" {
		var n db.Node
		if err := db.DB.First(&n, "id = ? OR ip = ?", targetNode, targetNode).Error; err == nil {
			// Check if targeted node is not in pause/drain/no_schedule status
			if n.Status == "active" || n.Status == "ready" {
				selectedNode = &n
			}
		}
	}

	if selectedNode == nil {
		var allNodes []db.Node
		// Fetch all active or ready nodes (excluding drain, pause, no_schedule, maintenance)
		db.DB.Where("status IN ?", []string{"active", "ready"}).Find(&allNodes)

		type candidateNode struct {
			node            db.Node
			serviceReplicas int
			totalTaskLoad   int64
			isManager       bool
		}

		var candidates []candidateNode

		for _, node := range allNodes {
			matchesAll := true
			for _, constraint := range service.Constraints {
				parts := strings.Split(constraint, "==")
				if len(parts) == 2 {
					leftSide := strings.TrimSpace(parts[0])
					val := strings.TrimSpace(parts[1])

					// Support node.role == worker / node.role == manager directly
					if leftSide == "node.role" || leftSide == "node.labels.node.role" || leftSide == "node.labels.gbnt.node.role" || leftSide == "gbnt.node.role" {
						if !strings.EqualFold(node.Role, val) && !strings.EqualFold(node.Labels["gbnt.node.role"], val) {
							matchesAll = false
							break
						}
						continue
					}

					// Support node.hostname == ... or node.id == ...
					if leftSide == "node.hostname" || leftSide == "gbnt.node.hostname" || leftSide == "node.labels.gbnt.node.hostname" || leftSide == "node.id" || leftSide == "gbnt.node.id" {
						if !strings.EqualFold(node.Labels["gbnt.node.hostname"], val) && !strings.EqualFold(node.ID, val) && !strings.EqualFold(node.IP, val) {
							matchesAll = false
							break
						}
						continue
					}

					if !strings.HasPrefix(leftSide, "node.labels.") && !strings.HasPrefix(leftSide, "gbnt.node.") {
						// Skip non-node-placement constraints (like ingress.host, stack.name, gbnt.caddy.port, gbnt.caddy.lb)
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
						matchesAll = false
						break
					}
				}
			}

			if !matchesAll {
				continue
			}

			var totalLoad int64
			db.DB.Model(&db.Task{}).Where("node_id = ? AND status IN ?", node.ID, []string{"running", "pending", "pulling", "starting"}).Count(&totalLoad)

			var svcTaskCount int64
			db.DB.Model(&db.Task{}).Where("service_id = ? AND node_id = ? AND status != 'dead'", service.ID, node.ID).Count(&svcTaskCount)
			inMemoryReplicas := assignedNodeIDs[node.ID]
			totalSvcReplicas := int(svcTaskCount) + inMemoryReplicas

			candidates = append(candidates, candidateNode{
				node:            node,
				serviceReplicas: totalSvcReplicas,
				totalTaskLoad:   totalLoad,
				isManager:       strings.ToLower(node.Role) == "manager",
			})
		}

		if len(candidates) > 0 {
			sort.SliceStable(candidates, func(a, b int) bool {
				// 1. If spread is enabled, prioritize nodes with fewer replicas of THIS service (anti-affinity)
				if spread {
					if candidates[a].serviceReplicas != candidates[b].serviceReplicas {
						return candidates[a].serviceReplicas < candidates[b].serviceReplicas
					}
				}
				// 2. Prioritize Workers before Manager
				if candidates[a].isManager != candidates[b].isManager {
					return !candidates[a].isManager && candidates[b].isManager
				}
				// 3. Least loaded node first (total tasks)
				return candidates[a].totalTaskLoad < candidates[b].totalTaskLoad
			})

			selectedNode = &candidates[0].node
		}
	}

	if selectedNode != nil {
		assignedNodeIDs[selectedNode.ID]++
		task := db.Task{
			ID:                uuid.New().String(),
			ServiceID:         service.ID,
			NodeID:            selectedNode.ID,
			Status:            "pending", // executor will pick this up
			CpuLimit:          service.CpuLimit,
			MemoryLimit:       service.MemoryLimit,
			CpuReservation:    service.CpuReservation,
			MemoryReservation: service.MemoryReservation,
		}
		db.DB.Create(&task)
		slog.Info("scheduled service replica", "service", service.Name, "task_id", task.ID[:8], "node_id", selectedNode.ID, "node_ip", selectedNode.IP, "spread", spread)
		return &task
	}

	slog.Warn("could not find suitable node for service", "service", service.Name, "constraints", service.Constraints)
	task := db.Task{
		ID:                uuid.New().String(),
		ServiceID:         service.ID,
		NodeID:            "none",
		Status:            "dead",
		CpuLimit:          service.CpuLimit,
		MemoryLimit:       service.MemoryLimit,
		CpuReservation:    service.CpuReservation,
		MemoryReservation: service.MemoryReservation,
		Error:             "No suitable node found for placement constraints",
	}
	db.DB.Create(&task)
	return &task
}
