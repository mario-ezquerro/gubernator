package coredns

import (
	"context"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/db"
	"gorm.io/gorm"
)

const (
	// ContainerName is the name of the CoreDNS Docker container managed by Gubernator.
	ContainerName = "gbnt-coredns"

	// ImageName is the official CoreDNS Docker image.
	ImageName = "coredns/coredns:latest"

	// DNSPort is the port CoreDNS listens on (UDP+TCP 53 mapped to host 5354 to avoid privilege issues).
	DNSPort = "5354:53/udp"

	// VolumeName is the Docker named volume for CoreDNS config files.
	VolumeName = "gbnt-coredns-conf"

	// ConfigDir returns the path inside the container where config is mounted.
	ConfigMountPath = "/etc/coredns"
)

// CoreDNSDir returns the path to the CoreDNS config directory on the host (~/.gbnt/coredns/).
func CoreDNSDir() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".gbnt", "coredns")
}

// HostsFilePath returns the absolute path to the gubernator.hosts file.
func HostsFilePath() string {
	return filepath.Join(CoreDNSDir(), "gubernator.hosts")
}

// CorefilePath returns the absolute path to the Corefile.
func CorefilePath() string {
	return filepath.Join(CoreDNSDir(), "Corefile")
}

// detectLocalIP returns the preferred outbound IP of this machine.
// If GBNT_HOST_IP is set, it will be prioritized.
func detectLocalIP() string {
	if envIP := os.Getenv("GBNT_HOST_IP"); envIP != "" {
		return envIP
	}

	conn, err := net.Dial("udp", "8.8.8.8:53")
	if err == nil {
		defer conn.Close()
		localAddr := conn.LocalAddr().(*net.UDPAddr)
		return localAddr.IP.String()
	}
	return "127.0.0.1"
}

// EnsureConfigDir creates the CoreDNS config directory and writes default config files if they don't exist.
func EnsureConfigDir() error {
	dir := CoreDNSDir()
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create coredns config dir: %w", err)
	}

	// Always write Corefile to ensure the dynamic hostIP (GBNT_HOST_IP) is up to date
	corefilePath := CorefilePath()
	if err := os.WriteFile(corefilePath, []byte(defaultCorefile()), 0644); err != nil {
		return fmt.Errorf("failed to write Corefile: %w", err)
	}

	// Write empty hosts file if it doesn't exist
	hostsPath := HostsFilePath()
	if _, err := os.Stat(hostsPath); os.IsNotExist(err) {
		if err := os.WriteFile(hostsPath, []byte("# Gubernator Auto-Generated CoreDNS Hosts File\n"), 0644); err != nil {
			return fmt.Errorf("failed to write initial hosts file: %w", err)
		}
	}

	return nil
}

// defaultCorefile returns the CoreDNS configuration.
// Uses the 'hosts' plugin to serve *.gbnt and *.gbnt.local from gubernator.hosts,
// falling back to templated host IP, and forwarding other queries to public DNS.
func defaultCorefile() string {
	forwarders := os.Getenv("GBNT_DNS_FORWARDERS")
	if forwarders == "" {
		forwarders = "8.8.8.8 1.1.1.1"
	}
	hostIP := detectLocalIP()
	return fmt.Sprintf(`# Gubernator CoreDNS Configuration
# Managed automatically — do not edit manually.

gbnt gbnt.local {
    hosts /etc/coredns/gubernator.hosts {
        ttl 5
        reload 3s
        fallthrough
    }
    forward . 127.0.0.1:1053
    log
    errors
}

gbnt:1053 gbnt.local:1053 {
    template IN A {
        match "^.*$"
        answer "{{ .Name }} 60 IN A %s"
    }
    log
    errors
}

. {
    forward . %s
    cache 30
    log
    errors
}
`, hostIP, forwarders)
}

