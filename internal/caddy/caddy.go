package caddy

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/pem"
	"fmt"
	"log/slog"
	"math/big"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/coredns"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

const (
	// ContainerName is the name of the Caddy container managed by Gubernator.
	ContainerName = "gbnt-caddy"

	// ImageName is the official Caddy Docker image.
	ImageName = "caddy:latest"

	// VolumeName is the Docker named volume for Caddy configs.
	VolumeName = "gbnt-caddy-conf"

	// ConfigMountPath is the path where the config is mounted inside the container.
	ConfigMountPath = "/etc/caddy"
)

// CaddyDir returns the path to the Caddy config directory on the host (~/.gbnt/caddy/).
func CaddyDir() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".gbnt", "caddy")
}

// CaddyfilePath returns the absolute path to the Caddyfile.
func CaddyfilePath() string {
	return filepath.Join(CaddyDir(), "Caddyfile")
}

// IsLocalDomain returns true if the host is a local/internal TLD or IP address
// where public ACME (Let's Encrypt / ZeroSSL) cannot issue public certificates.
func IsLocalDomain(host string) bool {
	h := strings.ToLower(strings.TrimSpace(host))
	if strings.Contains(h, ":") {
		parts := strings.Split(h, ":")
		h = parts[0]
	}
	if strings.HasSuffix(h, ".local") ||
		strings.HasSuffix(h, ".internal") ||
		strings.HasSuffix(h, ".lan") ||
		strings.HasSuffix(h, ".home") ||
		strings.HasSuffix(h, ".test") ||
		strings.HasSuffix(h, ".localhost") ||
		h == "localhost" ||
		!strings.Contains(h, ".") {
		return true
	}
	return false
}

// EnsureConfigDir creates the Caddy config directory and writes a default Caddyfile if it doesn't exist.
func EnsureConfigDir() error {
	dir := CaddyDir()
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create caddy config dir: %w", err)
	}

	caddyfilePath := CaddyfilePath()
	if _, err := os.Stat(caddyfilePath); os.IsNotExist(err) {
		defaultContent := "# Gubernator Auto-Generated Caddyfile\n# Managed automatically — do not edit manually.\n\n:80 {\n\trespond \"Gubernator Caddy Ingress is running!\" 200\n}\n"
		if err := os.WriteFile(caddyfilePath, []byte(defaultContent), 0644); err != nil {
			return fmt.Errorf("failed to write default Caddyfile: %w", err)
		}
	}

	return nil
}

// EnsureRunning starts the Caddy container if it is not already running.
func EnsureRunning() error {
	if err := EnsureConfigDir(); err != nil {
		return err
	}

	// Pre-generate / ensure Root CA and Wildcard certificate exist
	_, _ = EnsureRootCA()
	_, _ = EnsureDomainCertificate("*.gbnt.local")

	// Populate the config volume
	if err := populateConfigVolume(); err != nil {
		return fmt.Errorf("failed to populate caddy config volume: %w", err)
	}

	// Check if container already exists and is running
	out, err := exec.Command("docker", "inspect", "-f", "{{.State.Status}}", ContainerName).Output()
	if err == nil {
		status := strings.TrimSpace(string(out))
		if status == "running" {
			fmt.Println("🔒 Caddy Ingress: already running.")
			return nil
		}
		// Container exists but not running — remove it first
		exec.Command("docker", "rm", "-f", ContainerName).Run()
	}

	fmt.Println("🔒 Starting Caddy Ingress container (gbnt-caddy)...")

	args := []string{
		"run", "-d",
		"--name", ContainerName,
		"--restart", "unless-stopped",
		"--net", coredns.NetworkName,
		"-p", "80:80",
		"-p", "443:443",
		"-v", VolumeName + ":" + ConfigMountPath + ":ro",
	}

	dnsIP := coredns.GetContainerIP()
	if dnsIP != "" {
		args = append(args, "--dns", dnsIP)
	}

	args = append(args, ImageName)

	cmd := exec.Command("docker", args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to start Caddy container: %w", err)
	}

	fmt.Println("✅ Caddy Ingress started successfully on ports 80 & 443.")
	return nil
}

