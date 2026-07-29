package updater

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/db"
)

// UpdateInfo holds version comparison details and release notes.
type UpdateInfo struct {
	CurrentVersion  string `json:"current_version"`
	LatestVersion   string `json:"latest_version"`
	UpdateAvailable bool   `json:"update_available"`
	ReleaseNotes    string `json:"release_notes"`
	ReleaseURL      string `json:"release_url"`
	CheckedAt       string `json:"checked_at"`
}

type githubRelease struct {
	TagName     string `json:"tag_name"`
	HTMLURL     string `json:"html_url"`
	Body        string `json:"body"`
	PublishedAt string `json:"published_at"`
}

var (
	cachedInfo *UpdateInfo
	cacheMutex sync.Mutex
	cacheTTL   = 15 * time.Minute
)

// CheckLatestRelease queries GitHub Releases API for the latest Gubernator tag.
func CheckLatestRelease(currentVersion string, forceRefresh bool) (*UpdateInfo, error) {
	cacheMutex.Lock()
	if !forceRefresh && cachedInfo != nil && time.Since(parseTime(cachedInfo.CheckedAt)) < cacheTTL {
		info := *cachedInfo
		info.CurrentVersion = currentVersion
		cacheMutex.Unlock()
		return &info, nil
	}
	cacheMutex.Unlock()

	req, err := http.NewRequest("GET", "https://api.github.com/repos/mario-ezquerro/gubernator/releases/latest", nil)
	if err != nil {
		return fallbackInfo(currentVersion), nil
	}
	req.Header.Set("User-Agent", "Gubernator-AutoUpdater")
	req.Header.Set("Accept", "application/vnd.github.v3+json")

	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Do(req)
	if err != nil || resp.StatusCode != http.StatusOK {
		return fallbackInfo(currentVersion), nil
	}
	defer resp.Body.Close()

	var rel githubRelease
	if err := json.NewDecoder(resp.Body).Decode(&rel); err != nil {
		return fallbackInfo(currentVersion), nil
	}

	latest := strings.TrimSpace(rel.TagName)
	if latest == "" {
		return fallbackInfo(currentVersion), nil
	}

	updateAvailable := isNewerVersion(currentVersion, latest)

	info := &UpdateInfo{
		CurrentVersion:  currentVersion,
		LatestVersion:   latest,
		UpdateAvailable: updateAvailable,
		ReleaseNotes:    rel.Body,
		ReleaseURL:      rel.HTMLURL,
		CheckedAt:       time.Now().Format(time.RFC3339),
	}

	cacheMutex.Lock()
	cachedInfo = info
	cacheMutex.Unlock()

	return info, nil
}

func fallbackInfo(current string) *UpdateInfo {
	return &UpdateInfo{
		CurrentVersion:  current,
		LatestVersion:   current,
		UpdateAvailable: false,
		ReleaseNotes:    "",
		ReleaseURL:      "",
		CheckedAt:       time.Now().Format(time.RFC3339),
	}
}

func isNewerVersion(current, latest string) bool {
	c := strings.TrimPrefix(current, "v")
	l := strings.TrimPrefix(latest, "v")
	if c == "dev" || c == "" {
		return false
	}
	return l != c && l > c
}

func parseTime(tStr string) time.Time {
	t, _ := time.Parse(time.RFC3339, tStr)
	return t
}

// ApplyClusterUpdate triggers image pulling, version updating, cache invalidation and node updates across the cluster.
func ApplyClusterUpdate(targetVersion string) error {
	slog.Info("🚀 Initiating cluster-wide update", "target_version", targetVersion)

	cacheMutex.Lock()
	cachedInfo = nil
	cacheMutex.Unlock()

	if targetVersion != "" {
		for _, path := range []string{"VERSION", "/app/VERSION", "../VERSION"} {
			if _, err := os.Stat(path); err == nil {
				os.WriteFile(path, []byte(targetVersion), 0644)
			}
		}
	}

	if db.DB != nil {
		var config db.ClusterConfig
		if err := db.DB.First(&config, "id = ?", "global").Error; err == nil {
			config.TargetVersion = targetVersion
			db.DB.Save(&config)
		}
	}

	img := fmt.Sprintf("marioezquerro/gubernator:%s", targetVersion)
	if targetVersion == "" || targetVersion == "latest" {
		img = "marioezquerro/gubernator:latest"
	}

	slog.Info("pulling Docker image for update", "image", img)
	exec.Command("docker", "pull", img).Run()

	// Trigger asynchronous container restart so HTTP response completes cleanly before restart
	go func() {
		time.Sleep(1500 * time.Millisecond)
		slog.Info("restarting gbnt-manager container to complete auto-update...")
		exec.Command("docker", "restart", "gbnt-manager").Run()
	}()

	return nil
}
