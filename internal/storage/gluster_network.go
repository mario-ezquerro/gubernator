package storage

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/coredns"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

// StorageNetworkInterface represents a physical or virtual network interface on a node.
type StorageNetworkInterface struct {
	Name         string   `json:"name"`
	IPAddresses  []string `json:"ip_addresses"`
	HardwareAddr string   `json:"mac"`
	MTU          int      `json:"mtu"`
	Flags        string   `json:"flags"`
	IsUp         bool     `json:"is_up"`
	IsStorage    bool     `json:"is_storage"`
	RxBytes      uint64   `json:"rx_bytes"`
	TxBytes      uint64   `json:"tx_bytes"`
	RxPackets    uint64   `json:"rx_packets"`
	TxPackets    uint64   `json:"tx_packets"`
	RxRateMBs    float64  `json:"rx_rate_mbs"`
	TxRateMBs    float64  `json:"tx_rate_mbs"`
	RxErrors     uint64   `json:"rx_errors"`
	TxErrors     uint64   `json:"tx_errors"`
}

// NodeStorageNetworkInfo represents the network interfaces and storage traffic for a single Centurion node.
type NodeStorageNetworkInfo struct {
	NodeID     string                    `json:"node_id"`
	NodeRole   string                    `json:"node_role"`
	HostIP     string                    `json:"host_ip"`
	StorageIP  string                    `json:"storage_ip"`
	StorageDNS string                    `json:"storage_dns"`
	StorageNIC string                    `json:"storage_nic"`
	Interfaces []StorageNetworkInterface `json:"interfaces"`
	IsOnline   bool                      `json:"is_online"`
}

// ClusterStorageNetworkReport contains cluster-wide storage traffic and Dual-NIC topology.
type ClusterStorageNetworkReport struct {
	DedicatedSubnet string                   `json:"dedicated_subnet"`
	CoreDNSSuffix   string                   `json:"coredns_suffix"`
	Nodes           []NodeStorageNetworkInfo `json:"nodes"`
	TotalRxRateMBs  float64                  `json:"total_rx_rate_mbs"`
	TotalTxRateMBs  float64                  `json:"total_tx_rate_mbs"`
	ActiveTraffic   bool                     `json:"active_traffic"`
	Timestamp       time.Time                `json:"timestamp"`
}

// interfaceSample stores historical traffic samples for rate calculation.
type interfaceSample struct {
	Timestamp time.Time
	RxBytes   uint64
	TxBytes   uint64
	RxPackets uint64
	TxPackets uint64
}

var (
	trafficCacheMu sync.Mutex
	trafficCache   = make(map[string]interfaceSample) // key: "<nodeID>:<ifaceName>"
)

// GetClusterStorageNetworkReport discovers and samples network traffic across all cluster nodes.
func GetClusterStorageNetworkReport() (*ClusterStorageNetworkReport, error) {
	report := &ClusterStorageNetworkReport{
		DedicatedSubnet: "10.10.100.0/24",
		CoreDNSSuffix:   ".storage.gbnt.local",
		Nodes:           []NodeStorageNetworkInfo{},
		Timestamp:       time.Now().UTC(),
	}

	var allNodes []db.Node
	if db.DB != nil {
		_ = db.DB.Find(&allNodes).Error
	}

	// Always sample local Manager first
	localInfo := getLocalNodeNetworkInfo()
	report.Nodes = append(report.Nodes, localInfo)

	// Sample worker nodes via SSH
	for _, n := range allNodes {
		if n.Role == "manager" || n.IP == localInfo.HostIP || n.IP == "127.0.0.1" || n.IP == "localhost" {
			continue
		}
		workerInfo := getRemoteNodeNetworkInfo(n)
		report.Nodes = append(report.Nodes, workerInfo)
	}

	// Calculate cluster totals
	for _, n := range report.Nodes {
		for _, iface := range n.Interfaces {
			if iface.IsStorage {
				report.TotalRxRateMBs += iface.RxRateMBs
				report.TotalTxRateMBs += iface.TxRateMBs
			}
		}
	}
	if report.TotalRxRateMBs > 0.01 || report.TotalTxRateMBs > 0.01 {
		report.ActiveTraffic = true
	}

	// Sync Storage DNS records to CoreDNS in background
	go syncCoreDNSStorageHosts(report)

	return report, nil
}

