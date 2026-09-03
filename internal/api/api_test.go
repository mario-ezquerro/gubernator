package api

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"sync"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/aqueducts"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

// testDBMutex ensures only one test at a time can initialize and use the database
// to prevent race conditions from concurrent database access
var testDBMutex sync.Mutex

// setupRouter builds a test router with auth middleware and all routes, backed
// by an isolated in-memory SQLite database.
func setupRouter(t *testing.T) (_ *gin.Engine, _ string) {
	t.Helper()

	// Lock to ensure sequential database initialization
	testDBMutex.Lock()
	t.Cleanup(func() {
		aqueducts.WG.Wait()
		testDBMutex.Unlock()
	})

	gin.SetMode(gin.TestMode)

	dsn := fmt.Sprintf("file:%s?mode=memory&cache=private", t.Name())
	if err := db.Init(dsn); err != nil {
		t.Fatalf("db.Init: %v", err)
	}

	token := db.GetAPIToken()
	os.Setenv("GBNT_API_TOKEN", token)

	r := gin.New()

	authMiddleware := func(c *gin.Context) {
		if c.GetHeader("Authorization") != "Bearer "+token {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
			return
		}
		c.Next()
	}

	v1 := r.Group("/v1")
	{
		node := v1.Group("/node", authMiddleware)
		node.GET("/ls", NodeListHandler)
		node.POST("/join", NodeJoinHandler)
		node.POST("/heartbeat", NodeHeartbeatHandler)
		// /tasks/* must be registered before /:id to avoid wildcard conflicts
		node.GET("/tasks/:node_id", NodeTasksHandler)
		node.POST("/tasks/:task_id/status", UpdateTaskStatusHandler)
		node.GET("/:id", NodeInspectHandler)
		node.POST("/:id/role", NodeRoleHandler)
		node.POST("/:id/availability", NodeAvailabilityHandler)
		node.POST("/:id/leave", NodeLeaveHandler)
		node.POST("/:id/labels", NodeLabelsHandler)

		cluster := v1.Group("/cluster")
		cluster.GET("/token", ClusterTokenHandler)
		cluster.GET("/info", ClusterInfoHandler)

		stack := v1.Group("/stack", authMiddleware)
		stack.POST("/deploy", StackDeployHandler)
		stack.POST("/save", StackSaveHandler)
		stack.GET("/ls", StackListHandler)
		stack.GET("/:id/services", StackServicesHandler)
		stack.DELETE("/:id", StackRmHandler)

		service := v1.Group("/service", authMiddleware)
		service.GET("/ls", ServiceListHandler)
		service.GET("/:id/tasks", ServiceTasksHandler)
		service.DELETE("/:id", ServiceRmHandler)
		service.POST("/:id/scale", ServiceScaleHandler)

		task := v1.Group("/task", authMiddleware)
		task.GET("/ls", TaskListHandler)
		task.DELETE("/:id", TaskRmHandler)

		sloRoute := v1.Group("/slo", authMiddleware)
		sloRoute.GET("/ls", SLOListHandler)
		sloRoute.POST("/sync", SLOSyncHandler)
	}

	return r, token
}

func authHeader(token string) string { return "Bearer " + token }

// ── Auth middleware ────────────────────────────────────────────────────────────

func TestAuth_MissingToken(t *testing.T) {
	r, _ := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/node/ls", http.NoBody)
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d", w.Code)
	}
}

func TestAuth_WrongToken(t *testing.T) {
	r, _ := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/node/ls", http.NoBody)
	req.Header.Set("Authorization", "Bearer wrong-token")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d", w.Code)
	}
}

func TestAuth_ValidToken(t *testing.T) {
	r, tok := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/node/ls", http.NoBody)
	req.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}
}

// ── Node handlers ─────────────────────────────────────────────────────────────

func TestNodeList_ContainsManagerNode(t *testing.T) {
	r, tok := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/node/ls", http.NoBody)
	req.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	if !bytes.Contains(w.Body.Bytes(), []byte("node-local-manager")) {
		t.Errorf("expected seeded manager node in response, got: %s", w.Body.String())
	}
}

func TestNodeInspect_Found(t *testing.T) {
	r, tok := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/node/node-local-manager", http.NoBody)
	req.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}
}

func TestNodeInspect_NotFound(t *testing.T) {
	r, tok := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/node/does-not-exist", http.NoBody)
	req.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w, req)
	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d", w.Code)
	}
}

func TestNodeJoin_ValidToken(t *testing.T) {
	r, tok := setupRouter(t)

	joinToken := db.GetJoinToken()
	body, _ := json.Marshal(map[string]interface{}{
		"id":    "worker-test",
		"ip":    "10.0.0.99",
		"token": joinToken,
	})
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/v1/node/join", bytes.NewReader(body))
	req.Header.Set("Authorization", authHeader(tok))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	// Node should now appear in the list
	w2 := httptest.NewRecorder()
	req2, _ := http.NewRequest("GET", "/v1/node/worker-test", http.NoBody)
	req2.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w2, req2)
	if w2.Code != http.StatusOK {
		t.Errorf("joined node not found: %s", w2.Body.String())
	}
}

