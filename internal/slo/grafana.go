package slo

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strconv"

	"github.com/mario-ezquerro/gubernator/internal/db"
	"gorm.io/gorm"
)

// GenerateGrafanaDashboardJSON generates a Grafana Dashboard JSON for all active SLOs
func GenerateGrafanaDashboardJSON(gormDB *gorm.DB) (string, error) {
	var services []db.Service
	if err := gormDB.Find(&services).Error; err != nil {
		return "", fmt.Errorf("failed to query services: %w", err)
	}

	var panels []map[string]interface{}
	panelID := 1

	for _, svc := range services {
		cmap := parseConstraints(svc.Constraints)
		if cmap["gbnt.slo.enable"] != "true" && cmap["gbnt.slo.enable"] != "1" {
			continue
		}

		targetVal, _ := strconv.ParseFloat(cmap["gbnt.slo.target"], 64)
		if targetVal <= 0 {
			targetVal = 99.9
		}

		// Panel 1: Error Budget Gauge
		panels = append(panels, map[string]interface{}{
			"id":    panelID,
			"title": fmt.Sprintf("%s — Error Budget Remaining", svc.Name),
			"type":  "gauge",
			"gridPos": map[string]interface{}{
				"h": 8, "w": 12, "x": 0, "y": (panelID - 1) * 8,
			},
			"targets": []map[string]interface{}{
				{
					"expr":         fmt.Sprintf(`slo:period_error_budget_remaining:ratio{gbnt_service_id="%s"} * 100`, svc.ID),
					"legendFormat": "Budget Remaining %",
				},
			},
			"fieldConfig": map[string]interface{}{
				"defaults": map[string]interface{}{
					"unit": "percent",
					"min":  0,
					"max":  100,
					"thresholds": map[string]interface{}{
						"mode": "absolute",
						"steps": []map[string]interface{}{
							{"color": "red", "value": nil},
							{"color": "yellow", "value": 20},
							{"color": "green", "value": 50},
						},
					},
				},
			},
		})
		panelID++

		// Panel 2: Burn Rate Time Series
		panels = append(panels, map[string]interface{}{
			"id":    panelID,
			"title": fmt.Sprintf("%s — Burn Rate Trend", svc.Name),
			"type":  "timeseries",
			"gridPos": map[string]interface{}{
				"h": 8, "w": 12, "x": 12, "y": (panelID - 2) * 8,
			},
			"targets": []map[string]interface{}{
				{
					"expr":         fmt.Sprintf(`slo:current_burn_rate:ratio{gbnt_service_id="%s"}`, svc.ID),
					"legendFormat": "Current Burn Rate (5m)",
				},
				{
					"expr":         fmt.Sprintf(`slo:period_burn_rate:ratio{gbnt_service_id="%s"}`, svc.ID),
					"legendFormat": "Period Burn Rate (30d)",
				},
			},
			"fieldConfig": map[string]interface{}{
				"defaults": map[string]interface{}{
					"unit": "short",
				},
			},
		})
		panelID++
	}

	dashboard := map[string]interface{}{
		"annotations": map[string]interface{}{"list": []interface{}{}},
		"editable":    true,
		"title":       "Gubernator — SLO & Error Budgets",
		"tags":        []string{"gubernator", "slo", "sloth", "prometheus"},
		"timezone":    "browser",
		"panels":      panels,
		"schemaVersion": 38,
		"version":       1,
	}

	data, err := json.MarshalIndent(dashboard, "", "  ")
	if err != nil {
		return "", fmt.Errorf("failed to marshal grafana dashboard: %w", err)
	}

	return string(data), nil
}

// SyncGrafanaDashboard writes the generated SLO dashboard JSON to Grafana's provisioned directory
func SyncGrafanaDashboard(gormDB *gorm.DB) error {
	jsonStr, err := GenerateGrafanaDashboardJSON(gormDB)
	if err != nil {
		return err
	}

	dataDir := os.Getenv("GBNT_DATA_DIR")
	if dataDir == "" {
		dataDir = "/data"
	}
	if _, err := os.Stat(dataDir); os.IsNotExist(err) {
		dataDir = "."
	}

	dashDir := filepath.Join(dataDir, "monitor", "grafana", "dashboards")
	_ = os.MkdirAll(dashDir, 0755)
	dashPath := filepath.Join(dashDir, "slo_dashboard.json")

	if jsonStr == "" {
		_ = os.Remove(dashPath)
		return nil
	}

	if err := os.WriteFile(dashPath, []byte(jsonStr), 0644); err != nil {
		return fmt.Errorf("failed to write slo_dashboard.json: %w", err)
	}

	slog.Info("SLO Engine: updated Grafana SLO dashboard", "path", dashPath)
	return nil
}
