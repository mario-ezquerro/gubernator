package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/mario-ezquerro/gubernator/internal/slo"
	"gopkg.in/yaml.v3"
)

type SLOItem struct {
	ServiceID            string  `json:"service_id"`
	ServiceName          string  `json:"service_name"`
	StackID              string  `json:"stack_id"`
	Target               float64 `json:"target"`
	Window               string  `json:"window"`
	Indicator            string  `json:"indicator,omitempty"`
	LatencyThreshold     string  `json:"latency_threshold,omitempty"`
	Template             string  `json:"template,omitempty"`
	Journey              string  `json:"journey,omitempty"`
	ErrorQuery           string  `json:"error_query"`
	TotalQuery           string  `json:"total_query"`
	ErrorBudgetRemaining float64 `json:"error_budget_remaining"`
	BurnRate             float64 `json:"burn_rate"`
	Status               string  `json:"status"` // "healthy", "warning", "exhausted", "no_data"
}

type UserJourney struct {
	Name                 string    `json:"name"`
	Services             []SLOItem `json:"services"`
	CompositeTarget      float64   `json:"composite_target"`
	AvgErrorBudget       float64   `json:"avg_error_budget"`
	BottleneckService    string    `json:"bottleneck_service"`
	BottleneckBudget     float64   `json:"bottleneck_budget"`
	Status               string    `json:"status"`
}

type SLOCorrelationEvent struct {
	Timestamp   string  `json:"timestamp"`
	Type        string  `json:"type"` // "deployment", "scaling", "restart"
	StackName   string  `json:"stack_name"`
	ServiceName string  `json:"service_name"`
	Description string  `json:"description"`
	BurnRate    float64 `json:"burn_rate"`
}

type SLOValidateRequest struct {
	ComposeRaw string `json:"compose_raw" binding:"required"`
}

type SLOValidationItem struct {
	ServiceName     string  `json:"service_name"`
	Valid           bool    `json:"valid"`
	Target          float64 `json:"target"`
	Window          string  `json:"window"`
	Template        string  `json:"template"`
	ErrorQuery      string  `json:"error_query"`
	TotalQuery      string  `json:"total_query"`
	Error           string  `json:"error,omitempty"`
	BacktestStatus  string  `json:"backtest_status"` // "passed", "warning", "no_data"
	BacktestDetails string  `json:"backtest_details"`
}

type SLOHistoryPoint struct {
	Timestamp       string  `json:"timestamp"`
	BudgetRemaining float64 `json:"budget_remaining"`
	BurnRate        float64 `json:"burn_rate"`
}

type SLOREDMetrics struct {
	RPS          float64 `json:"rps"`
	ErrorRPS     float64 `json:"error_rps"`
	P99LatencyMs float64 `json:"p99_latency_ms"`
}

var (
	promCache      = make(map[string]cacheEntry)
	promCacheMutex sync.RWMutex
	cacheTTL       = 15 * time.Second
)