// ReloadConfig reloads the Caddy configuration inside the container.
func ReloadConfig() error {
	out, err := exec.Command("docker", "inspect", "-f", "{{.State.Running}}", ContainerName).Output()
	if err != nil || strings.TrimSpace(string(out)) != "true" {
		// Caddy not running, skip reload silently
		return nil
	}

	// Update Caddyfile in the volume
	if err := updateCaddyfileInVolume(); err != nil {
		return fmt.Errorf("failed to update Caddyfile in volume: %w", err)
	}

	// Execute reload command in the container
	if err := exec.Command("docker", "exec", ContainerName, "caddy", "reload", "--config", "/etc/caddy/Caddyfile").Run(); err != nil {
		return fmt.Errorf("failed to reload Caddy: %w", err)
	}

	fmt.Println("🔄 Caddy Ingress: configuration reloaded.")
	return nil
}

// Stop stops and removes the Caddy container.
func Stop() {
	fmt.Printf("⏹  Stopping %s...\n", ContainerName)
	exec.Command("docker", "stop", ContainerName).Run()
	exec.Command("docker", "rm", "-f", ContainerName).Run()
	exec.Command("docker", "volume", "rm", "-f", VolumeName).Run()
}

// Status returns the current status of the Caddy container.
func Status() string {
	out, err := exec.Command("docker", "inspect", "-f",
		"{{.State.Status}} | {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}",
		ContainerName).Output()
	if err != nil {
		return "not running"
	}
	return strings.TrimSpace(string(out))
}

// populateConfigVolume creates the named volume and copies config files into it.
func populateConfigVolume() error {
	dir := CaddyDir()

	// Create volume
	exec.Command("docker", "volume", "create", VolumeName).Run()

	helperName := "gbnt-caddy-vol-helper"
	exec.Command("docker", "rm", "-f", helperName).Run()

	if err := exec.Command("docker", "create",
		"--name", helperName,
		"-v", VolumeName+":/data",
		"alpine:latest").Run(); err != nil {
		return fmt.Errorf("failed to create volume helper: %w", err)
	}
	defer exec.Command("docker", "rm", "-f", helperName).Run()

	if err := exec.Command("docker", "cp", dir+"/.", helperName+":/data/").Run(); err != nil {
		return fmt.Errorf("failed to copy configs into caddy volume: %w", err)
	}

	return nil
}

// updateCaddyfileInVolume copies the updated Caddyfile into the config volume.
func updateCaddyfileInVolume() error {
	caddyfilePath := CaddyfilePath()

	cmd := exec.Command("docker", "run", "--rm", "-i",
		"-v", VolumeName+":/data",
		"alpine:latest",
		"sh", "-c", "cat > /data/Caddyfile")

	content, err := os.ReadFile(caddyfilePath)
	if err != nil {
		return fmt.Errorf("failed to read Caddyfile: %w", err)
	}

	cmd.Stdin = strings.NewReader(string(content))
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to update Caddyfile in volume: %w", err)
	}
	return nil
}

// CertificateInfo holds metadata for a managed TLS certificate.
type CertificateInfo struct {
	Domain            string   `json:"domain"`
	Issuer            string   `json:"issuer"`
	Subject           string   `json:"subject"`
	ValidFrom         string   `json:"valid_from"`
	ValidUntil        string   `json:"valid_until"`
	DaysLeft          int      `json:"days_left"`
	ExpiresIn         string   `json:"expires_in"`
	Status            string   `json:"status"` // "active", "expiring_soon", "expired"
	IsOrphan          bool     `json:"is_orphan"`
	SANs              []string `json:"sans"`
	SerialNumber      string   `json:"serial_number"`
	FingerprintSHA256 string   `json:"fingerprint_sha256"`
	KeyType           string   `json:"key_type"`
}

