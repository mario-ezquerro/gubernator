package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"

	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/mario-ezquerro/gubernator/internal/security"
	"github.com/spf13/cobra"
)

// Scan command
var scanCmd = &cobra.Command{
	Use:   "scan [image]",
	Short: "Scan container images for known vulnerabilities (CVEs)",
	Run: func(cmd *cobra.Command, args []string) {
		if len(args) == 0 {
			// List all scans
			resp, err := DoAPIRequest("GET", "/v1/security/scans", nil)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
				os.Exit(1)
			}
			defer resp.Body.Close()

			var data struct {
				Scans   []db.ImageScan            `json:"scans"`
				Summary *security.SecuritySummary `json:"summary"`
			}
			if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
				fmt.Fprintf(os.Stderr, "Failed to parse response: %v\n", err)
				os.Exit(1)
			}

			if len(data.Scans) == 0 {
				fmt.Println("No image scans found. Run 'gbnt scan <image>' to scan an image.")
				return
			}

			fmt.Printf("%-35s %-10s %-8s %-6s %-6s %-6s %-12s\n", "IMAGE", "SIGNATURE", "CRITICAL", "HIGH", "MED", "LOW", "SCANNED")
			fmt.Println("---------------------------------------------------------------------------------------------------------")
			for _, s := range data.Scans {
				sigBadge := "Unsigned"
				if s.SignatureStatus == "verified" {
					sigBadge = "Verified"
				}
				scannedStr := s.ScannedAt.Format("2006-01-02 15:04")
				fmt.Printf("%-35s %-10s %-8d %-6d %-6d %-6d %-12s\n",
					s.ImageName, sigBadge, s.CriticalCount, s.HighCount, s.MediumCount, s.LowCount, scannedStr)
			}
			return
		}

		imageName := args[0]
		reqBody, _ := json.Marshal(map[string]string{"image": imageName})
		resp, err := DoAPIRequest("POST", "/v1/security/scans/trigger", bytes.NewReader(reqBody))
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			fmt.Fprintf(os.Stderr, "Scan failed: %s\n", string(body))
			os.Exit(1)
		}

		var result struct {
			Message         string                  `json:"message"`
			Scan            db.ImageScan            `json:"scan"`
			Vulnerabilities []db.ImageVulnerability `json:"vulnerabilities"`
		}
		json.NewDecoder(resp.Body).Decode(&result)

		fmt.Printf("🔍 Security Scan Report for: %s\n", imageName)
		fmt.Printf("Status: Signature=%s | Critical=%d | High=%d | Medium=%d | Low=%d\n\n",
			result.Scan.SignatureStatus, result.Scan.CriticalCount, result.Scan.HighCount, result.Scan.MediumCount, result.Scan.LowCount)

		if len(result.Vulnerabilities) == 0 {
			fmt.Println("✅ No vulnerabilities detected!")
			return
		}

		fmt.Printf("%-16s %-10s %-6s %-25s %-15s %-15s\n", "CVE ID", "SEVERITY", "CVSS", "PACKAGE", "INSTALLED", "FIXED IN")
		fmt.Println("---------------------------------------------------------------------------------------------------")
		for _, v := range result.Vulnerabilities {
			fixed := v.FixedVersion
			if fixed == "" {
				fixed = "None"
			}
			fmt.Printf("%-16s %-10s %-6.1f %-25s %-15s %-15s\n",
				v.CVEID, v.Severity, v.CVSSScore, v.PackageName, v.InstalledVersion, fixed)
		}
	},
}

// SBOM command
var sbomFormatFlag string

var sbomCmd = &cobra.Command{
	Use:   "sbom <image>",
	Short: "Generate and export Software Bill of Materials (SBOM) for an image",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		imageName := args[0]
		url := fmt.Sprintf("/v1/security/sbom?image=%s&format=%s", imageName, sbomFormatFlag)
		resp, err := DoAPIRequest("GET", url, nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			fmt.Fprintf(os.Stderr, "Failed to get SBOM: %s\n", string(body))
			os.Exit(1)
		}

		body, _ := io.ReadAll(resp.Body)
		fmt.Println(string(body))
	},
}

// Image command group
var imageCmd = &cobra.Command{
	Use:   "image",
	Short: "Manage container image signing and verification (Cosign)",
}

var imageKeyFlag string
var imageSignerFlag string

