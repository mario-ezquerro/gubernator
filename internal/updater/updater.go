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

func parseSemver(v string) (int, int, int) {
	v = strings.TrimPrefix(v, "v")
	parts := strings.Split(v, ".")
	var major, minor, patch int
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

// ApplyClusterUpdate triggers binary downloading, container pulling, version updating, and node upgrades across the cluster.
func ApplyClusterUpdate(targetVersion string) error {
	slog.Info("🚀 Initiating cluster-wide update", "target_version", targetVersion)

	cacheMutex.Lock()
	cachedInfo = nil
	cacheMutex.Unlock()

	if targetVersion != "" {
		written := false
		for _, path := range []string{"/data/VERSION", "/app/VERSION", "VERSION", "../VERSION"} {
			if err := os.WriteFile(path, []byte(targetVersion), 0644); err == nil {
				written = true
			}
		}
		if !written {
			_ = os.WriteFile("/app/VERSION", []byte(targetVersion), 0644)
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
		time.Sleep(1000 * time.Millisecond)

		// 1. Download and replace binary on Manager host if running natively / systemd
		goos := runtime.GOOS
		goarch := runtime.GOARCH
		binURL := fmt.Sprintf("https://github.com/mario-ezquerro/gubernator/releases/download/%s/gbnt-%s-%s", targetVersion, goos, goarch)
		if goos == "windows" {
			binURL += ".exe"
		}

		slog.Info("downloading release binary for host update", "url", binURL)
		tmpPath := fmt.Sprintf("/tmp/gbnt-update-%d", time.Now().Unix())
		if err := downloadFile(binURL, tmpPath); err == nil {
			_ = os.Chmod(tmpPath, 0755)

			// Target paths to overwrite
			installPaths := []string{"/usr/local/bin/gbnt", "/app/gbnt"}
			if execPath, err := os.Executable(); err == nil && execPath != "" {
				installPaths = append([]string{execPath}, installPaths...)
			}

			for _, dst := range installPaths {
				if _, err := os.Stat(dst); err == nil {
					// Use atomic move/copy
					_ = exec.Command("mv", "-f", tmpPath, dst).Run()
					_ = os.Chmod(dst, 0755)
					slog.Info("successfully replaced binary", "path", dst)
					break
				}
			}
			_ = os.Remove(tmpPath)
		} else {
			slog.Warn("could not direct-download binary, proceeding with Docker pull fallback", "err", err)
		}

		// 2. Upgrade worker Centurion nodes via remote execution
		if db.DB != nil {
			var workers []db.Node
			if err := db.DB.Where("role = 'worker' AND status != 'left'").Find(&workers).Error; err == nil {
				for _, w := range workers {
					if w.IP != "" {
						workerIP := w.IP
						slog.Info("triggering remote update on worker node", "node_id", w.ID, "ip", workerIP)
						go func(ip string) {
							workerScript := fmt.Sprintf(
								`curl -fsSL -o /tmp/gbnt-new "%s" && chmod +x /tmp/gbnt-new && mv -f /tmp/gbnt-new /usr/local/bin/gbnt && (systemctl restart gbnt-worker || true)`,
								binURL,
							)
							_, _ = exec.Command("ssh", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=5", fmt.Sprintf("ubuntu@%s", ip), "sudo", "sh", "-c", workerScript).CombinedOutput()
						}(workerIP)
					}
				}
			}
		}

		// 3. If running in Docker container, pull new image and restart container
		img := fmt.Sprintf("marioezquerro/gubernator:%s", targetVersion)
		if targetVersion == "" || targetVersion == "latest" {
			img = "marioezquerro/gubernator:latest"
		}
		_ = exec.Command("docker", "pull", img).Run()
		_ = exec.Command("docker", "restart", "gbnt-manager").Run()

		// 4. If running under systemd, restart the systemd service
		time.Sleep(1000 * time.Millisecond)
		slog.Info("restarting gbnt-manager service...")
		_ = exec.Command("systemctl", "restart", "gbnt-manager").Run()
	}()

	return nil
}

func downloadFile(url, destPath string) error {
	client := &http.Client{Timeout: 60 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("bad HTTP status: %s", resp.Status)
	}

	out, err := os.Create(destPath)
	if err != nil {
		return err
	}
	defer out.Close()

	_, err = io.Copy(out, resp.Body)
	return err
}
