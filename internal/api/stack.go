package api

import (
	"fmt"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/mario-ezquerro/gubernator/internal/slo"
	"gopkg.in/yaml.v3"
)

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
		var m map[string]string
		if err := value.Decode(&m); err != nil {
			return err
		}
		*l = m
		return nil
	}

	return fmt.Errorf("invalid labels format: must be a list or map")
}

type ComposeFile struct {
	Name     string                    `yaml:"name"` // Top-level name in compose file
	Services map[string]ComposeService `yaml:"services"`
}

// ComposeService maps a docker-compose service definition, capturing all
// fields needed to run a container: image, replicas, ports, env, volumes, command, placement.
type ComposeService struct {
	Image       string            `yaml:"image"`
	Ports       []string          `yaml:"ports"`       // e.g. ["8080:80"]
	Environment EnvSlice          `yaml:"environment"` // handles both list and map formats
	EnvMap      map[string]string `yaml:"environment_map,omitempty"`
	Volumes     []string          `yaml:"volumes"` // e.g. ["./data:/app/data"]
	Command     string            `yaml:"command"` // optional command override
	Labels      LabelsMap         `yaml:"labels"`  // handles service labels (e.g. gbnt.slo.*)
	Deploy      struct {
		Replicas  int `yaml:"replicas"`
		Placement struct {
			Constraints []string `yaml:"constraints"`
		} `yaml:"placement"`
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

	stackName := req.Name

	// Try to infer it from the raw YAML if present
	var tempCompose ComposeFile
	if err := yaml.Unmarshal([]byte(req.ComposeRaw), &tempCompose); err == nil {
		extractedName := ""
		// Fallback: search for stack.name == XXX in constraints
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
			stackName = extractedName // Constraint has highest priority
		} else if stackName == "" && tempCompose.Name != "" {
			stackName = tempCompose.Name
		}
	}

	if stackName == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Stack name must be provided via API or defined in compose file as 'name: <name>' or 'stack.name == <name>' constraint"})
		return
	}

	// Replace placeholders like {{stack.name}} with the actual stack name
	composeRaw := strings.ReplaceAll(req.ComposeRaw, "{{stack.name}}", stackName)

	// Parse YAML for actual deployment
	var compose ComposeFile
	if err := yaml.Unmarshal([]byte(composeRaw), &compose); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Failed to parse YAML: %v", err)})
		return
	}

	// Create Stack record
	stackID := uuid.New().String()
	stack := db.Stack{
		ID:             stackID,
		Name:           stackName,
		RawComposeFile: composeRaw,
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

		service := db.Service{
			ID:              uuid.New().String(),
			StackID:         stackID,
			Name:            srvName,
			Image:           srvDef.Image,
			DesiredReplicas: replicas,
			Constraints:     constraints,
			Ports:           srvDef.Ports,
			Env:             []string(srvDef.Environment),
			Volumes:         srvDef.Volumes,
			Command:         srvDef.Command,
		}
		db.DB.Create(&service)

		// Scheduler: assign Tasks to Nodes based on Constraints
		scheduleService(&service, req.TargetNode)
	}

	// Trigger generation of Prometheus SLO rules
	_ = slo.SyncSLORulesToPrometheus(db.DB)

	c.JSON(http.StatusOK, gin.H{
		"message":  "Stack deployed successfully",
		"stack_id": stackID,
		"name":     stackName,
	})
}

func scheduleService(service *db.Service, targetNode string) {
	// For each replica, find a suitable node
	for i := 0; i < service.DesiredReplicas; i++ {
		var selectedNode *db.Node

		if targetNode != "" && targetNode != "auto" {
			var n db.Node
			if err := db.DB.First(&n, "id = ?", targetNode).Error; err == nil {
				selectedNode = &n
			}
		}

		if selectedNode == nil {
			var allNodes []db.Node
			db.DB.Where("status = ?", "active").Find(&allNodes)

			// MVP constraint matching
			for _, node := range allNodes {
			matchesAll := true
			for _, constraint := range service.Constraints {
				// Constraint example: "node.labels.gbnt.node.gpu == nvidia"
				parts := strings.Split(constraint, "==")
				if len(parts) == 2 {
					leftSide := strings.TrimSpace(parts[0])
					if !strings.HasPrefix(leftSide, "node.labels.") {
						// Skip non-node-placement constraints (like ingress.host)
						continue
					}
					key := strings.TrimPrefix(leftSide, "node.labels.")
					val := strings.TrimSpace(parts[1])

					if nodeVal, exists := node.Labels[key]; !exists || nodeVal != val {
						matchesAll = false
						break
					}
				}
			}

			if matchesAll {
				selectedNode = &node
				break // Found a matching node (MVP: picks the first one)
			}
		}
		}

		if selectedNode != nil {
			task := db.Task{
				ID:        uuid.New().String(),
				ServiceID: service.ID,
				NodeID:    selectedNode.ID,
				Status:    "pending", // executor will pick this up
			}
			db.DB.Create(&task)
		} else {
			fmt.Printf("Warning: Could not find a suitable node for service %s replica %d\n", service.Name, i+1)
			task := db.Task{
				ID:        uuid.New().String(),
				ServiceID: service.ID,
				NodeID:    "none", // Or a dummy node ID
				Status:    "dead",
				Error:     "No suitable node found for placement constraints",
			}
			db.DB.Create(&task)
		}
	}
}
