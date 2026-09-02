package api

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/docker"
)

// ImageHostListHandler returns physical Docker images found on cluster nodes.
func ImageHostListHandler(c *gin.Context) {
	targetNode := c.DefaultQuery("node", "all")
	images, err := docker.ListClusterHostImages(targetNode)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to list host images: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"images": images,
		"count":  len(images),
		"node":   targetNode,
	})
}

// ImageHistoryHandler inspects the layer history of an image and returns a reconstructed Dockerfile.
func ImageHistoryHandler(c *gin.Context) {
	image := c.Query("image")
	if image == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "image query parameter is required"})
		return
	}
	targetNode := c.DefaultQuery("node", "manager")

	history, err := docker.InspectImageHistory(targetNode, image)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to inspect image history: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, history)
}

// ImageHostDeleteHandler deletes a Docker image from a specific node or all cluster nodes.
func ImageHostDeleteHandler(c *gin.Context) {
	image := c.Query("image")
	if image == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "image query parameter is required"})
		return
	}
	targetNode := c.DefaultQuery("node", "all")
	force := strings.EqualFold(c.DefaultQuery("force", "false"), "true")

	res, err := docker.RemoveHostImage(targetNode, image, force)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete image: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, res)
}

// ImagePruneHandler executes docker image prune across cluster nodes.
func ImagePruneHandler(c *gin.Context) {
	var req struct {
		Node      string `json:"node"`
		AllUnused bool   `json:"all_unused"`
	}
	_ = c.ShouldBindJSON(&req)
	if req.Node == "" {
		req.Node = "all"
	}

	res, err := docker.PruneHostImages(req.Node, req.AllUnused)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to prune images: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, res)
}

// ImageBuildHandler builds a Docker image on a Centurion node from a Dockerfile.
func ImageBuildHandler(c *gin.Context) {
	var req docker.ImageBuildRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid build request payload: " + err.Error()})
		return
	}

	if req.Tag == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "tag field is required"})
		return
	}
	if req.Dockerfile == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "dockerfile field is required"})
		return
	}
	if req.NodeID == "" {
		req.NodeID = "manager"
	}

	res, err := docker.BuildHostImage(req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":  "Build failed: " + err.Error(),
			"result": res,
		})
		return
	}

	c.JSON(http.StatusOK, res)
}