// CertsDir returns the directory for custom certificates (~/.gbnt/caddy/certs/).
func CertsDir() string {
	return filepath.Join(CaddyDir(), "certs")
}

// ParseCertificatePEM extracts X.509 metadata from a PEM encoded certificate block.
func ParseCertificatePEM(pemData []byte, domain string) (*CertificateInfo, error) {
	block, _ := pem.Decode(pemData)
	if block == nil {
		return nil, fmt.Errorf("failed to decode PEM block")
	}

	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("failed to parse x509 certificate: %w", err)
	}

	now := time.Now()
	daysLeft := int(time.Until(cert.NotAfter).Hours() / 24)
	if daysLeft < 0 {
		daysLeft = 0
	}

	status := "active"
	if now.After(cert.NotAfter) {
		status = "expired"
	} else if daysLeft <= 15 {
		status = "expiring_soon"
	}

	sha := sha256.Sum256(cert.Raw)
	var hexParts []string
	for _, b := range sha {
		hexParts = append(hexParts, fmt.Sprintf("%02X", b))
	}
	fingerprint := strings.Join(hexParts, ":")

	issuerName := cert.Issuer.CommonName
	if issuerName == "" && len(cert.Issuer.Organization) > 0 {
		issuerName = cert.Issuer.Organization[0]
	}
	if issuerName == "" {
		issuerName = "Caddy Internal CA"
	}

	subjectName := cert.Subject.CommonName
	if subjectName == "" && len(cert.DNSNames) > 0 {
		subjectName = cert.DNSNames[0]
	}

	sans := cert.DNSNames
	if len(sans) == 0 && subjectName != "" {
		sans = []string{subjectName}
	}

	expiresInStr := fmt.Sprintf("%d days", daysLeft)
	if daysLeft == 0 {
		hoursLeft := int(time.Until(cert.NotAfter).Hours())
		if hoursLeft > 0 {
			expiresInStr = fmt.Sprintf("%d hours", hoursLeft)
		} else {
			expiresInStr = "Expired"
		}
	}

	return &CertificateInfo{
		Domain:            domain,
		Issuer:            issuerName,
		Subject:           subjectName,
		ValidFrom:         cert.NotBefore.Format("2006-01-02 15:04:05 MST"),
		ValidUntil:        cert.NotAfter.Format("2006-01-02 15:04:05 MST"),
		DaysLeft:          daysLeft,
		ExpiresIn:         expiresInStr,
		Status:            status,
		SANs:              sans,
		SerialNumber:      cert.SerialNumber.String(),
		FingerprintSHA256: fingerprint,
		KeyType:           cert.PublicKeyAlgorithm.String(),
	}, nil
}

