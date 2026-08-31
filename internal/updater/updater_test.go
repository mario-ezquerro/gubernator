package updater

import (
	"testing"
)

func TestIsNewerVersion(t *testing.T) {
	tests := []struct {
		current  string
		latest   string
		expected bool
	}{
		{"v2.57.2", "v2.58.0", true},
		{"v2.57.2", "v2.57.3", true},
		{"v2.57.2", "v3.0.0", true},
		{"v2.58.0", "v2.58.0", false},
		{"v2.58.0", "v2.57.2", false},
		{"2.57.2", "2.58.0", true},
		{"v2.58.0", "v2.58.0-rc1", false},
		{"dev", "v2.58.0", false},
		{"", "v2.58.0", false},
	}

	for _, tc := range tests {
		got := isNewerVersion(tc.current, tc.latest)
		if got != tc.expected {
			t.Errorf("isNewerVersion(%q, %q) = %v; want %v", tc.current, tc.latest, got, tc.expected)
		}
	}
}

func TestCheckLatestRelease_LiveOrFallback(t *testing.T) {
	info, err := CheckLatestRelease("v2.57.2", true)
	if err != nil {
		t.Fatalf("CheckLatestRelease returned unexpected error: %v", err)
	}

	if info == nil {
		t.Fatalf("CheckLatestRelease returned nil info")
	}

	t.Logf("Detected latest version: %s (Update available: %v)", info.LatestVersion, info.UpdateAvailable)

	if info.LatestVersion == "" {
		t.Errorf("LatestVersion should not be empty")
	}

	// Given current is v2.57.2 and GitHub has v2.58.0, update_available should be true
	if info.LatestVersion == "v2.58.0" && !info.UpdateAvailable {
		t.Errorf("Expected UpdateAvailable to be true for current v2.57.2 vs latest v2.58.0")
	}
}
