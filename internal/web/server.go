package web

import (
	"embed"
	"fmt"
	"io/fs"
	"log/slog"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/exec"
	"sort"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/creack/pty"
	"github.com/mario-ezquerro/gubernator/internal/aqueducts"
	"github.com/mario-ezquerro/gubernator/internal/caddy"
	"github.com/mario-ezquerro/gubernator/internal/coredns"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/mario-ezquerro/gubernator/internal/monitor"
	"golang.org/x/crypto/ssh"
	"gopkg.in/yaml.v3"
)

//go:embed flutter/*
var flutterFS embed.FS

// Version is the current version of Gubernator, populated by main or VERSION file.
var Version = "dev"

func GetVersion() string {
	if Version == "" || Version == "dev" {
		for _, path := range []string{"VERSION", "/app/VERSION", "../VERSION"} {
			if data, err := os.ReadFile(path); err == nil {
				v := strings.TrimSpace(string(data))
				if v != "" {
					Version = v
					return v
				}
			}
		}
	}
	return Version
}


// envSlice handles both sequence/list (e.g. ["FOO=bar"]) and map (e.g. FOO: bar) formats for environment variables in YAML.
type envSlice []string

func (e *envSlice) UnmarshalYAML(value *yaml.Node) error {
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

// composeFile and composeService are local copies of the API types to avoid
// circular imports (api → web → api). They must stay in sync with api.ComposeFile.
type composeFile struct {
	Name     string                    `yaml:"name"` // Top-level name in compose file
	Services map[string]composeService `yaml:"services"`
}

type composeService struct {
	Image       string   `yaml:"image"`
	Ports       []string `yaml:"ports"`
	Environment envSlice `yaml:"environment"` // handles both list and map formats
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
func webScheduleService(service *db.Service, targetNode string) {
	for i := 0; i < service.DesiredReplicas; i++ {
		var selectedNode *db.Node

		if targetNode != "" && targetNode != "auto" {
			var n db.Node
			if err := db.DB.First(&n, "id = ? OR ip = ?", targetNode, targetNode).Error; err == nil {
				selectedNode = &n
			}
		}

		if selectedNode == nil {
			var allNodes []db.Node
			db.DB.Where("status = ?", "active").Find(&allNodes)

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
		}

		if selectedNode != nil {
			task := db.Task{
				ID:        uuid.New().String(),
				ServiceID: service.ID,
				NodeID:    selectedNode.ID,
				Status:    "pending",
			}
			db.DB.Create(&task)
		} else {
			task := db.Task{
				ID:        uuid.New().String(),
				ServiceID: service.ID,
				NodeID:    "none",
				Status:    "dead",
				Error:     "No suitable node found for placement constraints",
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
		slog.Info("web dashboard disabled; set GBNT_WEB=true, GBNT_WEB_USER and GBNT_WEB_PASSWORD to enable")
		return
	}

	if user == "" || pass == "" {
		slog.Warn("web dashboard missing credentials; provide GBNT_WEB_USER and GBNT_WEB_PASSWORD")
		return
	}

	sessionToken := uuid.New().String()

	gin.SetMode(gin.ReleaseMode)
	r := gin.Default()

	// Setup Basic Auth
	authorized := r.Group("/", gin.BasicAuth(gin.Accounts{
		user: pass,
	}))

	// Middleware to set SSO cookie on successful Basic Auth & disable static caching
	authorized.Use(func(c *gin.Context) {
		c.Header("Cache-Control", "no-cache, no-store, must-revalidate")
		c.Header("Pragma", "no-cache")
		c.Header("Expires", "0")
		authUser := c.GetString(gin.AuthUserKey)
		if authUser != "" {
			c.SetCookie("gbnt_session", sessionToken, 3600*24, "/", "", false, true)
		}
		c.Next()
	})

	// API for dashboard
	api := authorized.Group("/api")
	{
		api.GET("/state", stateHandler)
		api.GET("/stack/:id/compose", getStackComposeHandler)
		api.PUT("/stack/:id/compose", updateStackComposeHandler)
		api.POST("/stack/:id/redeploy", redeployStackHandler)
		api.POST("/stack", deployStackHandler)
		api.DELETE("/stack/:id", deleteStackHandler)
		api.POST("/stack/:id/migrate", migrateStackHandler)
		api.DELETE("/task/:id", deleteTaskHandler)
		api.POST("/task/:id/action", taskActionHandler)
		api.GET("/task/:id/logs", taskLogsHandler)
		api.GET("/task/:id/inspect", taskInspectHandler)
		api.GET("/task/:id/shell", taskShellHandler)
		api.GET("/settings", getSettingsHandler)
		api.PUT("/settings", updateSettingsHandler)
		api.PUT("/settings/password", changePasswordHandler)

		// Node operations
		api.GET("/node/:id", nodeInspectHandler)
		api.POST("/node/:id/role", nodeRoleHandler)
		api.POST("/node/:id/availability", nodeAvailabilityHandler)
		api.POST("/node/:id/reboot", nodeRebootHandler)
		api.POST("/node/:id/leave", nodeLeaveHandler)
		api.POST("/node/:id/labels", nodeLabelsHandler)
		api.POST("/node/add", nodeAddHandler)
		api.GET("/node/:id/shell", nodeShellHandler)

		// CoreDNS config
		api.GET("/coredns/config", getCoreDNSConfigHandler)
		api.PUT("/coredns/config", updateCoreDNSConfigHandler)

		// Weave Scope Network Topology
		api.GET("/scope/status", scopeStatusHandler)
		api.POST("/scope/enable", scopeEnableHandler)
		api.POST("/scope/disable", scopeDisableHandler)
	}

	// Serve the Flutter web app — SPA routing
	flutterContent, err := fs.Sub(flutterFS, "flutter")
	if err != nil {
		slog.Error("failed to access embedded Flutter build", "err", err)
		return
	}
	fileServer := http.FileServer(http.FS(flutterContent))

	// Serve root path
	authorized.GET("/", func(c *gin.Context) {
		fileServer.ServeHTTP(c.Writer, c.Request)
	})

	r.GET("/grafana", func(c *gin.Context) {
		c.Redirect(http.StatusMovedPermanently, "/grafana/")
	})
	r.Any("/grafana/*proxyPath", func(c *gin.Context) {
		grafanaProxyHandler(c, sessionToken, user, pass)
	})

	r.GET("/jaeger", func(c *gin.Context) {
		c.Redirect(http.StatusMovedPermanently, "/jaeger/")
	})
	r.Any("/jaeger/*proxyPath", func(c *gin.Context) {
		jaegerProxyHandler(c, sessionToken, user, pass)
	})

	// Catch-all: serve static file if exists, otherwise serve index.html (SPA)
	r.NoRoute(gin.BasicAuth(gin.Accounts{user: pass}), func(c *gin.Context) {
		c.Header("Cache-Control", "no-cache, no-store, must-revalidate")
		c.Header("Pragma", "no-cache")
		c.Header("Expires", "0")
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

	slog.Info("starting web dashboard", "addr", ":4001")
	if err := r.Run(":4001"); err != nil {
		slog.Error("web dashboard error", "err", err)
	}
}

type DNSRecord struct {
	IP       string `json:"ip"`
	Hostname string `json:"hostname"`
}

func getDNSRecords() []DNSRecord {
	records := []DNSRecord{}
	hostsPath := coredns.HostsFilePath()
	content, err := os.ReadFile(hostsPath)
	if err != nil {
		return records
	}
	lines := strings.Split(string(content), "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) >= 2 {
			records = append(records, DNSRecord{
				IP:       fields[0],
				Hostname: fields[1],
			})
		}
	}
	return records
}

func stateHandler(c *gin.Context) {
	// Sync worker system stacks (cleans up any orphan stacks from left nodes)
	coredns.SyncWorkerCoreStacks(db.DB)
	monitor.SyncWorkerSreStacks(db.DB)

	var nodes []db.Node
	var stacks []db.Stack
	var services []db.Service
	var tasks []db.Task

	db.DB.Find(&nodes)
	db.DB.Find(&stacks)
	db.DB.Find(&services)
	db.DB.Find(&tasks)

	monitor.PopulateNodeMetrics(nodes)

	caddyfilePath := caddy.CaddyfilePath()
	caddyfileContent := ""
	if content, err := os.ReadFile(caddyfilePath); err == nil {
		caddyfileContent = string(content)
	}

	// Dynamic population of the Manager's live Caddy configuration inside the nodes list
	for i, n := range nodes {
		if n.Role == "manager" {
			nodes[i].CaddyStatus = caddy.Status()
			nodes[i].Caddyfile = caddyfileContent
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"nodes":           nodes,
		"stacks":          stacks,
		"services":        services,
		"tasks":           tasks,
		"monitor_running": monitor.IsRunning(),
		"dns_records":     getDNSRecords(),
		"caddy_status":    caddy.Status(),
		"caddyfile":       caddyfileContent,
		"version":         GetVersion(),
	})
}

// --- CoreDNS Endpoints ---

func getCoreDNSConfigHandler(c *gin.Context) {
	content, err := os.ReadFile(coredns.CorefilePath())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read CoreDNS config: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"config": string(content)})
}

func updateCoreDNSConfigHandler(c *gin.Context) {
	var req struct {
		Config string `json:"config"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body"})
		return
	}

	if req.Config == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Config cannot be empty"})
		return
	}

	if err := os.WriteFile(coredns.CorefilePath(), []byte(req.Config), 0644); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save CoreDNS config: " + err.Error()})
		return
	}

	if err := coredns.Restart(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Config saved but failed to restart CoreDNS: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true})
}

// --- Settings Endpoints ---

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

	// Special handling for SRE Monitor stack
	if id == monitor.SREStackID {
		// Stop and remove all monitoring containers (Docker)
		monitor.StopAll()
		// Update tasks status to "dead" and clear container IP in DB, keeping stack and services
		var services []db.Service
		db.DB.Where("stack_id = ?", id).Find(&services)
		for _, svc := range services {
			db.DB.Model(&db.Task{}).Where("service_id = ?", svc.ID).Updates(map[string]interface{}{
				"status":       "dead",
				"container_ip": "",
			})
		}
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
		return
	}

	// Special handling for Core stack (CoreDNS + Caddy + Gubernator)
	if id == coredns.CoreStackID {
		// Restart the core containers but do not delete them from database or stop/remove them permanently
		var services []db.Service
		db.DB.Where("stack_id = ?", id).Find(&services)
		for _, svc := range services {
			var tasks []db.Task
			db.DB.Where("service_id = ?", svc.ID).Find(&tasks)
			for _, task := range tasks {
				if task.ContainerName != "" {
					go func(name string) {
						exec.Command("docker", "restart", name).Run()
					}(task.ContainerName)
				}
			}
		}
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
		return
	}

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

	go aqueducts.GenerateHostsFile()
	go aqueducts.GenerateCaddyfile()

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

	go aqueducts.GenerateHostsFile()
	go aqueducts.GenerateCaddyfile()

	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func taskActionHandler(c *gin.Context) {
	id := c.Param("id")
	var req struct {
		Action string `json:"action" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid payload"})
		return
	}

	var task db.Task
	if err := db.DB.First(&task, "id = ?", id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Task not found"})
		return
	}

	if task.ContainerName == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Task has no container assigned"})
		return
	}

	var err error
	switch req.Action {
	case "pause":
		err = exec.Command("docker", "pause", task.ContainerName).Run()
	case "unpause":
		err = exec.Command("docker", "unpause", task.ContainerName).Run()
	case "restart":
		err = exec.Command("docker", "restart", task.ContainerName).Run()
	case "start":
		err = exec.Command("docker", "start", task.ContainerName).Run()
	case "stop":
		err = exec.Command("docker", "stop", task.ContainerName).Run()
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "Unknown action"})
		return
	}

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to execute docker action: %v", err)})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func taskLogsHandler(c *gin.Context) {
	id := c.Param("id")
	var task db.Task
	if err := db.DB.First(&task, "id = ?", id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Task not found"})
		return
	}
	if task.ContainerName == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Task has no container assigned"})
		return
	}

	out, err := exec.Command("docker", "logs", "--tail", "200", task.ContainerName).CombinedOutput()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to get logs: %v", err)})
		return
	}

	c.JSON(http.StatusOK, gin.H{"logs": string(out)})
}

