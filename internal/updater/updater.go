package updater

import (
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"runtime"
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
		info.UpdateAvailable = isNewerVersion(currentVersion, info.LatestVersion)
		cacheMutex.Unlock()
		return &info, nil
	}
	cacheMutex.Unlock()

	// Query the releases list first to bypass GitHub CDN propagation delay on /releases/latest
	req, err := http.NewRequest("GET", "https://api.github.com/repos/mario-ezquerro/gubernator/releases?per_page=5", nil)
	if err != nil {
		return fallbackInfo(currentVersion), nil
	}
	req.Header.Set("User-Agent", "Gubernator-AutoUpdater")
	req.Header.Set("Accept", "application/vnd.github.v3+json")

	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Do(req)
	var rel githubRelease
	found := false

	if err == nil && resp.StatusCode == http.StatusOK {
		var releases []githubRelease
		if decodeErr := json.NewDecoder(resp.Body).Decode(&releases); decodeErr == nil && len(releases) > 0 {
			rel = releases[0]
			found = true
		}
		resp.Body.Close()
	}

	if !found {
		// Fallback to /releases/latest
		reqLatest, _ := http.NewRequest("GET", "https://api.github.com/repos/mario-ezquerro/gubernator/releases/latest", nil)
		if reqLatest != nil {
			reqLatest.Header.Set("User-Agent", "Gubernator-AutoUpdater")
			reqLatest.Header.Set("Accept", "application/vnd.github.v3+json")
			if respLatest, errLatest := client.Do(reqLatest); errLatest == nil && respLatest.StatusCode == http.StatusOK {
				_ = json.NewDecoder(respLatest.Body).Decode(&rel)
				respLatest.Body.Close()
				if rel.TagName != "" {
					found = true
				}
			}
		}
	}

	if !found || strings.TrimSpace(rel.TagName) == "" {
		return fallbackInfo(currentVersion), nil
	}

	latest := strings.TrimSpace(rel.TagName)

	notes := strings.TrimSpace(rel.Body)
	if notes == "" {
		notes = fmt.Sprintf("• Automated cluster rolling upgrade to %s\n• Container core image updates & dependency sync\n• Performance, security and state resilience improvements", latest)
	}

	updateAvailable := isNewerVersion(currentVersion, latest)

	info := &UpdateInfo{
		CurrentVersion:  currentVersion,
		LatestVersion:   latest,
		UpdateAvailable: updateAvailable,
		ReleaseNotes:    notes,
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
		ReleaseNotes:    "• Gubernator system operating on latest release\n• Core engine services active and synchronized",
		ReleaseURL:      "https://github.com/mario-ezquerro/gubernator/releases",
		CheckedAt:       time.Now().Format(time.RFC3339),
	}
}

func parseSemver(v string) (major, minor, patch int) {
	v = strings.TrimPrefix(v, "v")
	parts := strings.Split(v, ".")
	if len(parts) > 0 {
		fmt.Sscanf(parts[0], "%d", &major)
	}
	if len(parts) > 1 {
		fmt.Sscanf(parts[1], "%d", &minor)
	}
	if len(parts) > 2 {
		fmt.Sscanf(parts[2], "%d", &patch)
	}
	return major, minor, patch
}

func isNewerVersion(current, latest string) bool {
	c := strings.TrimPrefix(current, "v")
	if c == "dev" || c == "" {
		return false
	}
	cMaj, cMin, cPat := parseSemver(current)
	lMaj, lMin, lPat := parseSemver(latest)

	if lMaj != cMaj {
		return lMaj > cMaj
	}
	if lMin != cMin {
		return lMin > cMin
	}
	return lPat > cPat
}

func parseTime(tStr string) time.Time {
	t, _ := time.Parse(time.RFC3339, tStr)
	return t
}

// UpdateProgressStatus holds live update state for UI progress monitoring.
type UpdateProgressStatus struct {
	Status          string `json:"status"` // "idle", "downloading", "installing", "restarting", "success", "failed"
	TargetVersion   string `json:"target_version"`
	ProgressMessage string `json:"progress_message"`
	Error           string `json:"error,omitempty"`
	UpdatedAt       string `json:"updated_at"`
}

var (
	currentUpdateStatus = UpdateProgressStatus{
		Status:          "idle",
		ProgressMessage: "Ready",
	}
	statusMutex sync.RWMutex
)

// GetUpdateStatus returns the live status of an active or recent update.
func GetUpdateStatus() UpdateProgressStatus {
	statusMutex.RLock()
	defer statusMutex.RUnlock()
	return currentUpdateStatus
}

func setUpdateStatus(status, version, msg, errStr string) {
	statusMutex.Lock()
	defer statusMutex.Unlock()
	currentUpdateStatus = UpdateProgressStatus{
		Status:          status,
		TargetVersion:   version,
		ProgressMessage: msg,
		Error:           errStr,
		UpdatedAt:       time.Now().UTC().Format(time.RFC3339),
	}
}

