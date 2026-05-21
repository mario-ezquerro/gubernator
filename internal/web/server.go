package web

import (
	"embed"
	"fmt"
	"io/fs"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/mario-ezquerro/gubernator/internal/caddy"
	"github.com/mario-ezquerro/gubernator/internal/coredns"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/mario-ezquerro/gubernator/internal/monitor"
	"gopkg.in/yaml.v3"
)

//go:embed flutter/*
var flutterFS embed.FS

// composeFile and composeService are local copies of the API types to avoid
// circular imports (api → web → api). They must stay in sync with api.ComposeFile.
type composeFile struct {
	Services map[string]composeService `yaml:"services"`
}

type composeService struct {
	Image       string   `yaml:"image"`
	Ports       []string `yaml:"ports"`
	Environment []string `yaml:"environment"`
	Volumes     []string `yaml:"volumes"`
	Command     string   `yaml:"command"`
	Deploy      struct {
		Replicas  int `yaml:"replicas"`
		Placement struct {
			Constraints []string `yaml:"constraints"`
		} `yaml:"placement"`
	} `yaml:"deploy"`
}

// webScheduleService schedules tasks for a service (same logic as api.scheduleService).
func webScheduleService(service *db.Service) {
	for i := 0; i < service.DesiredReplicas; i++ {
		var allNodes []db.Node
		db.DB.Where("status = ?", "active").Find(&allNodes)

		var selectedNode *db.Node
		for _, node := range allNodes {
			matchesAll := true
			for _, constraint := range service.Constraints {
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
				break
			}
		}

		if selectedNode != nil {
			task := db.Task{
				ID:        uuid.New().String(),
				ServiceID: service.ID,
				NodeID:    selectedNode.ID,
				Status:    "pending",
			}
			db.DB.Create(&task)
		}
	}
}

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
		api.POST("/stack", deployStackHandler)
		api.DELETE("/stack/:id", deleteStackHandler)
		api.DELETE("/task/:id", deleteTaskHandler)
		api.GET("/settings", getSettingsHandler)
		api.PUT("/settings", updateSettingsHandler)
		api.PUT("/settings/password", changePasswordHandler)

		// Node operations
		api.GET("/node/:id", nodeInspectHandler)
		api.POST("/node/:id/role", nodeRoleHandler)
		api.POST("/node/:id/availability", nodeAvailabilityHandler)
		api.POST("/node/:id/leave", nodeLeaveHandler)
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

	authorized.GET("/grafana", func(c *gin.Context) {
		c.Redirect(http.StatusMovedPermanently, "/grafana/")
	})
	authorized.Any("/grafana/*proxyPath", grafanaProxyHandler)

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
		"nodes":           nodes,
		"stacks":          stacks,
		"services":        services,
		"tasks":           tasks,
		"monitor_running": monitor.IsRunning(),
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