func taskInspectHandler(c *gin.Context) {
	id := c.Param("id")
	var task db.Task
	if err := db.DB.First(&task, "id = ?", id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Task not found"})
		return
	}
	if task.ContainerName == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Task has no container assigned"})
		return
	}

	out, err := exec.Command("docker", "inspect", task.ContainerName).CombinedOutput()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to inspect: %v", err)})
		return
	}

	c.Data(http.StatusOK, "application/json", out)
}

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true // Allow all origins for the dashboard
	},
}

func taskShellHandler(c *gin.Context) {
	id := c.Param("id")
	var task db.Task
	if err := db.DB.First(&task, "id = ?", id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Task not found"})
		return
	}
	if task.ContainerName == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Task has no container assigned"})
		return
	}

	ws, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		slog.Error("failed to upgrade websocket", "err", err)
		return
	}
	defer ws.Close()

	cmd := exec.Command("docker", "exec", "-it", task.ContainerName, "/bin/sh")
	ptmx, err := pty.Start(cmd)
	if err != nil {
		ws.WriteMessage(websocket.TextMessage, []byte(fmt.Sprintf("Failed to start shell: %v\r\n", err)))
		return
	}
	defer func() {
		_ = ptmx.Close()
	}()

	// Copy from PTY to WebSocket
	go func() {
		buf := make([]byte, 1024)
		for {
			n, err := ptmx.Read(buf)
			if err != nil {
				break
			}
			if err := ws.WriteMessage(websocket.TextMessage, buf[:n]); err != nil {
				break
			}
		}
	}()

	// Copy from WebSocket to PTY
	for {
		_, msg, err := ws.ReadMessage()
		if err != nil {
			break
		}
		_, err = ptmx.Write(msg)
		if err != nil {
			break
		}
	}
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

	var stack db.Stack
	if err := db.DB.First(&stack, "id = ?", id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Stack not found"})
		return
	}

	// Replace placeholders like {{stack.name}} with the actual stack name
	composeRaw := strings.ReplaceAll(req.Compose, "{{stack.name}}", stack.Name)

	if res := db.DB.Model(&db.Stack{}).Where("id = ?", id).Update("raw_compose_file", composeRaw); res.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update compose"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "saved"})
}

