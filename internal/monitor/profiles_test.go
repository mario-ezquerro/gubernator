package monitor

import (
	"testing"
)

func TestListProfiles(t *testing.T) {
	profiles := ListProfiles()
	if len(profiles) != 5 {
		t.Fatalf("expected 5 SRE profiles, got %d", len(profiles))
	}

	foundActive := false
	for _, p := range profiles {
		if p.ID == "" || p.Name == "" || p.RecommendedHosts == "" || p.RecommendedContainers == "" || p.RecommendedRAM == "" {
			t.Errorf("profile %s has missing fields: %+v", p.ID, p)
		}
		if p.IsActive {
			foundActive = true
		}
	}

	if !foundActive {
		t.Errorf("expected at least one active profile, none was active")
	}
}

func TestGetProfileByID(t *testing.T) {
	p := GetProfileByID("ultra-light")
	if p == nil {
		t.Fatalf("expected ultra-light profile, got nil")
	}
	if p.Name != "Ultra-Lightweight" {
		t.Errorf("expected name Ultra-Lightweight, got %s", p.Name)
	}

	invalid := GetProfileByID("non-existent")
	if invalid != nil {
		t.Errorf("expected nil for non-existent profile, got %+v", invalid)
	}
}
