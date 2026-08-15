package nodemanager

import (
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"sync"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/db"
)

// AuthMismatch tracks unauthorized requests from cluster nodes with stale/invalid tokens.
type AuthMismatch struct {
	IP          string    `json:"ip"`
	NodeID      string    `json:"node_id"`
	LastAttempt time.Time `json:"last_attempt"`
	FailedCount int       `json:"failed_count"`
}

var (
	mismatchesLock sync.RWMutex
	mismatches     = make(map[string]*AuthMismatch) // keyed by IP
)

// RecordAuthMismatch registers an unauthorized request from a given client IP/NodeID.
func RecordAuthMismatch(ip string, nodeID string) {
	if ip == "" || ip == "127.0.0.1" || ip == "::1" {
		return
	}
	mismatchesLock.Lock()
	defer mismatchesLock.Unlock()

	entry, exists := mismatches[ip]
	if !exists {
		entry = &AuthMismatch{
			IP:     ip,
			NodeID: nodeID,
		}
		mismatches[ip] = entry
	}
	if nodeID != "" {
		entry.NodeID = nodeID
	}
	entry.LastAttempt = time.Now()
	entry.FailedCount++
	slog.Warn("detected stale authentication token from node", "ip", ip, "node_id", nodeID, "fails", entry.FailedCount)
}

// ClearAuthMismatch clears the auth mismatch record for a given IP.
func ClearAuthMismatch(ip string) {
	mismatchesLock.Lock()
	defer mismatchesLock.Unlock()
	delete(mismatches, ip)
}

// HasAuthMismatch returns true if the specified IP or NodeID has a recent auth failure (within 10m).
func HasAuthMismatch(ip string, nodeID string) bool {
	mismatchesLock.RLock()
	defer mismatchesLock.RUnlock()

	if entry, exists := mismatches[ip]; exists {
		if time.Since(entry.LastAttempt) < 10*time.Minute {
			return true
		}
	}

	if nodeID != "" {
		for _, entry := range mismatches {
			if entry.NodeID == nodeID && time.Since(entry.LastAttempt) < 10*time.Minute {
				return true
			}
		}
	}
	return false
}

// SyncWorkerToken connects via SSH to the worker host and restarts gbnt-worker with the active tokens.
func SyncWorkerToken(nodeID string) error {
	var node db.Node
	if err := db.DB.First(&node, "id = ?", nodeID).Error; err != nil {
		return fmt.Errorf("node %s not found: %w", nodeID, err)
	}

	if node.Role == "manager" {
		return fmt.Errorf("node %s is a manager; token sync is for worker nodes", nodeID)
	}

	targetIP := node.IP
	if targetIP == "" || targetIP == "127.0.0.1" {
		return fmt.Errorf("invalid IP address for worker node %s", nodeID)
	}

	apiToken := os.Getenv("GBNT_API_TOKEN")
	if apiToken == "" {
		apiToken = db.GetAPIToken()
	}
	joinToken := db.GetJoinToken()
	managerIP := db.GetManagerIP()
	if managerIP == "" {
		managerIP = "192.168.252.27"
	}
	managerAddr := fmt.Sprintf("%s:4000", managerIP)

	slog.Info("syncing authentication token to worker via SSH", "node_id", nodeID, "ip", targetIP)

	sshArgs := []string{"-o", "UserKnownHostsFile=/dev/null", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=5"}
	keyCandidates := []string{
		"/root/.ssh/id_ed25519",
		"/root/.ssh/id_rsa",
		"/data/id_ed25519",
		"/data/id_rsa",
		"/data/ssh/id_ed25519",
		"/data/ssh/id_rsa",
	}
	for _, k := range keyCandidates {
		if _, err := os.Stat(k); err == nil {
			sshArgs = append(sshArgs, "-i", k)
			break
		}
	}

	// Remote command to update worker daemon
	remoteCmd := fmt.Sprintf(`sudo docker rm -f gbnt-worker 2>/dev/null; sudo docker run -d --name gbnt-worker --restart unless-stopped --net host -v /var/run/docker.sock:/var/run/docker.sock -v /data:/data marioezquerro/gubernator:latest legion join --token %s --api-token %s --manager %s`,
		joinToken, apiToken, managerAddr)

	sshArgs = append(sshArgs, fmt.Sprintf("ubuntu@%s", targetIP), "sh", "-c", remoteCmd)

	cmd := exec.Command("ssh", sshArgs...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("failed to sync token to %s via SSH: %w (output: %s)", targetIP, err, string(out))
	}

	ClearAuthMismatch(targetIP)
	ClearAuthMismatch(node.IP)
	slog.Info("successfully synced authentication token to worker", "node_id", nodeID, "ip", targetIP)
	return nil
}