func deployStackHandler(c *gin.Context) {
	var req struct {
		Name       string `json:"name"`
		Compose    string `json:"compose" binding:"required"`
		TargetNode string `json:"target_node"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	stackName := req.Name

	// Try to infer it from the raw YAML if present
	var tempCompose composeFile
	if err := yaml.Unmarshal([]byte(req.Compose), &tempCompose); err == nil {
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
		c.JSON(http.StatusBadRequest, gin.H{"error": "Stack name is required"})
		return
	}

	// Replace placeholders like {{stack.name}} with the actual stack name
	composeRaw := strings.ReplaceAll(req.Compose, "{{stack.name}}", stackName)

	// Re-parse the compose YAML
	var compose composeFile
	if err := yaml.Unmarshal([]byte(composeRaw), &compose); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Failed to parse YAML: %v", err)})
		return
	}

	// Check if stack name already exists to prevent duplicate/collisions
	var existing db.Stack
	if err := db.DB.First(&existing, "name = ?", stackName).Error; err == nil {
		c.JSON(http.StatusConflict, gin.H{"error": fmt.Sprintf("Stack with name '%s' already exists", stackName)})
		return
	}

	stackID := uuid.New().String()
	stack := db.Stack{
		ID:             stackID,
		Name:           stackName,
		RawComposeFile: composeRaw,
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
			Env:             []string(srvDef.Environment),
			Volumes:         srvDef.Volumes,
			Command:         srvDef.Command,
		}
		db.DB.Create(&service)
		webScheduleService(&service, req.TargetNode)
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

	// 1. Parse the (potentially updated) compose YAML
	var compose composeFile
	if err := yaml.Unmarshal([]byte(composeRaw), &compose); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to parse YAML: %v", err)})
		return
	}

	// 2. Load existing services for this stack, indexed by name
	var existingServices []db.Service
	db.DB.Where("stack_id = ?", id).Find(&existingServices)
	existingByName := make(map[string]db.Service)
	for _, svc := range existingServices {
		existingByName[svc.Name] = svc
	}

	var summary []string

	// 3. Process each service in the new compose definition
	for srvName, srvDef := range compose.Services {
		newReplicas := srvDef.Deploy.Replicas
		if newReplicas == 0 {
			newReplicas = 1
		}

		if existing, ok := existingByName[srvName]; ok {
			// Service already exists — check what changed
			if serviceDefinitionChanged(existing, srvDef) {
				// Definition changed (image, ports, env, etc.) → full teardown + recreate
				slog.Info("redeploy: definition changed, full recreate", "service", srvName)
				stopAllTasksForService(existing.ID)
				updateServiceRecord(&existing, srvDef, newReplicas)
				webScheduleService(&existing, "")
				summary = append(summary, fmt.Sprintf("%s: recreated (%d replicas)", srvName, newReplicas))
			} else if existing.DesiredReplicas != newReplicas {
				// Only replica count changed → incremental scale
				delta := newReplicas - existing.DesiredReplicas
				slog.Info("redeploy: scaling service", "service", srvName, "from", existing.DesiredReplicas, "to", newReplicas, "delta", delta)
				if delta > 0 {
					scaleServiceUp(&existing, delta)
				} else {
					scaleServiceDown(&existing, -delta)
				}
				// Update DesiredReplicas in DB
				db.DB.Model(&db.Service{}).Where("id = ?", existing.ID).Update("desired_replicas", newReplicas)
				summary = append(summary, fmt.Sprintf("%s: scaled %d → %d", srvName, existing.DesiredReplicas, newReplicas))
			} else {
				// Nothing changed for this service
				summary = append(summary, fmt.Sprintf("%s: unchanged", srvName))
			}
			delete(existingByName, srvName)
		} else {
			// Brand new service — create and schedule
			slog.Info("redeploy: new service, creating replicas", "service", srvName, "replicas", newReplicas)
			service := db.Service{
				ID:              uuid.New().String(),
				StackID:         id,
				Name:            srvName,
				Image:           srvDef.Image,
				DesiredReplicas: newReplicas,
				Constraints:     srvDef.Deploy.Placement.Constraints,
				Ports:           srvDef.Ports,
				Env:             []string(srvDef.Environment),
				Volumes:         srvDef.Volumes,
				Command:         srvDef.Command,
			}
			db.DB.Create(&service)
			webScheduleService(&service, "")
			summary = append(summary, fmt.Sprintf("%s: created (%d replicas)", srvName, newReplicas))
		}
	}

	// 4. Remove services that were in the old compose but not in the new one
	for srvName, orphan := range existingByName {
		slog.Info("redeploy: service removed, stopping", "service", srvName)
		stopAllTasksForService(orphan.ID)
		db.DB.Where("id = ?", orphan.ID).Delete(&db.Service{})
		summary = append(summary, fmt.Sprintf("%s: removed", srvName))
	}

	c.JSON(http.StatusOK, gin.H{"status": "redeployed", "stack_id": id, "changes": summary})
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
	if err := monitor.DeployManagerStack(os.Getenv("GBNT_WEB_USER"), os.Getenv("GBNT_WEB_PASSWORD")); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("SRE deploy failed: %v", err)})
		return
	}

	// 4. Re-register in DB
	if err := monitor.RegisterInDB(db.DB); err != nil {
		slog.Warn("SRE stack deployed but failed to register in DB", "err", err)
	}
	aqueducts.GenerateHostsFile()

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
		slog.Warn("core stack deployed but failed to register in DB", "err", err)
	}
	aqueducts.GenerateHostsFile()

	c.JSON(http.StatusOK, gin.H{"status": "redeployed"})
}

// ─── Incremental Scaling Helpers ─────────────────────────────────────

// serviceDefinitionChanged returns true if any field besides DesiredReplicas
// differs between the existing DB service and the new compose definition.
func serviceDefinitionChanged(existing db.Service, newDef composeService) bool {
	if existing.Image != newDef.Image {
		return true
	}
	if existing.Command != newDef.Command {
		return true
	}
	if !stringSlicesEqual(existing.Ports, newDef.Ports) {
		return true
	}
	if !stringSlicesEqual(existing.Env, []string(newDef.Environment)) {
		return true
	}
	if !stringSlicesEqual(existing.Volumes, newDef.Volumes) {
		return true
	}
	if !stringSlicesEqual(existing.Constraints, newDef.Deploy.Placement.Constraints) {
		return true
	}
	return false
}

func migrateStackHandler(c *gin.Context) {
	id := c.Param("id")
	var req struct {
		TargetNode string `json:"target_node" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Target node is required"})
		return
	}

	var stack db.Stack
	if err := db.DB.First(&stack, "id = ?", id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Stack not found"})
		return
	}

	// Reject system infrastructure stacks from manual host migration
	if id == monitor.SREStackID || id == coredns.CoreStackID ||
		strings.Contains(strings.ToLower(stack.Name), "sre") ||
		strings.Contains(strings.ToLower(stack.Name), "core-gbnt") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Infrastructure stacks cannot be manually migrated"})
		return
	}

	// Validate target node exists and is active
	var targetNode db.Node
	if err := db.DB.First(&targetNode, "id = ? OR ip = ?", req.TargetNode, req.TargetNode).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Target node not found"})
		return
	}
	if targetNode.Status != "active" && targetNode.Status != "ready" {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Target node %s is not active (status: %s)", targetNode.ID, targetNode.Status)})
		return
	}

	// Load all services belonging to this stack
	var services []db.Service
	db.DB.Where("stack_id = ?", id).Find(&services)

	for _, svc := range services {
		slog.Info("Migrating service tasks to target node", "stack", stack.Name, "service", svc.Name, "target_node", targetNode.ID)
		// 1. Stop and remove existing tasks for this service
		stopAllTasksForService(svc.ID)
		// 2. Schedule new replicas explicitly targeting the new target node
		webScheduleService(&svc, targetNode.ID)
	}

	// Regenerate DNS & Caddy ingress
	go aqueducts.GenerateHostsFile()
	go aqueducts.GenerateCaddyfile()

	c.JSON(http.StatusOK, gin.H{
		"status":      "migrated",
		"stack_id":    id,
		"target_node": targetNode.ID,
		"target_ip":   targetNode.IP,
	})
}

