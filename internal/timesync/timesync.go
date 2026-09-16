package timesync

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os/exec"
	"runtime"
	"sync"
	"time"
)

var (
	syncMu      sync.Mutex
	lastSync    time.Time
	httpTimeout = 3 * time.Second
)

// SyncSystemClock sets the operating system clock to the provided time.
// On Linux systems (where Gubernator runs in VMs/hosts as root), it uses
// `date -u -s @<unix>` and optionally syncs the hardware clock via hwclock.
func SyncSystemClock(targetTime time.Time) error {
	syncMu.Lock()
	defer syncMu.Unlock()

	// Rate limit system clock adjustments to at most once every 3 seconds
	if time.Since(lastSync) < 3*time.Second {
		return nil
	}

	if runtime.GOOS != "linux" {
		slog.Debug("timesync: system clock update skipped (non-linux platform)", "goos", runtime.GOOS)
		lastSync = time.Now()
		return nil
	}

	unixSec := targetTime.Unix()
	cmd := exec.Command("date", "-u", "-s", fmt.Sprintf("@%d", unixSec))
	out, err := cmd.CombinedOutput()
	if err != nil {
		slog.Warn("timesync: failed to set system time", "err", err, "output", string(out))
		return fmt.Errorf("set system time: %w (output: %s)", err, string(out))
	}

	// Sync hwclock if available to persist across hypervisor sleep / RTC
	_ = exec.Command("hwclock", "-w").Run()

	lastSync = time.Now()
	slog.Info("timesync: system clock synchronized successfully", "target_time", targetTime.UTC(), "unix", unixSec)
	return nil
}

// SyncFromClientTimestamp validates and applies a timestamp received from a trusted client/browser.
func SyncFromClientTimestamp(clientTimestamp int64) error {
	// Sanity bounds: between 2024-01-01 (1704067200) and 2038-01-01 (2145916800)
	if clientTimestamp < 1704067200 || clientTimestamp > 2145916800 {
		return fmt.Errorf("timestamp %d is outside sane bounds", clientTimestamp)
	}

	clientTime := time.Unix(clientTimestamp, 0)
	drift := clientTimestamp - time.Now().Unix()

	// Adjust if clock skew is 2 seconds or more
	if drift >= 2 || drift <= -2 {
		slog.Info("timesync: adjusting host system clock from client beacon", "drift_seconds", drift, "client_time", clientTime.UTC())
		return SyncSystemClock(clientTime)
	}
	return nil
}

// FetchNetworkTime queries HTTP Date headers from fast, reliable public endpoints.
func FetchNetworkTime() (time.Time, error) {
	endpoints := []string{
		"https://www.google.com",
		"https://cloudflare.com",
		"https://1.1.1.1",
	}

	client := &http.Client{
		Timeout: httpTimeout,
		Transport: &http.Transport{
			DisableKeepAlives: true,
		},
	}

	for _, url := range endpoints {
		req, err := http.NewRequest("HEAD", url, nil)
		if err != nil {
			continue
		}
		req.Header.Set("User-Agent", "Gubernator-TimeSync/2.0")

		resp, err := client.Do(req)
		if err != nil {
			continue
		}
		_ = resp.Body.Close()

		dateHeader := resp.Header.Get("Date")
		if dateHeader == "" {
			continue
		}

		parsed, err := http.ParseTime(dateHeader)
		if err == nil && !parsed.IsZero() {
			return parsed, nil
		}
	}

	return time.Time{}, fmt.Errorf("no network time endpoints reachable")
}

// TriggerNetworkSync attempts to fetch network time and update the system clock if drifted.
func TriggerNetworkSync() {
	go func() {
		netTime, err := FetchNetworkTime()
		if err != nil {
			slog.Debug("timesync: network time sync unavailable", "err", err)
			return
		}

		drift := netTime.Unix() - time.Now().Unix()
		if drift >= 2 || drift <= -2 {
			slog.Info("timesync: network time drift detected", "drift_seconds", drift, "net_time", netTime.UTC())
			_ = SyncSystemClock(netTime)
		}
	}()
}

// StartWatchdog starts a background monitor that:
// 1. Detects host sleep / VM suspend wakeup (when elapsed time between 1s ticks > 4s).
// 2. Periodically checks and syncs network time.
func StartWatchdog(ctx context.Context) {
	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()

	// Initial network sync on startup
	TriggerNetworkSync()

	lastTick := time.Now()
	periodicCounter := 0

	for {
		select {
		case <-ctx.Done():
			return
		case now := <-ticker.C:
			elapsed := now.Sub(lastTick)
			// If more than 4 seconds elapsed between 1-second ticks,
			// the VM was suspended/frozen (e.g., laptop lid closed)!
			if elapsed > 4*time.Second {
				slog.Warn("timesync: system wakeup from sleep/standby detected!", "elapsed_gap", elapsed)
				TriggerNetworkSync()
			}

			periodicCounter++
			// Every 30 seconds, perform a routine network sync check
			if periodicCounter >= 30 {
				periodicCounter = 0
				TriggerNetworkSync()
			}

			lastTick = now
		}
	}
}
