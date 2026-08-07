package slo

import (
	"strings"
	"testing"

	"github.com/glebarez/sqlite"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"gorm.io/gorm"
)

func setupTestDB(t *testing.T) *gorm.DB {
	gormDB, err := gorm.Open(sqlite.Open("file::memory:?cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to open memory db: %v", err)
	}
	if err := gormDB.AutoMigrate(&db.Service{}); err != nil {
		t.Fatalf("failed to migrate service schema: %v", err)
	}
	return gormDB
}

func TestGenerateRulesFromServices(t *testing.T) {
	gormDB := setupTestDB(t)

	svc := db.Service{
		ID:      "svc-payment",
		StackID: "stack-core",
		Name:    "payment-api",
		Constraints: []string{
			"gbnt.slo.enable=true",
			"gbnt.slo.target=99.9",
			"gbnt.slo.window=30d",
			`gbnt.slo.sli.error_query=sum(rate(http_requests_total{service="payment-api",status=~"5.."}[5m]))`,
			`gbnt.slo.sli.total_query=sum(rate(http_requests_total{service="payment-api"}[5m]))`,
		},
	}
	if err := gormDB.Create(&svc).Error; err != nil {
		t.Fatalf("failed to create test service: %v", err)
	}

	rulesYAML, err := GenerateRulesFromServices(gormDB)
	if err != nil {
		t.Fatalf("unexpected error generating rules: %v", err)
	}

	if rulesYAML == "" {
		t.Fatalf("expected generated rules YAML, got empty string")
	}

	t.Logf("Generated YAML:\n%s", rulesYAML)

	if !strings.Contains(rulesYAML, "slo:") {
		t.Errorf("expected generated YAML to contain sloth recording rule prefix 'slo:'")
	}
}