// stringSlicesEqual compares two string slices for equality (order-sensitive).
func stringSlicesEqual(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// stopAllTasksForService stops all running containers for a service and deletes
// the task records from the DB. This is synchronous — it waits for each stop.
func stopAllTasksForService(serviceID string) {
	var tasks []db.Task
	db.DB.Where("service_id = ? AND container_name != ''", serviceID).Find(&tasks)
	for _, task := range tasks {
		stopContainerByName(task.ContainerName)
	}
	db.DB.Where("service_id = ?", serviceID).Delete(&db.Task{})
}

// updateServiceRecord updates an existing service's definition in the DB
// to match the new compose values, then persists the change.
func updateServiceRecord(svc *db.Service, newDef composeService, replicas int) {
	svc.Image = newDef.Image
	svc.Ports = newDef.Ports
	svc.Env = []string(newDef.Environment)
	svc.Volumes = newDef.Volumes
	svc.Command = newDef.Command
	svc.Constraints = newDef.Deploy.Placement.Constraints
	svc.DesiredReplicas = replicas
	db.DB.Save(svc)
}

// scaleServiceUp schedules `count` new tasks for an existing service.
func scaleServiceUp(svc *db.Service, count int) {
	for i := 0; i < count; i++ {
		var allNodes []db.Node
		db.DB.Where("status = ?", "active").Find(&allNodes)

		var selectedNode *db.Node
		for _, node := range allNodes {
			matchesAll := true
			for _, constraint := range svc.Constraints {
				parts := strings.Split(constraint, "==")
				if len(parts) == 2 {
					leftSide := strings.TrimSpace(parts[0])
					if !strings.HasPrefix(leftSide, "node.labels.") {
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
				ServiceID: svc.ID,
				NodeID:    selectedNode.ID,
				Status:    "pending",
			}
			db.DB.Create(&task)
		}
	}
}

// scaleServiceDown stops and removes the `count` newest tasks for a service.
// Tasks are sorted by created_at DESC so the most recently created are removed first.
func scaleServiceDown(svc *db.Service, count int) {
	var tasks []db.Task
	db.DB.Where("service_id = ?", svc.ID).Find(&tasks)

	// Sort by CreatedAt descending (newest first)
	sort.Slice(tasks, func(i, j int) bool {
		return tasks[i].CreatedAt.After(tasks[j].CreatedAt)
	})

	// Stop up to `count` tasks
	for i := 0; i < count && i < len(tasks); i++ {
		if tasks[i].ContainerName != "" {
			stopContainerByName(tasks[i].ContainerName)
		}
		db.DB.Where("id = ?", tasks[i].ID).Delete(&db.Task{})
	}
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
		slog.Warn("failed to update Prometheus config on node role change", "err", err)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Node role updated"})
}

func nodeAvailabilityHandler(c *gin.Context) {
	id := c.Param("id")
	var req struct {
		Availability string `json:"availability" binding:"required"` // "active", "maintenance"
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	status := req.Availability
	if status != "active" && status != "maintenance" && status != "pause" && status != "drain" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid availability"})
		return
	}

	res := db.DB.Model(&db.Node{}).Where("id = ?", id).Update("status", status)
	if res.Error != nil || res.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "Node not found"})
		return
	}

	// Trigger node task draining if status is maintenance, drain or pause
	if status == "drain" || status == "maintenance" || status == "pause" {
		go webDrainNodeTasks(id)
	} else if status == "active" {
		// When reactivating node, reschedule missing replicas and re-evaluate services
		go webRescheduleUnassignedTasks()
	}

	// Trigger Prometheus targets reload
	if err := monitor.UpdatePrometheusConfig(); err != nil {
		slog.Warn("failed to update Prometheus config on node availability change", "err", err)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Node availability updated"})
}

func nodeRebootHandler(c *gin.Context) {
	id := c.Param("id")

	var node db.Node
	if err := db.DB.First(&node, "id = ?", id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Node not found"})
		return
	}

	// 1. Mark status as maintenance and evacuate tasks
	db.DB.Model(&node).Update("status", "maintenance")
	go webDrainNodeTasks(id)

	// 2. Trigger reboot asynchronously via SSH to target node IP
	targetIP := node.IP
	if targetIP == "" || targetIP == "127.0.0.1" {
		targetIP = "192.168.252.11"
	}

	go func(ip string) {
		time.Sleep(1 * time.Second)
		slog.Info("node reboot initiated via SSH", "node_id", id, "ip", ip)

		sshArgs := []string{"-o", "UserKnownHostsFile=/dev/null", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=5"}
		keyCandidates := []string{
			"/root/.ssh/id_ed25519",
			"/root/.ssh/id_rsa",
			"/data/id_ed25519",
			"/data/id_rsa",
			"/data/ssh/id_ed25519",
			"/data/ssh/id_rsa",
		}
		for _, k := range keyCandidates {
			if _, err := os.Stat(k); err == nil {
				sshArgs = append(sshArgs, "-i", k)
				break
			}
		}
		sshArgs = append(sshArgs, fmt.Sprintf("ubuntu@%s", ip), "sudo", "reboot")
		
		// Try SSH reboot to worker/manager host
		cmd := exec.Command("ssh", sshArgs...)
		if err := cmd.Run(); err != nil {
			slog.Warn("ssh reboot returned error, trying fallback local reboot", "ip", ip, "err", err)
			exec.Command("sudo", "reboot").Run()
		}
	}(targetIP)

	c.JSON(http.StatusOK, gin.H{"message": fmt.Sprintf("Reboot initiated for node %s (%s)", node.ID, targetIP)})
}

func nodeLeaveHandler(c *gin.Context) {
	id := c.Param("id")

	// 1. Drain node tasks and migrate all services to active nodes before leaving
	webDrainNodeTasks(id)

	// 2. Delete node record from database completely
	res := db.DB.Where("id = ?", id).Delete(&db.Node{})
	if res.Error != nil || res.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "Node not found"})
		return
	}

	// Trigger Prometheus targets reload
	if err := monitor.UpdatePrometheusConfig(); err != nil {
		slog.Warn("failed to update Prometheus config on node leave", "err", err)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Node drained and deleted from cluster"})
}

