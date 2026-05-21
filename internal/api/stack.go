package api

import (
	"fmt"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"gopkg.in/yaml.v3"
)

// ComposeFile represents a simplified structure of docker-compose.yml
type ComposeFile struct {
	Services map[string]ComposeService `yaml:"services"`
}

// ComposeService maps a docker-compose service definition, capturing all
// fields needed to run a container: image, replicas, ports, env, volumes, command, placement.
type ComposeService struct {
	Image       string            `yaml:"image"`
	Ports       []string          `yaml:"ports"`       // e.g. ["8080:80"]
	Environment []string          `yaml:"environment"` // e.g. ["FOO=bar"] or map form
	EnvMap      map[string]string `yaml:"environment_map,omitempty"`
	Volumes     []string          `yaml:"volumes"` // e.g. ["./data:/app/data"]
	Command     string            `yaml:"command"` // optional command override
	Deploy      struct {
		Replicas  int `yaml:"replicas"`
		Placement struct {
			Constraints []string `yaml:"constraints"`
		} `yaml:"placement"`
	} `yaml:"deploy"`
}

type StackDeployRequest struct {
	Name       string `json:"name" binding:"required"`
	ComposeRaw string `json:"compose_raw" binding:"required"`
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

	// Parse YAML
	var compose ComposeFile
	if err := yaml.Unmarshal([]byte(req.ComposeRaw), &compose); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Failed to parse YAML: %v", err)})
		return
	}

	// Create Stack record
	stackID := uuid.New().String()
	stack := db.Stack{
		ID:             stackID,
		Name:           req.Name,
		RawComposeFile: req.ComposeRaw,
	}
	db.DB.Create(&stack)

	// Process Services
	for srvName, srvDef := range compose.Services {
		replicas := srvDef.Deploy.Replicas
		if replicas == 0 {
			replicas = 1 // default
		}

		service := db.Service{
			ID:              uuid.New().String(),
			StackID:         stackID,
			Name:            srvName,
			Image:           srvDef.Image,
			DesiredReplicas: replicas,
			Constraints:     srvDef.Deploy.Placement.Constraints,
			Ports:           srvDef.Ports,
			Env:             srvDef.Environment,
			Volumes:         srvDef.Volumes,
			Command:         srvDef.Command,
		}
		db.DB.Create(&service)

		// Scheduler: assign Tasks to Nodes based on Constraints
		scheduleService(&service)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Stack deployed successfully", "stack_id": stackID})
}

func scheduleService(service *db.Service) {
	// For each replica, find a suitable node
	for i := 0; i < service.DesiredReplicas; i++ {
		var allNodes []db.Node
		db.DB.Where("status = ?", "active").Find(&allNodes)

		var selectedNode *db.Node

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
		}
	}
}
