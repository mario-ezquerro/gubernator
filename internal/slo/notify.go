package slo

import (
	"bytes"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"net/smtp"
	"strconv"
	"time"

	"gorm.io/gorm"

	"github.com/mario-ezquerro/gubernator/internal/db"
)

const NotificationConfigID = "default"

// GetNotificationConfig retrieves or initializes the SLO alert notification settings.
func GetNotificationConfig(gormDB *gorm.DB) (*db.SLONotificationConfig, error) {
	var cfg db.SLONotificationConfig
	err := gormDB.First(&cfg, "id = ?", NotificationConfigID).Error
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			cfg = db.SLONotificationConfig{
				ID:                 NotificationConfigID,
				EnableEmail:        false,
				SMTPHost:           "smtp.gmail.com",
				SMTPPort:           587,
				SMTPUser:           "",
				SMTPPass:           "",
				FromEmail:          "alerts@gubernator.local",
				ToEmail:            "",
				EnableWebhook:      false,
				WebhookURL:         "",
				NotifyOnExhaustion: true,
				NotifyOnBurn:       true,
				UpdatedAt:          time.Now(),
			}
			_ = gormDB.Create(&cfg).Error
			return &cfg, nil
		}
		return nil, err
	}
	return &cfg, nil
}

// SaveNotificationConfig updates the SLO alert notification settings.
func SaveNotificationConfig(gormDB *gorm.DB, updated *db.SLONotificationConfig) error {
	updated.ID = NotificationConfigID
	updated.UpdatedAt = time.Now()
	return gormDB.Save(updated).Error
}

// SendEmailAlert sends an email alert via SMTP.
func SendEmailAlert(cfg *db.SLONotificationConfig, subject, body string) error {
	if cfg.SMTPHost == "" || cfg.ToEmail == "" {
		return fmt.Errorf("SMTP host or recipient email not configured")
	}

	addr := net.JoinHostPort(cfg.SMTPHost, strconv.Itoa(cfg.SMTPPort))
	from := cfg.FromEmail
	if from == "" {
		from = "gubernator-alerts@local"
	}

	header := fmt.Sprintf("From: %s\r\nTo: %s\r\nSubject: %s\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n", from, cfg.ToEmail, subject)
	message := []byte(header + body)

	var auth smtp.Auth
	if cfg.SMTPUser != "" && cfg.SMTPPass != "" {
		auth = smtp.PlainAuth("", cfg.SMTPUser, cfg.SMTPPass, cfg.SMTPHost)
	}

	// Try standard SendMail first
	err := smtp.SendMail(addr, auth, from, []string{cfg.ToEmail}, message)
	if err != nil && cfg.SMTPPort == 465 {
		// Fallback for SSL (port 465)
		tlsConfig := &tls.Config{InsecureSkipVerify: true, ServerName: cfg.SMTPHost}
		conn, tlsErr := tls.Dial("tcp", addr, tlsConfig)
		if tlsErr != nil {
			return fmt.Errorf("TLS dial failed: %w (standard error: %v)", tlsErr, err)
		}
		client, clientErr := smtp.NewClient(conn, cfg.SMTPHost)
		if clientErr != nil {
			return fmt.Errorf("SMTP client failed: %w", clientErr)
		}
		defer client.Quit()

		if auth != nil {
			if errAuth := client.Auth(auth); errAuth != nil {
				return fmt.Errorf("SMTP auth failed: %w", errAuth)
			}
		}
		if errMail := client.Mail(from); errMail != nil {
			return fmt.Errorf("SMTP mail from failed: %w", errMail)
		}
		if errRcpt := client.Rcpt(cfg.ToEmail); errRcpt != nil {
			return fmt.Errorf("SMTP rcpt to failed: %w", errRcpt)
		}
		w, errData := client.Data()
		if errData != nil {
			return fmt.Errorf("SMTP data failed: %w", errData)
		}
		_, _ = w.Write(message)
		_ = w.Close()
		return nil
	}

	return err
}