type addNodeRequest struct {
	Host     string `json:"host" binding:"required"`
	User     string `json:"user" binding:"required"`
	Password string `json:"password" binding:"required"`
}

func runRemoteSSHCommand(host, user, password, command string) (string, error) {
	config := &ssh.ClientConfig{
		User: user,
		Auth: []ssh.AuthMethod{
			ssh.Password(password),
		},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         12 * time.Second,
	}

	address := host
	if !strings.Contains(address, ":") {
		address = address + ":22"
	}

	client, err := ssh.Dial("tcp", address, config)
	if err != nil {
		return "", fmt.Errorf("SSH connection failed to %s: %v", address, err)
	}
	defer client.Close()

	session, err := client.NewSession()
	if err != nil {
		return "", fmt.Errorf("failed to open SSH session: %v", err)
	}
	defer session.Close()

	output, err := session.CombinedOutput(command)
	return string(output), err
}

func nodeAddHandler(c *gin.Context) {
	var req addNodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Host, User, and Password are required"})
		return
	}

	// 1. Fetch system info via SSH from target host
	infoCmd := "hostname && uname -m && nproc && free -m | awk '/Mem:/ {print $2}'"
	out, err := runRemoteSSHCommand(req.Host, req.User, req.Password, infoCmd)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Failed to connect via SSH: %v", err)})
		return
	}

	lines := strings.Split(strings.TrimSpace(out), "\n")
	hostname := strings.TrimSpace(req.Host)
	if len(lines) > 0 && strings.TrimSpace(lines[0]) != "" {
		hostname = strings.TrimSpace(lines[0])
	}

	var cpuCount int = 2
	var ramMB int = 2048
	if len(lines) >= 3 {
		fmt.Sscanf(lines[2], "%d", &cpuCount)
	}
	if len(lines) >= 4 {
		fmt.Sscanf(lines[3], "%d", &ramMB)
	}

	nodeID := fmt.Sprintf("node-%s", strings.ReplaceAll(hostname, ".", "-"))

	// Check if node already exists in DB
	var existing db.Node
	if err := db.DB.First(&existing, "id = ? OR ip = ?", nodeID, req.Host).Error; err == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Node with IP %s or ID %s already exists", req.Host, existing.ID)})
		return
	}

	// 2. Deploy Worker Container on remote host via SSH
	managerIP := os.Getenv("GBNT_MANAGER_IP")
	if managerIP == "" {
		managerIP = "192.168.252.11"
	}
	joinToken := db.GetJoinToken()

	deployCmd := fmt.Sprintf(
		"sudo docker run -d --name gbnt-worker --network host --restart always "+
			"-v /var/run/docker.sock:/var/run/docker.sock "+
			"marioezquerro/gubernator:latest agent --join %s:4000 --token %s",
		managerIP, joinToken,
	)

	// Attempt remote docker deployment asynchronously
	go func() {
		_, err := runRemoteSSHCommand(req.Host, req.User, req.Password, deployCmd)
		if err != nil {
			slog.Warn("remote docker run error (or container already running)", "host", req.Host, "err", err)
		}
	}()

	// 3. Register Node in Database
	node := db.Node{
		ID:        nodeID,
		IP:        req.Host,
		Role:      "worker",
		Status:    "active",
		Labels:    map[string]string{"gbnt.node.role": "worker"},
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}

	if err := db.DB.Create(&node).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to save node: %v", err)})
		return
	}

	// Trigger Prometheus & Aqueducts updates
	go aqueducts.GenerateHostsFile()
	go aqueducts.GenerateCaddyfile()
	if err := monitor.UpdatePrometheusConfig(); err != nil {
		slog.Warn("failed to update Prometheus config on node add", "err", err)
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Node successfully added to cluster",
		"node":    node,
	})
}