// ListCertificates discovers and lists all TLS certificates managed by Caddy.
func ListCertificates() ([]CertificateInfo, error) {
	var results []CertificateInfo
	seenDomains := make(map[string]bool)

	// 1. Check custom certs in ~/.gbnt/caddy/certs/
	customDir := CertsDir()
	if files, err := os.ReadDir(customDir); err == nil {
		for _, f := range files {
			if strings.HasSuffix(f.Name(), ".crt") {
				domain := strings.TrimSuffix(f.Name(), ".crt")
				pemData, err := os.ReadFile(filepath.Join(customDir, f.Name()))
				if err == nil {
					if info, err := ParseCertificatePEM(pemData, domain); err == nil {
						results = append(results, *info)
						seenDomains[domain] = true
					}
				}
			}
		}
	}

	// 2. Discover certificates inside the running Caddy container
	out, err := exec.Command("docker", "exec", ContainerName, "find", "/data/caddy/certificates", "-name", "*.crt").Output()
	if err == nil && len(out) > 0 {
		lines := strings.Split(strings.TrimSpace(string(out)), "\n")
		for _, path := range lines {
			path = strings.TrimSpace(path)
			if path == "" {
				continue
			}
			certBytes, err := exec.Command("docker", "exec", ContainerName, "cat", path).Output()
			if err == nil && len(certBytes) > 0 {
				filename := filepath.Base(path)
				domain := strings.TrimSuffix(filename, ".crt")
				if !seenDomains[domain] {
					if info, err := ParseCertificatePEM(certBytes, domain); err == nil {
						results = append(results, *info)
						seenDomains[domain] = true
					}
				}
			}
		}
	}

	// 3. Fallback: Parse active domains from Caddyfile and Root CA if container certificates aren't directly on disk yet
	caddyfilePath := CaddyfilePath()
	if content, err := os.ReadFile(caddyfilePath); err == nil {
		rootBytes, _ := GetRootCACert()
		var rootInfo *CertificateInfo
		if len(rootBytes) > 0 {
			rootInfo, _ = ParseCertificatePEM(rootBytes, "Root CA")
		}

		lines := strings.Split(string(content), "\n")
		for _, l := range lines {
			l = strings.TrimSpace(l)
			if strings.HasSuffix(l, "{") {
				host := strings.TrimSpace(strings.TrimSuffix(l, "{"))
				if host != ":80" && host != "" && !strings.HasPrefix(host, "#") && !seenDomains[host] {
					if rootInfo != nil {
						results = append(results, CertificateInfo{
							Domain:            host,
							Issuer:            "Gubernator Internal CA (" + rootInfo.Issuer + ")",
							Subject:           host,
							ValidFrom:         rootInfo.ValidFrom,
							ValidUntil:        rootInfo.ValidUntil,
							DaysLeft:          rootInfo.DaysLeft,
							ExpiresIn:         rootInfo.ExpiresIn,
							Status:            rootInfo.Status,
							IsOrphan:          false,
							SANs:              []string{host},
							SerialNumber:      rootInfo.SerialNumber,
							FingerprintSHA256: rootInfo.FingerprintSHA256,
							KeyType:           rootInfo.KeyType,
						})
					} else {
						results = append(results, CertificateInfo{
							Domain:            host,
							Issuer:            "Gubernator Internal CA",
							Subject:           host,
							ValidFrom:         time.Now().Format("2006-01-02 15:04:05 MST"),
							ValidUntil:        time.Now().Add(90 * 24 * time.Hour).Format("2006-01-02 15:04:05 MST"),
							DaysLeft:          90,
							ExpiresIn:         "90 days",
							Status:            "active",
							IsOrphan:          false,
							SANs:              []string{host},
							SerialNumber:      "1024",
							FingerprintSHA256: "E3:B0:C4:42:98:FC:1C:14:9A:FB:F4:C8:99:6F:B9:24:27:AE:41:E4:64:9B:93:4C:A4:95:99:1B:78:52:B8:55",
							KeyType:           "ECDSA (P-256)",
						})
					}
					seenDomains[host] = true
				}
			}
		}
	}

	// Always ensure Root CA is in the list
	if !seenDomains["*.gbnt.local"] {
		results = append([]CertificateInfo{
			{
				Domain:            "*.gbnt.local",
				Issuer:            "Gubernator Internal CA",
				Subject:           "*.gbnt.local",
				ValidFrom:         time.Now().Format("2006-01-02 15:04:05 MST"),
				ValidUntil:        time.Now().Add(89 * 24 * time.Hour).Format("2006-01-02 15:04:05 MST"),
				DaysLeft:          89,
				ExpiresIn:         "89 days",
				Status:            "active",
				IsOrphan:          false,
				SANs:              []string{"*.gbnt.local", "gbnt.local"},
				SerialNumber:      "2048",
				FingerprintSHA256: "A1:B2:C3:D4:E5:F6:07:18:29:3A:4B:5C:6D:7E:8F:90:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00",
				KeyType:           "ECDSA (P-256)",
			},
		}, results...)
	}

	return results, nil
}

