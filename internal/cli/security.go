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

			fmt.Printf("%-32s %-10s %-12s %-8s %-6s %-6s %-6s %-30s\n", "IMAGE", "SIGNATURE", "STATUS", "CRITICAL", "HIGH", "MED", "LOW", "DEPLOYED HOSTS")
			fmt.Println("-------------------------------------------------------------------------------------------------------------------------------------------")
			for _, s := range data.Scans {
				sigBadge := "Unsigned"
				if s.SignatureStatus == "verified" {
					sigBadge = "Verified"
				}
				statusBadge := "Active"
				if !s.InUse {
					statusBadge = "Not in Use"
				}
				hostsStr := strings.Join(s.Hosts, ", ")
				if hostsStr == "" {
					hostsStr = "-"
				}
				if len(hostsStr) > 30 {
					hostsStr = hostsStr[:27] + "..."
				}
				fmt.Printf("%-32s %-10s %-12s %-8d %-6d %-6d %-6d %-30s\n",
					s.ImageName, sigBadge, statusBadge, s.CriticalCount, s.HighCount, s.MediumCount, s.LowCount, hostsStr)
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

var imageUnsignCmd = &cobra.Command{
	Use:   "unsign <image>",
	Short: "Revoke/remove cryptographic signature from an image",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		imageName := args[0]
		reqBody, _ := json.Marshal(map[string]string{
			"image": imageName,
		})

		resp, err := DoAPIRequest("POST", "/v1/security/unsign", bytes.NewReader(reqBody))
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			fmt.Fprintf(os.Stderr, "Failed to unsign image: %s\n", string(body))
			os.Exit(1)
		}

		fmt.Printf("✅ Signature successfully revoked from image '%s' (status: unsigned)\n", imageName)
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

var (
	imageToFlag           string
	imageStackFlag        string
	imageAutoRollbackFlag bool
)

var imageFixCmd = &cobra.Command{
	Use:   "fix <current-image> [--to <target-image>] [--stack <stack-id>]",
	Short: "Auto-remediate vulnerable container image in a stack with safe rollback",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		currentImg := args[0]
		if imageToFlag == "" {
			// Fetch preview and suggestions
			resp, err := DoAPIRequest("GET", "/v1/security/remediate/preview?image="+currentImg, nil)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
				os.Exit(1)
			}
			defer resp.Body.Close()

			var prev security.RemediationPreview
			if err := json.NewDecoder(resp.Body).Decode(&prev); err != nil {
				fmt.Fprintf(os.Stderr, "Failed to parse response: %v\n", err)
				os.Exit(1)
			}

			fmt.Printf("🔍 Auto-Remediation Assessment for: %s\n", currentImg)
			fmt.Printf("Risk Level: %s | %s\n\n", strings.ToUpper(prev.RiskLevel), prev.RiskAssessment)

			if !prev.IsInUse || len(prev.AffectedStacks) == 0 {
				fmt.Printf("⚠️  Image '%s' is not in use by any active stack in the cluster.\n", currentImg)
				fmt.Println("Auto-remediation cannot redeploy an unreferenced container image.")
				fmt.Println("\nTo purge this stale scan report, run:")
				fmt.Printf("  gbnt scan rm %s\n", currentImg)
				fmt.Println("\nTo prune all stale / orphan scan reports across the cluster, run:")
				fmt.Println("  gbnt scan prune")
				return
			}

			fmt.Println("Suggested Patched Versions:")
			for _, v := range prev.SuggestedVersions {
				rec := ""
				if v.IsRecommended {
					rec = " [RECOMMENDED]"
				}
				fmt.Printf("  • %-28s (%s RISK)%s - %s\n", v.Version, strings.ToUpper(v.RiskLevel), rec, v.Description)
			}

			if len(prev.AffectedStacks) > 0 {
				fmt.Println("\nAffected Stacks:")
				for _, st := range prev.AffectedStacks {
					fmt.Printf("  • Stack: %-20s (Service: %s, Replicas: %d)\n", st.StackName, st.ServiceName, st.Replicas)
				}
			}

			fmt.Println("\nTo apply remediation, run:")
			fmt.Printf("  gbnt image fix %s --to <target-image> --stack <stack-id>\n", currentImg)
			return
		}

		if imageStackFlag == "" {
			fmt.Fprintf(os.Stderr, "Error: --stack is required when specifying --to\n")
			os.Exit(1)
		}

		reqBody, _ := json.Marshal(security.RemediationRequest{
			StackID:      imageStackFlag,
			CurrentImage: currentImg,
			TargetImage:  imageToFlag,
			AutoRollback: imageAutoRollbackFlag,
		})

		resp, err := DoAPIRequest("POST", "/v1/security/remediate", bytes.NewReader(reqBody))
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		var result security.RemediationResult
		json.NewDecoder(resp.Body).Decode(&result)

		fmt.Println("🚀 Executing Image Remediation Workflow:")
		for _, log := range result.Logs {
			fmt.Printf("  [%s] %-24s %s\n", log.Timestamp, "["+log.Step+"]", log.Message)
		}

		if result.Success && !result.RolledBack {
			fmt.Printf("\n✅ %s\n", result.Message)
		} else if result.RolledBack {
			fmt.Printf("\n⚠️ %s\n", result.Message)
		} else {
			fmt.Printf("\n❌ Remediation failed: %s\n", result.Message)
			os.Exit(1)
		}
	},
}