type nodeLabelsRequest struct {
	Labels map[string]string `json:"labels" binding:"required"`
}

func nodeLabelsHandler(c *gin.Context) {
	id := c.Param("id")
	var req nodeLabelsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := db.UpdateNodeLabels(id, req.Labels); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Trigger Prometheus targets reload
	if err := monitor.UpdatePrometheusConfig(); err != nil {
		slog.Warn("failed to update Prometheus config on node labels change", "err", err)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Node labels updated"})
}

func grafanaProxyHandler(c *gin.Context, sessionToken, expectedUser, expectedPass string) {
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
		
		username := c.GetString(gin.AuthUserKey)
		
		if username == "" {
			if cookie, err := c.Cookie("gbnt_session"); err == nil && cookie == sessionToken {
				username = expectedUser
			}
		}

		if username == "" {
			u, p, hasAuth := req.BasicAuth()
			if hasAuth && u == expectedUser && p == expectedPass {
				username = expectedUser
			}
		}

		if username == "" {
			return
		}

		req.Header.Set("X-WEBAUTH-USER", username)
		req.Header.Del("Authorization")
	}

	proxy.ModifyResponse = func(resp *http.Response) error {
		resp.Header.Del("X-Frame-Options")
		resp.Header.Del("Content-Security-Policy")
		
		// If proxy.Director left username empty and we passed the request to Grafana without headers,
		// Grafana might return 401 if it's strictly Auth Proxy.
		// In our case we want to catch the 401 BEFORE it goes to Grafana if there's no username,
		// but since httputil.ReverseProxy doesn't easily allow aborting from Director,
		// we check it before calling ServeHTTP.
		return nil
	}

	// Manually check auth before passing to proxy
	username := c.GetString(gin.AuthUserKey)
	if username == "" {
		if cookie, err := c.Cookie("gbnt_session"); err == nil && cookie == sessionToken {
			username = expectedUser
		}
	}
	if username == "" {
		u, p, hasAuth := c.Request.BasicAuth()
		if hasAuth && u == expectedUser && p == expectedPass {
			username = expectedUser
		}
	}

	if username == "" {
		c.Header("WWW-Authenticate", `Basic realm="Restricted"`)
		c.AbortWithStatus(http.StatusUnauthorized)
		return
	}

	proxy.ServeHTTP(c.Writer, c.Request)
}

