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
	"gopkg.in/yaml.v3"
)

//go:embed flutter/*
var flutterFS embed.FS

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
		slog.Info("web dashboard disabled; set GBNT_WEB=true, GBNT_WEB_USER and GBNT_WEB_PASSWORD to enable")
		return
	}

	if user == "" || pass == "" {
		slog.Warn("web dashboard missing credentials; provide GBNT_WEB_USER and GBNT_WEB_PASSWORD")
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
		api.POST("/node/:id/leave", nodeLeaveHandler)
		api.POST("/node/:id/labels", nodeLabelsHandler)
		api.GET("/node/:id/shell", nodeShellHandler)
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
	var nodes []db.Node
	var stacks []db.Stack
	var services []db.Service
	var tasks []db.Task

	db.DB.Find(&nodes)
	db.DB.Find(&stacks)
	db.DB.Find(&services)
	db.DB.Find(&tasks)

	caddyfilePath := caddy.CaddyfilePath()
	caddyfileContent := ""
	if content, err := os.ReadFile(caddyfilePath); err == nil {
		caddyfileContent = string(content)
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
		Name    string `json:"name"`
		Compose string `json:"compose" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	stackName := req.Name

	if stackName == "" {
		var tempCompose composeFile
		if err := yaml.Unmarshal([]byte(req.Compose), &tempCompose); err == nil {
			if tempCompose.Name != "" {
				stackName = tempCompose.Name
			} else {
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
			}
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
				webScheduleService(&existing)
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
			webScheduleService(&service)
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
	if err := monitor.DeployManagerStack(); err != nil {
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
		slog.Warn("failed to update Prometheus config on node availability change", "err", err)
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
		slog.Warn("failed to update Prometheus config on node leave", "err", err)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Node marked as left"})
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

	proxy.Rewrite = func(pr *httputil.ProxyRequest) {
		pr.SetURL(targetURL)
		pr.Out.Host = targetHost
		username, _, _ := pr.In.BasicAuth()
		if username != "" {
			pr.Out.Header.Set("X-WEBAUTH-USER", username)
		}
		pr.Out.Header.Del("Authorization")
	}

	proxy.ModifyResponse = func(resp *http.Response) error {
		resp.Header.Del("X-Frame-Options")
		resp.Header.Del("Content-Security-Policy")
		return nil
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
	cmd := exec.Command("docker", "run", "-it", "--rm", "--privileged", "--pid=host", "alpine", "nsenter", "-t", "1", "-m", "-u", "-n", "-i", "sh")
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