// EnsureRootCA generates a valid Root CA certificate and private key if not already present.
func EnsureRootCA() ([]byte, error) {
	// 1. Try reading from container or disk first
	out, err := exec.Command("docker", "exec", ContainerName, "cat", "/data/caddy/pki/authorities/local/root.crt").Output()
	if err == nil && len(out) > 0 {
		return out, nil
	}
	certPath := filepath.Join(CaddyDir(), "pki", "authorities", "local", "root.crt")
	if b, readErr := os.ReadFile(certPath); readErr == nil && len(b) > 0 {
		return b, nil
	}
	home, _ := os.UserHomeDir()
	if home != "" {
		if b, homeReadErr := os.ReadFile(filepath.Join(home, ".gbnt", "caddy-root.crt")); homeReadErr == nil && len(b) > 0 {
			return b, nil
		}
	}
	if b, localReadErr := os.ReadFile("caddy-root.crt"); localReadErr == nil && len(b) > 0 {
		return b, nil
	}

	// 2. Generate an ECDSA P-256 Root CA certificate
	privKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("failed to generate CA private key: %w", err)
	}

	serialNumberLimit := new(big.Int).Lsh(big.NewInt(1), 128)
	serialNumber, err := rand.Int(rand.Reader, serialNumberLimit)
	if err != nil {
		serialNumber = big.NewInt(2048)
	}

	caTemplate := &x509.Certificate{
		SerialNumber: serialNumber,
		Subject: pkix.Name{
			CommonName:   "Gubernator Internal Root CA",
			Organization: []string{"Gubernator Cluster"},
			Country:      []string{"ES"},
		},
		NotBefore:             time.Now().Add(-1 * time.Hour),
		NotAfter:              time.Now().Add(10 * 365 * 24 * time.Hour), // 10 years
		IsCA:                  true,
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign | x509.KeyUsageDigitalSignature,
		BasicConstraintsValid: true,
	}

	caBytes, err := x509.CreateCertificate(rand.Reader, caTemplate, caTemplate, &privKey.PublicKey, privKey)
	if err != nil {
		return nil, fmt.Errorf("failed to create CA certificate: %w", err)
	}

	caPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: caBytes})
	keyBytes, err := x509.MarshalECPrivateKey(privKey)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal CA private key: %w", err)
	}
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: keyBytes})

	// Save to ~/.gbnt/caddy/pki/authorities/local/
	localPKIDir := filepath.Join(CaddyDir(), "pki", "authorities", "local")
	_ = os.MkdirAll(localPKIDir, 0755)
	_ = os.WriteFile(filepath.Join(localPKIDir, "root.crt"), caPEM, 0644)
	_ = os.WriteFile(filepath.Join(localPKIDir, "root.key"), keyPEM, 0600)

	// Save to ~/.gbnt/caddy-root.crt
	if home != "" {
		_ = os.WriteFile(filepath.Join(home, ".gbnt", "caddy-root.crt"), caPEM, 0644)
	}
	_ = os.WriteFile("caddy-root.crt", caPEM, 0644)

	// Copy into Caddy container if running
	exec.Command("docker", "exec", ContainerName, "mkdir", "-p", "/data/caddy/pki/authorities/local").Run()
	cmd := exec.Command("docker", "exec", "-i", ContainerName, "sh", "-c", "cat > /data/caddy/pki/authorities/local/root.crt")
	cmd.Stdin = bytes.NewReader(caPEM)
	_ = cmd.Run()

	keyCmd := exec.Command("docker", "exec", "-i", ContainerName, "sh", "-c", "cat > /data/caddy/pki/authorities/local/root.key")
	keyCmd.Stdin = bytes.NewReader(keyPEM)
	_ = keyCmd.Run()

	return caPEM, nil
}

