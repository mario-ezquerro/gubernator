package api

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/mario-ezquerro/gubernator/internal/security"
)

// SecurityScansListHandler returns all vulnerability scan reports.
func SecurityScansListHandler(c *gin.Context) {
	scans, err := security.ListScans()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	summary, _ := security.GetSecuritySummary()
	c.JSON(http.StatusOK, gin.H{
		"scans":   scans,
		"summary": summary,
	})
}

// SecurityScanDetailsHandler returns details and CVEs for a specific scan ID.
func SecurityScanDetailsHandler(c *gin.Context) {
	id := c.Param("id")
	scan, vulns, err := security.GetScanDetails(id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Scan report not found: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"scan":            scan,
		"vulnerabilities": vulns,
	})
}

// SecurityScanTriggerHandler triggers a new scan for an image.
func SecurityScanTriggerHandler(c *gin.Context) {
	var req struct {
		Image string `json:"image" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "image field is required"})
		return
	}

	scan, vulns, err := security.TriggerScan(req.Image)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":         "Scan completed successfully",
		"scan":            scan,
		"vulnerabilities": vulns,
	})
}

// SecurityScanSyncAllHandler rescans all cluster images.
func SecurityScanSyncAllHandler(c *gin.Context) {
	scans, err := security.SyncAllClusterImages()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	summary, _ := security.GetSecuritySummary()
	c.JSON(http.StatusOK, gin.H{
		"message": "All images scanned successfully",
		"scans":   scans,
		"summary": summary,
	})
}

// SecurityScanDeleteHandler removes a specific scan report and its CVEs from the database.
func SecurityScanDeleteHandler(c *gin.Context) {
	id := c.Param("id")
	if err := security.DeleteScan(id); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete scan: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"message": "Scan report purged successfully",
		"id":      id,
	})
}

// SecurityScanPruneOrphansHandler purges all scans for images no longer used in any active stack.
func SecurityScanPruneOrphansHandler(c *gin.Context) {
	count, err := security.PurgeOrphanScans()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to prune orphan scans: " + err.Error()})
		return
	}
	scans, _ := security.ListScans()
	summary, _ := security.GetSecuritySummary()
	c.JSON(http.StatusOK, gin.H{
		"message": "Pruned orphan scans successfully",
		"purged":  count,
		"scans":   scans,
		"summary": summary,
	})
}

// SecuritySBOMGetHandler retrieves or exports an image's SBOM.
func SecuritySBOMGetHandler(c *gin.Context) {
	image := c.Query("image")
	if image == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "image query parameter required"})
		return
	}
	format := c.DefaultQuery("format", "cyclonedx-json")

	rawSBOM, err := security.ExportSBOM(image, format)
	if err != nil {
		// If not found, trigger scan and generate it
		_, _, scanErr := security.TriggerScan(image)
		if scanErr != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": scanErr.Error()})
			return
		}
		rawSBOM, err = security.ExportSBOM(image, format)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	c.Data(http.StatusOK, "application/json", rawSBOM)
}

// SecurityKeysListHandler returns trusted public signing keys.
func SecurityKeysListHandler(c *gin.Context) {
	keys, err := security.ListTrustedKeys()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"keys": keys})
}

// SecurityKeyGenerateHandler creates a new ECDSA Cosign keypair.
func SecurityKeyGenerateHandler(c *gin.Context) {
	var req struct {
		Name      string `json:"name" binding:"required"`
		IsDefault bool   `json:"is_default"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "name is required"})
		return
	}

	pubPEM, privPEM, err := security.GenerateCosignKeypair(req.Name)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	key, err := security.SaveTrustedKey(req.Name, pubPEM, privPEM, req.IsDefault)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":     "Keypair generated successfully",
		"key":         key,
		"public_pem":  pubPEM,
		"private_pem": privPEM,
	})
}

