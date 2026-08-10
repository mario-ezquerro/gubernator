package api

import (
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/mario-ezquerro/gubernator/internal/aqueducts"
	"github.com/mario-ezquerro/gubernator/internal/coredns"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

// @Summary Get CoreDNS Configuration
// @Description Returns the raw text of the Corefile
// @Tags CoreDNS
// @Produce plain
// @Success 200 {string} string "CoreDNS configuration content"
// @Router /v1/coredns/config [get]
func GetCoreDNSConfig(c *gin.Context) {
	content, err := os.ReadFile(coredns.CorefilePath())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read CoreDNS config: " + err.Error()})
		return
	}
	c.String(http.StatusOK, string(content))
}

type UpdateConfigRequest struct {
	Config string `json:"config"`
}

// @Summary Update CoreDNS Configuration
// @Description Overwrites the Corefile and restarts the CoreDNS container
// @Tags CoreDNS
// @Accept json
// @Produce json
// @Param body body UpdateConfigRequest true "New configuration"
// @Success 200 {object} map[string]string
// @Router /v1/coredns/config [put]
func UpdateCoreDNSConfig(c *gin.Context) {
	var req UpdateConfigRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body"})
		return
	}

	if req.Config == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Config cannot be empty"})
		return
	}

	// Write the new config
	if err := os.WriteFile(coredns.CorefilePath(), []byte(req.Config), 0644); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save CoreDNS config: " + err.Error()})
		return
	}

	// Restart CoreDNS to pick up the new Corefile
	if err := coredns.Restart(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Config saved but failed to restart CoreDNS: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "CoreDNS configuration updated successfully"})
}

type CreateCustomDNSRecordRequest struct {
	Domain     string `json:"domain" binding:"required"`
	IP         string `json:"ip" binding:"required"`
	RecordType string `json:"record_type"` // A, AAAA, CNAME, TXT, PTR
	TTL        int    `json:"ttl"`
}

type DigRequest struct {
	Domain     string `json:"domain" binding:"required"`
	RecordType string `json:"record_type"`
}

func GetCoreDNSStatusHandler(c *gin.Context) {
	status := coredns.GetCoreDNSStatusInfo(db.DB)
	c.JSON(http.StatusOK, status)
}

func GetCustomDNSRecordsHandler(c *gin.Context) {
	var records []db.CustomDNSRecord
	if err := db.DB.Order("created_at desc").Find(&records).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch custom DNS records"})
		return
	}
	c.JSON(http.StatusOK, records)
}

func CreateCustomDNSRecordHandler(c *gin.Context) {
	var req CreateCustomDNSRecordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	recType := strings.ToUpper(strings.TrimSpace(req.RecordType))
	if recType == "" {
		recType = "A"
	}
	ttlVal := req.TTL
	if ttlVal <= 0 {
		ttlVal = 60
	}

	record := db.CustomDNSRecord{
		ID:         uuid.New().String(),
		Domain:     strings.TrimSpace(req.Domain),
		IP:         strings.TrimSpace(req.IP),
		RecordType: recType,
		TTL:        ttlVal,
		CreatedAt:  time.Now(),
		UpdatedAt:  time.Now(),
	}

	if err := db.DB.Create(&record).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create custom DNS record"})
		return
	}

	aqueducts.GenerateHostsFile()

	c.JSON(http.StatusCreated, record)
}

func DeleteCustomDNSRecordHandler(c *gin.Context) {
	id := c.Param("id")
	if err := db.DB.Where("id = ?", id).Delete(&db.CustomDNSRecord{}).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete custom DNS record"})
		return
	}

	aqueducts.GenerateHostsFile()

	c.JSON(http.StatusOK, gin.H{"message": "Custom DNS record deleted successfully"})
}

func CoreDNSDigHandler(c *gin.Context) {
	var req DigRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	res, err := coredns.PerformDig(req.Domain, req.RecordType)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, res)
}
