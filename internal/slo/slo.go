package slo

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/prometheus/prometheus/model/rulefmt"
	"github.com/slok/sloth/pkg/common/model"
	slothlib "github.com/slok/sloth/pkg/lib"
	prometheusv1 "github.com/slok/sloth/pkg/prometheus/api/v1"
	"gopkg.in/yaml.v3"
	"gorm.io/gorm"

	"github.com/mario-ezquerro/gubernator/internal/db"
)

// Spec represents Gubernator's SLO definition for a service
type Spec struct {
	ID          string  `json:"id"`
	ServiceID   string  `json:"service_id"`
	ServiceName string  `json:"service_name"`
	Target      float64 `json:"target"`
	Window      string  `json:"window"`
	ErrorQuery  string  `json:"error_query"`
	TotalQuery  string  `json:"total_query"`
}

func parseConstraints(constraints []string) map[string]string {
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

func ensureWindowVariable(query string) string {
	if strings.Contains(query, "{{.window}}") || strings.Contains(query, "{{ .window }}") {
		return query
	}
	re := regexp.MustCompile(`\[\s*\d+[smhd]\s*\]`)
	if re.MatchString(query) {
		return re.ReplaceAllString(query, "[{{.window}}]")
	}
	return query
}

func ExpandSLITemplate(tmpl, serviceName string) (errQuery, totalQuery string) {
	switch strings.ToLower(strings.TrimSpace(tmpl)) {
	case "caddy-http":
		return `sum(rate(caddy_http_response_status_code_total{status=~"5.."}[{{.window}}]))`,
			`sum(rate(caddy_http_response_status_code_total[{{.window}}]))`
	case "http-status":
		return `sum(rate(http_requests_total{status=~"5.."}[{{.window}}]))`,
			`sum(rate(http_requests_total[{{.window}}]))`
	case "latency-p99":
		return `sum(rate(http_request_duration_seconds_bucket{le="0.5"}[{{.window}}]))`,
			`sum(rate(http_request_duration_seconds_count[{{.window}}]))`
	case "grpc":
		return `sum(rate(grpc_server_handled_total{grpc_code=~"Unknown|Internal|Unavailable|DataLoss"}[{{.window}}]))`,
			`sum(rate(grpc_server_handled_total[{{.window}}]))`
	default:
		return "", ""
	}
}

// GenerateRulesFromServices scans all DB services for SLO labels and produces a single Prometheus rules YAML file.
func GenerateRulesFromServices(gormDB *gorm.DB) (string, error) {
	var services []db.Service
	if err := gormDB.Find(&services).Error; err != nil {
		return "", fmt.Errorf("failed to query services: %w", err)
	}

	var slothSLOs []prometheusv1.SLO
	for _, svc := range services {
		constraintsMap := parseConstraints(svc.Constraints)
		enabled := constraintsMap["gbnt.slo.enable"]
		if enabled != "true" && enabled != "1" {
			continue
		}

		targetStr := constraintsMap["gbnt.slo.target"]
		targetVal, err := strconv.ParseFloat(targetStr, 64)
		if err != nil || targetVal <= 0 {
			targetVal = 99.9
		}

		errQuery := ensureWindowVariable(constraintsMap["gbnt.slo.sli.error_query"])
		totalQuery := ensureWindowVariable(constraintsMap["gbnt.slo.sli.total_query"])

		if (errQuery == "" || totalQuery == "") && constraintsMap["gbnt.slo.template"] != "" {
			tErr, tTot := ExpandSLITemplate(constraintsMap["gbnt.slo.template"], svc.Name)
			if errQuery == "" {
				errQuery = tErr
			}
			if totalQuery == "" {
				totalQuery = tTot
			}
		}

		if errQuery == "" || totalQuery == "" {
			continue
		}

		slothSLO := prometheusv1.SLO{
			Name:      fmt.Sprintf("gbnt-slo-%s", svc.ID),
			Objective: targetVal,
			SLI: prometheusv1.SLI{
				Events: &prometheusv1.SLIEvents{
					ErrorQuery: errQuery,
					TotalQuery: totalQuery,
				},
			},
			Labels: map[string]string{
				"gbnt_service_id": svc.ID,
				"gbnt_stack_id":   svc.StackID,
			},
			Alerting: prometheusv1.Alerting{
				Name: fmt.Sprintf("%sSLOAlert", svc.Name),
			},
		}
		slothSLOs = append(slothSLOs, slothSLO)
	}

	if len(slothSLOs) == 0 {
		return "", nil
	}

	spec := prometheusv1.Spec{
		Version: prometheusv1.Version,
		Service: "gubernator-services",
		SLOs:    slothSLOs,
	}

	generator, err := slothlib.NewPrometheusSLOGenerator(slothlib.PrometheusSLOGeneratorConfig{})
	if err != nil {
		return "", fmt.Errorf("could not create sloth generator: %w", err)
	}

	ctx := context.Background()
	result, err := generator.GenerateFromSlothV1(ctx, spec)
	if err != nil {
		return "", fmt.Errorf("sloth rule generation failed: %w", err)
	}

	var ruleGroups []rulefmt.RuleGroup
	for _, res := range result.SLOResults {
		for _, rg := range []model.PromRuleGroup{res.PrometheusRules.SLIErrorRecRules, res.PrometheusRules.MetadataRecRules, res.PrometheusRules.AlertRules} {
			if len(rg.Rules) == 0 {
				continue
			}
			ruleGroups = append(ruleGroups, rulefmt.RuleGroup{
				Name:  rg.Name,
				Rules: rg.Rules,
			})
		}
		for _, extra := range res.PrometheusRules.ExtraRules {
			if len(extra.Rules) == 0 {
				continue
			}
			ruleGroups = append(ruleGroups, rulefmt.RuleGroup{
				Name:  extra.Name,
				Rules: extra.Rules,
			})
		}
	}

	promRuleFile := struct {
		Groups []rulefmt.RuleGroup `yaml:"groups"`
	}{
		Groups: ruleGroups,
	}

	var buf bytes.Buffer
	encoder := yaml.NewEncoder(&buf)
	encoder.SetIndent(2)
	if err := encoder.Encode(promRuleFile); err != nil {
		return "", fmt.Errorf("failed to encode prometheus rules: %w", err)
	}

	return buf.String(), nil
}

// SyncSLORulesToPrometheus generates and writes the Prometheus SLO rules file, notifying Prometheus if active.
func SyncSLORulesToPrometheus(gormDB *gorm.DB) error {
	rulesYAML, err := GenerateRulesFromServices(gormDB)
	if err != nil {
		return err
	}

	_ = SyncGrafanaDashboard(gormDB)

	dataDir := os.Getenv("GBNT_DATA_DIR")
	if dataDir == "" {
		dataDir = "/data"
	}
	if _, err := os.Stat(dataDir); os.IsNotExist(err) {
		dataDir = "."
	}

	rulesDir := filepath.Join(dataDir, "monitor", "prometheus", "rules")
	_ = os.MkdirAll(rulesDir, 0755)
	rulesPath := filepath.Join(rulesDir, "slo_rules.yml")

	if rulesYAML == "" {
		_ = os.Remove(rulesPath)
		return nil
	}

	if err := os.WriteFile(rulesPath, []byte(rulesYAML), 0644); err != nil {
		return fmt.Errorf("failed to write slo_rules.yml: %w", err)
	}

	slog.Info("SLO Engine: updated slo_rules.yml", "path", rulesPath)

	// Automatically notify Prometheus to reload rules if active
	go func() {
		client := &http.Client{Timeout: 2 * time.Second}
		resp, err := client.Post("http://localhost:9090/-/reload", "text/plain", nil)
		if err == nil && resp != nil {
			_ = resp.Body.Close()
			slog.Info("SLO Engine: reloaded Prometheus rules via /-/reload")
		}
	}()

	return nil
}

// QueryPrometheusMetric sends a instant PromQL query to local Prometheus instance.
func QueryPrometheusMetric(query string) (float64, error) {
	client := &http.Client{Timeout: 2 * time.Second}
	u := fmt.Sprintf("http://localhost:9090/api/v1/query?query=%s", strings.ReplaceAll(query, "+", "%2B"))
	resp, err := client.Get(u)
	if err != nil {
		return -1, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return -1, fmt.Errorf("prometheus query failed: status %d", resp.StatusCode)
	}

	var data struct {
		Data struct {
			Result []struct {
				Value []interface{} `json:"value"`
			} `json:"result"`
		} `json:"data"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
		return -1, err
	}

	if len(data.Data.Result) > 0 && len(data.Data.Result[0].Value) > 1 {
		valStr, ok := data.Data.Result[0].Value[1].(string)
		if ok {
			val, err := strconv.ParseFloat(valStr, 64)
			if err == nil {
				return val, nil
			}
		}
	}
	return -1, fmt.Errorf("no scalar metric value returned")
}