type cacheEntry struct {
	val       float64
	err       error
	fetchedAt time.Time
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

		indicator := cmap["gbnt.slo.indicator"]
		if indicator == "" {
			indicator = "ratio"
		}
		latencyThresh := cmap["gbnt.slo.latency.threshold"]

		template := cmap["gbnt.slo.template"]
		journey := cmap["gbnt.slo.journey"]
		errQuery := cmap["gbnt.slo.sli.error_query"]
		totalQuery := cmap["gbnt.slo.sli.total_query"]

		if (errQuery == "" || totalQuery == "") && template != "" {
			tErr, tTot := slo.ExpandSLITemplate(template, svc.Name)
			if errQuery == "" {
				errQuery = tErr
			}
			if totalQuery == "" {
				totalQuery = tTot
			}
		}

		item := SLOItem{
			ServiceID:            svc.ID,
			ServiceName:          svc.Name,
			StackID:              svc.StackID,
			Target:               targetVal,
			Window:               window,
			Indicator:            indicator,
			LatencyThreshold:     latencyThresh,
			Template:             template,
			Journey:              journey,
			ErrorQuery:           errQuery,
			TotalQuery:           totalQuery,
			ErrorBudgetRemaining: 100.0,
			BurnRate:             0.0,
			Status:               "no_data",
		}

		budgetRatio, err := queryPrometheusMetricCached(fmt.Sprintf(`slo:period_error_budget_remaining:ratio{gbnt_service_id="%s"}`, svc.ID))
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

		burnRate, err := queryPrometheusMetricCached(fmt.Sprintf(`slo:current_burn_rate:ratio{gbnt_service_id="%s"}`, svc.ID))
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

// @Summary Get Composite User Journeys
// @Description Aggregate service SLOs by user journey name
// @Tags slo
// @Produce json
// @Success 200 {array} UserJourney
// @Router /v1/slo/journeys [get]
func SLOJourneysHandler(c *gin.Context) {
	var services []db.Service
	if err := db.DB.Find(&services).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch services"})
		return
	}

	journeysMap := make(map[string][]SLOItem)
	for _, svc := range services {
		cmap := parseConstraintsMap(svc.Constraints)
		if cmap["gbnt.slo.enable"] != "true" && cmap["gbnt.slo.enable"] != "1" {
			continue
		}
		journey := cmap["gbnt.slo.journey"]
		if journey == "" {
			journey = "Default Journey"
		}

		targetVal, _ := strconv.ParseFloat(cmap["gbnt.slo.target"], 64)
		if targetVal <= 0 {
			targetVal = 99.9
		}
		window := cmap["gbnt.slo.window"]
		if window == "" {
			window = "30d"
		}

		errQuery := cmap["gbnt.slo.sli.error_query"]
		totalQuery := cmap["gbnt.slo.sli.total_query"]
		if (errQuery == "" || totalQuery == "") && cmap["gbnt.slo.template"] != "" {
			tErr, tTot := slo.ExpandSLITemplate(cmap["gbnt.slo.template"], svc.Name)
			if errQuery == "" {
				errQuery = tErr
			}
			if totalQuery == "" {
				totalQuery = tTot
			}
		}

		item := SLOItem{
			ServiceID:            svc.ID,
			ServiceName:          svc.Name,
			StackID:              svc.StackID,
			Target:               targetVal,
			Window:               window,
			Template:             cmap["gbnt.slo.template"],
			Journey:              journey,
			ErrorQuery:           errQuery,
			TotalQuery:           totalQuery,
			ErrorBudgetRemaining: 100.0,
			BurnRate:             0.0,
			Status:               "no_data",
		}

		budgetRatio, err := queryPrometheusMetricCached(fmt.Sprintf(`slo:period_error_budget_remaining:ratio{gbnt_service_id="%s"}`, svc.ID))
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
		burnRate, err := queryPrometheusMetricCached(fmt.Sprintf(`slo:current_burn_rate:ratio{gbnt_service_id="%s"}`, svc.ID))
		if err == nil && burnRate >= 0 {
			item.BurnRate = burnRate
		}

		journeysMap[journey] = append(journeysMap[journey], item)
	}

	var result []UserJourney
	for jName, items := range journeysMap {
		var totalTarget float64
		var totalBudget float64
		bottleneckSvc := ""
		minBudget := 101.0
		worstStatus := "healthy"

		for _, it := range items {
			totalTarget += it.Target
			totalBudget += it.ErrorBudgetRemaining
			if it.ErrorBudgetRemaining < minBudget {
				minBudget = it.ErrorBudgetRemaining
				bottleneckSvc = it.ServiceName
			}
			if it.Status == "exhausted" || (it.Status == "warning" && worstStatus != "exhausted") {
				worstStatus = it.Status
			}
		}

		if minBudget > 100 {
			minBudget = 100
		}

		result = append(result, UserJourney{
			Name:              jName,
			Services:          items,
			CompositeTarget:   totalTarget / float64(len(items)),
			AvgErrorBudget:    totalBudget / float64(len(items)),
			BottleneckService: bottleneckSvc,
			BottleneckBudget:  minBudget,
			Status:            worstStatus,
		})
	}

	c.JSON(http.StatusOK, result)
}

// @Summary Get SLO Deployment Correlations
// @Description Cross-reference burn rate spikes with stack deployment timestamps
// @Tags slo
// @Produce json
// @Success 200 {array} SLOCorrelationEvent
// @Router /v1/slo/correlation [get]
func SLOCorrelationHandler(c *gin.Context) {
	var stacks []db.Stack
	db.DB.Order("updated_at desc").Limit(10).Find(&stacks)

	var events []SLOCorrelationEvent
	for _, st := range stacks {
		var services []db.Service
		db.DB.Where("stack_id = ?", st.ID).Find(&services)

		for _, svc := range services {
			burnRate, _ := queryPrometheusMetricCached(fmt.Sprintf(`slo:current_burn_rate:ratio{gbnt_service_id="%s"}`, svc.ID))
			if burnRate < 0 {
				burnRate = 0
			}

			events = append(events, SLOCorrelationEvent{
				Timestamp:   st.UpdatedAt.Format("2006-01-02 15:04:05"),
				Type:        "deployment",
				StackName:   st.Name,
				ServiceName: svc.Name,
				Description: fmt.Sprintf("Stack '%s' updated/redeployed", st.Name),
				BurnRate:    burnRate,
			})
		}
	}

	c.JSON(http.StatusOK, events)
}