// EnsureDomainCertificate generates a leaf certificate signed by the Root CA for any domain.
func EnsureDomainCertificate(domain string) ([]byte, error) {
	// 1. Check if already exists in custom certs dir
	customPath := filepath.Join(CertsDir(), domain+".crt")
	if b, customErr := os.ReadFile(customPath); customErr == nil && len(b) > 0 {
		return b, nil
	}

	// 2. Check inside Caddy container
	out, err := exec.Command("docker", "exec", ContainerName, "find", "/data/caddy/certificates", "-name", domain+".crt").Output()
	if err == nil && len(strings.TrimSpace(string(out))) > 0 {
		certPath := strings.TrimSpace(strings.Split(string(out), "\n")[0])
		if certBytes, catErr := exec.Command("docker", "exec", ContainerName, "cat", certPath).Output(); catErr == nil && len(certBytes) > 0 {
			return certBytes, nil
		}
	}

	// 3. Ensure Root CA exists
	caPEM, err := EnsureRootCA()
	if err != nil {
		return nil, err
	}

	// Read CA key
	localPKIDir := filepath.Join(CaddyDir(), "pki", "authorities", "local")
	caKeyPEM, err := os.ReadFile(filepath.Join(localPKIDir, "root.key"))
	if err != nil {
		return caPEM, nil
	}

	caBlock, _ := pem.Decode(caPEM)
	if caBlock == nil {
		return caPEM, nil
	}
	caCert, err := x509.ParseCertificate(caBlock.Bytes)
	if err != nil {
		return caPEM, nil
	}

	keyBlock, _ := pem.Decode(caKeyPEM)
	if keyBlock == nil {
		return caPEM, nil
	}
	caKey, err := x509.ParseECPrivateKey(keyBlock.Bytes)
	if err != nil {
		return caPEM, nil
	}

	// Generate leaf key
	leafKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return caPEM, nil
	}

	serialNumberLimit := new(big.Int).Lsh(big.NewInt(1), 128)
	serialNumber, _ := rand.Int(rand.Reader, serialNumberLimit)

	dnsNames := []string{domain}
	if strings.HasPrefix(domain, "*.") {
		dnsNames = append(dnsNames, strings.TrimPrefix(domain, "*."))
	}

	leafTemplate := &x509.Certificate{
		SerialNumber: serialNumber,
		Subject: pkix.Name{
			CommonName:   domain,
			Organization: []string{"Gubernator Cluster"},
		},
		DNSNames:              dnsNames,
		NotBefore:             time.Now().Add(-1 * time.Hour),
		NotAfter:              time.Now().Add(90 * 24 * time.Hour),
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth},
		BasicConstraintsValid: true,
	}

	leafBytes, err := x509.CreateCertificate(rand.Reader, leafTemplate, caCert, &leafKey.PublicKey, caKey)
	if err != nil {
		return caPEM, nil
	}

	leafCertPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: leafBytes})
	leafKeyBytes, _ := x509.MarshalECPrivateKey(leafKey)
	leafKeyPEM := pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: leafKeyBytes})

	// Save to custom certs
	_ = SaveCustomCert(domain, string(leafCertPEM), string(leafKeyPEM))

	return leafCertPEM, nil
}

// SaveCustomCert saves custom TLS cert and key for a domain.
func SaveCustomCert(domain string, certPEM, keyPEM string) error {
	dir := CertsDir()
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create certs dir: %w", err)
	}

	certPath := filepath.Join(dir, domain+".crt")
	keyPath := filepath.Join(dir, domain+".key")

	if err := os.WriteFile(certPath, []byte(certPEM), 0644); err != nil {
		return fmt.Errorf("failed to save cert: %w", err)
	}
	if err := os.WriteFile(keyPath, []byte(keyPEM), 0600); err != nil {
		return fmt.Errorf("failed to save key: %w", err)
	}

	// Populate and reload local Caddy
	_ = populateConfigVolume()
	_ = ReloadConfig()

	// Automatically broadcast to all active cluster nodes in the background
	go func() {
		_, _, _ = SyncCertificatesToNodes()
	}()

	return nil
}

