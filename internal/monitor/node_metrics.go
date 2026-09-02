package monitor

import (
	"encoding/json"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/mario-ezquerro/gubernator/internal/storage"
)

type prometheusQueryResponse struct {
	Status string `json:"status"`
	Data   struct {
		Result []struct {
			Metric map[string]string `json:"metric"`
			Value  []interface{}     `json:"value"`
		} `json:"result"`
	} `json:"data"`
}

func queryPrometheus(query string) map[string]float64 {
	results := make(map[string]float64)
	client := http.Client{Timeout: 800 * time.Millisecond}

	urls := []string{
		"http://localhost:9090/api/v1/query?query=" + url.QueryEscape(query),
		"http://gbnt-monitor-prometheus:9090/api/v1/query?query=" + url.QueryEscape(query),
		"http://127.0.0.1:9090/api/v1/query?query=" + url.QueryEscape(query),
	}

	var resp *http.Response
	var err error
	for _, u := range urls {
		resp, err = client.Get(u)
		if err == nil && resp.StatusCode == 200 {
			break
		}
	}
	if err != nil || resp == nil || resp.StatusCode != 200 {
		return results
	}
	defer resp.Body.Close()

	var pResp prometheusQueryResponse
	if err := json.NewDecoder(resp.Body).Decode(&pResp); err != nil {
		return results
	}

	for _, item := range pResp.Data.Result {
		instance := item.Metric["instance"]
		if len(item.Value) >= 2 {
			var val float64
			switch v := item.Value[1].(type) {
			case string:
				val, _ = strconv.ParseFloat(v, 64)
			case float64:
				val = v
			}
			results[instance] = val
		}
	}
	return results
}

func queryPrometheusMap(query string, keyLabel string) map[string]float64 {
	results := make(map[string]float64)
	client := http.Client{Timeout: 1200 * time.Millisecond}

	urls := []string{
		"http://localhost:9090/api/v1/query?query=" + url.QueryEscape(query),
		"http://gbnt-monitor-prometheus:9090/api/v1/query?query=" + url.QueryEscape(query),
		"http://127.0.0.1:9090/api/v1/query?query=" + url.QueryEscape(query),
	}

	var resp *http.Response
	var err error
	for _, u := range urls {
		resp, err = client.Get(u)
		if err == nil && resp.StatusCode == 200 {
			break
		}
	}
	if err != nil || resp == nil || resp.StatusCode != 200 {
		return results
	}
	defer resp.Body.Close()

	var pResp prometheusQueryResponse
	if err := json.NewDecoder(resp.Body).Decode(&pResp); err != nil {
		return results
	}

	for _, item := range pResp.Data.Result {
		k := item.Metric[keyLabel]
		if k == "" {
			k = item.Metric["name"]
		}
		if k == "" {
			k = item.Metric["id"]
		}
		if k != "" && len(item.Value) >= 2 {
			var val float64
			switch v := item.Value[1].(type) {
			case string:
				val, _ = strconv.ParseFloat(v, 64)
			case float64:
				val = v
			}
			results[k] = val
		}
	}
	return results
}

// PopulateContainerMetrics queries Prometheus cAdvisor metrics and populates CpuPercent and MemUsedBytes for tasks.
func PopulateContainerMetrics(tasks []db.Task) {
	if len(tasks) == 0 {
		return
	}

	cpuMap := queryPrometheusMap("sum by (name) (rate(container_cpu_usage_seconds_total{name=~\"gbnt-.+\"}[1m]) * 100)", "name")
	memMap := queryPrometheusMap("container_memory_working_set_bytes{name=~\"gbnt-.+\"}", "name")

	for i := range tasks {
		t := &tasks[i]
		if t.Status != "running" {
			t.CpuPercent = 0.0
			t.MemUsedBytes = 0
			continue
		}

		findMetric := func(m map[string]float64) float64 {
			if t.ContainerName != "" {
				if v, ok := m[t.ContainerName]; ok {
					return v
				}
				// Try match by substring
				for k, v := range m {
					if strings.Contains(k, t.ContainerName) || strings.Contains(t.ContainerName, k) {
						return v
					}
				}
			}
			// Search by task ID
			if len(t.ID) >= 8 {
				prefix := t.ID[:8]
				for k, v := range m {
					if strings.Contains(k, prefix) {
						return v
					}
				}
			}
			return 0
		}

		t.CpuPercent = findMetric(cpuMap)
		t.MemUsedBytes = uint64(findMetric(memMap))
	}
}

// PopulateNodeMetrics queries Prometheus for node-exporter metrics and fills the Node metrics fields.
func PopulateNodeMetrics(nodes []db.Node) {
	if len(nodes) == 0 {
		return
	}

	cpuMap := queryPrometheus("100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)")
	memTotalMap := queryPrometheus("node_memory_MemTotal_bytes")
	memAvailMap := queryPrometheus("node_memory_MemAvailable_bytes")
	netMap := queryPrometheus("sum by (instance) (rate(node_network_receive_bytes_total[5m]) + rate(node_network_transmit_bytes_total[5m]))")
	diskTotalMap := queryPrometheus("sum by (instance) (node_filesystem_size_bytes{mountpoint=~\"/|/rootfs|/data\"})")
	diskAvailMap := queryPrometheus("sum by (instance) (node_filesystem_avail_bytes{mountpoint=~\"/|/rootfs|/data\"})")

	for i := range nodes {
		n := &nodes[i]
		findVal := func(m map[string]float64) float64 {
			for k, v := range m {
				if strings.Contains(k, n.IP) || (n.Role == "manager" && (strings.Contains(k, "host.docker.internal") || strings.Contains(k, "127.0.0.1") || strings.Contains(k, "localhost"))) {
					return v
				}
			}
			if len(m) == 1 {
				for _, v := range m {
					return v
				}
			}
			for k, v := range m {
				if v > 0 && (strings.HasPrefix(k, n.IP) || n.Role == "manager") {
					return v
				}
			}
			return 0
		}

		n.CpuPercent = findVal(cpuMap)
		memTotal := uint64(findVal(memTotalMap))
		memAvail := uint64(findVal(memAvailMap))

		if memTotal > 0 {
			n.MemTotalBytes = memTotal
			if memTotal >= memAvail {
				n.MemUsedBytes = memTotal - memAvail
				n.MemPercent = (float64(n.MemUsedBytes) / float64(memTotal)) * 100
			}
		}

		// Populate Host Disk space metrics
		diskTotal := uint64(findVal(diskTotalMap))
		diskAvail := uint64(findVal(diskAvailMap))

		if diskTotal == 0 && (n.Role == "manager" || len(nodes) == 1) {
			// Query local host filesystem directly
			for _, checkPath := range []string{"/data", "/var/contenedores", "/", "."} {
				if t, f, err := storage.GetDiskSpace(checkPath); err == nil && t > 0 {
					diskTotal = t
					diskAvail = f
					break
				}
			}
		}

		if diskTotal > 0 {
			n.DiskTotalBytes = diskTotal
			n.DiskFreeBytes = diskAvail
			if diskTotal >= diskAvail {
				n.DiskUsedBytes = diskTotal - diskAvail
				n.DiskPercent = (float64(n.DiskUsedBytes) / float64(diskTotal)) * 100
			}
		}

		n.NetBps = findVal(netMap)
	}
}