// getLocalNodeNetworkInfo inspects local interfaces and /proc/net/dev on the Manager.
func getLocalNodeNetworkInfo() NodeStorageNetworkInfo {
	info := NodeStorageNetworkInfo{
		NodeID:     "gbnt-manager",
		NodeRole:   "manager",
		HostIP:     os.Getenv("GBNT_HOST_IP"),
		StorageDNS: "gbnt-manager.storage.gbnt.local",
		StorageNIC: "enp0s2",
		Interfaces: []StorageNetworkInterface{},
		IsOnline:   true,
	}
	if info.HostIP == "" {
		info.HostIP = "127.0.0.1"
	}

	// Read interfaces from system
	ifaces, err := net.Interfaces()
	if err == nil {
		procStats := parseProcNetDev("/proc/net/dev")
		for _, iface := range ifaces {
			// Skip docker and veth interfaces
			if strings.HasPrefix(iface.Name, "veth") || strings.HasPrefix(iface.Name, "br-") || strings.HasPrefix(iface.Name, "docker") || iface.Name == "lo" {
				continue
			}

			item := StorageNetworkInterface{
				Name:         iface.Name,
				HardwareAddr: iface.HardwareAddr.String(),
				MTU:          iface.MTU,
				Flags:        iface.Flags.String(),
				IsUp:         iface.Flags&net.FlagUp != 0,
				IPAddresses:  []string{},
			}

			addrs, _ := iface.Addrs()
			for _, a := range addrs {
				ipNet, ok := a.(*net.IPNet)
				if ok && ipNet.IP.To4() != nil {
					item.IPAddresses = append(item.IPAddresses, ipNet.IP.String())
					if isStorageIP(ipNet.IP.String()) || iface.Name == "enp0s2" || iface.Name == "eth1" {
						item.IsStorage = true
						info.StorageIP = ipNet.IP.String()
						info.StorageNIC = iface.Name
					}
				}
			}

			// Apply /proc/net/dev counters and rates
			if stat, exists := procStats[iface.Name]; exists {
				item.RxBytes = stat.RxBytes
				item.TxBytes = stat.TxBytes
				item.RxPackets = stat.RxPackets
				item.TxPackets = stat.TxPackets
				item.RxErrors = stat.RxErrors
				item.TxErrors = stat.TxErrors

				cacheKey := fmt.Sprintf("manager:%s", iface.Name)
				item.RxRateMBs, item.TxRateMBs = calculateRate(cacheKey, stat.RxBytes, stat.TxBytes)
			}

			info.Interfaces = append(info.Interfaces, item)
		}
	}

	return info
}