// SendWebhookAlert posts JSON alert payloads to Webhooks (Slack/Discord/Teams/Custom).
func SendWebhookAlert(cfg *db.SLONotificationConfig, subject, details string, isSlack, isDiscord bool) error {
	if cfg.WebhookURL == "" {
		return fmt.Errorf("webhook URL is empty")
	}

	var payload map[string]interface{}
	if isDiscord {
		payload = map[string]interface{}{
			"content": fmt.Sprintf("**%s**\n%s", subject, details),
		}
	} else {
		// Slack & generic default payload
		payload = map[string]interface{}{
			"text": fmt.Sprintf("*%s*\n%s", subject, details),
			"attachments": []map[string]interface{}{
				{
					"color": "#E53E3E",
					"title": subject,
					"text":  details,
					"ts":    time.Now().Unix(),
				},
			},
		}
	}

	buf, err := json.Marshal(payload)
	if err != nil {
		return err
	}

	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Post(cfg.WebhookURL, "application/json", bytes.NewBuffer(buf))
	if err != nil {
		return fmt.Errorf("webhook POST failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("webhook returned status %d", resp.StatusCode)
	}

	return nil
}

// DispatchTestNotification sends a test email or webhook to verify channel settings.
func DispatchTestNotification(gormDB *gorm.DB, channel string) (string, error) {
	cfg, err := GetNotificationConfig(gormDB)
	if err != nil {
		return "", err
	}

	subject := "🚨 [Gubernator] Test SLO Alert Notification"
	details := fmt.Sprintf("This is a test SLO Alert from Gubernator Cluster Management System.\nTime: %s\nStatus: Verified OK.", time.Now().Format(time.RFC1123))

	switch channel {
	case "email":
		if !cfg.EnableEmail {
			return "", fmt.Errorf("email notifications are disabled in settings")
		}
		if err := SendEmailAlert(cfg, subject, details); err != nil {
			return "", fmt.Errorf("failed to send test email: %w", err)
		}
		return fmt.Sprintf("Test email successfully sent to %s", cfg.ToEmail), nil

	case "webhook":
		if !cfg.EnableWebhook {
			return "", fmt.Errorf("webhook notifications are disabled in settings")
		}
		isDiscord := bytes.Contains([]byte(cfg.WebhookURL), []byte("discord.com"))
		isSlack := bytes.Contains([]byte(cfg.WebhookURL), []byte("slack.com"))
		if err := SendWebhookAlert(cfg, subject, details, isSlack, isDiscord); err != nil {
			return "", fmt.Errorf("failed to send test webhook: %w", err)
		}
		return "Test webhook payload delivered successfully!", nil

	default:
		return "", fmt.Errorf("unknown channel: %s", channel)
	}
}

// StartSLONotifierBackgroundWorker runs periodic background checks for SLO breaches.
func StartSLONotifierBackgroundWorker(gormDB *gorm.DB) {
	go func() {
		ticker := time.NewTicker(2 * time.Minute)
		defer ticker.Stop()

		var reportedBreaches = make(map[string]time.Time)

		for range ticker.C {
			cfg, err := GetNotificationConfig(gormDB)
			if err != nil || (!cfg.EnableEmail && !cfg.EnableWebhook) {
				continue
			}

			var services []db.Service
			if err := gormDB.Find(&services).Error; err != nil {
				continue
			}

			for _, svc := range services {
				constraintsMap := parseConstraints(svc.Constraints)
				if constraintsMap["gbnt.slo.enable"] != "true" && constraintsMap["gbnt.slo.enable"] != "1" {
					continue
				}

				// Check cooldown (don't spam alerts for same service within 30 min)
				if lastSent, ok := reportedBreaches[svc.ID]; ok && time.Since(lastSent) < 30*time.Minute {
					continue
				}

				targetStr := constraintsMap["gbnt.slo.target"]
				targetVal, _ := strconv.ParseFloat(targetStr, 64)
				if targetVal <= 0 {
					targetVal = 99.9
				}

				// Query Prometheus budget remaining ratio
				budgetRatio, err := QueryPrometheusMetric(fmt.Sprintf(`slo:period_error_budget_remaining:ratio{gbnt_service_id="%s"}`, svc.ID))
				if err == nil && budgetRatio >= 0 {
					budgetRemaining := budgetRatio * 100.0
					if budgetRemaining <= 0 {
						subject := fmt.Sprintf("🚨 [SLO Exhausted] %s Error Budget Depleted!", svc.Name)
						details := fmt.Sprintf("Service: %s\nTarget Availability: %.2f%%\nError Budget Remaining: 0.00%%\nTime: %s",
							svc.Name, targetVal, time.Now().Format(time.RFC1123))

						slog.Warn("SLO Budget Exhausted Alert Triggered", "service", svc.Name, "target", targetVal)

						if cfg.EnableEmail {
							_ = SendEmailAlert(cfg, subject, details)
						}
						if cfg.EnableWebhook {
							isDiscord := bytes.Contains([]byte(cfg.WebhookURL), []byte("discord.com"))
							isSlack := bytes.Contains([]byte(cfg.WebhookURL), []byte("slack.com"))
							_ = SendWebhookAlert(cfg, subject, details, isSlack, isDiscord)
						}
						reportedBreaches[svc.ID] = time.Now()
					}
				}
			}
		}
	}()
}
