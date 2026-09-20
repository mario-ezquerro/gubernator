package coredns

import (
	"context"
	"fmt"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// CurlRequest specifies options for testing an HTTP/HTTPS endpoint.
type CurlRequest struct {
	Hostname       string `json:"hostname"`
	IP             string `json:"ip"`
	Protocol       string `json:"protocol"` // "http" or "https"
	Port           int    `json:"port"`
	Path           string `json:"path"`
	Method         string `json:"method"`
	FollowRedirect bool   `json:"follow_redirect"`
	Insecure       bool   `json:"insecure"`
	TimeoutSeconds int    `json:"timeout_seconds"`
}

// CurlResult holds the diagnostic outcome of an executed curl command.
type CurlResult struct {
	Command    string  `json:"command"`
	StatusCode int     `json:"status_code"`
	StatusText string  `json:"status_text"`
	LatencyMs  float64 `json:"latency_ms"`
	Headers    string  `json:"headers"`
	Body       string  `json:"body"`
	RawOutput  string  `json:"raw_output"`
	TargetIP   string  `json:"target_ip"`
	Success    bool    `json:"success"`
	Error      string  `json:"error,omitempty"`
}

// PingRequest specifies options for testing ICMP / network reachability.
type PingRequest struct {
	Hostname string `json:"hostname"`
	IP       string `json:"ip"`
	Count    int    `json:"count"`
}

// PingResult holds the diagnostic outcome of an executed ping command.
type PingResult struct {
	Command     string  `json:"command"`
	Target      string  `json:"target"`
	PacketsSent int     `json:"packets_sent"`
	PacketsRecv int     `json:"packets_recv"`
	PacketLoss  float64 `json:"packet_loss"`
	MinLatency  float64 `json:"min_latency"`
	AvgLatency  float64 `json:"avg_latency"`
	MaxLatency  float64 `json:"max_latency"`
	RawOutput   string  `json:"raw_output"`
	Success     bool    `json:"success"`
	Error       string  `json:"error,omitempty"`
}

// PerformCurl executes a curl request from the manager host against the target hostname.
func PerformCurl(req CurlRequest) (*CurlResult, error) {
	hostname := strings.TrimSpace(req.Hostname)
	if hostname == "" {
		return nil, fmt.Errorf("hostname cannot be empty")
	}

	protocol := strings.ToLower(strings.TrimSpace(req.Protocol))
	if protocol != "https" {
		protocol = "http"
	}

	method := strings.ToUpper(strings.TrimSpace(req.Method))
	if method == "" {
		method = "GET"
	}

	path := strings.TrimSpace(req.Path)
	if path == "" {
		path = "/"
	}
	if !strings.HasPrefix(path, "/") {
		path = "/" + path
	}

	timeoutSec := req.TimeoutSeconds
	if timeoutSec <= 0 {
		timeoutSec = 5
	}
	if timeoutSec > 15 {
		timeoutSec = 15
	}

	targetURL := fmt.Sprintf("%s://%s", protocol, hostname)
	if req.Port > 0 {
		targetURL = fmt.Sprintf("%s:%d", targetURL, req.Port)
	}
	targetURL += path

	// Construct curl CLI arguments
	args := []string{
		"-i", // include HTTP status & headers
		"-s", // silent mode
		"-S", // show error if it fails
		"-k", // allow self-signed or local certificates
		"--max-time", strconv.Itoa(timeoutSec),
	}

	if req.FollowRedirect {
		args = append(args, "-L")
	}

	if method == "HEAD" {
		args = append(args, "-I")
	} else if method != "GET" {
		args = append(args, "-X", method)
	}

	// Resolve mapping if IP is provided: binds hostname directly to the target IP
	targetIP := strings.TrimSpace(req.IP)
	if targetIP != "" {
		args = append(args, "--resolve", fmt.Sprintf("%s:80:%s", hostname, targetIP))
		args = append(args, "--resolve", fmt.Sprintf("%s:443:%s", hostname, targetIP))
		if req.Port > 0 && req.Port != 80 && req.Port != 443 {
			args = append(args, "--resolve", fmt.Sprintf("%s:%d:%s", hostname, req.Port, targetIP))
		}
	}

	args = append(args, targetURL)
	fullCmd := "curl " + strings.Join(args, " ")

	start := time.Now()
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeoutSec+2)*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, "curl", args...)
	outBytes, err := cmd.CombinedOutput()
	latencyMs := float64(time.Since(start).Microseconds()) / 1000.0

	raw := string(outBytes)
	res := &CurlResult{
		Command:   fullCmd,
		LatencyMs: latencyMs,
		RawOutput: raw,
		TargetIP:  targetIP,
		Success:   err == nil,
	}

	if err != nil {
		res.Error = err.Error()
		if strings.TrimSpace(raw) == "" {
			res.RawOutput = fmt.Sprintf("curl execution failed: %v", err)
		}
	}

	parseCurlOutput(res, raw)
	return res, nil
}

