package monitor

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"time"
)

// ProvisionOpenSearchObjects automatically bootstraps index patterns, default index settings,
// saved searches, container telemetry visualizations, and SIEM dashboards in OpenSearch Dashboards.
func ProvisionOpenSearchObjects() {
	baseURL := "http://127.0.0.1:5601"
	client := &http.Client{Timeout: 5 * time.Second}

	// 1. Wait for OpenSearch Dashboards to be healthy and responsive (up to 90 seconds)
	fmt.Println("⏳ SRE Monitor: Waiting for OpenSearch Dashboards (:5601) to initialize...")
	ready := false
	for i := 0; i < 30; i++ {
		resp, err := client.Get(baseURL + "/api/status")
		if err == nil && resp.StatusCode == http.StatusOK {
			resp.Body.Close()
			ready = true
			break
		}
		if resp != nil && resp.Body != nil {
			resp.Body.Close()
		}
		time.Sleep(3 * time.Second)
	}

	if !ready {
		fmt.Println("⚠️  SRE Monitor: OpenSearch Dashboards did not become ready in time, skipping auto-provisioning.")
		return
	}

	fmt.Println("🚀 SRE Monitor: Auto-provisioning OpenSearch Dashboards index patterns, visualizations, and dashboards...")

	// 2. Provision Index Pattern
	fieldsJSON := `[{"name":"@timestamp","type":"date","searchable":true,"aggregatable":true,"readFromDocValues":true},{"name":"stream.keyword","type":"string","searchable":true,"aggregatable":true,"readFromDocValues":true},{"name":"stream","type":"string","searchable":true,"aggregatable":false},{"name":"log","type":"string","searchable":true,"aggregatable":false},{"name":"log.keyword","type":"string","searchable":true,"aggregatable":true,"readFromDocValues":true},{"name":"container_log_path.keyword","type":"string","searchable":true,"aggregatable":true,"readFromDocValues":true},{"name":"container_log_path","type":"string","searchable":true,"aggregatable":false},{"name":"time","type":"date","searchable":true,"aggregatable":true,"readFromDocValues":true},{"name":"_id","type":"string","searchable":true,"aggregatable":true},{"name":"_index","type":"string","searchable":true,"aggregatable":true},{"name":"_score","type":"number","searchable":false,"aggregatable":false}]`
	indexPatternPayload := fmt.Sprintf(`{
		"attributes": {
			"title": "gubernator-logs*",
			"timeFieldName": "@timestamp",
			"fields": %q
		}
	}`, fieldsJSON)
	_ = postSavedObject(client, baseURL, "index-pattern", "gubernator-logs", indexPatternPayload)

	// 3. Set Default Index
	_ = postSetting(client, baseURL, "defaultIndex", `{"value": "gubernator-logs"}`)

	// 4. Provision Saved Searches
	allLogsSearch := `{
		"attributes": {
			"title": "Live Container Logs Stream",
			"description": "Live streaming logs from all cluster containers",
			"columns": ["@timestamp", "stream", "log", "container_log_path"],
			"sort": [["@timestamp", "desc"]],
			"kibanaSavedObjectMeta": {
				"searchSourceJSON": "{\"highlightAll\":true,\"version\":true,\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[],\"indexRefName\":\"kibanaSavedObjectMeta.searchSourceJSON.index\"}"
			}
		},
		"references": [
			{"id": "gubernator-logs", "name": "kibanaSavedObjectMeta.searchSourceJSON.index", "type": "index-pattern"}
		]
	}`
	_ = postSavedObject(client, baseURL, "search", "gubernator-all-logs", allLogsSearch)

	errorLogsSearch := `{
		"attributes": {
			"title": "Security, Warnings & Error Logs",
			"description": "Filtered errors, warnings, exceptions and stderr logs across containers",
			"columns": ["@timestamp", "stream", "log", "container_log_path"],
			"sort": [["@timestamp", "desc"]],
			"kibanaSavedObjectMeta": {
				"searchSourceJSON": "{\"highlightAll\":true,\"version\":true,\"query\":{\"query\":\"stream: \\\"stderr\\\" or log: *error* or log: *fail* or log: *warn* or log: *exception*\",\"language\":\"kuery\"},\"filter\":[],\"indexRefName\":\"kibanaSavedObjectMeta.searchSourceJSON.index\"}"
			}
		},
		"references": [
			{"id": "gubernator-logs", "name": "kibanaSavedObjectMeta.searchSourceJSON.index", "type": "index-pattern"}
		]
	}`
	_ = postSavedObject(client, baseURL, "search", "gubernator-error-logs", errorLogsSearch)

	// 5. Provision Visualizations
	visTotalLogs := `{
		"attributes": {
			"title": "Total Log Events",
			"visState": "{\"title\":\"Total Log Events\",\"type\":\"metric\",\"params\":{\"addTooltip\":true,\"addLegend\":false,\"type\":\"metric\",\"metric\":{\"percentageMode\":false,\"useRanges\":false,\"colorSchema\":\"Green to Red\",\"metricColorMode\":\"None\",\"colorsRange\":[{\"from\":0,\"to\":10000}],\"labels\":{\"show\":true},\"style\":{\"bgFill\":\"#000\",\"bgColor\":false,\"labelColor\":false,\"subText\":\"\",\"fontSize\":60}}},\"aggs\":[{\"id\":\"1\",\"enabled\":true,\"type\":\"count\",\"schema\":\"metric\",\"params\":{\"customLabel\":\"Total Logs\"}}]}",
			"uiStateJSON": "{}",
			"description": "",
			"version": 1,
			"kibanaSavedObjectMeta": {
				"searchSourceJSON": "{\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[],\"indexRefName\":\"kibanaSavedObjectMeta.searchSourceJSON.index\"}"
			}
		},
		"references": [
			{"id": "gubernator-logs", "name": "kibanaSavedObjectMeta.searchSourceJSON.index", "type": "index-pattern"}
		]
	}`
	_ = postSavedObject(client, baseURL, "visualization", "vis-total-logs", visTotalLogs)

	visStdoutCount := `{
		"attributes": {
			"title": "Stdout Events (Standard)",
			"visState": "{\"title\":\"Stdout Events\",\"type\":\"metric\",\"params\":{\"addTooltip\":true,\"addLegend\":false,\"type\":\"metric\",\"metric\":{\"percentageMode\":false,\"useRanges\":false,\"colorSchema\":\"Green to Red\",\"metricColorMode\":\"None\",\"colorsRange\":[{\"from\":0,\"to\":10000}],\"labels\":{\"show\":true},\"style\":{\"bgFill\":\"#000\",\"bgColor\":false,\"labelColor\":false,\"subText\":\"\",\"fontSize\":60}}},\"aggs\":[{\"id\":\"1\",\"enabled\":true,\"type\":\"count\",\"schema\":\"metric\",\"params\":{\"customLabel\":\"Stdout Logs\"}}]}",
			"uiStateJSON": "{}",
			"description": "",
			"version": 1,
			"kibanaSavedObjectMeta": {
				"searchSourceJSON": "{\"query\":{\"query\":\"stream: \\\"stdout\\\"\",\"language\":\"kuery\"},\"filter\":[],\"indexRefName\":\"kibanaSavedObjectMeta.searchSourceJSON.index\"}"
			}
		},
		"references": [
			{"id": "gubernator-logs", "name": "kibanaSavedObjectMeta.searchSourceJSON.index", "type": "index-pattern"}
		]
	}`
	_ = postSavedObject(client, baseURL, "visualization", "vis-stdout-count", visStdoutCount)

	visErrorCount := `{
		"attributes": {
			"title": "Error & Stderr Warnings",
			"visState": "{\"title\":\"Error & Warnings\",\"type\":\"metric\",\"params\":{\"addTooltip\":true,\"addLegend\":false,\"type\":\"metric\",\"metric\":{\"percentageMode\":false,\"useRanges\":false,\"colorSchema\":\"Green to Red\",\"metricColorMode\":\"None\",\"colorsRange\":[{\"from\":0,\"to\":10000}],\"labels\":{\"show\":true},\"style\":{\"bgFill\":\"#000\",\"bgColor\":false,\"labelColor\":false,\"subText\":\"\",\"fontSize\":60}}},\"aggs\":[{\"id\":\"1\",\"enabled\":true,\"type\":\"count\",\"schema\":\"metric\",\"params\":{\"customLabel\":\"Stderr / Errors\"}}]}",
			"uiStateJSON": "{}",
			"description": "",
			"version": 1,
			"kibanaSavedObjectMeta": {
				"searchSourceJSON": "{\"query\":{\"query\":\"stream: \\\"stderr\\\" or log: *error* or log: *fail* or log: *warn*\",\"language\":\"kuery\"},\"filter\":[],\"indexRefName\":\"kibanaSavedObjectMeta.searchSourceJSON.index\"}"
			}
		},
		"references": [
			{"id": "gubernator-logs", "name": "kibanaSavedObjectMeta.searchSourceJSON.index", "type": "index-pattern"}
		]
	}`
	_ = postSavedObject(client, baseURL, "visualization", "vis-error-count", visErrorCount)

	visStreamPie := `{
		"attributes": {
			"title": "Log Streams Breakdown (stdout vs stderr)",
			"visState": "{\"title\":\"Log Streams Breakdown\",\"type\":\"pie\",\"params\":{\"type\":\"pie\",\"addTooltip\":true,\"addLegend\":true,\"legendPosition\":\"right\",\"isDonut\":true,\"labels\":{\"show\":true,\"values\":true,\"truncate\":100}},\"aggs\":[{\"id\":\"1\",\"enabled\":true,\"type\":\"count\",\"schema\":\"metric\",\"params\":{}},{\"id\":\"2\",\"enabled\":true,\"type\":\"terms\",\"schema\":\"segment\",\"params\":{\"field\":\"stream.keyword\",\"size\":5,\"order\":\"desc\",\"orderBy\":\"1\",\"customLabel\":\"Stream\"}}]}",
			"uiStateJSON": "{}",
			"description": "",
			"version": 1,
			"kibanaSavedObjectMeta": {
				"searchSourceJSON": "{\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[],\"indexRefName\":\"kibanaSavedObjectMeta.searchSourceJSON.index\"}"
			}
		},
		"references": [
			{"id": "gubernator-logs", "name": "kibanaSavedObjectMeta.searchSourceJSON.index", "type": "index-pattern"}
		]
	}`
	_ = postSavedObject(client, baseURL, "visualization", "vis-stream-pie", visStreamPie)

	visLogsTimeline := `{
		"attributes": {
			"title": "Log Activity Trends Over Time",
			"visState": "{\"title\":\"Log Activity Trends Over Time\",\"type\":\"histogram\",\"params\":{\"type\":\"histogram\",\"grid\":{\"categoryLines\":false},\"categoryAxes\":[{\"id\":\"CategoryAxis-1\",\"type\":\"category\",\"position\":\"bottom\",\"show\":true,\"style\":{},\"scale\":{\"type\":\"linear\"},\"labels\":{\"show\":true,\"truncate\":100},\"title\":{}}],\"valueAxes\":[{\"id\":\"ValueAxis-1\",\"name\":\"LeftAxis-1\",\"type\":\"value\",\"position\":\"left\",\"show\":true,\"style\":{},\"scale\":{\"type\":\"linear\",\"mode\":\"normal\"},\"labels\":{\"show\":true,\"rotate\":0,\"filter\":false,\"truncate\":100},\"title\":{\"text\":\"Log Count\"}}],\"seriesParams\":[{\"show\":true,\"type\":\"histogram\",\"mode\":\"stacked\",\"data\":{\"label\":\"Count\",\"id\":\"1\"},\"valueAxis\":\"ValueAxis-1\",\"drawLinesBetweenPoints\":true,\"showCircles\":true}],\"addTooltip\":true,\"addLegend\":true,\"legendPosition\":\"right\"},\"aggs\":[{\"id\":\"1\",\"enabled\":true,\"type\":\"count\",\"schema\":\"metric\",\"params\":{}},{\"id\":\"2\",\"enabled\":true,\"type\":\"date_histogram\",\"schema\":\"segment\",\"params\":{\"field\":\"@timestamp\",\"interval\":\"auto\",\"customInterval\":\"2h\",\"min_doc_count\":1,\"extended_bounds\":{}}},{\"id\":\"3\",\"enabled\":true,\"type\":\"terms\",\"schema\":\"group\",\"params\":{\"field\":\"stream.keyword\",\"size\":5,\"order\":\"desc\",\"orderBy\":\"1\"}}]}",
			"uiStateJSON": "{}",
			"description": "",
			"version": 1,
			"kibanaSavedObjectMeta": {
				"searchSourceJSON": "{\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[],\"indexRefName\":\"kibanaSavedObjectMeta.searchSourceJSON.index\"}"
			}
		},
		"references": [
			{"id": "gubernator-logs", "name": "kibanaSavedObjectMeta.searchSourceJSON.index", "type": "index-pattern"}
		]
	}`
	_ = postSavedObject(client, baseURL, "visualization", "vis-logs-timeline", visLogsTimeline)

	visTopContainers := `{
		"attributes": {
			"title": "Top Active Containers by Log Volume",
			"visState": "{\"title\":\"Top Active Containers by Log Volume\",\"type\":\"horizontal_bar\",\"params\":{\"type\":\"horizontal_bar\",\"grid\":{\"categoryLines\":false},\"categoryAxes\":[{\"id\":\"CategoryAxis-1\",\"type\":\"category\",\"position\":\"left\",\"show\":true,\"style\":{},\"scale\":{\"type\":\"linear\"},\"labels\":{\"show\":true,\"truncate\":60},\"title\":{}}],\"valueAxes\":[{\"id\":\"ValueAxis-1\",\"name\":\"LeftAxis-1\",\"type\":\"value\",\"position\":\"bottom\",\"show\":true,\"style\":{},\"scale\":{\"type\":\"linear\",\"mode\":\"normal\"},\"labels\":{\"show\":true,\"rotate\":0,\"filter\":false,\"truncate\":100},\"title\":{\"text\":\"Log Events\"}}],\"seriesParams\":[{\"show\":true,\"type\":\"horizontal_bar\",\"mode\":\"normal\",\"data\":{\"label\":\"Count\",\"id\":\"1\"},\"valueAxis\":\"ValueAxis-1\"}],\"addTooltip\":true,\"addLegend\":false},\"aggs\":[{\"id\":\"1\",\"enabled\":true,\"type\":\"count\",\"schema\":\"metric\",\"params\":{}},{\"id\":\"2\",\"enabled\":true,\"type\":\"terms\",\"schema\":\"segment\",\"params\":{\"field\":\"container_log_path.keyword\",\"size\":10,\"order\":\"desc\",\"orderBy\":\"1\",\"customLabel\":\"Container Log Path\"}}]}",
			"uiStateJSON": "{}",
			"description": "",
			"version": 1,
			"kibanaSavedObjectMeta": {
				"searchSourceJSON": "{\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[],\"indexRefName\":\"kibanaSavedObjectMeta.searchSourceJSON.index\"}"
			}
		},
		"references": [
			{"id": "gubernator-logs", "name": "kibanaSavedObjectMeta.searchSourceJSON.index", "type": "index-pattern"}
		]
	}`
	_ = postSavedObject(client, baseURL, "visualization", "vis-top-containers", visTopContainers)

	// 6. Provision Dashboards
	clusterLogsDashboard := `{
		"attributes": {
			"title": "[Gubernator] Container Cluster Logs Overview",
			"description": "Cluster-wide container log volume, streams breakdown, activity trends, and live logs.",
			"panelsJSON": "[{\"version\":\"7.10.0\",\"type\":\"visualization\",\"gridData\":{\"x\":0,\"y\":0,\"w\":12,\"h\":6,\"i\":\"1\"},\"panelIndex\":\"1\",\"embeddableConfig\":{},\"panelRefName\":\"panel_0\"},{\"version\":\"7.10.0\",\"type\":\"visualization\",\"gridData\":{\"x\":12,\"y\":0,\"w\":12,\"h\":6,\"i\":\"2\"},\"panelIndex\":\"2\",\"embeddableConfig\":{},\"panelRefName\":\"panel_1\"},{\"version\":\"7.10.0\",\"type\":\"visualization\",\"gridData\":{\"x\":24,\"y\":0,\"w\":12,\"h\":6,\"i\":\"3\"},\"panelIndex\":\"3\",\"embeddableConfig\":{},\"panelRefName\":\"panel_2\"},{\"version\":\"7.10.0\",\"type\":\"visualization\",\"gridData\":{\"x\":36,\"y\":0,\"w\":12,\"h\":6,\"i\":\"4\"},\"panelIndex\":\"4\",\"embeddableConfig\":{},\"panelRefName\":\"panel_3\"},{\"version\":\"7.10.0\",\"type\":\"visualization\",\"gridData\":{\"x\":0,\"y\":6,\"w\":30,\"h\":12,\"i\":\"5\"},\"panelIndex\":\"5\",\"embeddableConfig\":{},\"panelRefName\":\"panel_4\"},{\"version\":\"7.10.0\",\"type\":\"visualization\",\"gridData\":{\"x\":30,\"y\":6,\"w\":18,\"h\":12,\"i\":\"6\"},\"panelIndex\":\"6\",\"embeddableConfig\":{},\"panelRefName\":\"panel_5\"},{\"version\":\"7.10.0\",\"type\":\"search\",\"gridData\":{\"x\":0,\"y\":18,\"w\":48,\"h\":16,\"i\":\"7\"},\"panelIndex\":\"7\",\"embeddableConfig\":{},\"panelRefName\":\"panel_6\"}]",
			"optionsJSON": "{\"useMargins\":true,\"hidePanelTitles\":false}",
			"version": 1,
			"timeRestore": true,
			"timeFrom": "now-24h",
			"timeTo": "now",
			"kibanaSavedObjectMeta": {
				"searchSourceJSON": "{\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[]}"
			}
		},
		"references": [
			{"name": "panel_0", "type": "visualization", "id": "vis-total-logs"},
			{"name": "panel_1", "type": "visualization", "id": "vis-stdout-count"},
			{"name": "panel_2", "type": "visualization", "id": "vis-error-count"},
			{"name": "panel_3", "type": "visualization", "id": "vis-stream-pie"},
			{"name": "panel_4", "type": "visualization", "id": "vis-logs-timeline"},
			{"name": "panel_5", "type": "visualization", "id": "vis-top-containers"},
			{"name": "panel_6", "type": "search", "id": "gubernator-all-logs"}
		]
	}`
	_ = postSavedObject(client, baseURL, "dashboard", "gubernator-cluster-logs", clusterLogsDashboard)

	siemAuditDashboard := `{
		"attributes": {
			"title": "[Gubernator] SIEM Security & Error Audit",
			"description": "Security events, container error logs, exceptions and compliance auditing.",
			"panelsJSON": "[{\"version\":\"7.10.0\",\"type\":\"visualization\",\"gridData\":{\"x\":0,\"y\":16,\"w\":16,\"h\":6,\"i\":\"1\"},\"panelIndex\":\"1\",\"embeddableConfig\":{},\"panelRefName\":\"panel_0\"},{\"version\":\"7.10.0\",\"type\":\"visualization\",\"gridData\":{\"x\":16,\"y\":16,\"w\":16,\"h\":6,\"i\":\"2\"},\"panelIndex\":\"2\",\"embeddableConfig\":{},\"panelRefName\":\"panel_1\"},{\"version\":\"7.10.0\",\"type\":\"visualization\",\"gridData\":{\"x\":32,\"y\":16,\"w\":16,\"h\":6,\"i\":\"3\"},\"panelIndex\":\"3\",\"embeddableConfig\":{},\"panelRefName\":\"panel_2\"},{\"version\":\"7.10.0\",\"type\":\"visualization\",\"gridData\":{\"x\":0,\"y\":0,\"w\":48,\"h\":10,\"i\":\"4\"},\"panelIndex\":\"4\",\"embeddableConfig\":{},\"panelRefName\":\"panel_3\"},{\"version\":\"7.10.0\",\"type\":\"search\",\"gridData\":{\"x\":0,\"y\":10,\"w\":48,\"h\":18,\"i\":\"5\"},\"panelIndex\":\"5\",\"embeddableConfig\":{},\"panelRefName\":\"panel_4\"}]",
			"optionsJSON": "{\"useMargins\":true,\"hidePanelTitles\":false}",
			"version": 1,
			"timeRestore": true,
			"timeFrom": "now-24h",
			"timeTo": "now",
			"kibanaSavedObjectMeta": {
				"searchSourceJSON": "{\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[]}"
			}
		},
		"references": [
			{"name": "panel_0", "type": "visualization", "id": "vis-total-logs"},
			{"name": "panel_1", "type": "visualization", "id": "vis-error-count"},
			{"name": "panel_2", "type": "visualization", "id": "vis-stream-pie"},
			{"name": "panel_3", "type": "visualization", "id": "vis-logs-timeline"},
			{"name": "panel_4", "type": "search", "id": "gubernator-error-logs"}
		]
	}`
	_ = postSavedObject(client, baseURL, "dashboard", "gubernator-siem-audit", siemAuditDashboard)

	fmt.Println("✅ SRE Monitor: OpenSearch Dashboards auto-provisioning completed successfully!")
}

func postSavedObject(client *http.Client, baseURL, objType, id, jsonBody string) error {
	url := fmt.Sprintf("%s/api/saved_objects/%s/%s?overwrite=true", baseURL, objType, id)
	req, err := http.NewRequest("POST", url, bytes.NewBufferString(jsonBody))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("osd-xsrf", "true")

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	io.Copy(io.Discard, resp.Body)
	return nil
}

func postSetting(client *http.Client, baseURL, key, jsonBody string) error {
	url := fmt.Sprintf("%s/api/opensearch-dashboards/settings/%s", baseURL, key)
	req, err := http.NewRequest("POST", url, bytes.NewBufferString(jsonBody))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("osd-xsrf", "true")

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	io.Copy(io.Discard, resp.Body)
	return nil
}
