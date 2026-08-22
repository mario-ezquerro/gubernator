package telemetry

import (
	"testing"
)

func TestAdoptionStatsDefaults(t *testing.T) {
	stats := GetAdoptionStats(false)
	if stats == nil {
		t.Fatal("expected non-nil adoption stats")
	}

	if stats.DataSource == "" {
		t.Error("expected non-empty data source description")
	}

	if stats.PrivacyPolicy == "" {
		t.Error("expected non-empty privacy policy description")
	}

	if stats.DownloadsByOS == nil {
		t.Error("expected initialized DownloadsByOS map")
	}
}

func TestTelemetryOptOut(t *testing.T) {
	t.Setenv("DO_NOT_TRACK", "1")
	if IsTelemetryEnabled() {
		t.Error("expected telemetry to be disabled when DO_NOT_TRACK=1")
	}

	stats := GetAdoptionStats(true)
	if stats.TelemetryEnabled {
		t.Error("expected stats.TelemetryEnabled to be false")
	}
}