func jaegerProxyHandler(c *gin.Context, sessionToken, expectedUser, expectedPass string) {
	targetHost := "gbnt-monitor-jaeger:16686"
	_, err := net.LookupHost("gbnt-monitor-jaeger")
	if err != nil {
		targetHost = "127.0.0.1:16686"
	}

	targetURL, err := url.Parse("http://" + targetHost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to parse target URL"})
		return
	}

	proxy := httputil.NewSingleHostReverseProxy(targetURL)
	proxy.ModifyResponse = func(resp *http.Response) error {
		resp.Header.Del("X-Frame-Options")
		resp.Header.Del("Content-Security-Policy")
		return nil
	}

	// Manually check auth before passing to proxy
	username := c.GetString(gin.AuthUserKey)
	if username == "" {
		if cookie, err := c.Cookie("gbnt_session"); err == nil && cookie == sessionToken {
			username = expectedUser
		}
	}
	if username == "" {
		u, p, hasAuth := c.Request.BasicAuth()
		if hasAuth && u == expectedUser && p == expectedPass {
			username = expectedUser
		}
	}

	if username == "" {
		c.Header("WWW-Authenticate", `Basic realm="Restricted"`)
		c.AbortWithStatus(http.StatusUnauthorized)
		return
	}

	proxy.ServeHTTP(c.Writer, c.Request)
}



