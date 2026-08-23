package storage

import (
	"bufio"
	"fmt"
	"strings"
	"time"
)

// GlusterRebalanceStatus represents the volume rebalance status.
type GlusterRebalanceStatus struct {
	VolumeName     string    `json:"volume_name"`
	TaskID         string    `json:"task_id"`
	Status         string    `json:"status"` // in progress, completed, not started, failed
	FilesProcessed uint64    `json:"files_processed"`
	SizeProcessedMB float64  `json:"size_processed_mb"`
	LookupsFailed  uint64    `json:"lookups_failed"`
	Skipped        uint64    `json:"skipped"`
	TimeElapsedSec uint64    `json:"time_elapsed_sec"`
	Timestamp      time.Time `json:"timestamp"`
}

// StartGlusterVolumeRebalance starts data migration across reconfigured bricks.
func StartGlusterVolumeRebalance(volumeName string, fixLayoutOnly ...bool) (*GlusterRebalanceStatus, error) {
	args := []string{"--mode=script", "volume", "rebalance", volumeName}
	if len(fixLayoutOnly) > 0 && fixLayoutOnly[0] {
		args = append(args, "fix-layout", "start")
	} else {
		args = append(args, "start")
	}

	cmd := ExecGlusterCmd(args...)
	out, err := cmd.CombinedOutput()
	if err != nil && !strings.Contains(string(out), "started") {
		return nil, fmt.Errorf("failed to start rebalance on %s: %w (%s)", volumeName, err, strings.TrimSpace(string(out)))
	}

	return GetGlusterVolumeRebalanceStatus(volumeName)
}

// StopGlusterVolumeRebalance stops an ongoing rebalance task.
func StopGlusterVolumeRebalance(volumeName string) error {
	cmd := ExecGlusterCmd("--mode=script", "volume", "rebalance", volumeName, "stop")
	_, _ = cmd.CombinedOutput()
	return nil
}

// GetGlusterVolumeRebalanceStatus queries current rebalance progress.
func GetGlusterVolumeRebalanceStatus(volumeName string) (*GlusterRebalanceStatus, error) {
	cmd := ExecGlusterCmd("--mode=script", "volume", "rebalance", volumeName, "status")
	out, err := cmd.CombinedOutput()
	raw := string(out)

	res := &GlusterRebalanceStatus{
		VolumeName: volumeName,
		Status:     "not started",
		Timestamp:  time.Now().UTC(),
	}

	if err != nil || strings.Contains(raw, "not started") {
		return res, nil
	}

	scanner := bufio.NewScanner(strings.NewReader(raw))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if strings.Contains(line, "in progress") {
			res.Status = "in progress"
		} else if strings.Contains(line, "completed") {
			res.Status = "completed"
		} else if strings.Contains(line, "failed") {
			res.Status = "failed"
		}

		if strings.HasPrefix(line, "Node") || strings.HasPrefix(line, "--") || strings.HasPrefix(line, "volume rebalance") {
			continue
		}

		fields := strings.Fields(line)
		if len(fields) >= 7 {
			res.FilesProcessed++
		}
	}

	return res, nil
}
