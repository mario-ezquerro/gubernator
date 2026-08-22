package telemetry

import (
	"encoding/json"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/db"
)

// AdoptionStats holds aggregated GitHub adoption metrics, release downloads, and cluster telemetry.
type AdoptionStats struct {
	TotalDownloads    int            `json:"total_downloads"`
	DownloadsByOS     map[string]int `json:"downloads_by_os"`
	TotalReleases     int            `json:"total_releases"`
	LatestReleaseTag  string         `json:"latest_release_tag"`
	LatestReleaseDate string         `json:"latest_release_date"`
	GitHubStars       int            `json:"github_stars"`
	GitHubForks       int            `json:"github_forks"`
	GitHubWatchers    int            `json:"github_watchers"`
	GitHubOpenIssues  int            `json:"github_open_issues"`
	RecentReleases    []ReleaseStats `json:"recent_releases"`
	ClusterStats      ClusterStats   `json:"cluster_stats"`
	DataSource        string         `json:"data_source"`
	PrivacyPolicy     string         `json:"privacy_policy"`
	TelemetryEnabled  bool           `json:"telemetry_enabled"`
	DocumentationURL  string         `json:"documentation_url"`
	CheckedAt         string         `json:"checked_at"`
}

// ReleaseStats contains download details for a specific GitHub release.
type ReleaseStats struct {
	TagName     string `json:"tag_name"`
	PublishedAt string `json:"published_at"`
	Downloads   int    `json:"downloads"`
	HTMLURL     string `json:"html_url"`
}

// ClusterStats contains local operational stats without sensitive information.
type ClusterStats struct {
	NodesCount  int `json:"nodes_count"`
	StacksCount int `json:"stacks_count"`
	TasksCount  int `json:"tasks_count"`
	MountsCount int `json:"mounts_count"`
}

type ghReleaseAsset struct {
	Name          string `json:"name"`
	DownloadCount int    `json:"download_count"`
}

type ghReleaseItem struct {
	TagName     string           `json:"tag_name"`
	PublishedAt string           `json:"published_at"`
	HTMLURL     string           `json:"html_url"`
	Assets      []ghReleaseAsset `json:"assets"`
}

type ghRepoInfo struct {
	StargazersCount int `json:"stargazers_count"`
	ForksCount      int `json:"forks_count"`
	WatchersCount   int `json:"watchers_count"`
	OpenIssuesCount int `json:"open_issues_count"`
}

var (
	cachedStats *AdoptionStats
	statsMutex  sync.Mutex
	statsTTL    = 15 * time.Minute
)

// IsTelemetryEnabled checks if external metric checks are allowed by environment variables.
func IsTelemetryEnabled() bool {
	if os.Getenv("DO_NOT_TRACK") == "1" || strings.ToLower(os.Getenv("GBNT_TELEMETRY")) == "false" || os.Getenv("GBNT_TELEMETRY") == "0" {
		return false
	}
	return true
}