var imageSignCmd = &cobra.Command{
	Use:   "sign <image>",
	Short: "Cryptographically sign an image with an ECDSA private key",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		imageName := args[0]
		var privKeyPEM string

		if imageKeyFlag != "" {
			data, err := os.ReadFile(imageKeyFlag)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Failed to read private key file: %v\n", err)
				os.Exit(1)
			}
			privKeyPEM = string(data)
		} else {
			// Automatically generate or use in-cluster key
			_, privPEM, err := security.GenerateCosignKeypair("cli-auto-key")
			if err != nil {
				fmt.Fprintf(os.Stderr, "Failed to generate signing key: %v\n", err)
				os.Exit(1)
			}
			privKeyPEM = privPEM
		}

		reqBody, _ := json.Marshal(map[string]string{
			"image":       imageName,
			"private_key": privKeyPEM,
			"signer_name": imageSignerFlag,
		})

		resp, err := DoAPIRequest("POST", "/v1/security/sign", bytes.NewReader(reqBody))
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			fmt.Fprintf(os.Stderr, "Failed to sign image: %s\n", string(body))
			os.Exit(1)
		}

		fmt.Printf("✅ Image '%s' signed successfully by '%s'!\n", imageName, imageSignerFlag)
	},
}

var imageVerifyCmd = &cobra.Command{
	Use:   "verify <image>",
	Short: "Verify cryptographic signature of an image against trusted keys",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		imageName := args[0]
		reqBody, _ := json.Marshal(map[string]string{"image": imageName})
		resp, err := DoAPIRequest("POST", "/v1/security/evaluate", bytes.NewReader(reqBody))
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		var result struct {
			Decision security.AdmissionDecision `json:"decision"`
		}
		json.NewDecoder(resp.Body).Decode(&result)

		if result.Decision.Allowed {
			fmt.Printf("✅ Image '%s' passed admission verification: %s\n", imageName, result.Decision.Decision)
		} else {
			fmt.Printf("❌ Image '%s' REJECTED: %s\n", imageName, result.Decision.Reason)
		}
	},
}

// Security command group
var securityCmd = &cobra.Command{
	Use:   "security",
	Short: "Manage cluster security policies and trusted signing keys",
}

var securityPolicyCmd = &cobra.Command{
	Use:   "policy",
	Short: "View or update cluster security admission policies",
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := DoAPIRequest("GET", "/v1/security/policy", nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		var result struct {
			Policy db.SecurityPolicy `json:"policy"`
		}
		json.NewDecoder(resp.Body).Decode(&result)

		p := result.Policy
		fmt.Printf("📜 Cluster Admission Security Policy:\n")
		fmt.Printf("  • Enforce Signatures:    %s\n", strings.ToUpper(p.EnforceSignatures))
		fmt.Printf("  • Block on CVE Severity: %s\n", strings.ToUpper(p.BlockCVESeverity))
		fmt.Printf("  • Allow Unfixed CVEs:    %v\n", p.AllowUnfixedCVE)
		fmt.Printf("  • Trusted Registries:    %s\n", p.TrustedRegistries)
		fmt.Printf("  • Last Updated:          %s\n", p.UpdatedAt.Format("2006-01-02 15:04:05"))
	},
}

var securityKeyCmd = &cobra.Command{
	Use:   "key",
	Short: "Manage trusted public signing keys",
}

var securityKeyLsCmd = &cobra.Command{
	Use:   "ls",
	Short: "List trusted public signing keys",
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := DoAPIRequest("GET", "/v1/security/keys", nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		var result struct {
			Keys []db.TrustedSigningKey `json:"keys"`
		}
		json.NewDecoder(resp.Body).Decode(&result)

		if len(result.Keys) == 0 {
			fmt.Println("No trusted signing keys found.")
			return
		}

		fmt.Printf("%-15s %-25s %-15s %-10s %-20s\n", "ID", "NAME", "KEY TYPE", "DEFAULT", "CREATED AT")
		fmt.Println("---------------------------------------------------------------------------------------------")
		for _, k := range result.Keys {
			defStr := "No"
			if k.IsDefault {
				defStr = "Yes"
			}
			fmt.Printf("%-15s %-25s %-15s %-10s %-20s\n",
				k.ID, k.Name, k.KeyType, defStr, k.CreatedAt.Format("2006-01-02 15:04"))
		}
	},
}

func init() {
	sbomCmd.Flags().StringVarP(&sbomFormatFlag, "format", "f", "cyclonedx-json", "SBOM format (cyclonedx-json, spdx-json)")

	imageSignCmd.Flags().StringVarP(&imageKeyFlag, "key", "k", "", "Path to PEM-encoded ECDSA private key")
	imageSignCmd.Flags().StringVarP(&imageSignerFlag, "signer", "s", "Cluster Administrator", "Signer identity name")
	imageCmd.AddCommand(imageSignCmd)
	imageCmd.AddCommand(imageVerifyCmd)

	securityKeyCmd.AddCommand(securityKeyLsCmd)
	securityCmd.AddCommand(securityPolicyCmd)
	securityCmd.AddCommand(securityKeyCmd)

	rootCmd.AddCommand(scanCmd)
	rootCmd.AddCommand(sbomCmd)
	rootCmd.AddCommand(imageCmd)
	rootCmd.AddCommand(securityCmd)
}
