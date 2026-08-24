package storage

import (
	"encoding/base64"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/db"
)

// IsLocalHost checks whether the given IP address corresponds to the local host/manager.
func IsLocalHost(ip string) bool {
	ip = strings.TrimSpace(ip)
	if ip == "" || ip == "localhost" || ip == "127.0.0.1" || ip == "::1" || ip == "local" || ip == "manager" {
		return true
	}
	managerIP := db.GetManagerIP()
	if managerIP != "" && ip == managerIP {
		return true
	}

	// Check against all local interface IPs (e.g. secondary storage NICs, docker bridges)
	ifaces, err := net.Interfaces()
	if err == nil {
		for _, iface := range ifaces {
			addrs, err := iface.Addrs()
			if err != nil {
				continue
			}
			for _, addr := range addrs {
				var currentIP string
				switch v := addr.(type) {
				case *net.IPNet:
					currentIP = v.IP.String()
				case *net.IPAddr:
					currentIP = v.IP.String()
				}
				if currentIP != "" && currentIP == ip {
					return true
				}
			}
		}
	}

	return false
}

// GetTargetHostIPs resolves a target_node string ("all", Node ID, or Node IP) into a list of node IPs.
func GetTargetHostIPs(targetNode string) []string {
	targetNode = strings.TrimSpace(strings.ToLower(targetNode))
	var ips []string

	if targetNode == "" || targetNode == "all" || targetNode == "cluster" {
		// Include local manager first
		managerIP := db.GetManagerIP()
		if managerIP != "" {
			ips = append(ips, managerIP)
		} else {
			ips = append(ips, "127.0.0.1")
		}

		// Query all worker nodes from DB
		if db.DB != nil {
			var nodes []db.Node
			if err := db.DB.Where("status != 'left'").Find(&nodes).Error; err == nil {
				for _, n := range nodes {
					if n.IP != "" && !containsString(ips, n.IP) {
						ips = append(ips, n.IP)
					}
				}
			}
		}
		return ips
	}

	// Lookup by Node ID or role
	if db.DB != nil {
		var node db.Node
		if err := db.DB.Where("id = ? OR ip = ?", targetNode, targetNode).First(&node).Error; err == nil && node.IP != "" {
			return []string{node.IP}
		}
	}

	// Fallback to raw IP
	return []string{targetNode}
}

// ExecuteRemoteScript runs a bash shell script either locally or remotely on a Centurion node via SSH.
func ExecuteRemoteScript(targetIP string, script string) (string, error) {
	if IsLocalHost(targetIP) {
		cmd := exec.Command("sudo", "sh", "-c", script)
		out, err := cmd.CombinedOutput()
		if err != nil {
			cmd2 := exec.Command("sh", "-c", script)
			out2, err2 := cmd2.CombinedOutput()
			if err2 == nil {
				return strings.TrimSpace(string(out2)), nil
			}
		}
		return strings.TrimSpace(string(out)), err
	}

	sshArgs := []string{
		"-o", "UserKnownHostsFile=/dev/null",
		"-o", "StrictHostKeyChecking=no",
		"-o", "ConnectTimeout=6",
	}

	keyCandidates := []string{
		"/home/ubuntu/.ssh/id_ed25519",
		"/home/ubuntu/.ssh/id_rsa",
		"/root/.ssh/id_ed25519",
		"/root/.ssh/id_rsa",
		"/data/id_ed25519",
		"/data/id_rsa",
		"/data/ssh/id_ed25519",
		"/data/ssh/id_rsa",
	}
	if home := os.Getenv("HOME"); home != "" {
		keyCandidates = append([]string{
			filepath.Join(home, ".ssh", "id_ed25519"),
			filepath.Join(home, ".ssh", "id_rsa"),
		}, keyCandidates...)
	}

	for _, k := range keyCandidates {
		if _, err := os.Stat(k); err == nil {
			sshArgs = append(sshArgs, "-i", k)
			break
		}
	}

	sshArgs = append(sshArgs, fmt.Sprintf("ubuntu@%s", targetIP), "sudo", "sh")

	cmd := exec.Command("ssh", sshArgs...)
	cmd.Stdin = strings.NewReader(script)
	out, err := cmd.CombinedOutput()
	outputStr := strings.TrimSpace(string(out))
	if err != nil {
		return outputStr, fmt.Errorf("ssh command failed on node %s: %w (output: %s)", targetIP, err, outputStr)
	}
	return outputStr, nil
}