func parseCurlOutput(res *CurlResult, raw string) {
	if strings.TrimSpace(raw) == "" {
		return
	}

	// Look for HTTP status line e.g. "HTTP/1.1 200 OK" or "HTTP/2 302"
	lines := strings.Split(raw, "\n")
	var lastStatusLine string
	var headerLines []string
	inHeaders := false
	bodyStartIndex := -1

	for idx, line := range lines {
		trimmed := strings.TrimRight(line, "\r")
		if strings.HasPrefix(trimmed, "HTTP/") {
			lastStatusLine = trimmed
			inHeaders = true
			headerLines = []string{trimmed}
			continue
		}
		if inHeaders {
			if trimmed == "" {
				inHeaders = false
				bodyStartIndex = idx + 1
			} else {
				headerLines = append(headerLines, trimmed)
			}
		}
	}

	if lastStatusLine != "" {
		parts := strings.Fields(lastStatusLine)
		if len(parts) >= 2 {
			if code, err := strconv.Atoi(parts[1]); err == nil {
				res.StatusCode = code
			}
		}
		if len(parts) >= 3 {
			res.StatusText = strings.Join(parts[2:], " ")
		} else if res.StatusCode > 0 {
			res.StatusText = fmt.Sprintf("HTTP %d", res.StatusCode)
		}
	}

	if len(headerLines) > 0 {
		res.Headers = strings.Join(headerLines, "\n")
	}

	if bodyStartIndex >= 0 && bodyStartIndex < len(lines) {
		res.Body = strings.TrimSpace(strings.Join(lines[bodyStartIndex:], "\n"))
	}
}

// PerformPing executes an ICMP ping from the host against the target.
func PerformPing(req PingRequest) (*PingResult, error) {
	count := req.Count
	if count <= 0 {
		count = 3
	}
	if count > 5 {
		count = 5
	}

	target := strings.TrimSpace(req.IP)
	if target == "" {
		target = strings.TrimSpace(req.Hostname)
	}
	if target == "" {
		return nil, fmt.Errorf("hostname or IP cannot be empty")
	}

	args := []string{"-c", strconv.Itoa(count), target}
	fullCmd := "ping " + strings.Join(args, " ")

	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(count*2+3)*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, "ping", args...)
	outBytes, err := cmd.CombinedOutput()
	raw := string(outBytes)

	res := &PingResult{
		Command:     fullCmd,
		Target:      target,
		PacketsSent: count,
		RawOutput:   raw,
		Success:     err == nil,
	}

	if err != nil {
		res.Error = err.Error()
	}

	parsePingOutput(res, raw)
	return res, nil
}

func parsePingOutput(res *PingResult, raw string) {
	if strings.TrimSpace(raw) == "" {
		return
	}

	// Packets: "3 packets transmitted, 3 received, 0% packet loss"
	// or macOS: "3 packets transmitted, 3 packets received, 0.0% packet loss"
	pktRe := regexp.MustCompile(`(\d+)\s+packets transmitted,\s+(\d+)\s+(?:packets\s+)?received,\s+([\d\.]+)%\s+packet loss`)
	if m := pktRe.FindStringSubmatch(raw); len(m) >= 4 {
		if sent, err := strconv.Atoi(m[1]); err == nil {
			res.PacketsSent = sent
		}
		if recv, err := strconv.Atoi(m[2]); err == nil {
			res.PacketsRecv = recv
		}
		if loss, err := strconv.ParseFloat(m[3], 64); err == nil {
			res.PacketLoss = loss
		}
	}

	// RTT: "rtt min/avg/max/mdev = 0.028/0.034/0.038/0.004 ms"
	// or macOS: "round-trip min/avg/max/stddev = 0.028/0.034/0.038/0.004 ms"
	rttRe := regexp.MustCompile(`(?:rtt|round-trip)\s+(?:min/avg/max/\w+)\s*=\s*([\d\.]+)/([\d\.]+)/([\d\.]+)`)
	if m := rttRe.FindStringSubmatch(raw); len(m) >= 4 {
		if minVal, err := strconv.ParseFloat(m[1], 64); err == nil {
			res.MinLatency = minVal
		}
		if avgVal, err := strconv.ParseFloat(m[2], 64); err == nil {
			res.AvgLatency = avgVal
		}
		if maxVal, err := strconv.ParseFloat(m[3], 64); err == nil {
			res.MaxLatency = maxVal
		}
	}
}