// SecurityKeySaveHandler imports a trusted public signing key.
func SecurityKeySaveHandler(c *gin.Context) {
	var req struct {
		Name         string `json:"name" binding:"required"`
		PublicKeyPEM string `json:"public_key_pem" binding:"required"`
		IsDefault    bool   `json:"is_default"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "name and public_key_pem are required"})
		return
	}

	key, err := security.SaveTrustedKey(req.Name, req.PublicKeyPEM, "", req.IsDefault)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Trusted key imported successfully",
		"key":     key,
	})
}

// SecurityKeyDeleteHandler deletes a trusted public signing key.
func SecurityKeyDeleteHandler(c *gin.Context) {
	id := c.Param("id")
	if err := security.DeleteTrustedKey(id); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Key deleted successfully"})
}

// SecurityImageSignHandler signs an image with a provided private key or in-cluster key ID.
func SecurityImageSignHandler(c *gin.Context) {
	var req struct {
		Image      string `json:"image" binding:"required"`
		KeyID      string `json:"key_id"`
		PrivateKey string `json:"private_key"`
		SignerName string `json:"signer_name"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "image is required"})
		return
	}

	// 1. Resolve private key from KeyID or default cluster key if not explicitly passed
	if req.PrivateKey == "" && req.KeyID != "" {
		key, err := security.GetTrustedKeyByID(req.KeyID)
		if err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "Signing key not found: " + err.Error()})
			return
		}
		if key.PrivateKeyPEM == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Selected key does not contain a private key; please provide private_key manually"})
			return
		}
		req.PrivateKey = key.PrivateKeyPEM
		if req.SignerName == "" {
			req.SignerName = key.Name
		}
	}

	if req.PrivateKey == "" {
		// Fallback to default cluster key
		defKey, err := security.GetDefaultSigningKey()
		if err == nil && defKey != nil && defKey.PrivateKeyPEM != "" {
			req.PrivateKey = defKey.PrivateKeyPEM
			if req.SignerName == "" {
				req.SignerName = defKey.Name
			}
		}
	}

	if req.PrivateKey == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Private key is required; please specify private_key or select a cluster key with private key stored"})
		return
	}

	if req.SignerName == "" {
		req.SignerName = "Cluster Administrator"
	}

	// 2. Discover cryptographic digest of image via Docker
	digest := security.ResolveImageDigest(req.Image)

	// 3. Sign digest using ECDSA private key
	sig, err := security.SignImageDigest(req.Image, digest, req.PrivateKey, req.SignerName)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to sign image: " + err.Error()})
		return
	}

	// 4. Update or trigger scan with verified status
	scan, _, _ := security.GetScanByImage(req.Image)
	if scan == nil {
		scan, _, _ = security.TriggerScan(req.Image)
	}
	if scan != nil {
		db.DB.Model(&db.ImageScan{}).Where("id = ?", scan.ID).Updates(map[string]interface{}{
			"signature_status": "verified",
			"signature_signer": req.SignerName,
			"image_digest":     digest,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"message":   "Image signed successfully",
		"image":     req.Image,
		"digest":    digest,
		"signature": sig,
		"signer":    req.SignerName,
	})
}

// SecurityImageUnsignHandler revokes the signature of an image.
func SecurityImageUnsignHandler(c *gin.Context) {
	var req struct {
		Image string `json:"image" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "image field is required"})
		return
	}

	if err := security.RevokeImageSignature(req.Image); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to revoke signature: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Image signature successfully revoked",
		"image":   req.Image,
		"status":  "unsigned",
	})
}

// SecurityPolicyGetHandler returns active cluster admission policy.
func SecurityPolicyGetHandler(c *gin.Context) {
	policy, err := security.GetClusterPolicy()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"policy": policy})
}

// SecurityPolicySaveHandler updates cluster admission policy.
func SecurityPolicySaveHandler(c *gin.Context) {
	var policy db.SecurityPolicy
	if err := c.ShouldBindJSON(&policy); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := security.UpdateClusterPolicy(&policy); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Security policy updated successfully",
		"policy":  policy,
	})
}

// SecurityAdmissionEvaluateHandler evaluates whether an image can be deployed under current policies.
func SecurityAdmissionEvaluateHandler(c *gin.Context) {
	var req struct {
		Image  string            `json:"image" binding:"required"`
		Labels map[string]string `json:"labels"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "image is required"})
		return
	}

	decision := security.EvaluateAdmission(req.Image, req.Labels)
	c.JSON(http.StatusOK, gin.H{"decision": decision})
}

// SecurityRemediatePreviewHandler returns suggested upgrade versions and risk analysis.
func SecurityRemediatePreviewHandler(c *gin.Context) {
	image := strings.TrimSpace(c.Query("image"))
	if image == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "image query parameter is required"})
		return
	}

	preview, err := security.PreviewRemediation(image)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, preview)
}

// SecurityRemediateExecuteHandler applies atomic image upgrade in a stack with automated rollback protection.
func SecurityRemediateExecuteHandler(c *gin.Context) {
	var req security.RemediationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.StackID == "" || req.CurrentImage == "" || req.TargetImage == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "stack_id, current_image, and target_image are required"})
		return
	}

	result, err := security.RemediateImageInStack(req.StackID, req.CurrentImage, req.TargetImage, req.AutoRollback)
	if err != nil && result == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, result)
}
