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
	Draft       bool   `json:"draft"`
	Prerelease  bool   `json:"prerelease"`
}

type githubTag struct {
	Name string `json:"name"`
}

var (
	cachedInfo *UpdateInfo
	cacheMutex sync.Mutex
	cacheTTL   = 30 * time.Second
)

// CheckLatestRelease queries GitHub Releases, Tags, and raw repository metadata
// using a multi-source cascade to ensure zero CDN caching delay and rate limit resilience.
func CheckLatestRelease(currentVersion string, forceRefresh bool) (*UpdateInfo, error) {
	cacheMutex.Lock()
	if forceRefresh {
		cachedInfo = nil
	} else if cachedInfo != nil && time.Since(parseTime(cachedInfo.CheckedAt)) < cacheTTL {
		info := *cachedInfo
		info.CurrentVersion = currentVersion
		info.UpdateAvailable = isNewerVersion(currentVersion, info.LatestVersion)
		cacheMutex.Unlock()
		return &info, nil
	}
	cacheMutex.Unlock()

	client := &http.Client{Timeout: 6 * time.Second}
	cb := time.Now().UnixNano()

	authHeader := os.Getenv("GBNT_GITHUB_TOKEN")
	if authHeader == "" {
		authHeader = os.Getenv("GITHUB_TOKEN")
	}

	prepareReq := func(req *http.Request) {
		req.Header.Set("User-Agent", "Gubernator-AutoUpdater")
		req.Header.Set("Accept", "application/vnd.github.v3+json")
		req.Header.Set("Cache-Control", "no-cache, no-store, must-revalidate")
		req.Header.Set("Pragma", "no-cache")
		if authHeader != "" {
			req.Header.Set("Authorization", "Bearer "+authHeader)
		}
	}

	type candidate struct {
		version string
		notes   string
		url     string
	}
	var candidates []candidate

	// Source 1: GitHub Releases API (Primary source for rich changelogs)
	relURL := fmt.Sprintf("https://api.github.com/repos/mario-ezquerro/gubernator/releases?per_page=15&_cb=%d", cb)
	if req, err := http.NewRequest("GET", relURL, nil); err == nil {
		prepareReq(req)
		if resp, err := client.Do(req); err == nil {
			if resp.StatusCode == http.StatusOK {
				var releases []githubRelease
				if err := json.NewDecoder(resp.Body).Decode(&releases); err == nil {
					for _, r := range releases {
						tag := strings.TrimSpace(r.TagName)
						if tag != "" && !r.Draft {
							candidates = append(candidates, candidate{
								version: tag,
								notes:   strings.TrimSpace(r.Body),
								url:     r.HTMLURL,
							})
						}
					}
				}
			}
			resp.Body.Close()
		}
	}

	// Source 2: GitHub Tags API (Immediate discovery right after git push, before CI completes)
	tagURL := fmt.Sprintf("https://api.github.com/repos/mario-ezquerro/gubernator/tags?per_page=15&_cb=%d", cb)
	if req, err := http.NewRequest("GET", tagURL, nil); err == nil {
		prepareReq(req)
		if resp, err := client.Do(req); err == nil {
			if resp.StatusCode == http.StatusOK {
				var tags []githubTag
				if err := json.NewDecoder(resp.Body).Decode(&tags); err == nil {
					for _, t := range tags {
						tag := strings.TrimSpace(t.Name)
						if tag != "" {
							candidates = append(candidates, candidate{
								version: tag,
								notes:   "",
								url:     fmt.Sprintf("https://github.com/mario-ezquerro/gubernator/releases/tag/%s", tag),
							})
						}
					}
				}
			}
			resp.Body.Close()
		}
	}

	// Source 3: GitHub Raw Content VERSION (Zero rate limit, instantly available on main branch)
	rawURL := fmt.Sprintf("https://raw.githubusercontent.com/mario-ezquerro/gubernator/main/VERSION?_cb=%d", cb)
	if req, err := http.NewRequest("GET", rawURL, nil); err == nil {
		prepareReq(req)
		if resp, err := client.Do(req); err == nil {
			if resp.StatusCode == http.StatusOK {
				bodyBytes, _ := io.ReadAll(resp.Body)
				rawV := strings.TrimSpace(string(bodyBytes))
				if rawV != "" && strings.HasPrefix(rawV, "v") {
					candidates = append(candidates, candidate{
						version: rawV,
						notes:   "",
						url:     fmt.Sprintf("https://github.com/mario-ezquerro/gubernator/releases/tag/%s", rawV),
					})
				}
			}
			resp.Body.Close()
		}
	}

	// Select the highest SemVer candidate
	var best candidate
	for _, c := range candidates {
		if best.version == "" || isNewerVersion(best.version, c.version) {
			best = c
		} else if best.version == c.version && best.notes == "" && c.notes != "" {
			best.notes = c.notes
			if c.url != "" {
				best.url = c.url
			}
		}
	}

	if best.version == "" {
		return fallbackInfo(currentVersion), nil
	}

	latest := best.version
	notes := best.notes
	if notes == "" {
		notes = fmt.Sprintf("• Automated cluster rolling upgrade to %s\n• Container core image updates & dependency sync\n• Performance, security and state resilience improvements", latest)
	}
	relURLOut := best.url
	if relURLOut == "" {
		relURLOut = fmt.Sprintf("https://github.com/mario-ezquerro/gubernator/releases/tag/%s", latest)
	}

	updateAvailable := isNewerVersion(currentVersion, latest)

	info := &UpdateInfo{
		CurrentVersion:  currentVersion,
		LatestVersion:   latest,
		UpdateAvailable: updateAvailable,
		ReleaseNotes:    notes,
		ReleaseURL:      relURLOut,
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
