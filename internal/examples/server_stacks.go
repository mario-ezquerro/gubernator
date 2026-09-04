package examples

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/db"
	"gopkg.in/yaml.v3"
)

// ServerStackFile represents a Compose file discovered on the Master server host.
type ServerStackFile struct {
	Path         string `json:"path"`
	Filename     string `json:"filename"`
	Directory    string `json:"directory"`
	Size         int64  `json:"size"`
	ModifiedAt   string `json:"modified_at"`
	InferredName string `json:"inferred_name"`
	IsExample    bool   `json:"is_example"`
	Services     int    `json:"services"`
}

// ServerStackFileContent holds the full YAML content and parsed metadata of a server file.
type ServerStackFileContent struct {
	Path         string   `json:"path"`
	Filename     string   `json:"filename"`
	Directory    string   `json:"directory"`
	Content      string   `json:"content"`
	InferredName string   `json:"inferred_name"`
	Services     []string `json:"services"`
	Size         int64    `json:"size"`
}

// ServerDirectoryItem represents a directory discovered on the Master server filesystem for interactive navigation.
type ServerDirectoryItem struct {
	Name string `json:"name"`
	Path string `json:"path"`
}

// ServerStackBrowseResult contains files, subdirectories, current path, and parent path for interactive browsing.
type ServerStackBrowseResult struct {
	CurrentDir     string                `json:"current_dir"`
	ParentDir      string                `json:"parent_dir"`
	Subdirectories []ServerDirectoryItem `json:"subdirectories"`
	Files          []ServerStackFile     `json:"files"`
	StacksDir      string                `json:"stacks_dir"`
	ExamplesDir    string                `json:"examples_dir"`
	Total          int                   `json:"total"`
}

// BrowseServerStackDirectory lists Compose files and navigable subdirectories within a given Master server directory.
func BrowseServerStackDirectory(customDir string) (*ServerStackBrowseResult, error) {
	_ = EnsureServerDirectories()

	homeDir, _ := os.UserHomeDir()
	targetDir := strings.TrimSpace(customDir)

	// Expand ~
	if strings.HasPrefix(targetDir, "~") {
		if homeDir != "" {
			targetDir = filepath.Join(homeDir, strings.TrimPrefix(targetDir, "~"))
		}
	}

	if targetDir == "" {
		targetDir = DefaultServerStacksDir()
	}

	targetDir = filepath.Clean(targetDir)

	// If directory doesn't exist, try home or default
	if fi, err := os.Stat(targetDir); err != nil || !fi.IsDir() {
		targetDir = DefaultServerStacksDir()
		if fi2, err2 := os.Stat(targetDir); err2 != nil || !fi2.IsDir() {
			if homeDir != "" {
				targetDir = homeDir
			} else {
				targetDir = "/"
			}
		}
	}

	// Calculate parent directory
	parentDir := ""
	parent := filepath.Dir(targetDir)
	if parent != targetDir && parent != "" {
		parentDir = parent
	}

	var subdirs []ServerDirectoryItem
	// Read directory entries for subdirectories
	entries, err := os.ReadDir(targetDir)
	if err == nil {
		for _, e := range entries {
			if e.IsDir() {
				name := e.Name()
				// Hide hidden dirs but keep .gbnt
				if strings.HasPrefix(name, ".") && name != ".gbnt" {
					continue
				}
				subdirs = append(subdirs, ServerDirectoryItem{
					Name: name,
					Path: filepath.Join(targetDir, name),
				})
			}
		}
	}
	sort.Slice(subdirs, func(i, j int) bool {
		return strings.ToLower(subdirs[i].Name) < strings.ToLower(subdirs[j].Name)
	})

	// Also find .yml / .yaml files in targetDir (up to 2 levels deep)
	var files []ServerStackFile
	seenPaths := make(map[string]bool)

	scanDirs := []string{targetDir}
	if targetDir == DefaultServerStacksDir() {
		scanDirs = append(scanDirs, DefaultServerExamplesDir())
	}

	for _, sDir := range scanDirs {
		if _, err := os.Stat(sDir); err != nil {
			continue
		}
		_ = filepath.WalkDir(sDir, func(path string, d fs.DirEntry, wErr error) error {
			if wErr != nil {
				return nil
			}
			if d.IsDir() {
				rel, relErr := filepath.Rel(sDir, path)
				if relErr == nil && strings.Count(rel, string(filepath.Separator)) > 2 {
					return filepath.SkipDir
				}
				return nil
			}

			ext := strings.ToLower(filepath.Ext(path))
			if ext != ".yml" && ext != ".yaml" {
				return nil
			}

			if seenPaths[path] {
				return nil
			}
			seenPaths[path] = true

			info, statErr := d.Info()
			if statErr != nil {
				return nil
			}

			data, readErr := os.ReadFile(path)
			if readErr != nil {
				return nil
			}

			inferredName := inferStackName(filepath.Base(path), string(data))
			svcCount := countServicesInYAML(string(data))
			isExample := strings.Contains(path, "examples")

			files = append(files, ServerStackFile{
				Path:         path,
				Filename:     d.Name(),
				Directory:    filepath.Dir(path),
				Size:         info.Size(),
				ModifiedAt:   info.ModTime().Format(time.RFC3339),
				InferredName: inferredName,
				IsExample:    isExample,
				Services:     svcCount,
			})
			return nil
		})
	}

	sort.Slice(files, func(i, j int) bool {
		return strings.ToLower(files[i].Filename) < strings.ToLower(files[j].Filename)
	})

	return &ServerStackBrowseResult{
		CurrentDir:     targetDir,
		ParentDir:      parentDir,
		Subdirectories: subdirs,
		Files:          files,
		StacksDir:      DefaultServerStacksDir(),
		ExamplesDir:    DefaultServerExamplesDir(),
		Total:          len(files),
	}, nil
}