// GetAdoptionStats gathers GitHub release downloads and local cluster metrics transparently.
func GetAdoptionStats(forceRefresh bool) *AdoptionStats {
	statsMutex.Lock()
	if !forceRefresh && cachedStats != nil {
		t, err := time.Parse(time.RFC3339, cachedStats.CheckedAt)
		if err == nil && time.Since(t) < statsTTL {
			// Update local cluster counts dynamically
			cachedStats.ClusterStats = getLocalClusterStats()
			copyStats := *cachedStats
			statsMutex.Unlock()
			return &copyStats
		}
	}
	statsMutex.Unlock()

	stats := &AdoptionStats{
		DownloadsByOS: map[string]int{
			"linux":   0,
			"darwin":  0,
			"windows": 0,
		},
		RecentReleases:   make([]ReleaseStats, 0),
		ClusterStats:     getLocalClusterStats(),
		DataSource:       "Official GitHub Releases & Repository API (https://api.github.com/repos/mario-ezquerro/gubernator)",
		PrivacyPolicy:    "100% GDPR compliant. Gubernator does not track, send or log any container payloads, private IP addresses, passwords or database data.",
		TelemetryEnabled: IsTelemetryEnabled(),
		DocumentationURL: "https://github.com/mario-ezquerro/gubernator#telemetry-adoption-metrics--privacy-transparency",
		CheckedAt:        time.Now().Format(time.RFC3339),
	}

	if !stats.TelemetryEnabled {
		stats.DataSource = "Air-gapped mode (DO_NOT_TRACK / GBNT_TELEMETRY=false enabled)"
		return stats
	}

	client := &http.Client{Timeout: 5 * time.Second}

	// 1. Query Releases for download counts
	reqRel, err := http.NewRequest("GET", "https://api.github.com/repos/mario-ezquerro/gubernator/releases?per_page=100", nil)
	if err == nil {
		reqRel.Header.Set("User-Agent", "Gubernator-Adoption-Telemetry")
		reqRel.Header.Set("Accept", "application/vnd.github.v3+json")
		if resp, err := client.Do(reqRel); err == nil && resp.StatusCode == http.StatusOK {
			defer resp.Body.Close()
			var releases []ghReleaseItem
			if err := json.NewDecoder(resp.Body).Decode(&releases); err == nil {
				stats.TotalReleases = len(releases)
				if len(releases) > 0 {
					stats.LatestReleaseTag = releases[0].TagName
					stats.LatestReleaseDate = releases[0].PublishedAt
				}

				totalDl := 0
				for idx, r := range releases {
					relDl := 0
					for _, a := range r.Assets {
						dl := a.DownloadCount
						relDl += dl
						totalDl += dl
						lowName := strings.ToLower(a.Name)
						if strings.Contains(lowName, "linux") {
							stats.DownloadsByOS["linux"] += dl
						} else if strings.Contains(lowName, "darwin") || strings.Contains(lowName, "macos") {
							stats.DownloadsByOS["darwin"] += dl
						} else if strings.Contains(lowName, "windows") || strings.HasSuffix(lowName, ".exe") {
							stats.DownloadsByOS["windows"] += dl
						}
					}
					if idx < 10 {
						stats.RecentReleases = append(stats.RecentReleases, ReleaseStats{
							TagName:     r.TagName,
							PublishedAt: r.PublishedAt,
							Downloads:   relDl,
							HTMLURL:     r.HTMLURL,
						})
					}
				}
				stats.TotalDownloads = totalDl
			}
		}
	}

	// 2. Query Repo Info for Stars, Forks, Watchers
	reqRepo, err := http.NewRequest("GET", "https://api.github.com/repos/mario-ezquerro/gubernator", nil)
	if err == nil {
		reqRepo.Header.Set("User-Agent", "Gubernator-Adoption-Telemetry")
		reqRepo.Header.Set("Accept", "application/vnd.github.v3+json")
		if resp, err := client.Do(reqRepo); err == nil && resp.StatusCode == http.StatusOK {
			defer resp.Body.Close()
			var repo ghRepoInfo
			if err := json.NewDecoder(resp.Body).Decode(&repo); err == nil {
				stats.GitHubStars = repo.StargazersCount
				stats.GitHubForks = repo.ForksCount
				stats.GitHubWatchers = repo.WatchersCount
				stats.GitHubOpenIssues = repo.OpenIssuesCount
			}
		}
	}

	statsMutex.Lock()
	cachedStats = stats
	statsMutex.Unlock()

	return stats
}

func getLocalClusterStats() ClusterStats {
	var cs ClusterStats
	if db.DB == nil {
		return cs
	}
	var nodeCount, stackCount, taskCount, mountCount int64
	db.DB.Model(&db.Node{}).Count(&nodeCount)
	db.DB.Model(&db.Stack{}).Count(&stackCount)
	db.DB.Model(&db.Task{}).Count(&taskCount)
	db.DB.Model(&db.StorageMount{}).Count(&mountCount)

	cs.NodesCount = int(nodeCount)
	cs.StacksCount = int(stackCount)
	cs.TasksCount = int(taskCount)
	cs.MountsCount = int(mountCount)
	return cs
}