func deployStackHandler(c *gin.Context) {
	var req struct {
		Name    string `json:"name" binding:"required"`
		Compose string `json:"compose" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Re-parse the compose YAML
	var compose composeFile
	if err := yaml.Unmarshal([]byte(req.Compose), &compose); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Failed to parse YAML: %v", err)})
		return
	}

	// Check if stack name already exists to prevent duplicate/collisions
	var existing db.Stack
	if err := db.DB.First(&existing, "name = ?", req.Name).Error; err == nil {
		c.JSON(http.StatusConflict, gin.H{"error": fmt.Sprintf("Stack with name '%s' already exists", req.Name)})
		return
	}

	stackID := uuid.New().String()
	stack := db.Stack{
		ID:             stackID,
		Name:           req.Name,
		RawComposeFile: req.Compose,
	}
	db.DB.Create(&stack)

	for srvName, srvDef := range compose.Services {
		replicas := srvDef.Deploy.Replicas
		if replicas == 0 {
			replicas = 1
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
		webScheduleService(&service)
	}

	c.JSON(http.StatusOK, gin.H{"status": "deployed", "stack_id": stackID})
}

func redeployStackHandler(c *gin.Context) {
	id := c.Param("id")

	var stack db.Stack
	if err := db.DB.First(&stack, "id = ?", id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Stack not found"})
		return
	}

	// Special handling for the SRE Monitor stack
	if id == monitor.SREStackID {
		redeploySREStack(c)
		return
	}

	// Special handling for the Core stack (CoreDNS + Caddy)
	if id == coredns.CoreStackID {
		redeployCoreStack(c)
		return
	}

	composeRaw := stack.RawComposeFile
	stackName := stack.Name

	// 1. Stop and remove all existing containers for this stack SYNCHRONOUSLY
	var services []db.Service
	db.DB.Where("stack_id = ?", id).Find(&services)
	for _, svc := range services {
		var tasks []db.Task
		db.DB.Where("service_id = ? AND container_name != ''", svc.ID).Find(&tasks)
		for _, task := range tasks {
			stopContainerByName(task.ContainerName) // synchronous — wait for stop
		}
		db.DB.Where("service_id = ?", svc.ID).Delete(&db.Task{})
	}
	db.DB.Where("stack_id = ?", id).Delete(&db.Service{})
	db.DB.Where("id = ?", id).Delete(&db.Stack{})

	// 2. Brief pause to let Docker release the ports
	time.Sleep(2 * time.Second)

	// 3. Re-parse the compose YAML and re-deploy as a new stack
	var compose composeFile
	if err := yaml.Unmarshal([]byte(composeRaw), &compose); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to parse YAML: %v", err)})
		return
	}

	newStackID := uuid.New().String()
	newStack := db.Stack{
		ID:             newStackID,
		Name:           stackName,
		RawComposeFile: composeRaw,
	}
	db.DB.Create(&newStack)

	for srvName, srvDef := range compose.Services {
		replicas := srvDef.Deploy.Replicas
		if replicas == 0 {
			replicas = 1
		}

		service := db.Service{
			ID:              uuid.New().String(),
			StackID:         newStackID,
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
		webScheduleService(&service)
	}

	c.JSON(http.StatusOK, gin.H{"status": "redeployed", "new_stack_id": newStackID})
}

// redeploySREStack handles redeploy for the special SRE Monitor stack.
// It stops all monitoring containers, re-deploys the full stack via monitor package,
// and re-registers the containers in the database.
func redeploySREStack(c *gin.Context) {
	// 1. Stop all monitoring containers and clean up
	monitor.StopAll()
	monitor.UnregisterFromDB(db.DB)

	// 2. Brief pause for Docker to release resources
	time.Sleep(2 * time.Second)

	// 3. Re-deploy the full SRE stack
	if err := monitor.EnsureNetwork(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to create network: %v", err)})
		return
	}
	if err := monitor.WriteConfigs(nil); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to write configs: %v", err)})
		return
	}
	if err := monitor.DeployManagerStack(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("SRE deploy failed: %v", err)})
		return
	}

	// 4. Re-register in DB
	if err := monitor.RegisterInDB(db.DB); err != nil {
		log.Printf("Warning: SRE stack deployed but failed to register in DB: %v", err)
	}

	c.JSON(http.StatusOK, gin.H{"status": "redeployed"})
}

// redeployCoreStack handles redeploy for the Core Gubernator stack.
func redeployCoreStack(c *gin.Context) {
	// 1. Stop CoreDNS and Caddy
	coredns.Stop()
	caddy.Stop()
	coredns.UnregisterFromDB(db.DB)

	// 2. Brief pause for Docker to release resources
	time.Sleep(2 * time.Second)

	// 3. Re-deploy CoreDNS and Caddy
	if err := coredns.EnsureNetwork(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to create network: %v", err)})
		return
	}
	if err := coredns.EnsureRunning(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("CoreDNS deploy failed: %v", err)})
		return
	}
	if err := caddy.EnsureRunning(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Caddy deploy failed: %v", err)})
		return
	}

	// 4. Re-register in DB
	if err := coredns.RegisterInDB(db.DB); err != nil {
		log.Printf("Warning: Core stack deployed but failed to register in DB: %v", err)
	}

	c.JSON(http.StatusOK, gin.H{"status": "redeployed"})
}

// stopContainerByName calls docker stop + rm on a named container.
func stopContainerByName(name string) {
	exec.Command("docker", "stop", name).Run()
	exec.Command("docker", "rm", "-f", name).Run()
}

func nodeInspectHandler(c *gin.Context) {
	id := c.Param("id")
	var node db.Node
	if err := db.DB.First(&node, "id = ?", id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Node not found"})
		return
	}
	c.JSON(http.StatusOK, node)
}

func nodeRoleHandler(c *gin.Context) {
	id := c.Param("id")
	var req struct {
		Role string `json:"role" binding:"required"` // "worker" or "manager"
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Role != "worker" && req.Role != "manager" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid role"})
		return
	}

	res := db.DB.Model(&db.Node{}).Where("id = ?", id).Update("role", req.Role)
	if res.Error != nil || res.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "Node not found"})
		return
	}

	// Trigger Prometheus targets reload
	if err := monitor.UpdatePrometheusConfig(); err != nil {
		log.Printf("Warning: failed to update Prometheus config on node role change: %v", err)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Node role updated"})
}

func nodeAvailabilityHandler(c *gin.Context) {
	id := c.Param("id")
	var req struct {
		Availability string `json:"availability" binding:"required"` // "active", "pause", "drain"
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Availability != "active" && req.Availability != "pause" && req.Availability != "drain" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid availability"})
		return
	}

	status := "active"
	if req.Availability != "active" {
		status = req.Availability
	}

	res := db.DB.Model(&db.Node{}).Where("id = ?", id).Update("status", status)
	if res.Error != nil || res.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "Node not found"})
		return
	}

	// Trigger Prometheus targets reload
	if err := monitor.UpdatePrometheusConfig(); err != nil {
		log.Printf("Warning: failed to update Prometheus config on node availability change: %v", err)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Node availability updated"})
}

func nodeLeaveHandler(c *gin.Context) {
	id := c.Param("id")
	res := db.DB.Model(&db.Node{}).Where("id = ?", id).Update("status", "left")
	if res.Error != nil || res.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "Node not found"})
		return
	}

	// Trigger Prometheus targets reload
	if err := monitor.UpdatePrometheusConfig(); err != nil {
		log.Printf("Warning: failed to update Prometheus config on node leave: %v", err)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Node marked as left"})
}

func grafanaProxyHandler(c *gin.Context) {
	targetHost := "gbnt-monitor-grafana:3000"
	_, err := net.LookupHost("gbnt-monitor-grafana")
	if err != nil {
		targetHost = "127.0.0.1:3000"
	}

	targetURL, err := url.Parse("http://" + targetHost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to parse target URL"})
		return
	}

	proxy := httputil.NewSingleHostReverseProxy(targetURL)

	originalDirector := proxy.Director
	proxy.Director = func(req *http.Request) {
		originalDirector(req)
		req.Host = targetHost
		username, _, _ := req.BasicAuth()
		if username != "" {
			req.Header.Set("X-WEBAUTH-USER", username)
		}
		req.Header.Del("Authorization")
	}

	proxy.ServeHTTP(c.Writer, c.Request)
}


