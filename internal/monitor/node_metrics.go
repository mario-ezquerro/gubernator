package monitor

import (
	"encoding/json"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/db"
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

// PopulateNodeMetrics queries Prometheus for node-exporter metrics and fills the Node metrics fields.
func PopulateNodeMetrics(nodes []db.Node) {
	if len(nodes) == 0 {
		return
	}

	cpuMap := queryPrometheus("100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)")
	memTotalMap := queryPrometheus("node_memory_MemTotal_bytes")
	memAvailMap := queryPrometheus("node_memory_MemAvailable_bytes")
	netMap := queryPrometheus("sum by (instance) (rate(node_network_receive_bytes_total[5m]) + rate(node_network_transmit_bytes_total[5m]))")

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
		n.NetBps = findVal(netMap)
	}
}
