package api

import (
	"net/http"

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

	key, err := security.SaveTrustedKey(req.Name, pubPEM, req.IsDefault)
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

	key, err := security.SaveTrustedKey(req.Name, req.PublicKeyPEM, req.IsDefault)
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

// SecurityImageSignHandler signs an image with a provided private key.
func SecurityImageSignHandler(c *gin.Context) {
	var req struct {
		Image      string `json:"image" binding:"required"`
		PrivateKey string `json:"private_key" binding:"required"`
		SignerName string `json:"signer_name"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "image and private_key are required"})
		return
	}

	if req.SignerName == "" {
		req.SignerName = "Cluster Administrator"
	}

	// Sign digest
	sig, err := security.SignImageDigest(req.Image, "sha256:digest", req.PrivateKey, req.SignerName)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to sign image: " + err.Error()})
		return
	}

	// Update or create scan with verified status
	scan, _, _ := security.GetScanByImage(req.Image)
	if scan == nil {
		scan, _, _ = security.TriggerScan(req.Image)
	}
	if scan != nil {
		db.DB.Model(&db.ImageScan{}).Where("id = ?", scan.ID).Updates(map[string]interface{}{
			"signature_status": "verified",
			"signature_signer": req.SignerName,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"message":   "Image signed successfully",
		"image":     req.Image,
		"signature": sig,
		"signer":    req.SignerName,
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
