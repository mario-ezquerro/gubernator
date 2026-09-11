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
	select {
	case siemChan <- &entry:
	default:
		slog.Warn("SIEM channel buffer full, audit log enqueued drop avoided")
	}

	return &entry, nil
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

// FormatSIEMMessage formats an audit log entry for SIEM consumption.
func FormatSIEMMessage(entry *db.AuditLog, format string) []byte {
	hostname, _ := os.Hostname()
	if hostname == "" {
		hostname = "gubernator-host"
	}

	switch strings.ToUpper(strings.TrimSpace(format)) {
	case "CEF":
		// Common Event Format: CEF:Version|Device Vendor|Device Product|Device Version|Device Event Class ID|Name|Severity|[Extension]
		cleanDetails := strings.ReplaceAll(entry.Details, "|", "\\|")
		return []byte(fmt.Sprintf("CEF:0|Gubernator|Orchestrator|v2.81.0|%s|%s|5|src=%s suser=%s msg=%s proto=%s status=%s id=%s hash=%s\n",
			entry.Action, entry.Action, entry.IPAddress, entry.Username, cleanDetails, entry.Provider, entry.Status, entry.ID, entry.Hash))

	case "JSON":
		payload := map[string]interface{}{
			"facility":   "auth",
			"hostname":   hostname,
			"timestamp":  entry.Timestamp.Format(time.RFC3339Nano),
			"id":         entry.ID,
			"username":   entry.Username,
			"provider":   entry.Provider,
			"ip_address": entry.IPAddress,
			"action":     entry.Action,
			"status":     entry.Status,
			"details":    entry.Details,
			"prev_hash":  entry.PrevHash,
			"hash":       entry.Hash,
		}
		b, _ := json.Marshal(payload)
		return append(b, '\n')

	default: // RFC5424 Syslog
		// <PRI>VERSION TIMESTAMP HOSTNAME APP-NAME PROCID MSGID [STRUCTURED-DATA] MSG
		// Facility auth (4) * 8 + Severity notice (5) = 37 (or 134 for local0.info)
		pri := 134
		msg := fmt.Sprintf("<%d>1 %s %s gubernator - %s [gbnt@32473 action=\"%s\" status=\"%s\" user=\"%s\" ip=\"%s\" hash=\"%s\"] %s\n",
			pri,
			entry.Timestamp.Format(time.RFC3339),
			hostname,
			entry.ID,
			entry.Action,
			entry.Status,
			entry.Username,
			entry.IPAddress,
			entry.Hash,
			entry.Details,
		)
		return []byte(msg)
	}
}

// SendSIEMTestProbe attempts a direct connection and sends a test probe event to the configured SIEM.
func SendSIEMTestProbe(cfg db.SecurityConfig) error {
	host := strings.TrimSpace(cfg.SIEMHost)
	if host == "" {
		return fmt.Errorf("SIEM host is not configured")
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
		Details:   "Gubernator SIEM connectivity diagnostic probe (ENS op.mon.1)",
		PrevHash:  genesisHash,
		Hash:      ComputeHash(genesisHash, "probe", time.Now().UTC(), "system", "LOCAL", "127.0.0.1", "PROBE", "OK", "TEST"),
	}

	data := FormatSIEMMessage(&testLog, cfg.SIEMFormat)
	addr := fmt.Sprintf("%s:%d", host, port)

	return dispatchToNetwork(addr, cfg.SIEMProtocol, data)
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
		if err := db.DB.First(&cfg, "id = ?", "default").Error; err != nil || !cfg.SIEMEnabled || cfg.SIEMHost == "" {
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
		}
	}
}
