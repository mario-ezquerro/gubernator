package security

import (
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/db"
)

// AdmissionDecision represents the result of an image security evaluation.
type AdmissionDecision struct {
	Allowed        bool     `json:"allowed"`
	Decision       string   `json:"decision"` // "ALLOWED", "WARNING", "BLOCKED"
	Reason         string   `json:"reason"`
	Warnings       []string `json:"warnings"`
	PolicyApplied  string   `json:"policy_applied"`
	Image          string   `json:"image"`
	ScanReport     *db.ImageScan `json:"scan_report,omitempty"`
}

// GetClusterPolicy retrieves the active cluster admission security policy.
func GetClusterPolicy() (*db.SecurityPolicy, error) {
	var policy db.SecurityPolicy
	err := db.DB.First(&policy, "id = ?", "default").Error
	if err != nil {
		// Fallback default
		policy = db.SecurityPolicy{
			ID:                "default",
			Name:              "Cluster Default Security Policy",
			EnforceSignatures: "audit",
			BlockCVESeverity:  "none",
			AllowUnfixedCVE:   true,
			TrustedRegistries: `["docker.io","ghcr.io","quay.io"]`,
			UpdatedAt:         time.Now(),
		}
		db.DB.Create(&policy)
	}
	return &policy, nil
}

// UpdateClusterPolicy updates the cluster admission security policy.
func UpdateClusterPolicy(p *db.SecurityPolicy) error {
	p.ID = "default"
	p.UpdatedAt = time.Now()
	return db.DB.Save(p).Error
}

// EvaluateAdmission evaluates an image deployment against cluster policies and service labels.
func EvaluateAdmission(imageName string, labels map[string]string) *AdmissionDecision {
	imageName = strings.TrimSpace(imageName)
	policy, _ := GetClusterPolicy()
	if policy == nil {
		return &AdmissionDecision{
			Allowed:  true,
			Decision: "ALLOWED",
			Image:    imageName,
		}
	}

	decision := &AdmissionDecision{
		Allowed:       true,
		Decision:      "ALLOWED",
		PolicyApplied: policy.Name,
		Image:         imageName,
		Warnings:      make([]string, 0),
	}

	// 1. Check Signature Enforcement
	enforceSig := policy.EnforceSignatures
	if val, ok := labels["gbnt.security.require-signature"]; ok {
		if strings.ToLower(val) == "true" || val == "1" {
			enforceSig = "enforce"
		} else if strings.ToLower(val) == "false" || val == "0" {
			enforceSig = "disabled"
		}
	}

	// Fetch or trigger scan
	scan, vulns, err := GetScanByImage(imageName)
	if err != nil || scan == nil {
		scan, vulns, _ = TriggerScan(imageName)
	}
	decision.ScanReport = scan

	if enforceSig != "disabled" {
		trustedKeys, _ := ListTrustedKeys()
		sigStatus, _ := VerifyImageSignature(imageName, scan.SignatureStatus, trustedKeys)

		if sigStatus != "verified" {
			if enforceSig == "enforce" {
				decision.Allowed = false
				decision.Decision = "BLOCKED"
				decision.Reason = fmt.Sprintf("Deployment blocked: Image '%s' is not cryptographically signed by a trusted key (Gatekeeper: Strict Signature Enforcement).", imageName)
				slog.Warn("gatekeeper: blocked deployment due to missing signature", "image", imageName)
				return decision
			} else if enforceSig == "audit" {
				decision.Decision = "WARNING"
				decision.Warnings = append(decision.Warnings, fmt.Sprintf("Image '%s' is unsigned. Please sign image before production deployment.", imageName))
			}
		}
	}

	// 2. Check Vulnerability Thresholds
	blockSeverity := policy.BlockCVESeverity
	if val, ok := labels["gbnt.security.max-cve-severity"]; ok {
		blockSeverity = strings.ToLower(val)
	}

	if blockSeverity != "none" && scan != nil {
		if blockSeverity == "critical" && scan.CriticalCount > 0 {
			// Check if unfixed CVEs are allowed
			hasFixableCritical := false
			for _, v := range vulns {
				if v.Severity == "CRITICAL" && v.FixedVersion != "" {
					hasFixableCritical = true
					break
				}
			}

			if !policy.AllowUnfixedCVE || hasFixableCritical {
				decision.Allowed = false
				decision.Decision = "BLOCKED"
				decision.Reason = fmt.Sprintf("Deployment blocked: Image '%s' contains %d CRITICAL vulnerabilities (Gatekeeper: Block on Critical CVEs).", imageName, scan.CriticalCount)
				slog.Warn("gatekeeper: blocked deployment due to critical CVEs", "image", imageName, "critical_count", scan.CriticalCount)
				return decision
			}
		} else if (blockSeverity == "high" || blockSeverity == "medium") && (scan.CriticalCount > 0 || scan.HighCount > 0) {
			decision.Allowed = false
			decision.Decision = "BLOCKED"
			decision.Reason = fmt.Sprintf("Deployment blocked: Image '%s' contains %d High/Critical vulnerabilities exceeding threshold '%s'.", imageName, scan.CriticalCount+scan.HighCount, blockSeverity)
			slog.Warn("gatekeeper: blocked deployment due to high/critical CVEs", "image", imageName, "threshold", blockSeverity)
			return decision
		}
	}

	return decision
}