// EnsureRunningWorker starts the CoreDNS container in worker mode (forwarding gbnt queries to the manager).
func EnsureRunningWorker(managerIP string) error {
	dir := CoreDNSDir()
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create coredns config dir: %w", err)
	}

	// Write Corefile that forwards gbnt to the manager
	corefileContent := fmt.Sprintf(`# Gubernator CoreDNS Worker Configuration
gbnt gbnt.local {
    forward . %s:5354
    log
    errors
}

. {
    forward . 8.8.8.8 1.1.1.1
    cache 30
    log
    errors
}
`, managerIP)

	corefilePath := CorefilePath()
	if err := os.WriteFile(corefilePath, []byte(corefileContent), 0644); err != nil {
		return fmt.Errorf("failed to write Corefile: %w", err)
	}

	// Write empty hosts file if it doesn't exist
	hostsPath := HostsFilePath()
	if _, err := os.Stat(hostsPath); os.IsNotExist(err) {
		if err := os.WriteFile(hostsPath, []byte("# Gubernator Auto-Generated CoreDNS Hosts File\n"), 0644); err != nil {
			return fmt.Errorf("failed to write initial hosts file: %w", err)
		}
	}

	return EnsureRunning()
}

// EnsureRunning starts the CoreDNS container if it is not already running.
// This function is idempotent: calling it multiple times is safe.
func EnsureRunning() error {
	if err := EnsureConfigDir(); err != nil {
		return err
	}

	// Populate the config volume
	if err := populateConfigVolume(); err != nil {
		return fmt.Errorf("failed to populate coredns config volume: %w", err)
	}

	// Check if container already exists and is running
	out, err := exec.Command("docker", "inspect", "-f", "{{.State.Status}}", ContainerName).Output()
	if err == nil {
		status := strings.TrimSpace(string(out))
		if status == "running" {
			fmt.Println("🌐 CoreDNS: already running.")
			return nil
		}
		// Container exists but not running — remove it first
		exec.Command("docker", "rm", "-f", ContainerName).Run()
	}

	fmt.Println("🌐 Starting CoreDNS container (gbnt-coredns)...")

	hostIP := detectLocalIP()

	baseArgs := []string{
		"run", "-d",
		"--name", ContainerName,
		"--restart", "unless-stopped",
		"--net", NetworkName,
		"-p", DNSPort,
		"-p", strings.Replace(DNSPort, "udp", "tcp", 1),
		"-v", VolumeName + ":" + ConfigMountPath + ":ro",
	}

	// Try with privileged port 53 mapping first (for macOS resolver compatibility)
	argsPrivileged := append([]string{}, baseArgs...)
	argsPrivileged = append(argsPrivileged, 
		"-p", fmt.Sprintf("%s:53:53/udp", hostIP), 
		"-p", fmt.Sprintf("%s:53:53/tcp", hostIP), 
		ImageName, 
		"-conf", "/etc/coredns/Corefile")

	cmd := exec.Command("docker", argsPrivileged...)
	if err := cmd.Run(); err != nil {
		// Clean up the failed container attempt
		exec.Command("docker", "rm", "-f", ContainerName).Run()
		
		fmt.Println("⚠️  Could not bind to local port 53 (in use). Falling back to 5354 only...")
		
		argsFallback := append(baseArgs, ImageName, "-conf", "/etc/coredns/Corefile")
		cmdFallback := exec.Command("docker", argsFallback...)
		cmdFallback.Stdout = os.Stdout
		cmdFallback.Stderr = os.Stderr
		if err := cmdFallback.Run(); err != nil {
			return fmt.Errorf("failed to start CoreDNS container: %w", err)
		}
	} else {
		fmt.Printf("🌟 Bound successfully to %s:53 (macOS native resolver compatibility active!)\n", hostIP)
	}

	fmt.Println("✅ CoreDNS started successfully. DNS domain: *.gbnt")
	fmt.Printf("   📡 Listening on port 5354 (UDP+TCP)\n")
	fmt.Printf("   📁 Config: %s\n", CoreDNSDir())
	return nil
}

