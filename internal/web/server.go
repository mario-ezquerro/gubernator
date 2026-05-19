package web

import (
	"embed"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

//go:embed flutter/*
var flutterFS embed.FS

func StartDashboard() {
	webEnabled := os.Getenv("GBNT_WEB")
	user := os.Getenv("GBNT_WEB_USER")
	pass := os.Getenv("GBNT_WEB_PASSWORD")

	if webEnabled != "true" {
		log.Println("Web Dashboard disabled. Set GBNT_WEB=true, GBNT_WEB_USER and GBNT_WEB_PASSWORD to enable.")
		return
	}

	if user == "" || pass == "" {
		log.Println("Web Dashboard is enabled but missing credentials. Provide GBNT_WEB_USER and GBNT_WEB_PASSWORD.")
		return
	}

	gin.SetMode(gin.ReleaseMode)
	r := gin.Default()

	// Setup Basic Auth
	authorized := r.Group("/", gin.BasicAuth(gin.Accounts{
		user: pass,
	}))

	// API for dashboard
	api := authorized.Group("/api")
	{
		api.GET("/state", stateHandler)
		api.GET("/stack/:id/compose", getStackComposeHandler)
		api.PUT("/stack/:id/compose", updateStackComposeHandler)
		api.POST("/stack/:id/redeploy", redeployStackHandler)
		api.DELETE("/stack/:id", deleteStackHandler)
		api.DELETE("/task/:id", deleteTaskHandler)
		api.GET("/settings", getSettingsHandler)
		api.PUT("/settings", updateSettingsHandler)
		api.PUT("/settings/password", changePasswordHandler)
	}

	// Serve the Flutter web app — SPA routing
	flutterContent, err := fs.Sub(flutterFS, "flutter")
	if err != nil {
		log.Fatalf("Failed to access embedded Flutter build: %v", err)
	}
	fileServer := http.FileServer(http.FS(flutterContent))

	// Serve root path
	authorized.GET("/", func(c *gin.Context) {
		fileServer.ServeHTTP(c.Writer, c.Request)
	})

	// Catch-all: serve static file if exists, otherwise serve index.html (SPA)
	r.NoRoute(gin.BasicAuth(gin.Accounts{user: pass}), func(c *gin.Context) {
		path := c.Request.URL.Path
		// Try to serve the exact file
		if f, err := flutterContent.Open(strings.TrimPrefix(path, "/")); err == nil {
			f.Close()
			fileServer.ServeHTTP(c.Writer, c.Request)
			return
		}
		// For SPA routing, serve index.html
		c.Request.URL.Path = "/"
		fileServer.ServeHTTP(c.Writer, c.Request)
	})

	log.Println("Starting Web Dashboard (Flutter) on :4001")
	if err := r.Run(":4001"); err != nil {
		log.Fatalf("Failed to start Web Dashboard: %v", err)
	}
}

func stateHandler(c *gin.Context) {
	var nodes []db.Node
	var stacks []db.Stack
	var services []db.Service
	var tasks []db.Task

	db.DB.Find(&nodes)
	db.DB.Find(&stacks)
	db.DB.Find(&services)
	db.DB.Find(&tasks)

	c.JSON(http.StatusOK, gin.H{
		"nodes":    nodes,
		"stacks":   stacks,
		"services": services,
		"tasks":    tasks,
	})
}

func getSettingsHandler(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"display_name": os.Getenv("GBNT_WEB_USER"),
		"theme":        "dark",
	})
}

func updateSettingsHandler(c *gin.Context) {
	var req struct {
		DisplayName string `json:"display_name"`
		Theme       string `json:"theme"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "saved"})
}

func changePasswordHandler(c *gin.Context) {
	var req struct {
		CurrentPassword string `json:"current_password"`
		NewPassword     string `json:"new_password"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	currentPass := os.Getenv("GBNT_WEB_PASSWORD")
	if req.CurrentPassword != currentPass {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Current password is incorrect"})
		return
	}

	// Update the environment variable for the current process
	os.Setenv("GBNT_WEB_PASSWORD", req.NewPassword)
	c.JSON(http.StatusOK, gin.H{"status": "password_changed"})
}

func deleteStackHandler(c *gin.Context) {
	id := c.Param("id")

	// Stop containers before deleting
	var services []db.Service
	db.DB.Where("stack_id = ?", id).Find(&services)
	for _, svc := range services {
		var tasks []db.Task
		db.DB.Where("service_id = ? AND container_name != ''", svc.ID).Find(&tasks)
		for _, task := range tasks {
			go stopContainerByName(task.ContainerName)
		}
		db.DB.Where("service_id = ?", svc.ID).Delete(&db.Task{})
	}
	db.DB.Where("stack_id = ?", id).Delete(&db.Service{})
	db.DB.Where("id = ?", id).Delete(&db.Stack{})

	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func deleteTaskHandler(c *gin.Context) {
	id := c.Param("id")

	// Stop the actual container first
	var task db.Task
	if err := db.DB.First(&task, "id = ?", id).Error; err == nil && task.ContainerName != "" {
		go stopContainerByName(task.ContainerName)
	}

	db.DB.Where("id = ?", id).Delete(&db.Task{})
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func getStackComposeHandler(c *gin.Context) {
	id := c.Param("id")
	var stack db.Stack
	if err := db.DB.First(&stack, "id = ?", id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Stack not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"compose": stack.RawComposeFile})
}

func updateStackComposeHandler(c *gin.Context) {
	id := c.Param("id")
	var req struct {
		Compose string `json:"compose" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if res := db.DB.Model(&db.Stack{}).Where("id = ?", id).Update("raw_compose_file", req.Compose); res.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update compose"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "saved"})
}

func redeployStackHandler(c *gin.Context) {
	id := c.Param("id")

	var stack db.Stack
	if err := db.DB.First(&stack, "id = ?", id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Stack not found"})
		return
	}

	// Stop and remove all existing containers for this stack
	var services []db.Service
	db.DB.Where("stack_id = ?", id).Find(&services)
	for _, svc := range services {
		var tasks []db.Task
		db.DB.Where("service_id = ? AND container_name != ''", svc.ID).Find(&tasks)
		for _, task := range tasks {
			go stopContainerByName(task.ContainerName)
		}
		db.DB.Where("service_id = ?", svc.ID).Delete(&db.Task{})
	}
	db.DB.Where("stack_id = ?", id).Delete(&db.Service{})

	// Re-trigger deploy via the REST API (reuse the same compose raw)
	webClient := &http.Client{}
	token := os.Getenv("GBNT_API_TOKEN")
	if token == "" {
		token = "admin"
	}
	payload := fmt.Sprintf(`{"name":%q,"compose_raw":%q}`, stack.Name, stack.RawComposeFile)
	req, _ := http.NewRequest("POST", "http://localhost:4000/v1/stack/deploy", strings.NewReader(payload))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	resp, err := webClient.Do(req)
	if err != nil || resp.StatusCode != http.StatusOK {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to redeploy stack"})
		return
	}
	resp.Body.Close()

	c.JSON(http.StatusOK, gin.H{"status": "redeployed"})
}

// stopContainerByName calls docker stop + rm on a named container.
func stopContainerByName(name string) {
	exec.Command("docker", "stop", name).Run()
	exec.Command("docker", "rm", "-f", name).Run()
}
