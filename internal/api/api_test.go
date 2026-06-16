package api

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

// setupRouter builds a test router with auth middleware and all routes, backed
// by an isolated in-memory SQLite database.
func setupRouter(t *testing.T) (*gin.Engine, string) {
	t.Helper()
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

		cluster := v1.Group("/cluster")
		cluster.GET("/token", ClusterTokenHandler)
		cluster.GET("/info", ClusterInfoHandler)

		stack := v1.Group("/stack", authMiddleware)
		stack.POST("/deploy", StackDeployHandler)
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
	}

	return r, token
}

func authHeader(token string) string { return "Bearer " + token }

// ── Auth middleware ───────────────────────────────────────────────────────────

func TestAuth_MissingToken(t *testing.T) {
	r, _ := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/node/ls", nil)
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d", w.Code)
	}
}

func TestAuth_WrongToken(t *testing.T) {
	r, _ := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/node/ls", nil)
	req.Header.Set("Authorization", "Bearer wrong-token")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d", w.Code)
	}
}

func TestAuth_ValidToken(t *testing.T) {
	r, tok := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/node/ls", nil)
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
	req, _ := http.NewRequest("GET", "/v1/node/ls", nil)
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
	req, _ := http.NewRequest("GET", "/v1/node/node-local-manager", nil)
	req.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}
}

func TestNodeInspect_NotFound(t *testing.T) {
	r, tok := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/node/does-not-exist", nil)
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
	req2, _ := http.NewRequest("GET", "/v1/node/worker-test", nil)
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
	req, _ := http.NewRequest("POST", "/v1/node/node-local-manager/leave", nil)
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
	req, _ := http.NewRequest("GET", "/v1/stack/ls", nil)
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
	req2, _ := http.NewRequest("GET", "/v1/stack/ls", nil)
	req2.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w2, req2)
	if !bytes.Contains(w2.Body.Bytes(), []byte("teststack")) {
		t.Errorf("deployed stack not found in list: %s", w2.Body.String())
	}
}

func TestStackDelete_NotFound(t *testing.T) {
	r, tok := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", "/v1/stack/nonexistent", nil)
	req.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w, req)
	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d", w.Code)
	}
}

// ── Service handlers ──────────────────────────────────────────────────────────

func TestServiceList_Empty(t *testing.T) {
	r, tok := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/service/ls", nil)
	req.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}
}

func TestServiceDelete_NotFound(t *testing.T) {
	r, tok := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", "/v1/service/nonexistent", nil)
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
	req, _ := http.NewRequest("GET", "/v1/task/ls", nil)
	req.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}
}

func TestTaskDelete_NotFound(t *testing.T) {
	r, tok := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", "/v1/task/nonexistent", nil)
	req.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w, req)
	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d", w.Code)
	}
}

// ── Cluster endpoints ─────────────────────────────────────────────────────────

func TestClusterToken_FromLocalhost(t *testing.T) {
	r, _ := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/cluster/token", nil)
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
	req, _ := http.NewRequest("GET", "/v1/cluster/token", nil)
	req.RemoteAddr = "203.0.113.5:9999" // non-local address
	r.ServeHTTP(w, req)
	if w.Code != http.StatusForbidden {
		t.Errorf("expected 403, got %d", w.Code)
	}
}

func TestClusterInfo_FromLocalhost(t *testing.T) {
	r, _ := setupRouter(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/cluster/info", nil)
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
	req, _ := http.NewRequest("GET", "/v1/stack/"+stackID+"/services", nil)
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
	req, _ := http.NewRequest("GET", "/v1/node/tasks/node-local-manager", nil)
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
	req, _ := http.NewRequest("GET", "/v1/service/ls", nil)
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
	req, _ := http.NewRequest("GET", "/v1/service/ls", nil)
	req.Header.Set("Authorization", authHeader(tok))
	r.ServeHTTP(w, req)

	var services []map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &services)
	if len(services) == 0 {
		t.Fatal("no services found after deploy")
	}
	svcID := fmt.Sprintf("%v", services[0]["id"])

	w2 := httptest.NewRecorder()
	req2, _ := http.NewRequest("GET", "/v1/service/"+svcID+"/tasks", nil)
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
	req, _ := http.NewRequest("GET", "/v1/task/ls", nil)
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