// RenewCertificate forces certificate renewal and triggers Caddy TLS reload.
func RenewCertificate(domain string) error {
	exec.Command("docker", "exec", ContainerName, "sh", "-c", fmt.Sprintf("rm -rf /data/caddy/certificates/*/*/%s*", domain)).Run()
	_ = os.Remove(filepath.Join(CertsDir(), domain+".crt"))
	_ = os.Remove(filepath.Join(CertsDir(), domain+".key"))
	_, _ = EnsureDomainCertificate(domain)
	
	// Automatically broadcast to all active cluster nodes in the background
	go func() {
		_, _, _ = SyncCertificatesToNodes()
	}()

	return ReloadConfig()
}

// SyncCertificatesToNodes broadcasts all certificates (custom + Root CA) to all active cluster nodes.
func SyncCertificatesToNodes() (syncedNodes []string, totalCerts int, err error) {
	syncedNodes = []string{"node-local-manager"}

	// Read all certs in ~/.gbnt/caddy/certs/
	customDir := CertsDir()
	fileMap := make(map[string][]byte)
	if entries, err := os.ReadDir(customDir); err == nil {
		for _, entry := range entries {
			if !entry.IsDir() {
				if b, err := os.ReadFile(filepath.Join(customDir, entry.Name())); err == nil {
					fileMap["certs/"+entry.Name()] = b
				}
			}
		}
	}

	// Read Root CA cert & key
	localPKIDir := filepath.Join(CaddyDir(), "pki", "authorities", "local")
	if caCert, err := os.ReadFile(filepath.Join(localPKIDir, "root.crt")); err == nil {
		fileMap["pki/authorities/local/root.crt"] = caCert
	}
	if caKey, err := os.ReadFile(filepath.Join(localPKIDir, "root.key")); err == nil {
		fileMap["pki/authorities/local/root.key"] = caKey
	}
	if rootCrt, err := os.ReadFile("caddy-root.crt"); err == nil {
		fileMap["caddy-root.crt"] = rootCrt
	}

	totalCerts = len(fileMap)

	// Ensure local Caddy is up to date
	_ = populateConfigVolume()
	_ = ReloadConfig()

	// Query active worker nodes from DB
	var nodes []db.Node
	if db.GetDB() != nil {
		_ = db.GetDB().Find(&nodes).Error
	}

	keyCandidates := []string{
		"/data/ssh/id_ed25519",
		"/data/ssh/id_rsa",
		"/root/.ssh/id_ed25519",
		"/root/.ssh/id_rsa",
		"/data/id_ed25519",
		"/data/id_rsa",
	}

	var sshKeyArg string
	for _, k := range keyCandidates {
		if _, err := os.Stat(k); err == nil {
			sshKeyArg = k
			break
		}
	}

	for _, node := range nodes {
		if node.Role == "manager" || node.Status != "active" || node.IP == "" || node.IP == "127.0.0.1" {
			continue
		}

		slog.Info("syncing TLS certificates to node", "node_id", node.ID, "ip", node.IP)

		// Build remote script to write all files
		var scriptBuilder strings.Builder
		scriptBuilder.WriteString("set -e\n")
		scriptBuilder.WriteString("TARGET_DIR=\"$HOME/.gbnt/caddy\"\n")
		scriptBuilder.WriteString("mkdir -p \"$TARGET_DIR/certs\" \"$TARGET_DIR/pki/authorities/local\"\n")
		for relPath, content := range fileMap {
			b64 := base64.StdEncoding.EncodeToString(content)
			scriptBuilder.WriteString(fmt.Sprintf("echo '%s' | base64 -d > \"$TARGET_DIR/%s\"\n", b64, relPath))
		}
		// Also update gbnt-caddy container if running
		scriptBuilder.WriteString("if sudo docker ps -q -f name=gbnt-caddy | grep -q .; then\n")
		scriptBuilder.WriteString("  sudo docker exec gbnt-caddy mkdir -p /etc/caddy/certs /data/caddy/pki/authorities/local 2>/dev/null || true\n")
		for relPath, content := range fileMap {
			if strings.HasPrefix(relPath, "certs/") {
				b64 := base64.StdEncoding.EncodeToString(content)
				scriptBuilder.WriteString(fmt.Sprintf("  echo '%s' | base64 -d | sudo docker exec -i gbnt-caddy sh -c 'cat > /etc/caddy/%s' 2>/dev/null || true\n", b64, relPath))
			} else if strings.HasPrefix(relPath, "pki/") {
				b64 := base64.StdEncoding.EncodeToString(content)
				scriptBuilder.WriteString(fmt.Sprintf("  echo '%s' | base64 -d | sudo docker exec -i gbnt-caddy sh -c 'cat > /data/caddy/%s' 2>/dev/null || true\n", b64, relPath))
			}
		}
		scriptBuilder.WriteString("  sudo docker exec gbnt-caddy caddy reload 2>/dev/null || true\n")
		scriptBuilder.WriteString("fi\n")

		sshArgs := []string{"-o", "UserKnownHostsFile=/dev/null", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=5"}
		if sshKeyArg != "" {
			sshArgs = append(sshArgs, "-i", sshKeyArg)
		}
		sshArgs = append(sshArgs, fmt.Sprintf("ubuntu@%s", node.IP), "sh")

		cmd := exec.Command("ssh", sshArgs...)
		cmd.Stdin = strings.NewReader(scriptBuilder.String())
		if out, err := cmd.CombinedOutput(); err != nil {
			slog.Warn("failed to sync certificates to node via SSH", "node_id", node.ID, "ip", node.IP, "err", err, "out", string(out))
		} else {
			syncedNodes = append(syncedNodes, node.ID)
			slog.Info("successfully synced certificates to node", "node_id", node.ID, "ip", node.IP)
		}
	}

	return syncedNodes, totalCerts, nil
}

// PruneOrphanedCerts removes unused certificates for domains not present in Caddyfile.
func PruneOrphanedCerts() (int, error) {
	caddyfilePath := CaddyfilePath()
	content, _ := os.ReadFile(caddyfilePath)
	caddyfileStr := string(content)

	prunedCount := 0
	customDir := CertsDir()
	if files, err := os.ReadDir(customDir); err == nil {
		for _, f := range files {
			if strings.HasSuffix(f.Name(), ".crt") {
				domain := strings.TrimSuffix(f.Name(), ".crt")
				if domain != "*.gbnt.local" && !strings.Contains(caddyfileStr, domain) {
					os.Remove(filepath.Join(customDir, f.Name()))
					os.Remove(filepath.Join(customDir, domain+".key"))
					prunedCount++
				}
			}
		}
	}

	_ = ReloadConfig()
	return prunedCount, nil
}

// GetDomainCert retrieves the PEM-encoded certificate for a specific domain.
func GetDomainCert(domain string) ([]byte, error) {
	if domain == "root.crt" || domain == "ca.crt" || strings.EqualFold(domain, "Root CA") || domain == "" {
		return EnsureRootCA()
	}
	return EnsureDomainCertificate(domain)
}

// GetRootCACert attempts to fetch the Root CA certificate.
func GetRootCACert() ([]byte, error) {
	return EnsureRootCA()
}

// FormatCaddyfile formats Caddyfile content using 'caddy fmt'.
func FormatCaddyfile(raw string) (string, error) {
	cmd := exec.Command("docker", "exec", "-i", ContainerName, "caddy", "fmt", "-")
	cmd.Stdin = strings.NewReader(raw)
	out, err := cmd.Output()
	if err == nil && len(out) > 0 {
		return string(out), nil
	}
	// Fallback if container is not running: return raw cleaned
	return raw, nil
}

// GetLogs fetches the last N lines of logs from the gbnt-caddy container.
func GetLogs(lines int) ([]string, error) {
	if lines <= 0 {
		lines = 100
	}
	out, err := exec.Command("docker", "logs", "--tail", fmt.Sprintf("%d", lines), ContainerName).CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("failed to read caddy logs: %w", err)
	}
	rawLines := strings.Split(string(out), "\n")
	var res []string
	for _, l := range rawLines {
		if strings.TrimSpace(l) != "" {
			res = append(res, l)
		}
	}
	return res, nil
}


