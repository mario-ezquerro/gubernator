package api

import (
	"fmt"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/examples"
)

// StackServerFilesHandler lists Compose files discovered on the Master server.
func StackServerFilesHandler(c *gin.Context) {
	customDir := c.Query("dir")
	files, err := examples.ListServerStackFiles(customDir)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"files":      files,
		"total":      len(files),
		"stacks_dir": examples.DefaultServerStacksDir(),
		"examples_dir": examples.DefaultServerExamplesDir(),
	})
}

// StackServerFileReadHandler reads the YAML content of a file on the Master server.
func StackServerFileReadHandler(c *gin.Context) {
	path := c.Query("path")
	if strings.TrimSpace(path) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "path parameter is required"})
		return
	}

	content, err := examples.ReadServerStackFile(path)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, content)
}

// StackServerDeployRequest is the payload for deploying from the server filesystem.
type StackServerDeployRequest struct {
	Path       string `json:"path" binding:"required"`
	Name       string `json:"name"`
	TargetNode string `json:"target_node"`
}

// StackServerDeployHandler deploys a Compose file residing on the Master server.
func StackServerDeployHandler(c *gin.Context) {
	var req StackServerDeployRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	stack, err := examples.DeployServerStackFile(req.Path, req.Name, req.TargetNode)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Failed to deploy stack from server file: %v", err)})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":  "Stack deployed successfully from Master server",
		"stack_id": stack.ID,
		"name":     stack.Name,
		"path":     req.Path,
	})
}

// ExamplesListHandler lists all built-in POC examples.
func ExamplesListHandler(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"examples": examples.GetAllPOCExamples(),
		"total":    len(examples.GetAllPOCExamples()),
	})
}

// ExampleGetHandler retrieves a single POC example by ID.
func ExampleGetHandler(c *gin.Context) {
	id := c.Param("id")
	ex, err := examples.GetPOCExample(id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, ex)
}

// ExampleDeployRequest is the payload for deploying a POC example.
type ExampleDeployRequest struct {
	ID         string `json:"id" binding:"required"`
	TargetNode string `json:"target_node"`
}

// ExampleDeployHandler deploys one or all POC examples into the cluster.
func ExampleDeployHandler(c *gin.Context) {
	var req ExampleDeployRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.ID == "all" {
		deployed, errs := examples.DeployAllPOCExamples(req.TargetNode)
		errStrs := make([]string, len(errs))
		for i, e := range errs {
			errStrs[i] = e.Error()
		}
		c.JSON(http.StatusOK, gin.H{
			"message":        fmt.Sprintf("Deployed %d POC examples", len(deployed)),
			"deployed_count": len(deployed),
			"errors":         errStrs,
		})
		return
	}

	stack, err := examples.DeployPOCExample(req.ID, req.TargetNode)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Failed to deploy example '%s': %v", req.ID, err)})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":    fmt.Sprintf("POC example '%s' deployed successfully", req.ID),
		"stack_id":   stack.ID,
		"stack_name": stack.Name,
	})
}