func TestNodeJoin_InvalidToken(t *testing.T) {
	r, tok := setupRouter(t)
	body, _ := json.Marshal(map[string]interface{}{
		"id":    "worker-bad",
		"ip":    "10.0.0.100",
		"token": "wrong-join-token",
	})
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/v1/node/join", bytes.NewReader(body))
	req.Header.Set("Authorization", authHeader(tok))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d", w.Code)
	}
}

func TestNodeRole_Update(t *testing.T) {
	r, tok := setupRouter(t)
	body, _ := json.Marshal(map[string]string{"role": "worker"})
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/v1/node/node-local-manager/role", bytes.NewReader(body))
	req.Header.Set("Authorization", authHeader(tok))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
}

func TestNodeRole_InvalidRole(t *testing.T) {
	r, tok := setupRouter(t)
	body, _ := json.Marshal(map[string]string{"role": "superuser"})
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/v1/node/node-local-manager/role", bytes.NewReader(body))
	req.Header.Set("Authorization", authHeader(tok))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestNodeAvailability_Drain(t *testing.T) {
	r, tok := setupRouter(t)
	body, _ := json.Marshal(map[string]string{"availability": "drain"})
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/v1/node/node-local-manager/availability", bytes.NewReader(body))
	req.Header.Set("Authorization", authHeader(tok))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
}

func TestNodeLeave(t *testing.T) {
	r, tok := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/v1/node/node-local-manager/leave", http.NoBody)
	req.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}
}

// ── Stack handlers ────────────────────────────────────────────────────────────

func TestStackList_Empty(t *testing.T) {
	r, tok := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/stack/ls", http.NoBody)
	req.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}
}

func TestStackDeploy_MinimalCompose(t *testing.T) {
	r, tok := setupRouter(t)

	compose := `
services:
  web:
    image: nginx:alpine
`
	body, _ := json.Marshal(map[string]string{
		"name":        "teststack",
		"compose_raw": compose,
	})
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/v1/stack/deploy", bytes.NewReader(body))
	req.Header.Set("Authorization", authHeader(tok))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	// Stack should now appear in list
	w2 := httptest.NewRecorder()
	req2, _ := http.NewRequest("GET", "/v1/stack/ls", http.NoBody)
	req2.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w2, req2)
	if !bytes.Contains(w2.Body.Bytes(), []byte("teststack")) {
		t.Errorf("deployed stack not found in list: %s", w2.Body.String())
	}
}

func TestStackDelete_NotFound(t *testing.T) {
	r, tok := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", "/v1/stack/nonexistent", http.NoBody)
	req.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w, req)
	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d", w.Code)
	}
}

// ── Service handlers ────────────────────────────────────────────────────────────

func TestServiceList_Empty(t *testing.T) {
	r, tok := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/service/ls", http.NoBody)
	req.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}
}

func TestServiceDelete_NotFound(t *testing.T) {
	r, tok := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", "/v1/service/nonexistent", http.NoBody)
	req.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w, req)
	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d", w.Code)
	}
}

// ── Task handlers ─────────────────────────────────────────────────────────────

func TestTaskList_Empty(t *testing.T) {
	r, tok := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/task/ls", http.NoBody)
	req.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}
}

func TestTaskDelete_NotFound(t *testing.T) {
	r, tok := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", "/v1/task/nonexistent", http.NoBody)
	req.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w, req)
	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d", w.Code)
	}
}

// ── Cluster endpoints ───────────────────────────────────────────────────────────

func TestClusterToken_FromLocalhost(t *testing.T) {
	r, _ := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/cluster/token", http.NoBody)
	req.RemoteAddr = "127.0.0.1:9999" // fake localhost
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if !bytes.Contains(w.Body.Bytes(), []byte("token")) {
		t.Errorf("expected token in response, got: %s", w.Body.String())
	}
}

func TestClusterToken_FromRemote(t *testing.T) {
	r, _ := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/cluster/token", http.NoBody)
	req.RemoteAddr = "203.0.113.5:9999" // non-local address
	r.ServeHTTP(w, req)
	if w.Code != http.StatusForbidden {
		t.Errorf("expected 403, got %d", w.Code)
	}
}

func TestClusterInfo_FromLocalhost(t *testing.T) {
	r, _ := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/cluster/info", http.NoBody)
	req.RemoteAddr = "127.0.0.1:9999"
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
}

// ── Node heartbeat ────────────────────────────────────────────────────────────

