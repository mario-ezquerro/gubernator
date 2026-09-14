package timesync

import (
	"context"
	"testing"
	"time"
)

func TestSyncFromClientTimestamp_Bounds(t *testing.T) {
	// Timestamp before 2024 should error
	err := SyncFromClientTimestamp(1600000000)
	if err == nil {
		t.Errorf("expected error for ancient timestamp, got nil")
	}

	// Timestamp after 2038 should error
	err = SyncFromClientTimestamp(2200000000)
	if err == nil {
		t.Errorf("expected error for far-future timestamp, got nil")
	}

	// Current timestamp should succeed (no drift or safely skipped on non-linux)
	now := time.Now().Unix()
	err = SyncFromClientTimestamp(now)
	if err != nil {
		t.Errorf("unexpected error for current timestamp: %v", err)
	}
}

func TestFetchNetworkTime(t *testing.T) {
	// Network test (may be skipped or run if internet reachable)
	netTime, err := FetchNetworkTime()
	if err != nil {
		t.Logf("FetchNetworkTime failed (likely offline/no internet): %v", err)
		return
	}

	if netTime.Year() < 2024 {
		t.Errorf("unexpected network time year: %d", netTime.Year())
	}
}

func TestStartWatchdog_Cancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})

	go func() {
		StartWatchdog(ctx)
		close(done)
	}()

	time.Sleep(50 * time.Millisecond)
	cancel()

	select {
	case <-done:
		// success
	case <-time.After(1 * time.Second):
		t.Errorf("watchdog did not exit on context cancellation")
	}
}