// GetHostFstab retrieves the raw /etc/fstab content from the specified Centurion node.
func GetHostFstab(targetNode string) (string, string, error) {
	ips := GetTargetHostIPs(targetNode)
	targetIP := "127.0.0.1"
	if len(ips) > 0 {
		targetIP = ips[0]
	}

	if IsLocalHost(targetIP) {
		content, err := GetRawFstab()
		return FstabPath(), content, err
	}

	script := "cat /etc/fstab"
	out, err := ExecuteRemoteScript(targetIP, script)
	if err != nil {
		return "/etc/fstab", "", err
	}
	return "/etc/fstab", out, nil
}

// SaveHostFstab updates the /etc/fstab on the target node(s) with an automated backup.
func SaveHostFstab(targetNode string, rawContent string) error {
	ips := GetTargetHostIPs(targetNode)
	b64Content := base64.StdEncoding.EncodeToString([]byte(rawContent))

	var errs []string
	for _, ip := range ips {
		if IsLocalHost(ip) {
			path := FstabPath()
			// Backup local
			if oldData, err := os.ReadFile(path); err == nil && len(oldData) > 0 {
				backupPath := fmt.Sprintf("%s.bak.%d", path, time.Now().Unix())
				_ = os.WriteFile(backupPath, oldData, 0644)
			}
			if err := os.WriteFile(path, []byte(rawContent), 0644); err != nil {
				errs = append(errs, fmt.Sprintf("local manager (%s): %v", ip, err))
			}
		} else {
			script := fmt.Sprintf(`
if [ -f /etc/fstab ]; then
  cp /etc/fstab /etc/fstab.bak.%d
fi
echo '%s' | base64 -d > /etc/fstab
`, time.Now().Unix(), b64Content)
			if _, err := ExecuteRemoteScript(ip, script); err != nil {
				errs = append(errs, fmt.Sprintf("worker %s: %v", ip, err))
			}
		}
	}

	if len(errs) > 0 {
		return fmt.Errorf("failed to save fstab on some nodes: %s", strings.Join(errs, "; "))
	}
	return nil
}

