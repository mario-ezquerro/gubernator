package api

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

func setupRouter() *gin.Engine {
	gin.SetMode(gin.TestMode)
	// Initialize in-memory DB for tests
	db.Init("file::memory:?cache=shared")

	r := gin.Default()
	
	v1 := r.Group("/v1")
	{
		node := v1.Group("/node")
		{
			node.GET("/ls", NodeListHandler)
			node.GET("/:id", NodeInspectHandler)
		}
	}
	return r
}

func TestNodeListEmpty(t *testing.T) {
	router := setupRouter()

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/node/ls", nil)
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d", w.Code)
	}

	// Init automatically seeds the local manager node
	if !strings.Contains(w.Body.String(), "node-local-manager") {
		t.Errorf("Expected body to contain the seeded manager node, got %v", w.Body.String())
	}
}

func TestNodeInspectNotFound(t *testing.T) {
	router := setupRouter()

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/v1/node/nonexistent", nil)
	router.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("Expected status 404, got %d", w.Code)
	}
}
