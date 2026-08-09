package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/mario-ezquerro/gubernator/internal/slo"
)

type SLOItem struct {
	ServiceID            string  `json:"service_id"`
	ServiceName          string  `json:"service_name"`
	StackID              string  `json:"stack_id"`
	Target               float64 `json:"target"`
	Window               string  `json:"window"`
	ErrorQuery           string  `json:"error_query"`
	TotalQuery           string  `json:"total_query"`
	ErrorBudgetRemaining float64 `json:"error_budget_remaining"`
	BurnRate             float64 `json:"burn_rate"`
	Status               string  `json:"status"` // "healthy", "warning", "exhausted"
}

func parseConstraintsMap(constraints []string) map[string]string {
	res := make(map[string]string)
	for _, c := range constraints {
		parts := strings.SplitN(c, "=", 2)
		if len(parts) == 2 {
			res[strings.TrimSpace(parts[0])] = strings.TrimSpace(parts[1])
		} else if len(parts) == 1 {
			res[strings.TrimSpace(parts[0])] = "true"
		}
	}
	return res
}

// @Summary List Service Level Objectives (SLOs)
// @Description Fetch all active SLOs across services and query Prometheus for error budget metrics
// @Tags slo
// @Produce json
// @Success 200 {array} SLOItem
// @Router /v1/slo/ls [get]
func SLOListHandler(c *gin.Context) {
	var services []db.Service
	if err := db.DB.Find(&services).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch services"})
		return
	}

	var items []SLOItem
	for _, svc := range services {
		cmap := parseConstraintsMap(svc.Constraints)
		if cmap["gbnt.slo.enable"] != "true" && cmap["gbnt.slo.enable"] != "1" {
			continue
		}

		targetVal, _ := strconv.ParseFloat(cmap["gbnt.slo.target"], 64)
		if targetVal <= 0 {
			targetVal = 99.9
		}
		window := cmap["gbnt.slo.window"]
		if window == "" {
			window = "30d"
		}

		item := SLOItem{
			ServiceID:            svc.ID,
			ServiceName:          svc.Name,
			StackID:              svc.StackID,
			Target:               targetVal,
			Window:               window,
			ErrorQuery:           cmap["gbnt.slo.sli.error_query"],
			TotalQuery:           cmap["gbnt.slo.sli.total_query"],
			ErrorBudgetRemaining: 100.0,
			BurnRate:             0.0,
			Status:               "no_data",
		}

		// Attempt to query Prometheus for real-time error budget ratio
		budgetRatio, err := queryPrometheusMetric(fmt.Sprintf(`slo:period_error_budget_remaining:ratio{gbnt_service_id="%s"}`, svc.ID))
		if err == nil && budgetRatio >= 0 {
			item.ErrorBudgetRemaining = budgetRatio * 100.0
			if item.ErrorBudgetRemaining <= 0 {
				item.Status = "exhausted"
			} else if item.ErrorBudgetRemaining < 20 {
				item.Status = "warning"
			} else {
				item.Status = "healthy"
			}
		}

		burnRate, err := queryPrometheusMetric(fmt.Sprintf(`slo:current_burn_rate:ratio{gbnt_service_id="%s"}`, svc.ID))
		if err == nil && burnRate >= 0 {
			item.BurnRate = burnRate
		}

		items = append(items, item)
	}

	c.JSON(http.StatusOK, items)
}

// @Summary Sync SLO Rules to Prometheus
// @Description Force generation and synchronization of Prometheus SLO rules
// @Tags slo
// @Produce json
// @Success 200 {object} map[string]string
// @Router /v1/slo/sync [post]
func SLOSyncHandler(c *gin.Context) {
	if err := slo.SyncSLORulesToPrometheus(db.DB); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("SLO sync failed: %v", err)})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "SLO rules generated and synced successfully"})
}

func queryPrometheusMetric(query string) (float64, error) {
	resp, err := http.Get(fmt.Sprintf("http://localhost:9090/api/v1/query?query=%s", query))
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()

	var result struct {
		Data struct {
			Result []struct {
				Value []interface{} `json:"value"`
			} `json:"result"`
		} `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return 0, err
	}

	if len(result.Data.Result) == 0 || len(result.Data.Result[0].Value) < 2 {
		return -1, fmt.Errorf("no metric data")
	}

	strVal, ok := result.Data.Result[0].Value[1].(string)
	if !ok {
		return 0, fmt.Errorf("invalid metric value type")
	}

	return strconv.ParseFloat(strVal, 64)
}