// getRemoteNodeNetworkInfo queries remote worker interfaces and /proc/net/dev via SSH.
func getRemoteNodeNetworkInfo(n db.Node) NodeStorageNetworkInfo {
	hostname := n.ID
	if hostname == "" {
		hostname = fmt.Sprintf("node-%s", n.IP)
	}

	info := NodeStorageNetworkInfo{
		NodeID:     n.ID,
		NodeRole:   n.Role,
		HostIP:     n.IP,
		StorageDNS: fmt.Sprintf("%s.storage.gbnt.local", hostname),
		StorageNIC: "enp0s2",
		Interfaces: []StorageNetworkInterface{},
		IsOnline:   n.Status == "active",
	}

	// Query remote node via SSH for ip -j addr and cat /proc/net/dev
	remoteCmd := `ip -j addr show; echo "---GBNT_SPLIT---"; cat /proc/net/dev`
	out, err := executeRemoteSSH(n.IP, remoteCmd)
	if err != nil || strings.TrimSpace(out) == "" {
		// Fallback to minimal info
		info.IsOnline = false
		return info
	}

	parts := strings.Split(out, "---GBNT_SPLIT---")
	var ipJsonPart, procNetPart string
	if len(parts) >= 2 {
		ipJsonPart = strings.TrimSpace(parts[0])
		procNetPart = strings.TrimSpace(parts[1])
	} else {
		procNetPart = strings.TrimSpace(parts[0])
	}

	// Parse /proc/net/dev from worker
	workerStats := parseProcNetDevContent(procNetPart)

	// Parse ip -j addr if JSON available
	type ipAddrObj struct {
		IfName    string   `json:"ifname"`
		OperState string   `json:"operstate"`
		Flags     []string `json:"flags"`
		Mtu       int      `json:"mtu"`
		Address   string   `json:"address"`
		AddrInfo  []struct {
			Local  string `json:"local"`
			Family string `json:"family"`
		} `json:"addr_info"`
	}

	var ipList []ipAddrObj
	if err := json.Unmarshal([]byte(ipJsonPart), &ipList); err == nil {
		for _, item := range ipList {
			if strings.HasPrefix(item.IfName, "veth") || strings.HasPrefix(item.IfName, "br-") || strings.HasPrefix(item.IfName, "docker") || item.IfName == "lo" {
				continue
			}

			ifaceModel := StorageNetworkInterface{
				Name:         item.IfName,
				HardwareAddr: item.Address,
				MTU:          item.Mtu,
				Flags:        strings.Join(item.Flags, ","),
				IsUp:         item.OperState == "UP" || strings.Contains(strings.Join(item.Flags, ","), "UP"),
				IPAddresses:  []string{},
			}

			for _, addr := range item.AddrInfo {
				if addr.Family == "inet" && addr.Local != "" {
					ifaceModel.IPAddresses = append(ifaceModel.IPAddresses, addr.Local)
					if isStorageIP(addr.Local) || item.IfName == "enp0s2" || item.IfName == "eth1" {
						ifaceModel.IsStorage = true
						info.StorageIP = addr.Local
						info.StorageNIC = item.IfName
					}
				}
			}

			if stat, exists := workerStats[item.IfName]; exists {
				ifaceModel.RxBytes = stat.RxBytes
				ifaceModel.TxBytes = stat.TxBytes
				ifaceModel.RxPackets = stat.RxPackets
				ifaceModel.TxPackets = stat.TxPackets
				ifaceModel.RxErrors = stat.RxErrors
				ifaceModel.TxErrors = stat.TxErrors

				cacheKey := fmt.Sprintf("%s:%s", n.IP, item.IfName)
				ifaceModel.RxRateMBs, ifaceModel.TxRateMBs = calculateRate(cacheKey, stat.RxBytes, stat.TxBytes)
			}

			info.Interfaces = append(info.Interfaces, ifaceModel)
		}
	} else {
		// If JSON failed, parse basic interfaces from stats
		for ifName, stat := range workerStats {
			if strings.HasPrefix(ifName, "veth") || strings.HasPrefix(ifName, "br-") || strings.HasPrefix(ifName, "docker") || ifName == "lo" {
				continue
			}
			ifaceModel := StorageNetworkInterface{
				Name:      ifName,
				IsUp:      true,
				RxBytes:   stat.RxBytes,
				TxBytes:   stat.TxBytes,
				RxPackets: stat.RxPackets,
				TxPackets: stat.TxPackets,
				RxErrors:  stat.RxErrors,
				TxErrors:  stat.TxErrors,
			}
			if ifName == "enp0s2" || ifName == "eth1" {
				ifaceModel.IsStorage = true
				info.StorageNIC = ifName
			}
			cacheKey := fmt.Sprintf("%s:%s", n.IP, ifName)
			ifaceModel.RxRateMBs, ifaceModel.TxRateMBs = calculateRate(cacheKey, stat.RxBytes, stat.TxBytes)
			info.Interfaces = append(info.Interfaces, ifaceModel)
		}
	}

	return info
}

type procNetDevStat struct {
	RxBytes   uint64
	RxPackets uint64
	RxErrors  uint64
	TxBytes   uint64
	TxPackets uint64
	TxErrors  uint64
}

func parseProcNetDev(path string) map[string]procNetDevStat {
	data, err := os.ReadFile(path)
	if err != nil {
		return make(map[string]procNetDevStat)
	}
	return parseProcNetDevContent(string(data))
}