// ReloadConfig sends a SIGHUP signal to the CoreDNS container so it reloads
// its hosts file. This is called automatically after GenerateHostsFile().
// Note: The 'hosts' plugin also has a built-in 'reload 3s' option as fallback.
func ReloadConfig() error {
	out, err := exec.Command("docker", "inspect", "-f", "{{.State.Running}}", ContainerName).Output()
	if err != nil || strings.TrimSpace(string(out)) != "true" {
		// CoreDNS not running, skip reload silently
		return nil
	}

	// First update the volume with the new hosts file
	if err := updateHostsInVolume(); err != nil {
		return fmt.Errorf("failed to update hosts in volume: %w", err)
	}

	// Send SIGHUP to trigger reload
	if err := exec.Command("docker", "kill", "-s", "SIGHUP", ContainerName).Run(); err != nil {
		return fmt.Errorf("failed to send SIGHUP to CoreDNS: %w", err)
	}

	fmt.Println("🔄 CoreDNS: hosts file reloaded.")
	return nil
}

// Stop stops and removes the CoreDNS container.
func Stop() {
	fmt.Printf("⏹  Stopping %s...\n", ContainerName)
	exec.Command("docker", "stop", ContainerName).Run()
	exec.Command("docker", "rm", "-f", ContainerName).Run()
	exec.Command("docker", "volume", "rm", "-f", VolumeName).Run()
}

// Restart stops and starts the CoreDNS container.
func Restart() error {
	Stop()
	return EnsureRunning()
}

// Status prints the current status of the CoreDNS container.
func Status() string {
	out, err := exec.Command("docker", "inspect", "-f",
		"{{.State.Status}} | {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}",
		ContainerName).Output()
	if err != nil {
		return "not running"
	}
	return strings.TrimSpace(string(out))
}

// GetContainerIP returns the IP address of the CoreDNS container within gbnt-net.
func GetContainerIP() string {
	out, err := exec.Command("docker", "inspect", "-f",
		fmt.Sprintf("{{(index .NetworkSettings.Networks \"%s\").IPAddress}}", NetworkName),
		ContainerName).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

// populateConfigVolume creates the named volume and copies config files into it
// using a temporary alpine container helper.
func populateConfigVolume() error {
	dir := CoreDNSDir()

	// Create volume
	exec.Command("docker", "volume", "create", VolumeName).Run()

	helperName := "gbnt-coredns-vol-helper"
	exec.Command("docker", "rm", "-f", helperName).Run()

	// Create helper container with the volume
	if err := exec.Command("docker", "create",
		"--name", helperName,
		"-v", VolumeName+":/data",
		"alpine:latest").Run(); err != nil {
		return fmt.Errorf("failed to create volume helper: %w", err)
	}
	defer exec.Command("docker", "rm", "-f", helperName).Run()

	// Copy config files into the volume
	if err := exec.Command("docker", "cp", dir+"/.", helperName+":/data/").Run(); err != nil {
		return fmt.Errorf("failed to copy configs into coredns volume: %w", err)
	}

	return nil
}

// updateHostsInVolume copies the updated gubernator.hosts into the config volume
// without recreating the full volume (faster, used on each DNS refresh).
func updateHostsInVolume() error {
	hostsPath := HostsFilePath()

	// Use a temporary alpine container to update only the hosts file
	cmd := exec.Command("docker", "run", "--rm", "-i",
		"-v", VolumeName+":/data",
		"alpine:latest",
		"sh", "-c", "cat > /data/gubernator.hosts")

	content, err := os.ReadFile(hostsPath)
	if err != nil {
		return fmt.Errorf("failed to read hosts file: %w", err)
	}

	cmd.Stdin = strings.NewReader(string(content))
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to update hosts in volume: %w", err)
	}
	return nil
}

type DNSRecordAnswer struct {
	Name string `json:"name"`
	Type string `json:"type"`
	TTL  int    `json:"ttl"`
	Data string `json:"data"`
}

type DigResult struct {
	Domain      string            `json:"domain"`
	RecordType  string            `json:"record_type"`
	Status      string            `json:"status"`
	QueryTimeMs float64           `json:"query_time_ms"`
	Server      string            `json:"server"`
	Answers     []DNSRecordAnswer `json:"answers"`
	RawOutput   string            `json:"raw_output"`
}

type CoreDNSStatusInfo struct {
	Status        string   `json:"status"`
	UptimeSeconds int64    `json:"uptime_seconds"`
	MemBytes      uint64   `json:"mem_bytes"`
	ListeningPort int      `json:"listening_port"`
	Forwarders    []string `json:"forwarders"`
	TotalRecords  int      `json:"total_records"`
}