func TestNodeHeartbeat_KnownNode(t *testing.T) {
	r, tok := setupRouter(t)
	body, _ := json.Marshal(map[string]string{"id": "node-local-manager"})
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/v1/node/heartbeat", bytes.NewReader(body))
	req.Header.Set("Authorization", authHeader(tok))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
}

func TestNodeHeartbeat_UnknownNode(t *testing.T) {
	r, tok := setupRouter(t)
	body, _ := json.Marshal(map[string]string{"id": "ghost-node"})
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/v1/node/heartbeat", bytes.NewReader(body))
	req.Header.Set("Authorization", authHeader(tok))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d", w.Code)
	}
}

// ── Stack services / node tasks / service scale ───────────────────────────────

// deployTestStack is a helper that deploys a minimal stack and returns the stack ID.
func deployTestStack(t *testing.T, r *gin.Engine, tok string) string {
	t.Helper()
	compose := "services:\n  web:\n    image: nginx:alpine\n"
	body, _ := json.Marshal(map[string]string{"name": "e2estack", "compose_raw": compose})
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/v1/stack/deploy", bytes.NewReader(body))
	req.Header.Set("Authorization", authHeader(tok))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("deploy stack failed: %d %s", w.Code, w.Body.String())
	}
	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	return fmt.Sprintf("%v", resp["stack_id"])
}

func TestStackServices_AfterDeploy(t *testing.T) {
	r, tok := setupRouter(t)
	stackID := deployTestStack(t, r, tok)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/stack/"+stackID+"/services", http.NoBody)
	req.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if !bytes.Contains(w.Body.Bytes(), []byte("web")) {
		t.Errorf("expected 'web' service in response, got: %s", w.Body.String())
	}
}

func TestNodeTasks_AfterDeploy(t *testing.T) {
	r, tok := setupRouter(t)
	deployTestStack(t, r, tok)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/node/tasks/node-local-manager", http.NoBody)
	req.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
}

func TestServiceScale_AfterDeploy(t *testing.T) {
	r, tok := setupRouter(t)
	deployTestStack(t, r, tok)

	// Fetch the created service ID
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/service/ls", http.NoBody)
	req.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w, req)

	var services []map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &services)
	if len(services) == 0 {
		t.Fatal("no services found after deploy")
	}
	svcID := fmt.Sprintf("%v", services[0]["id"])

	body, _ := json.Marshal(map[string]int{"replicas": 3})
	w2 := httptest.NewRecorder()
	req2, _ := http.NewRequest("POST", "/v1/service/"+svcID+"/scale", bytes.NewReader(body))
	req2.Header.Set("Authorization", authHeader(tok))
	req2.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w2, req2)
	if w2.Code != http.StatusOK {
		t.Errorf("expected 200, got %d: %s", w2.Code, w2.Body.String())
	}
}

func TestServiceTasks_AfterDeploy(t *testing.T) {
	r, tok := setupRouter(t)
	deployTestStack(t, r, tok)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/service/ls", http.NoBody)
	req.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w, req)

	var services []map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &services)
	if len(services) == 0 {
		t.Fatal("no services found after deploy")
	}
	svcID := fmt.Sprintf("%v", services[0]["id"])

	w2 := httptest.NewRecorder()
	req2, _ := http.NewRequest("GET", "/v1/service/"+svcID+"/tasks", http.NoBody)
	req2.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w2, req2)
	if w2.Code != http.StatusOK {
		t.Errorf("expected 200, got %d: %s", w2.Code, w2.Body.String())
	}
}

func TestUpdateTaskStatus(t *testing.T) {
	r, tok := setupRouter(t)
	deployTestStack(t, r, tok)

	// Get a task ID
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/task/ls", http.NoBody)
	req.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w, req)

	var tasks []map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &tasks)
	if len(tasks) == 0 {
		t.Fatal("no tasks found after deploy")
	}
	taskID := fmt.Sprintf("%v", tasks[0]["id"])

	body, _ := json.Marshal(map[string]string{"status": "running", "container_ip": "10.0.0.5"})
	w2 := httptest.NewRecorder()
	req2, _ := http.NewRequest("POST", "/v1/node/tasks/"+taskID+"/status", bytes.NewReader(body))
	req2.Header.Set("Authorization", authHeader(tok))
	req2.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w2, req2)
	if w2.Code != http.StatusOK {
		t.Errorf("expected 200, got %d: %s", w2.Code, w2.Body.String())
	}
}