func parseProcNetDevContent(content string) map[string]procNetDevStat {
	result := make(map[string]procNetDevStat)
	scanner := bufio.NewScanner(strings.NewReader(content))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if !strings.Contains(line, ":") || strings.HasPrefix(line, "Inter-") || strings.HasPrefix(line, "face") {
			continue
		}
		parts := strings.SplitN(line, ":", 2)
		if len(parts) != 2 {
			continue
		}
		ifaceName := strings.TrimSpace(parts[0])
		fields := strings.Fields(parts[1])
		if len(fields) < 16 {
			continue
		}

		rxBytes, _ := strconv.ParseUint(fields[0], 10, 64)
		rxPackets, _ := strconv.ParseUint(fields[1], 10, 64)
		rxErrors, _ := strconv.ParseUint(fields[2], 10, 64)
		txBytes, _ := strconv.ParseUint(fields[8], 10, 64)
		txPackets, _ := strconv.ParseUint(fields[9], 10, 64)
		txErrors, _ := strconv.ParseUint(fields[10], 10, 64)

		result[ifaceName] = procNetDevStat{
			RxBytes:   rxBytes,
			RxPackets: rxPackets,
			RxErrors:  rxErrors,
			TxBytes:   txBytes,
			TxPackets: txPackets,
			TxErrors:  txErrors,
		}
	}
	return result
}

func calculateRate(key string, currentRx, currentTx uint64) (rxMBs, txMBs float64) {
	trafficCacheMu.Lock()
	defer trafficCacheMu.Unlock()

	now := time.Now()
	prev, exists := trafficCache[key]
	trafficCache[key] = interfaceSample{
		Timestamp: now,
		RxBytes:   currentRx,
		TxBytes:   currentTx,
	}

	if !exists {
		return 0, 0
	}

	duration := now.Sub(prev.Timestamp).Seconds()
	if duration <= 0.2 {
		return 0, 0
	}

	if currentRx >= prev.RxBytes {
		rxBytesDiff := currentRx - prev.RxBytes
		rxMBs = (float64(rxBytesDiff) / (1024 * 1024)) / duration
	}
	if currentTx >= prev.TxBytes {
		txBytesDiff := currentTx - prev.TxBytes
		txMBs = (float64(txBytesDiff) / (1024 * 1024)) / duration
	}

	return rxMBs, txMBs
}

func isStorageIP(ipStr string) bool {
	return strings.HasPrefix(ipStr, "10.10.100.") || strings.HasPrefix(ipStr, "192.168.253.")
}

// syncCoreDNSStorageHosts updates CoreDNS hosts file with storage domain records.
func syncCoreDNSStorageHosts(report *ClusterStorageNetworkReport) {
	hostsPath := filepath.Join(coredns.CoreDNSDir(), "gubernator.hosts")
	existingBytes, err := os.ReadFile(hostsPath)
	var lines []string
	if err == nil {
		scanner := bufio.NewScanner(bytes.NewReader(existingBytes))
		for scanner.Scan() {
			l := strings.TrimSpace(scanner.Text())
			if l != "" && !strings.Contains(l, ".storage.gbnt.local") && !strings.Contains(l, ".storage.gbnt") {
				lines = append(lines, l)
			}
		}
	} else {
		lines = append(lines, "# Gubernator Auto-Generated CoreDNS Hosts File")
	}

	// Append dedicated storage hosts
	lines = append(lines, "# --- Dedicated Storage Network (GlusterFS) ---")
	for _, n := range report.Nodes {
		if n.StorageIP != "" && n.StorageDNS != "" {
			lines = append(lines, fmt.Sprintf("%-16s %s %s", n.StorageIP, n.StorageDNS, strings.Replace(n.StorageDNS, ".local", "", 1)))
		}
	}

	content := strings.Join(lines, "\n") + "\n"
	if string(existingBytes) != content {
		_ = os.WriteFile(hostsPath, []byte(content), 0644)
		_ = coredns.ReloadConfig()
	}
}

// ExecuteRemoteSSH is a helper to run commands over SSH using Manager private key.
func executeRemoteSSH(nodeIP, command string) (string, error) {
	keyPath := "/data/ssh/id_ed25519"
	if _, err := os.Stat(keyPath); os.IsNotExist(err) {
		home, _ := os.UserHomeDir()
		keyPath = filepath.Join(home, ".ssh", "id_ed25519")
	}

	args := []string{
		"-i", keyPath,
		"-o", "StrictHostKeyChecking=no",
		"-o", "UserKnownHostsFile=/dev/null",
		"-o", "ConnectTimeout=5",
		fmt.Sprintf("ubuntu@%s", nodeIP),
		command,
	}

	cmd := exec.Command("ssh", args...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	if err != nil {
		return "", fmt.Errorf("ssh failed on %s: %w (err: %s)", nodeIP, err, stderr.String())
	}
	return stdout.String(), nil
}