// ListServerStackFiles scans master server directories for docker-compose files.
func ListServerStackFiles(customDir string) ([]ServerStackFile, error) {

	_ = EnsureServerDirectories()

	dirsToScan := []string{
		DefaultServerStacksDir(),
		DefaultServerExamplesDir(),
		"/etc/gubernator/stacks",
		"./examples",
	}

	if strings.TrimSpace(customDir) != "" {
		dirsToScan = append([]string{strings.TrimSpace(customDir)}, dirsToScan...)
	}

	seenPaths := make(map[string]bool)
	var result []ServerStackFile

	for _, dir := range dirsToScan {
		if fi, err := os.Stat(dir); err != nil || !fi.IsDir() {
			continue
		}

		_ = filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
			if err != nil || d.IsDir() {
				// Don't recurse more than 3 levels
				if d != nil && d.IsDir() {
					rel, relErr := filepath.Rel(dir, path)
					if relErr == nil && strings.Count(rel, string(filepath.Separator)) > 2 {
						return filepath.SkipDir
					}
				}
				return nil
			}

			ext := strings.ToLower(filepath.Ext(path))
			if ext != ".yml" && ext != ".yaml" {
				return nil
			}

			if seenPaths[path] {
				return nil
			}
			seenPaths[path] = true

			info, statErr := d.Info()
			if statErr != nil {
				return nil
			}

			// Read file head to infer stack name and service count
			data, readErr := os.ReadFile(path)
			if readErr != nil {
				return nil
			}

			inferredName := inferStackName(filepath.Base(path), string(data))
			svcCount := countServicesInYAML(string(data))
			isExample := strings.Contains(path, "examples")

			result = append(result, ServerStackFile{
				Path:         path,
				Filename:     d.Name(),
				Directory:    filepath.Dir(path),
				Size:         info.Size(),
				ModifiedAt:   info.ModTime().Format(time.RFC3339),
				InferredName: inferredName,
				IsExample:    isExample,
				Services:     svcCount,
			})
			return nil
		})
	}

	return result, nil
}

// ReadServerStackFile safely reads the contents and metadata of a Compose file from the server.
func ReadServerStackFile(filePath string) (*ServerStackFileContent, error) {
	cleanPath := filepath.Clean(filePath)
	info, err := os.Stat(cleanPath)
	if err != nil {
		return nil, fmt.Errorf("file not found: %w", err)
	}
	if info.IsDir() {
		return nil, fmt.Errorf("path '%s' is a directory, not a file", cleanPath)
	}

	ext := strings.ToLower(filepath.Ext(cleanPath))
	if ext != ".yml" && ext != ".yaml" {
		return nil, fmt.Errorf("file '%s' is not a valid YAML file (.yml or .yaml)", cleanPath)
	}

	data, err := os.ReadFile(cleanPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read file: %w", err)
	}

	raw := string(data)
	inferredName := inferStackName(filepath.Base(cleanPath), raw)
	services := extractServiceNames(raw)

	return &ServerStackFileContent{
		Path:         cleanPath,
		Filename:     filepath.Base(cleanPath),
		Directory:    filepath.Dir(cleanPath),
		Content:      raw,
		InferredName: inferredName,
		Services:     services,
		Size:         info.Size(),
	}, nil
}

// DeployServerStackFile reads a Compose file from the Master server filesystem and deploys it as a stack.
func DeployServerStackFile(filePath, reqName, targetNode string) (*db.Stack, error) {
	content, err := ReadServerStackFile(filePath)
	if err != nil {
		return nil, err
	}

	name := strings.TrimSpace(reqName)
	if name == "" {
		name = content.InferredName
	}
	if name == "" {
		name = strings.TrimSuffix(content.Filename, filepath.Ext(content.Filename))
	}

	if DeployStackFn == nil {
		return nil, fmt.Errorf("stack deployment engine not initialized")
	}

	return DeployStackFn(name, content.Content, targetNode)
}

func inferStackName(filename, yamlContent string) string {
	var temp struct {
		Name     string `yaml:"name"`
		Services map[string]struct {
			Deploy struct {
				Placement struct {
					Constraints []string `yaml:"constraints"`
				} `yaml:"placement"`
			} `yaml:"deploy"`
		} `yaml:"services"`
	}

	if err := yaml.Unmarshal([]byte(yamlContent), &temp); err == nil {
		if temp.Name != "" {
			return temp.Name
		}
		for _, srv := range temp.Services {
			for _, constraint := range srv.Deploy.Placement.Constraints {
				parts := strings.Split(constraint, "==")
				if len(parts) == 2 && strings.TrimSpace(parts[0]) == "stack.name" {
					return strings.TrimSpace(parts[1])
				}
			}
		}
	}

	base := strings.TrimSuffix(filename, filepath.Ext(filename))
	base = strings.TrimPrefix(base, "docker-compose.")
	base = strings.TrimPrefix(base, "docker-compose")
	if base == "" {
		return "stack-" + time.Now().Format("01021504")
	}
	return strings.ToLower(strings.ReplaceAll(base, "_", "-"))
}

func countServicesInYAML(yamlContent string) int {
	var temp struct {
		Services map[string]interface{} `yaml:"services"`
	}
	if err := yaml.Unmarshal([]byte(yamlContent), &temp); err == nil {
		return len(temp.Services)
	}
	return 0
}

func extractServiceNames(yamlContent string) []string {
	var temp struct {
		Services map[string]interface{} `yaml:"services"`
	}
	var names []string
	if err := yaml.Unmarshal([]byte(yamlContent), &temp); err == nil {
		for k := range temp.Services {
			names = append(names, k)
		}
	}
	return names
}
