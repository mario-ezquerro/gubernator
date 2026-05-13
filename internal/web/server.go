package web

import (
	"embed"
	"html/template"
	"log"
	"net/http"
	"os"

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
	
	var services []db.Service
	db.DB.Where("stack_id = ?", id).Find(&services)
	for _, svc := range services {
		db.DB.Where("service_id = ?", svc.ID).Delete(&db.Task{})
	}
	db.DB.Where("stack_id = ?", id).Delete(&db.Service{})
	db.DB.Where("id = ?", id).Delete(&db.Stack{})
	
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func deleteTaskHandler(c *gin.Context) {
	id := c.Param("id")
	db.DB.Where("id = ?", id).Delete(&db.Task{})
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}