// SyncMountToTargetNode configures, writes fstab, and executes mount on a target node.
func SyncMountToTargetNode(m db.StorageMount, targetIP string) error {
	if IsLocalHost(targetIP) {
		_ = os.MkdirAll(m.MountPoint, 0755)
		if m.AutoMount {
			_ = appendFstabEntry(m)
		}
		out, err := exec.Command("sudo", "mount", m.MountPoint).CombinedOutput()
		if err != nil {
			out2, err2 := exec.Command("sudo", "mount", "-t", m.FSType, "-o", m.Options, m.Device, m.MountPoint).CombinedOutput()
			if err2 != nil {
				return fmt.Errorf("local mount failed: %v (%s / %s)", err, strings.TrimSpace(string(out)), strings.TrimSpace(string(out2)))
			}
		}
		return nil
	}

	// Prepare remote script
	var scriptBuilder strings.Builder
	scriptBuilder.WriteString(fmt.Sprintf("sudo mkdir -p %s\n", m.MountPoint))

	// Credentials file if any
	if m.CredentialsFile != "" {
		if credData, err := os.ReadFile(m.CredentialsFile); err == nil {
			b64Cred := base64.StdEncoding.EncodeToString(credData)
			scriptBuilder.WriteString("sudo mkdir -p /etc/gbnt/credentials\n")
			scriptBuilder.WriteString(fmt.Sprintf("echo '%s' | base64 -d | sudo tee %s >/dev/null\n", b64Cred, m.CredentialsFile))
			scriptBuilder.WriteString(fmt.Sprintf("sudo chmod 600 %s\n", m.CredentialsFile))
		}
	}

	if m.AutoMount {
		tagStart := fmt.Sprintf("# BEGIN GBNT MOUNT %s", m.ID)
		tagEnd := fmt.Sprintf("# END GBNT MOUNT %s", m.ID)
		fstabLine := fmt.Sprintf("%s\t%s\t%s\t%s\t%d\t%d", m.Device, m.MountPoint, m.FSType, m.Options, m.Dump, m.Pass)
		scriptBuilder.WriteString(fmt.Sprintf(`
if sudo grep -q "%s" /etc/fstab 2>/dev/null; then
  sudo sed -i '/%s/,/%s/d' /etc/fstab
fi
echo "%s (%s)" | sudo tee -a /etc/fstab >/dev/null
echo "%s" | sudo tee -a /etc/fstab >/dev/null
echo "%s" | sudo tee -a /etc/fstab >/dev/null
`, tagStart, tagStart, tagEnd, tagStart, m.Name, fstabLine, tagEnd))
	}

	scriptBuilder.WriteString(fmt.Sprintf("sudo mount %s 2>&1 || sudo mount -a 2>&1\n", m.MountPoint))

	_, err := ExecuteRemoteScript(targetIP, scriptBuilder.String())
	return err
}

// UnmountFromTargetNode unmounts the mount point on a target node.
func UnmountFromTargetNode(mountPoint string, targetIP string) error {
	if IsLocalHost(targetIP) {
		out, err := exec.Command("sudo", "umount", mountPoint).CombinedOutput()
		if err != nil {
			outLazy, errLazy := exec.Command("sudo", "umount", "-l", mountPoint).CombinedOutput()
			if errLazy != nil {
				return fmt.Errorf("local unmount failed: %v (%s / lazy: %s)", err, strings.TrimSpace(string(out)), strings.TrimSpace(string(outLazy)))
			}
		}
		return nil
	}

	script := fmt.Sprintf("sudo umount %s 2>/dev/null || sudo umount -l %s 2>/dev/null || true", mountPoint, mountPoint)
	_, err := ExecuteRemoteScript(targetIP, script)
	return err
}

// DeleteMountFromTargetNode removes fstab entries and unmounts on a target node.
func DeleteMountFromTargetNode(m db.StorageMount, targetIP string) error {
	if IsLocalHost(targetIP) {
		_ = exec.Command("sudo", "umount", "-l", m.MountPoint).Run()
		_ = removeFstabEntry(m.ID)
		if m.CredentialsFile != "" {
			_ = os.Remove(m.CredentialsFile)
		}
		return nil
	}

	tagStart := fmt.Sprintf("# BEGIN GBNT MOUNT %s", m.ID)
	tagEnd := fmt.Sprintf("# END GBNT MOUNT %s", m.ID)
	script := fmt.Sprintf(`
sudo umount -l %s 2>/dev/null || true
if sudo grep -q "%s" /etc/fstab 2>/dev/null; then
  sudo sed -i '/%s/,/%s/d' /etc/fstab
fi
if [ -n "%s" ]; then
  sudo rm -f %s 2>/dev/null || true
fi
`, m.MountPoint, tagStart, tagStart, tagEnd, m.CredentialsFile, m.CredentialsFile)

	_, err := ExecuteRemoteScript(targetIP, script)
	return err
}

// MountAllOnTargetNode runs mount -a on the target node.
func MountAllOnTargetNode(targetIP string) (string, error) {
	if IsLocalHost(targetIP) {
		out, err := exec.Command("mount", "-a").CombinedOutput()
		return strings.TrimSpace(string(out)), err
	}
	return ExecuteRemoteScript(targetIP, "sudo mount -a")
}

func containsString(slice []string, s string) bool {
	for _, item := range slice {
		if item == s {
			return true
		}
	}
	return false
}