// @Summary Get SLO Historical Trend Data Points
// @Description Fetch Prometheus range time-series points for an SLO
// @Tags slo
// @Produce json
// @Param service_id query string true "Service ID"
// @Param range query string false "Range duration (1h, 6h, 24h, 7d, 30d)"
// @Success 200 {array} SLOHistoryPoint
// @Router /v1/slo/history [get]
func SLOHistoryHandler(c *gin.Context) {
	serviceID := c.Query("service_id")
	rangeParam := c.Query("range")
	if rangeParam == "" {
		rangeParam = "24h"
	}

	var durationSec int64 = 86400
	var stepSec int64 = 300
	switch rangeParam {
	case "1h":
		durationSec = 3600
		stepSec = 15
	case "6h":
		durationSec = 21600
		stepSec = 60
	case "24h":
		durationSec = 86400
		stepSec = 300
	case "7d":
		durationSec = 604800
		stepSec = 1800
	case "30d":
		durationSec = 2592000
		stepSec = 7200
	}

	now := time.Now().Unix()
	start := now - durationSec

	queryBudget := fmt.Sprintf(`slo:period_error_budget_remaining:ratio{gbnt_service_id="%s"}`, serviceID)
	queryBurn := fmt.Sprintf(`slo:current_burn_rate:ratio{gbnt_service_id="%s"}`, serviceID)

	budgetPoints := queryPrometheusRangeMetric(queryBudget, start, now, stepSec)
	burnPoints := queryPrometheusRangeMetric(queryBurn, start, now, stepSec)

	pointsMap := make(map[int64]*SLOHistoryPoint)
	for t, val := range budgetPoints {
		pointsMap[t] = &SLOHistoryPoint{
			Timestamp:       time.Unix(t, 0).Format("15:04"),
			BudgetRemaining: val * 100.0,
			BurnRate:        0.0,
		}
	}
	for t, val := range burnPoints {
		if pt, exists := pointsMap[t]; exists {
			pt.BurnRate = val
		} else {
			pointsMap[t] = &SLOHistoryPoint{
				Timestamp:       time.Unix(t, 0).Format("15:04"),
				BudgetRemaining: 100.0,
				BurnRate:        val,
			}
		}
	}

	var result []SLOHistoryPoint
	for i := start; i <= now; i += stepSec {
		closest := i - (i % stepSec)
		if pt, exists := pointsMap[closest]; exists {
			result = append(result, *pt)
		}
	}

	c.JSON(http.StatusOK, result)
}

// @Summary Get Service RED Metrics (Rate, Errors, Duration)
// @Description Query Prometheus for RPS, Error RPS, and P99 Duration
// @Tags slo
// @Produce json
// @Param service_id query string true "Service ID"
// @Success 200 {object} SLOREDMetrics
// @Router /v1/slo/red [get]
func SLOREDMetricsHandler(c *gin.Context) {
	serviceID := c.Query("service_id")
	var svc db.Service
	if err := db.DB.First(&svc, "id = ?", serviceID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Service not found"})
		return
	}

	rps, _ := queryPrometheusMetricCached(fmt.Sprintf(`sum(rate(caddy_http_response_status_code_total{service="%s"}[5m]))`, svc.Name))
	errRps, _ := queryPrometheusMetricCached(fmt.Sprintf(`sum(rate(caddy_http_response_status_code_total{service="%s",status=~"5.."}[5m]))`, svc.Name))
	p99, _ := queryPrometheusMetricCached(fmt.Sprintf(`histogram_quantile(0.99, sum(rate(caddy_http_request_duration_seconds_bucket{service="%s"}[5m])) by (le)) * 1000`, svc.Name))

	if rps < 0 {
		rps = 0
	}
	if errRps < 0 {
		errRps = 0
	}
	if p99 < 0 {
		p99 = 0
	}

	c.JSON(http.StatusOK, SLOREDMetrics{
		RPS:          rps,
		ErrorRPS:     errRps,
		P99LatencyMs: p99,
	})
}