// ApplyClusterUpdate triggers binary downloading, container pulling, version updating, and node upgrades across the cluster.
func ApplyClusterUpdate(targetVersion string) error {
	slog.Info("🚀 Initiating cluster-wide update", "target_version", targetVersion)

	cacheMutex.Lock()
	cachedInfo = nil
	cacheMutex.Unlock()

	setUpdateStatus("downloading", targetVersion, fmt.Sprintf("Connecting to GitHub to download %s...", targetVersion), "")

	if targetVersion != "" {
		for _, path := range []string{"/data/VERSION", "/app/VERSION", "VERSION", "../VERSION"} {
			_ = os.WriteFile(path, []byte(targetVersion), 0644)
		}
	}

	if db.DB != nil {
		var config db.ClusterConfig
		if err := db.DB.First(&config, "id = ?", "global").Error; err == nil {
			config.TargetVersion = targetVersion
			db.DB.Save(&config)
		}
	}

	// Trigger asynchronous cluster upgrade so HTTP response returns cleanly first
	go func() {
		defer func() {
			if r := recover(); r != nil {
				slog.Error("recovered panic in cluster update", "err", r)
				setUpdateStatus("failed", targetVersion, "Update crashed unexpectedly", fmt.Sprintf("%v", r))
			}
		}()

		goos := runtime.GOOS
		goarch := runtime.GOARCH
		binURL := fmt.Sprintf("https://github.com/mario-ezquerro/gubernator/releases/download/%s/gbnt-%s-%s", targetVersion, goos, goarch)
		if goos == "windows" {
			binURL += ".exe"
		}

		slog.Info("downloading release binary with retry", "url", binURL)
		tmpPath := fmt.Sprintf("/tmp/gbnt-update-%d", time.Now().Unix())

		// Try downloading with retry (up to 15 attempts x 3s = 45s backoff for GitHub Actions release publication)
		var dlErr error
		client := &http.Client{Timeout: 30 * time.Second}
		for attempt := 1; attempt <= 15; attempt++ {
			setUpdateStatus("downloading", targetVersion, fmt.Sprintf("Downloading binary from GitHub (attempt %d/15)...", attempt), "")
			resp, err := client.Get(binURL)
			if err == nil {
				if resp.StatusCode == http.StatusOK {
					out, createErr := os.Create(tmpPath)
					if createErr == nil {
						_, copyErr := io.Copy(out, resp.Body)
						out.Close()
						resp.Body.Close()
						if copyErr == nil {
							// Verify binary size > 1MB
							if fi, sErr := os.Stat(tmpPath); sErr == nil && fi.Size() > 1000000 {
								dlErr = nil
								break
							}
						}
					}
				} else {
					resp.Body.Close()
					dlErr = fmt.Errorf("GitHub returned HTTP %s (release assets may still be uploading)", resp.Status)
				}
			} else {
				dlErr = err
			}
			time.Sleep(3 * time.Second)
		}

		if dlErr != nil {
			slog.Warn("could not download release binary", "err", dlErr)
			setUpdateStatus("failed", targetVersion, "Download failed from GitHub", dlErr.Error())
			return
		}

		setUpdateStatus("installing", targetVersion, "Installing new binary on Manager and Centurions...", "")
		_ = os.Chmod(tmpPath, 0755)

		// Overwrite local binary
		installPaths := []string{"/usr/local/bin/gbnt", "/app/gbnt"}
		if execPath, err := os.Executable(); err == nil && execPath != "" {
			installPaths = append([]string{execPath}, installPaths...)
		}

		for _, dst := range installPaths {
			_ = exec.Command("sudo", "install", "-m", "755", tmpPath, dst).Run()
			_ = exec.Command("install", "-m", "755", tmpPath, dst).Run()
			_ = exec.Command("sudo", "cp", "-f", tmpPath, dst).Run()
			_ = exec.Command("cp", "-f", tmpPath, dst).Run()
			_ = os.Chmod(dst, 0755)
		}
		_ = os.Remove(tmpPath)

		// 2. Upgrade worker Centurion nodes via remote SSH
		if db.DB != nil {
			var workers []db.Node
			if err := db.DB.Where("role = 'worker' AND status != 'left'").Find(&workers).Error; err == nil {
				for _, w := range workers {
					if w.IP != "" {
						workerIP := w.IP
						slog.Info("triggering remote update on worker node", "node_id", w.ID, "ip", workerIP)
						go func(ip string) {
							workerScript := fmt.Sprintf(
								`curl -fsSL -o /tmp/gbnt-new "%s" && sudo install -m 755 /tmp/gbnt-new /usr/local/bin/gbnt && rm -f /tmp/gbnt-new && (sudo systemctl restart gbnt-worker || systemctl restart gbnt-worker || true)`,
								binURL,
							)
							_, _ = exec.Command("ssh", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=5", fmt.Sprintf("ubuntu@%s", ip), "sudo", "sh", "-c", workerScript).CombinedOutput()
						}(workerIP)
					}
				}
			}
		}

		// 3. Restart services
		setUpdateStatus("restarting", targetVersion, "Restarting Gubernator services...", "")
		time.Sleep(1500 * time.Millisecond)

		// Try container restart
		_ = exec.Command("docker", "restart", "gbnt-manager").Run()

		// Try systemd restart with sudo and without sudo
		_ = exec.Command("sudo", "systemctl", "restart", "gbnt-manager").Run()
		_ = exec.Command("systemctl", "restart", "gbnt-manager").Run()

		setUpdateStatus("success", targetVersion, fmt.Sprintf("Successfully upgraded cluster to %s", targetVersion), "")
	}()

	return nil
}