var scanPruneCmd = &cobra.Command{
	Use:   "prune",
	Short: "Prune all scan reports for images no longer used in any active stack",
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := DoAPIRequest("POST", "/v1/security/scans/prune-orphans", nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		var result struct {
			Message string `json:"message"`
			Purged  int    `json:"purged"`
		}
		json.NewDecoder(resp.Body).Decode(&result)
		fmt.Printf("🧹 %s (Pruned %d stale scan records)\n", result.Message, result.Purged)
	},
}

var scanRmCmd = &cobra.Command{
	Use:   "rm <id-or-image>",
	Short: "Remove a scan report from the cluster database",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := DoAPIRequest("DELETE", "/v1/security/scans/"+args[0], nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode == http.StatusOK {
			fmt.Printf("✅ Scan report for '%s' purged successfully.\n", args[0])
		} else {
			fmt.Fprintf(os.Stderr, "Failed to purge scan for '%s'.\n", args[0])
		}
	},
}

var (
	ensFormatFlag string
	ensReportFlag bool
)

var ensCmd = &cobra.Command{
	Use:   "ens",
	Short: "Audit cluster compliance with Spanish ENS (RD 311/2022)",
	Run: func(cmd *cobra.Command, args []string) {
		resp, err := DoAPIRequest("GET", "/v1/security/ens/status", nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to connect to Manager: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			fmt.Fprintf(os.Stderr, "Failed to evaluate ENS compliance: %s\n", string(body))
			os.Exit(1)
		}

		var s security.ENSSummary
		if err := json.NewDecoder(resp.Body).Decode(&s); err != nil {
			fmt.Fprintf(os.Stderr, "Failed to parse response: %v\n", err)
			os.Exit(1)
		}

		if ensReportFlag || ensFormatFlag == "markdown" || ensFormatFlag == "md" {
			reportResp, err := DoAPIRequest("GET", "/v1/security/ens/report", nil)
			if err == nil && reportResp.StatusCode == http.StatusOK {
				defer reportResp.Body.Close()
				body, _ := io.ReadAll(reportResp.Body)
				fmt.Println(string(body))
				return
			}
		}

		if ensFormatFlag == "json" {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			_ = enc.Encode(s)
			return
		}

		// Formatted terminal summary
		fmt.Println("=========================================================================================")
		fmt.Printf("🏛  ESQUEMA NACIONAL DE SEGURIDAD (ENS — RD 311/2022) | PUNTUACIÓN DE CONFORMIDAD\n")
		fmt.Println("=========================================================================================")
		fmt.Printf("  Categoría Alcanzada:   %s\n", s.OverallCategory)
		fmt.Printf("  Cumplimiento BÁSICO:   %.1f%%\n", s.BasicoScore)
		fmt.Printf("  Cumplimiento MEDIO:    %.1f%%\n", s.MedioScore)
		fmt.Printf("  Cumplimiento ALTO:     %.1f%%\n", s.AltoScore)
		fmt.Printf("  Medidas Evaluadas:     %d (%d Conformes, %d Parciales, %d No Conformes)\n", s.TotalMeasures, s.CompliantCount, s.PartialCount, s.NonCompliantCount)
		fmt.Println("-----------------------------------------------------------------------------------------")
		fmt.Printf("%-10s %-32s %-12s %-8s %-30s\n", "ID", "MEDIDA", "ESTADO", "SCORE", "EVIDENCIA TÉCNICA")
		fmt.Println("-----------------------------------------------------------------------------------------")
		for _, m := range s.Measures {
			statusStr := "❌ No Cumple"
			if m.Status == security.ENSStatusCompliant {
				statusStr = "✅ Cumple"
			} else if m.Status == security.ENSStatusPartial {
				statusStr = "⚠️ Parcial"
			}
			evid := m.Evidence
			if len(evid) > 40 {
				evid = evid[:37] + "..."
			}
			name := m.Name
			if len(name) > 30 {
				name = name[:27] + "..."
			}
			fmt.Printf("%-10s %-32s %-12s %-8.0f%% %-30s\n", m.ID, name, statusStr, m.Score, evid)
		}
		fmt.Println("=========================================================================================")
		fmt.Println("Tip: Ejecuta 'gbnt security ens --report' para ver el informe técnico completo de auditoría.")
	},
}