// PerformDig executes a DNS query against the local CoreDNS instance.
func PerformDig(domain string, recordType string) (*DigResult, error) {
	start := time.Now()
	recType := strings.ToUpper(strings.TrimSpace(recordType))
	if recType == "" {
		recType = "A"
	}
	dom := strings.TrimSpace(domain)
	if dom == "" {
		return nil, fmt.Errorf("domain cannot be empty")
	}

	cmd := exec.Command("docker", "exec", ContainerName, "nslookup", dom)
	outBytes, err := cmd.CombinedOutput()
	queryTime := float64(time.Since(start).Microseconds()) / 1000.0

	raw := string(outBytes)
	statusStr := "NOERROR"
	if err != nil {
		statusStr = "NXDOMAIN"
	}

	var answers []DNSRecordAnswer
	r := &net.Resolver{
		PreferGo: true,
		Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
			d := net.Dialer{Timeout: 2 * time.Second}
			conn, err := d.DialContext(ctx, "udp", "127.0.0.1:5354")
			if err != nil {
				return d.DialContext(ctx, "udp", "127.0.0.1:53")
			}
			return conn, nil
		},
	}

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	if recType == "A" || recType == "AAAA" {
		ips, err := r.LookupHost(ctx, dom)
		if err == nil {
			statusStr = "NOERROR"
			for _, ip := range ips {
				answers = append(answers, DNSRecordAnswer{
					Name: dom,
					Type: recType,
					TTL:  60,
					Data: ip,
				})
			}
		}
	} else if recType == "TXT" {
		txts, err := r.LookupTXT(ctx, dom)
		if err == nil {
			statusStr = "NOERROR"
			for _, txt := range txts {
				answers = append(answers, DNSRecordAnswer{
					Name: dom,
					Type: "TXT",
					TTL:  60,
					Data: txt,
				})
			}
		}
	} else if recType == "CNAME" {
		cname, err := r.LookupCNAME(ctx, dom)
		if err == nil {
			statusStr = "NOERROR"
			answers = append(answers, DNSRecordAnswer{
				Name: dom,
				Type: "CNAME",
				TTL:  60,
				Data: cname,
			})
		}
	}

	return &DigResult{
		Domain:      dom,
		RecordType:  recType,
		Status:      statusStr,
		QueryTimeMs: queryTime,
		Server:      "127.0.0.1:5354",
		Answers:     answers,
		RawOutput:   raw,
	}, nil
}

// GetCoreDNSStatusInfo inspects CoreDNS container and returns diagnostic details.
func GetCoreDNSStatusInfo(database *gorm.DB) *CoreDNSStatusInfo {
	info := &CoreDNSStatusInfo{
		Status:        "stopped",
		ListeningPort: 5354,
		Forwarders:    []string{"8.8.8.8", "1.1.1.1"},
	}

	out, err := exec.Command("docker", "inspect", "-f",
		"{{.State.Status}}|{{.State.StartedAt}}", ContainerName).Output()
	if err == nil {
		parts := strings.Split(strings.TrimSpace(string(out)), "|")
		if len(parts) >= 1 {
			info.Status = parts[0]
		}
		if len(parts) >= 2 {
			if t, err := time.Parse(time.RFC3339Nano, parts[1]); err == nil {
				info.UptimeSeconds = int64(time.Since(t).Seconds())
			}
		}
	}

	if content, err := os.ReadFile(CorefilePath()); err == nil {
		lines := strings.Split(string(content), "\n")
		for _, l := range lines {
			l = strings.TrimSpace(l)
			if strings.HasPrefix(l, "forward . ") {
				fields := strings.Fields(l)
				if len(fields) > 2 {
					info.Forwarders = fields[2:]
				}
			}
		}
	}

	var customCount int64
	var taskCount int64
	if db.DB != nil {
		db.DB.Model(&db.CustomDNSRecord{}).Count(&customCount)
		db.DB.Model(&db.Task{}).Where("status = ? AND container_ip != ?", "running", "").Count(&taskCount)
	}
	info.TotalRecords = int(customCount + taskCount*2)

	return info
}
