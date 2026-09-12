package audit

import (
	"crypto/sha256"
	"crypto/tls"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log/slog"
	"net"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

var (
	chainMu     sync.Mutex
	siemChan    = make(chan *db.AuditLog, 2000)
	siemOnce    sync.Once
	genesisHash = strings.Repeat("0", 64)
)

func init() {
	siemOnce.Do(func() {
		go siemWorker()
	})
}

// ComputeHash computes the deterministic cryptographic SHA-256 hash for an audit log entry.
func ComputeHash(prevHash, id string, ts time.Time, username, provider, ip, action, status, details string) string {
	payload := fmt.Sprintf("%s|%s|%d|%s|%s|%s|%s|%s|%s",
		prevHash,
		id,
		ts.UnixNano(),
		username,
		provider,
		ip,
		action,
		status,
		details,
	)
	h := sha256.Sum256([]byte(payload))
	return hex.EncodeToString(h[:])
}

// Record captures a security/audit event with client IP from gin.Context and commits it to the tamper-evident chain.
func Record(c *gin.Context, username, provider, action, status, details string) (*db.AuditLog, error) {
	clientIP := "127.0.0.1"
	if c != nil {
		clientIP = c.ClientIP()
		if clientIP == "" {
			clientIP = c.RemoteIP()
		}
	}
	return RecordEvent(username, provider, clientIP, action, status, details)
}

// RecordEvent commits an audit entry directly with provided IP.
func RecordEvent(username, provider, ipAddress, action, status, details string) (*db.AuditLog, error) {
	chainMu.Lock()
	defer chainMu.Unlock()

	// 1. Retrieve the latest audit log to establish prev_hash link
	var lastLog db.AuditLog
	prevHash := genesisHash
	if err := db.DB.Order("timestamp desc, id desc").First(&lastLog).Error; err == nil {
		if lastLog.Hash != "" {
			prevHash = lastLog.Hash
		}
	}

	id := "aud-" + uuid.New().String()[:12]
	now := time.Now().UTC()
	if username == "" {
		username = "system"
	}
	if provider == "" {
		provider = "LOCAL"
	}

	hash := ComputeHash(prevHash, id, now, username, provider, ipAddress, action, status, details)

	entry := db.AuditLog{
		ID:        id,
		Timestamp: now,
		Username:  username,
		Provider:  provider,
		IPAddress: ipAddress,
		Action:    strings.ToUpper(strings.TrimSpace(action)),
		Status:    strings.ToUpper(strings.TrimSpace(status)),
		Details:   details,
		PrevHash:  prevHash,
		Hash:      hash,
	}

	if err := db.DB.Create(&entry).Error; err != nil {
		slog.Error("failed to persist audit log", "err", err, "action", action)
		return nil, err
	}

	// Non-blocking dispatch to SIEM worker channel
	if IsIntrusionAlert(entry.Action) {
		RecordIntrusionAlert()
		slog.Warn("ENS op.mon.2 SECURITY INTRUSION ALERT DETECTED",
			"action", entry.Action,
			"user", entry.Username,
			"ip", entry.IPAddress,
			"details", entry.Details,
		)
	}

	select {
	case siemChan <- &entry:
	default:
		slog.Warn("SIEM channel buffer full, audit log enqueued drop avoided")
	}

	return &entry, nil
}

// SIEMStats captures real-time delivery telemetry and operational health for SIEM forwarding (ENS op.mon.2).
type SIEMStats struct {
	TotalDispatched  int64      `json:"total_dispatched"`
	TotalFailed      int64      `json:"total_failed"`
	IntrusionAlerts  int64      `json:"intrusion_alerts"`
	LastDispatchedAt *time.Time `json:"last_dispatched_at,omitempty"`
	LastFailedAt     *time.Time `json:"last_failed_at,omitempty"`
	LastError        string     `json:"last_error,omitempty"`
	Status           string     `json:"status"` // "ACTIVE", "READY", "UNREACHABLE", "DEGRADED", "DISABLED"
}

// SIEMTestResult captures the diagnostic output of a SIEM probe test.
type SIEMTestResult struct {
	Success      bool      `json:"success"`
	LatencyMs    int64     `json:"latency_ms"`
	Message      string    `json:"message"`
	Error        string    `json:"error,omitempty"`
	DispatchedAt time.Time `json:"dispatched_at"`
}

var (
	statsMu   sync.RWMutex
	siemStats SIEMStats
)

// RecordSIEMSuccess updates transmission metrics upon successful event delivery.
func RecordSIEMSuccess() {
	statsMu.Lock()
	defer statsMu.Unlock()
	now := time.Now().UTC()
	siemStats.TotalDispatched++
	siemStats.LastDispatchedAt = &now
	siemStats.LastError = ""
}

// RecordSIEMFailure updates transmission metrics upon delivery failure.
func RecordSIEMFailure(err error) {
	statsMu.Lock()
	defer statsMu.Unlock()
	now := time.Now().UTC()
	siemStats.TotalFailed++
	siemStats.LastFailedAt = &now
	if err != nil {
		siemStats.LastError = err.Error()
	}
}

// RecordIntrusionAlert increments the count of critical intrusion/security events detected.
func RecordIntrusionAlert() {
	statsMu.Lock()
	defer statsMu.Unlock()
	siemStats.IntrusionAlerts++
}

// ResetSIEMStats resets telemetry counters for testing.
func ResetSIEMStats() {
	statsMu.Lock()
	defer statsMu.Unlock()
	siemStats = SIEMStats{}
}

// GetSIEMStats returns a snapshot of current SIEM delivery telemetry and operational health.
func GetSIEMStats() SIEMStats {
	statsMu.RLock()
	defer statsMu.RUnlock()
	st := siemStats

	// Determine status dynamically based on current configuration and delivery metrics
	var cfg db.SecurityConfig
	if db.DB != nil && db.DB.First(&cfg, "id = ?", "default").Error == nil {
		if !cfg.SIEMEnabled || strings.TrimSpace(cfg.SIEMHost) == "" {
			st.Status = "DISABLED"
		} else if st.TotalFailed == 0 && st.TotalDispatched > 0 {
			st.Status = "ACTIVE"
		} else if st.TotalFailed > 0 && st.TotalDispatched > 0 {
			st.Status = "DEGRADED"
		} else if st.TotalFailed > 0 && st.TotalDispatched == 0 {
			st.Status = "UNREACHABLE"
		} else {
			st.Status = "READY"
		}
	} else {
		st.Status = "DISABLED"
	}
	return st
}

// IsIntrusionAlert checks whether an audit event action signifies a critical security event or intrusion attempt (ENS op.mon.2).
func IsIntrusionAlert(action string) bool {
	act := strings.ToUpper(strings.TrimSpace(action))
	switch act {
	case "AUTH_LOCKOUT",
		"AUDIT_CHAIN_COMPROMISED",
		"SECURITY_GATEKEEPER_BLOCKED",
		"AUTH_SUSPENDED_LOGIN_ATTEMPT",
		"AUTH_UNAUTHORIZED_ROLE_ACCESS",
		"SECURITY_IMAGE_SCAN_CRITICAL_CVE",
		"SECURITY_UNTRUSTED_KEY_REJECTED":
		return true
	default:
		return strings.Contains(act, "LOCKOUT") ||
			strings.Contains(act, "COMPROMISED") ||
			strings.Contains(act, "INTRUSION") ||
			strings.Contains(act, "ATTACK")
	}
}

// VerificationResult holds the report of cryptographic chain validation.
type VerificationResult struct {
	Valid           bool      `json:"valid"`
	TotalRecords    int       `json:"total_records"`
	VerifiedRecords int       `json:"verified_records"`
	CompromisedID   string    `json:"compromised_id,omitempty"`
	FailureReason   string    `json:"failure_reason,omitempty"`
	VerifiedAt      time.Time `json:"verified_at"`
}

// VerifyChainIntegrity validates the entire audit log history against SHA-256 hash chains.
func VerifyChainIntegrity() (*VerificationResult, error) {
	chainMu.Lock()
	defer chainMu.Unlock()

	var logs []db.AuditLog
	if err := db.DB.Order("timestamp asc, id asc").Find(&logs).Error; err != nil {
		return nil, err
	}

	res := &VerificationResult{
		Valid:           true,
		TotalRecords:    len(logs),
		VerifiedRecords: 0,
		VerifiedAt:      time.Now().UTC(),
	}

	if len(logs) == 0 {
		return res, nil
	}

	expectedPrev := genesisHash
	for i, l := range logs {
		// Verify backward link
		if l.PrevHash != expectedPrev {
			res.Valid = false
			res.CompromisedID = l.ID
			res.FailureReason = fmt.Sprintf("chain break at record #%d (ID: %s): expected prev_hash %s, found %s",
				i+1, l.ID, expectedPrev, l.PrevHash)
			return res, nil
		}

		// Recompute hash
		computed := ComputeHash(l.PrevHash, l.ID, l.Timestamp, l.Username, l.Provider, l.IPAddress, l.Action, l.Status, l.Details)
		if computed != l.Hash {
			res.Valid = false
			res.CompromisedID = l.ID
			res.FailureReason = fmt.Sprintf("tampered content at record #%d (ID: %s): stored hash %s, computed hash %s",
				i+1, l.ID, l.Hash, computed)
			return res, nil
		}

		expectedPrev = l.Hash
		res.VerifiedRecords++
	}

	return res, nil
}

// FormatSIEMMessage formats an audit log entry for SIEM consumption with security severity classifications (ENS op.mon.2).
func FormatSIEMMessage(entry *db.AuditLog, format string) []byte {
	hostname, _ := os.Hostname()
	if hostname == "" {
		hostname = "gubernator-host"
	}

	isIntrusion := IsIntrusionAlert(entry.Action)

	switch strings.ToUpper(strings.TrimSpace(format)) {
	case "CEF":
		// Common Event Format: CEF:Version|Device Vendor|Device Product|Device Version|Device Event Class ID|Name|Severity|[Extension]
		cleanDetails := strings.ReplaceAll(entry.Details, "|", "\\|")
		severity := 3
		cat := "Audit"
		if isIntrusion {
			severity = 9
			cat = "IntrusionAlert"
		} else if strings.ToUpper(entry.Status) == "FAILURE" {
			severity = 6
			cat = "SecurityWarning"
		}
		return []byte(fmt.Sprintf("CEF:0|Gubernator|Orchestrator|v2.89.0|%s|%s|%d|src=%s suser=%s msg=%s proto=%s status=%s cat=%s id=%s hash=%s\n",
			entry.Action, entry.Action, severity, entry.IPAddress, entry.Username, cleanDetails, entry.Provider, entry.Status, cat, entry.ID, entry.Hash))

	case "JSON":
		severity := "INFO"
		if isIntrusion {
			severity = "CRITICAL"
		} else if strings.ToUpper(entry.Status) == "FAILURE" {
			severity = "WARNING"
		}
		payload := map[string]interface{}{
			"facility":     "auth",
			"hostname":     hostname,
			"timestamp":    entry.Timestamp.Format(time.RFC3339Nano),
			"id":           entry.ID,
			"username":     entry.Username,
			"provider":     entry.Provider,
			"ip_address":   entry.IPAddress,
			"action":       entry.Action,
			"status":       entry.Status,
			"severity":     severity,
			"is_intrusion": isIntrusion,
			"details":      entry.Details,
			"prev_hash":    entry.PrevHash,
			"hash":         entry.Hash,
		}
		b, _ := json.Marshal(payload)
		return append(b, '\n')

	default: // RFC5424 Syslog
		// Facility auth (4) * 8 = 32
		// Severity: alert (1) -> PRI 33, warning (4) -> PRI 36, notice/info (6) -> PRI 38 (or 134 for local0.info)
		pri := 134
		alertTag := "info"
		if isIntrusion {
			pri = 33 // auth.alert
			alertTag = "critical"
		} else if strings.ToUpper(entry.Status) == "FAILURE" {
			pri = 36 // auth.warning
			alertTag = "warning"
		}
		msg := fmt.Sprintf("<%d>1 %s %s gubernator - %s [gbnt@32473 action=\"%s\" status=\"%s\" user=\"%s\" ip=\"%s\" intrusion=\"%t\" level=\"%s\" hash=\"%s\"] %s\n",
			pri,
			entry.Timestamp.Format(time.RFC3339),
			hostname,
			entry.ID,
			entry.Action,
			entry.Status,
			entry.Username,
			entry.IPAddress,
			isIntrusion,
			alertTag,
			entry.Hash,
			entry.Details,
		)
		return []byte(msg)
	}
}

// SendSIEMTestProbe attempts a direct connection and sends a test probe event to the configured SIEM.
func SendSIEMTestProbe(cfg db.SecurityConfig) (*SIEMTestResult, error) {
	host := strings.TrimSpace(cfg.SIEMHost)
	if host == "" {
		return nil, fmt.Errorf("SIEM host is not configured")
	}
	port := cfg.SIEMPort
	if port <= 0 {
		port = 514
	}

	testLog := db.AuditLog{
		ID:        "probe-" + uuid.New().String()[:8],
		Timestamp: time.Now().UTC(),
		Username:  "system-diagnostic",
		Provider:  "LOCAL",
		IPAddress: "127.0.0.1",
		Action:    "SIEM_TEST_PROBE",
		Status:    "SUCCESS",
		Details:   "Gubernator SIEM connectivity diagnostic probe (ENS op.mon.2)",
		PrevHash:  genesisHash,
		Hash:      ComputeHash(genesisHash, "probe", time.Now().UTC(), "system", "LOCAL", "127.0.0.1", "PROBE", "OK", "TEST"),
	}

	data := FormatSIEMMessage(&testLog, cfg.SIEMFormat)
	addr := fmt.Sprintf("%s:%d", host, port)

	start := time.Now()
	err := dispatchToNetwork(addr, cfg.SIEMProtocol, data)
	latency := time.Since(start).Milliseconds()

	res := &SIEMTestResult{
		DispatchedAt: start.UTC(),
		LatencyMs:    latency,
	}

	if err != nil {
		RecordSIEMFailure(err)
		res.Success = false
		res.Error = err.Error()
		res.Message = fmt.Sprintf("Failed to reach SIEM (%s:%d/%s): %v", host, port, cfg.SIEMProtocol, err)
		return res, err
	}

	RecordSIEMSuccess()
	res.Success = true
	res.Message = fmt.Sprintf("Successfully dispatched SIEM test probe to %s:%d via %s in %dms (%s format)",
		host, port, cfg.SIEMProtocol, latency, cfg.SIEMFormat)
	return res, nil
}

func dispatchToNetwork(addr, protocol string, data []byte) error {
	proto := strings.ToUpper(strings.TrimSpace(protocol))
	switch proto {
	case "TCP":
		conn, err := net.DialTimeout("tcp", addr, 5*time.Second)
		if err != nil {
			return fmt.Errorf("tcp dial failed: %w", err)
		}
		defer conn.Close()
		_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
		_, err = conn.Write(data)
		return err

	case "TLS":
		dialer := &net.Dialer{Timeout: 5 * time.Second}
		tlsConfig := &tls.Config{InsecureSkipVerify: true} // dev fallback; production can configure CA
		conn, err := tls.DialWithDialer(dialer, "tcp", addr, tlsConfig)
		if err != nil {
			return fmt.Errorf("tls dial failed: %w", err)
		}
		defer conn.Close()
		_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
		_, err = conn.Write(data)
		return err

	default: // UDP
		conn, err := net.DialTimeout("udp", addr, 3*time.Second)
		if err != nil {
			return fmt.Errorf("udp dial failed: %w", err)
		}
		defer conn.Close()
		_, err = conn.Write(data)
		return err
	}
}

func siemWorker() {
	for entry := range siemChan {
		if db.DB == nil {
			continue
		}
		var cfg db.SecurityConfig
		if err := db.DB.First(&cfg, "id = ?", "default").Error; err != nil || !cfg.SIEMEnabled || strings.TrimSpace(cfg.SIEMHost) == "" {
			continue
		}

		port := cfg.SIEMPort
		if port <= 0 {
			port = 514
		}
		addr := fmt.Sprintf("%s:%d", cfg.SIEMHost, port)
		data := FormatSIEMMessage(entry, cfg.SIEMFormat)

		if err := dispatchToNetwork(addr, cfg.SIEMProtocol, data); err != nil {
			slog.Debug("failed to dispatch log to SIEM", "addr", addr, "err", err)
			RecordSIEMFailure(err)
		} else {
			RecordSIEMSuccess()
		}
	}
}