func TestNodeLabelsUpdate(t *testing.T) {
	r, tok := setupRouter(t)

	// Update manager node labels
	body, _ := json.Marshal(map[string]interface{}{
		"labels": map[string]string{
			"gbnt.node.role": "hacked-role", // should be ignored/restored to "manager"
			"gbnt.node.arch": "hacked-arch", // should be ignored/restored to the original or detected arch
			"custom-key":     "custom-val",
		},
	})
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/v1/node/node-local-manager/labels", bytes.NewReader(body))
	req.Header.Set("Authorization", authHeader(tok))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	// Fetch node details to verify labels
	w2 := httptest.NewRecorder()
	req2, _ := http.NewRequest("GET", "/v1/node/node-local-manager", http.NoBody)
	req2.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w2, req2)
	if w2.Code != http.StatusOK {
		t.Fatalf("failed to inspect manager: %d", w2.Code)
	}

	var node db.Node
	json.Unmarshal(w2.Body.Bytes(), &node)

	// Role should remain "manager"
	if node.Labels["gbnt.node.role"] != "manager" {
		t.Errorf("expected gbnt.node.role to be 'manager', got: %s", node.Labels["gbnt.node.role"])
	}

	// Hacked arch should be rejected/restored (since it wasn't hacked-arch originally)
	if node.Labels["gbnt.node.arch"] == "hacked-arch" {
		t.Errorf("expected gbnt.node.arch to not be 'hacked-arch'")
	}

	// Custom key should be set
	if node.Labels["custom-key"] != "custom-val" {
		t.Errorf("expected custom-key to be 'custom-val', got: %s", node.Labels["custom-key"])
	}
}

func TestComposeLabelsParsing(t *testing.T) {
	r, tok := setupRouter(t)

	composeRaw := `version: "3.8"
services:
  payment-api:
    image: nginx:alpine
    labels:
      gbnt.slo.enable: true
      gbnt.slo.target: 99.9
      gbnt.slo.window: 30d
      gbnt.slo.sli.error_query: 'sum(rate(http_requests_total{service="payment-api",status=~"5.."}[5m]))'
      gbnt.slo.sli.total_query: 'sum(rate(http_requests_total{service="payment-api"}[5m]))'
`
	body, _ := json.Marshal(StackDeployRequest{
		Name:       "slo-stack",
		ComposeRaw: composeRaw,
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/v1/stack/deploy", bytes.NewBuffer(body))
	req.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("deploy failed (%d): %s", w.Code, w.Body.String())
	}

	w2 := httptest.NewRecorder()
	req2, _ := http.NewRequest("GET", "/v1/slo/ls", http.NoBody)
	req2.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w2, req2)

	if w2.Code != http.StatusOK {
		t.Fatalf("slo ls failed (%d): %s", w2.Code, w2.Body.String())
	}

	var items []SLOItem
	if err := json.Unmarshal(w2.Body.Bytes(), &items); err != nil {
		t.Fatalf("failed to unmarshal SLO items: %v", err)
	}

	if len(items) != 1 {
		t.Fatalf("expected 1 SLO item, got %d", len(items))
	}

	if items[0].ServiceName != "payment-api" || items[0].Target != 99.9 {
		t.Errorf("unexpected SLO item: %+v", items[0])
	}
}

func TestStackSaveDraft(t *testing.T) {
	r, tok := setupRouter(t)

	composeYAML := `services:
  web:
    image: nginx:alpine
    ports:
      - "8080:80"
    deploy:
      replicas: 2
`

	body, _ := json.Marshal(map[string]string{
		"name":        "my-draft-stack",
		"compose_raw": composeYAML,
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/v1/stack/save", bytes.NewBuffer(body))
	req.Header.Set("Authorization", authHeader(tok))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("save stack failed (%d): %s", w.Code, w.Body.String())
	}

	var res map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("failed to parse save response: %v", err)
	}

	if res["status"] != "saved" {
		t.Errorf("expected status 'saved', got %v", res["status"])
	}

	stackID, ok := res["stack_id"].(string)
	if !ok || stackID == "" {
		t.Fatalf("expected non-empty stack_id, got %v", res["stack_id"])
	}

	// 1. Verify stack exists in db
	var stack db.Stack
	if err := db.DB.First(&stack, "id = ?", stackID).Error; err != nil {
		t.Fatalf("stack not found in db: %v", err)
	}
	if stack.Name != "my-draft-stack" {
		t.Errorf("expected stack name 'my-draft-stack', got %s", stack.Name)
	}

	// 2. Verify service is created in db
	var services []db.Service
	db.DB.Where("stack_id = ?", stackID).Find(&services)
	if len(services) != 1 {
		t.Fatalf("expected 1 service, got %d", len(services))
	}
	if services[0].Name != "web" || services[0].DesiredReplicas != 2 {
		t.Errorf("unexpected service values: %+v", services[0])
	}

	// 3. Crucially: Verify NO tasks (containers) were scheduled or launched
	var tasks []db.Task
	db.DB.Where("service_id = ?", services[0].ID).Find(&tasks)
	if len(tasks) != 0 {
		t.Fatalf("expected 0 tasks (no containers deployed), but found %d tasks!", len(tasks))
	}
}