func nodeShellHandler(c *gin.Context) {
	id := c.Param("id")
	var node db.Node
	if err := db.DB.First(&node, "id = ?", id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Node not found"})
		return
	}

	ws, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		slog.Error("failed to upgrade websocket", "err", err)
		return
	}
	defer ws.Close()

	// Use nsenter inside a privileged container to get host shell
	var cmd *exec.Cmd
	if node.Role == "manager" {
		cmd = exec.Command("docker", "run", "-it", "--rm", "--privileged", "--pid=host", "alpine", "nsenter", "-t", "1", "-m", "-u", "-n", "-i", "sh")
	} else {
		sshArgs := []string{"-t", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null"}
		keyCandidates := []string{
			"/root/.ssh/id_ed25519",
			"/root/.ssh/id_rsa",
			"/data/id_ed25519",
			"/data/id_rsa",
			"/data/ssh/id_ed25519",
			"/data/ssh/id_rsa",
		}
		for _, k := range keyCandidates {
			if _, err := os.Stat(k); err == nil {
				sshArgs = append(sshArgs, "-i", k)
				break
			}
		}
		sshArgs = append(sshArgs, "ubuntu@"+node.IP, "docker run -it --rm --privileged --pid=host alpine nsenter -t 1 -m -u -n -i sh")
		cmd = exec.Command("ssh", sshArgs...)
	}
	ptmx, err := pty.Start(cmd)
	if err != nil {
		ws.WriteMessage(websocket.TextMessage, []byte(fmt.Sprintf("Failed to start host shell: %v\r\n", err)))
		return
	}
	defer func() {
		_ = ptmx.Close()
	}()

	// Copy from PTY to WebSocket
	go func() {
		buf := make([]byte, 1024)
		for {
			n, err := ptmx.Read(buf)
			if err != nil {
				break
			}
			if err := ws.WriteMessage(websocket.TextMessage, buf[:n]); err != nil {
				break
			}
		}
	}()

	// Copy from WebSocket to PTY
	for {
		_, msg, err := ws.ReadMessage()
		if err != nil {
			break
		}
		_, err = ptmx.Write(msg)
		if err != nil {
			break
		}
	}
}

func webDrainNodeTasks(nodeID string) {
	var tasks []db.Task
	if err := db.DB.Where("node_id = ? AND status != ?", nodeID, "dead").Find(&tasks).Error; err != nil {
		return
	}

	for _, task := range tasks {
		var svc db.Service
		if err := db.DB.First(&svc, "id = ?", task.ServiceID).Error; err != nil {
			continue
		}

		// Filter out core system and monitoring stacks
		if svc.StackID == "core-gbnt-stack" || svc.StackID == "sre-monitor-stack" ||
			strings.Contains(strings.ToLower(svc.StackID), "core-gbnt") ||
			strings.Contains(strings.ToLower(svc.StackID), "monitor") {
			continue
		}

		slog.Info("Draining task from node", "task_id", task.ID, "node_id", nodeID, "service_id", svc.ID)

		// 1. Stop local container if it was running on the manager node itself
		if task.NodeID == "node-local-manager" && task.ContainerName != "" {
			exec.Command("docker", "stop", task.ContainerName).Run()
			exec.Command("docker", "rm", "-f", task.ContainerName).Run()
		}

		// 2. Mark the task as dead in DB (the worker agent will clean up its local container)
		db.DB.Model(&task).Updates(map[string]interface{}{
			"status":       "dead",
			"container_ip": "",
		})

		// 3. Reschedule a new replica (will be placed on another ACTIVE node)
		webScheduleService(&svc, "")
	}

	// Regenerate configurations
	go aqueducts.GenerateHostsFile()
	go aqueducts.GenerateCaddyfile()
}

func webRescheduleUnassignedTasks() {
	var services []db.Service
	db.DB.Find(&services)

	for _, svc := range services {
		// Filter out core system and monitoring stacks
		if svc.StackID == "core-gbnt-stack" || svc.StackID == "sre-monitor-stack" ||
			strings.Contains(strings.ToLower(svc.StackID), "core-gbnt") ||
			strings.Contains(strings.ToLower(svc.StackID), "monitor") {
			continue
		}

		var runningCount int64
		db.DB.Model(&db.Task{}).Where("service_id = ? AND status IN (?, ?)", svc.ID, "running", "pending").Count(&runningCount)

		missing := svc.DesiredReplicas - int(runningCount)
		if missing > 0 {
			slog.Info("Rescheduling missing service replicas", "service", svc.Name, "missing", missing)
			for i := 0; i < missing; i++ {
				webScheduleService(&svc, "")
			}
		}
	}
	go aqueducts.GenerateHostsFile()
	go aqueducts.GenerateCaddyfile()
}

func scopeStatusHandler(c *gin.Context) {
	hostIP := c.Request.Host
	if idx := strings.Index(hostIP, ":"); idx != -1 {
		hostIP = hostIP[:idx]
	}
	status := monitor.GetScopeStatus(hostIP)
	c.JSON(http.StatusOK, status)
}

func scopeEnableHandler(c *gin.Context) {
	if err := monitor.EnableScope(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	scopeStatusHandler(c)
}

func scopeDisableHandler(c *gin.Context) {
	if err := monitor.DisableScope(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	scopeStatusHandler(c)
}