func init() {
	ensCmd.Flags().StringVarP(&ensFormatFlag, "format", "f", "table", "Output format (table, json, markdown)")
	ensCmd.Flags().BoolVarP(&ensReportFlag, "report", "r", false, "Display full technical compliance audit report")

	sbomCmd.Flags().StringVarP(&sbomFormatFlag, "format", "f", "cyclonedx-json", "SBOM format (cyclonedx-json, spdx-json)")

	imageSignCmd.Flags().StringVarP(&imageKeyFlag, "key", "k", "", "Path to PEM-encoded ECDSA private key")
	imageSignCmd.Flags().StringVarP(&imageSignerFlag, "signer", "s", "Cluster Administrator", "Signer identity name")
	imageCmd.AddCommand(imageSignCmd)
	imageCmd.AddCommand(imageVerifyCmd)
	imageCmd.AddCommand(imageUnsignCmd)

	imageFixCmd.Flags().StringVarP(&imageToFlag, "to", "t", "", "Target upgraded image tag (e.g. postgres:16-alpine)")
	imageFixCmd.Flags().StringVarP(&imageStackFlag, "stack", "s", "", "Target Stack ID to modify and redeploy")
	imageFixCmd.Flags().BoolVar(&imageAutoRollbackFlag, "auto-rollback", true, "Enable automated rollback if updated container fails")
	imageCmd.AddCommand(imageFixCmd)

	scanCmd.AddCommand(scanPruneCmd)
	scanCmd.AddCommand(scanRmCmd)

	securityKeyCmd.AddCommand(securityKeyLsCmd)
	securityCmd.AddCommand(securityPolicyCmd)
	securityCmd.AddCommand(securityKeyCmd)
	securityCmd.AddCommand(ensCmd)

	rootCmd.AddCommand(scanCmd)
	rootCmd.AddCommand(sbomCmd)
	rootCmd.AddCommand(imageCmd)
	rootCmd.AddCommand(securityCmd)
	rootCmd.AddCommand(ensCmd)
}