// @Summary Validate and Backtest SLOs in Compose YAML
// @Description Dry-run validation & PromQL metric backtesting for Compose YAML
// @Tags slo
// @Accept json
// @Produce json
// @Param request body SLOValidateRequest true "SLO Validation Request"
// @Success 200 {array} SLOValidationItem
// @Router /v1/slo/validate [post]
func SLOValidateHandler(c *gin.Context) {
	var req SLOValidateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var compose ComposeFile
	if err := yaml.Unmarshal([]byte(req.ComposeRaw), &compose); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Invalid YAML: %v", err)})
		return
	}

	var results []SLOValidationItem
	for srvName, srvDef := range compose.Services {
		labels := make(map[string]string)
		for k, v := range srvDef.Labels {
			labels[k] = v
		}
		for k, v := range srvDef.Deploy.Labels {
			labels[k] = v
		}

		if labels["gbnt.slo.enable"] != "true" && labels["gbnt.slo.enable"] != "1" {
			continue
		}

		item := SLOValidationItem{
			ServiceName:     srvName,
			Valid:           true,
			Target:          99.9,
			Window:          "30d",
			Template:        labels["gbnt.slo.template"],
			ErrorQuery:      labels["gbnt.slo.sli.error_query"],
			TotalQuery:      labels["gbnt.slo.sli.total_query"],
			BacktestStatus:  "passed",
			BacktestDetails: "PromQL metrics syntax valid and active in Prometheus",
		}

		if tStr := labels["gbnt.slo.target"]; tStr != "" {
			if f, err := strconv.ParseFloat(tStr, 64); err == nil && f > 0 {
				item.Target = f
			} else {
				item.Valid = false
				item.Error = fmt.Sprintf("Invalid target '%s': must be positive float", tStr)
			}
		}

		if wStr := labels["gbnt.slo.window"]; wStr != "" {
			item.Window = wStr
		}

		if (item.ErrorQuery == "" || item.TotalQuery == "") && item.Template != "" {
			tErr, tTot := slo.ExpandSLITemplate(item.Template, srvName)
			if item.ErrorQuery == "" {
				item.ErrorQuery = tErr
			}
			if item.TotalQuery == "" {
				item.TotalQuery = tTot
			}
		}

		if item.ErrorQuery == "" || item.TotalQuery == "" {
			item.Valid = false
			item.Error = "Missing error_query or total_query (or valid template)"
		}

		if item.Valid {
			testQuery := strings.ReplaceAll(item.ErrorQuery, "{{.window}}", "5m")
			testQuery = strings.ReplaceAll(testQuery, "{{ .window }}", "5m")
			_, err := queryPrometheusMetricCached(testQuery)
			if err != nil {
				item.BacktestStatus = "no_data"
				item.BacktestDetails = "Prometheus returned no historical series for error query (dry-run mode)"
			}
		}

		results = append(results, item)
	}

	c.JSON(http.StatusOK, results)
}

func queryPrometheusMetricCached(query string) (float64, error) {
	promCacheMutex.RLock()
	entry, found := promCache[query]
	promCacheMutex.RUnlock()

	if found && time.Since(entry.fetchedAt) < cacheTTL {
		return entry.val, entry.err
	}

	val, err := queryPrometheusMetric(query)

	promCacheMutex.Lock()
	promCache[query] = cacheEntry{
		val:       val,
		err:       err,
		fetchedAt: time.Now(),
	}
	promCacheMutex.Unlock()

	return val, err
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

func queryPrometheusRangeMetric(query string, start, end, step int64) map[int64]float64 {
	res := make(map[int64]float64)
	urlStr := fmt.Sprintf("http://localhost:9090/api/v1/query_range?query=%s&start=%d&end=%d&step=%d", query, start, end, step)
	resp, err := http.Get(urlStr)
	if err != nil {
		return res
	}
	defer resp.Body.Close()

	var result struct {
		Data struct {
			Result []struct {
				Values [][]interface{} `json:"values"`
			} `json:"result"`
		} `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return res
	}

	if len(result.Data.Result) > 0 {
		for _, pair := range result.Data.Result[0].Values {
			if len(pair) >= 2 {
				tsFloat, ok1 := pair[0].(float64)
				strVal, ok2 := pair[1].(string)
				if ok1 && ok2 {
					if f, err := strconv.ParseFloat(strVal, 64); err == nil {
						res[int64(tsFloat)] = f
					}
				}
			}
		}
	}

	return res
}
