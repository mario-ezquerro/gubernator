package web

import (
	"embed"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

//go:embed templates/* static/*
var fs embed.FS

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

	// Load HTML templates from embedded filesystem
	templ := template.Must(template.New("").ParseFS(fs, "templates/*.html"))
	r.SetHTMLTemplate(templ)

	// Serve static files
	r.StaticFS("/static", http.FS(fs))

	// Setup Basic Auth
	authorized := r.Group("/", gin.BasicAuth(gin.Accounts{
		user: pass,
	}))

	authorized.GET("/", dashboardHandler)

	// API for dashboard
	api := authorized.Group("/api")
	{
		api.GET("/state", stateHandler)
		api.GET("/stack/:id/compose", getStackComposeHandler)
		api.PUT("/stack/:id/compose", updateStackComposeHandler)
		api.POST("/stack/:id/redeploy", redeployStackHandler)
		api.DELETE("/stack/:id", deleteStackHandler)
		api.DELETE("/task/:id", deleteTaskHandler)
	}

	log.Println("Starting Web Dashboard on :4001")
	if err := r.Run(":4001"); err != nil {
		log.Fatalf("Failed to start Web Dashboard: %v", err)
	}
}

func dashboardHandler(c *gin.Context) {
	c.HTML(http.StatusOK, "index.html", gin.H{
		"title": "Gubernator Dashboard",
	})
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
