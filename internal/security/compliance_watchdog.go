package security

import (
	"context"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"gorm.io/gorm"

	"github.com/mario-ezquerro/gubernator/internal/audit"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

var (
	complianceScoreGauge = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "gbnt_compliance_score",
			Help: "Current compliance score (0.0 to 100.0) evaluated by the continuous compliance audit engine.",
		},
		[]string{"framework"}, // "ens", "nis2", "cis_docker", "iso27001", "dora"
	)
	metricsRegistered sync.Once

	overviewMu     sync.RWMutex
	lastOverview   *ComplianceOverview
	triggerChan    = make(chan string, 50)
	watchdogActive bool
	watchdogMu     sync.Mutex
)

func init() {
	metricsRegistered.Do(func() {
		_ = prometheus.Register(complianceScoreGauge)
	})
}

// StandardScore summarizes a specific regulatory framework's score and tier.
type StandardScore struct {
	Name           string    `json:"name"`            // e.g. "Spanish ENS (RD 311/2022)"
	Code           string    `json:"code"`            // "ENS", "NIS2", "CIS", "ISO27001", "DORA"
	Score          float64   `json:"score"`           // 0.0 - 100.0
	Status         string    `json:"status"`          // "COMPLIANT", "PARTIAL", "NON_COMPLIANT"
	Category       string    `json:"category"`        // e.g. "ALTO", "MEDIO", "HIGH", "A+"
	CompliantCount int       `json:"compliant_count"` // Number of passing controls
	TotalMeasures  int       `json:"total_measures"`  // Total evaluated controls
	EvaluatedAt    time.Time `json:"evaluated_at"`
}

// ComplianceOverview aggregates evaluation results across all 5 regulatory frameworks.
type ComplianceOverview struct {
	EvaluatedAt       time.Time        `json:"evaluated_at"`
	TriggerSource     string           `json:"trigger_source"` // "SCHEDULER", "MANUAL", "MUTATION"
	OverallScore      float64          `json:"overall_score"`  // Average score across 5 frameworks (0-100)
	OverallStatus     string           `json:"overall_status"` // "EXEMPLARY", "COMPLIANT", "PARTIAL", "ACTION_REQUIRED"
	Standards         []StandardScore  `json:"standards"`
	ENS               ENSSummary       `json:"ens"`
	NIS2              NIS2Summary      `json:"nis2"`
	CIS               CISDockerSummary `json:"cis"`
	ISO27001          ISO27001Summary  `json:"iso27001"`
	DORA              DORASummary      `json:"dora"`
	DegradedStandards []string         `json:"degraded_standards,omitempty"`
}

// GetLatestOverview returns the most recently cached ComplianceOverview, or computes a fresh one if nil.
func GetLatestOverview(database *gorm.DB) ComplianceOverview {
	overviewMu.RLock()
	if lastOverview != nil {
		overview := *lastOverview
		overviewMu.RUnlock()
		return overview
	}
	overviewMu.RUnlock()

	return EvaluateAllCompliance(database, "ON_DEMAND")
}

// EvaluateAllCompliance evaluates all 4 compliance frameworks concurrently in parallel goroutines,
// computes aggregate scores, updates Prometheus metrics, detects compliance degradation, and logs alerts.
func EvaluateAllCompliance(database *gorm.DB, triggerSource string) ComplianceOverview {
	if database == nil {
		database = db.DB
	} else if db.DB == nil {
		db.DB = database
	}

	var wg sync.WaitGroup
	wg.Add(5)

	var ens ENSSummary
	var nis2 NIS2Summary
	var cis CISDockerSummary
	var iso ISO27001Summary
	var dora DORASummary

	go func() {
		defer wg.Done()
		ens = EvaluateENSCompliance(database)
	}()

	go func() {
		defer wg.Done()
		nis2 = EvaluateNIS2Compliance(database)
	}()

	go func() {
		defer wg.Done()
		cis = EvaluateCISDockerBenchmark(database)
	}()

	go func() {
		defer wg.Done()
		iso = EvaluateISO27001Compliance(database)
	}()

	go func() {
		defer wg.Done()
		dora = EvaluateDORACompliance(database)
	}()

	wg.Wait()

	now := time.Now().UTC()

	// Compute individual framework scores
	ensScore := ens.MedioScore
	if ensScore == 0 && ens.BasicoScore > 0 {
		ensScore = ens.BasicoScore
	}

	nis2Score := (nis2.EssentialScore + nis2.ImportantScore) / 2.0
	if nis2Score == 0 && nis2.EssentialScore > 0 {
		nis2Score = nis2.EssentialScore
	}

	cisScore := cis.ScorePercent
	isoScore := iso.OverallScore
	doraScore := dora.OverallScore

	// Update Prometheus metrics
	complianceScoreGauge.WithLabelValues("ens").Set(ensScore)
	complianceScoreGauge.WithLabelValues("nis2").Set(nis2Score)
	complianceScoreGauge.WithLabelValues("cis_docker").Set(cisScore)
	complianceScoreGauge.WithLabelValues("iso27001").Set(isoScore)
	complianceScoreGauge.WithLabelValues("dora").Set(doraScore)

	overallScore := (ensScore + nis2Score + cisScore + isoScore + doraScore) / 5.0

	overallStatus := "ACTION_REQUIRED"
	if overallScore >= 95.0 {
		overallStatus = "EXEMPLARY"
	} else if overallScore >= 80.0 {
		overallStatus = "COMPLIANT"
	} else if overallScore >= 60.0 {
		overallStatus = "PARTIAL"
	}

	standards := []StandardScore{
		{
			Name:           "Spanish ENS (RD 311/2022)",
			Code:           "ENS",
			Score:          ensScore,
			Status:         string(ens.OverallCategory),
			Category:       string(ens.OverallCategory),
			CompliantCount: ens.CompliantCount,
			TotalMeasures:  ens.TotalMeasures,
			EvaluatedAt:    now,
		},
		{
			Name:           "EU NIS 2 Directive (2022/2555)",
			Code:           "NIS2",
			Score:          nis2Score,
			Status:         string(nis2.OverallReadiness),
			Category:       string(nis2.OverallReadiness),
			CompliantCount: nis2.CompliantCount,
			TotalMeasures:  nis2.TotalMeasures,
			EvaluatedAt:    now,
		},
		{
			Name:           "CIS Docker Benchmark v1.6.0",
			Code:           "CIS",
			Score:          cisScore,
			Status:         cis.PostureGrade,
			Category:       cis.PostureGrade,
			CompliantCount: cis.PassCount,
			TotalMeasures:  cis.TotalChecks,
			EvaluatedAt:    now,
		},
		{
			Name:           "ISO/IEC 27001:2022 (Annex A)",
			Code:           "ISO27001",
			Score:          isoScore,
			Status:         iso.PostureGrade,
			Category:       iso.PostureGrade,
			CompliantCount: iso.CompliantCount,
			TotalMeasures:  iso.TotalControls,
			EvaluatedAt:    now,
		},
		{
			Name:           "EU DORA (Reg. 2022/2554)",
			Code:           "DORA",
			Score:          doraScore,
			Status:         string(dora.OverallReadiness),
			Category:       string(dora.OverallReadiness),
			CompliantCount: dora.CompliantCount,
			TotalMeasures:  dora.TotalMeasures,
			EvaluatedAt:    now,
		},
	}

	overview := ComplianceOverview{
		EvaluatedAt:   now,
		TriggerSource: triggerSource,
		OverallScore:  overallScore,
		OverallStatus: overallStatus,
		Standards:     standards,
		ENS:           ens,
		NIS2:          nis2,
		CIS:           cis,
		ISO27001:      iso,
		DORA:          dora,
	}

	// Degradation analysis against previous evaluation
	overviewMu.Lock()
	var degraded []string
	if lastOverview != nil {
		prevScores := make(map[string]float64)
		for _, s := range lastOverview.Standards {
			prevScores[s.Code] = s.Score
		}

		for _, cur := range standards {
			if prev, exists := prevScores[cur.Code]; exists {
				// If compliance dropped by more than 1%
				if cur.Score < prev-1.0 {
					degraded = append(degraded, cur.Code)
					msg := fmt.Sprintf("Compliance score degraded in %s: dropped from %.1f%% to %.1f%% (trigger: %s)",
						cur.Name, prev, cur.Score, triggerSource)
					slog.Warn("compliance degradation detected", "framework", cur.Code, "prev", prev, "cur", cur.Score, "trigger", triggerSource)
					_, _ = audit.RecordEvent("system", "COMPLIANCE", "127.0.0.1", "COMPLIANCE_DEGRADED", "WARNING", msg)
				} else if cur.Score > prev+1.0 && prev < 90.0 {
					msg := fmt.Sprintf("Compliance score improved in %s: increased from %.1f%% to %.1f%% (trigger: %s)",
						cur.Name, prev, cur.Score, triggerSource)
					slog.Info("compliance score improved", "framework", cur.Code, "prev", prev, "cur", cur.Score, "trigger", triggerSource)
					_, _ = audit.RecordEvent("system", "COMPLIANCE", "127.0.0.1", "COMPLIANCE_RESTORED", "SUCCESS", msg)
				}
			}
		}
	}
	overview.DegradedStandards = degraded
	lastOverview = &overview
	overviewMu.Unlock()

	return overview
}

// TriggerComplianceAudit schedules a non-blocking asynchronous re-evaluation of all compliance frameworks.
func TriggerComplianceAudit(source string) {
	select {
	case triggerChan <- source:
	default:
		slog.Debug("compliance watchdog: trigger channel full, audit already enqueued", "source", source)
	}
}

// StartComplianceWatchdog launches the continuous compliance auditing daemon.
// It executes periodic audits every 15 minutes and responds instantly to mutation trigger events.
func StartComplianceWatchdog(ctx context.Context, database *gorm.DB) {
	watchdogMu.Lock()
	if watchdogActive {
		watchdogMu.Unlock()
		return
	}
	watchdogActive = true
	watchdogMu.Unlock()

	slog.Info("compliance watchdog: starting continuous compliance audit scheduler (15-min interval)")

	// Initial evaluation after 5 seconds to allow full cluster bootstrap
	go func() {
		time.Sleep(5 * time.Second)
		_ = EvaluateAllCompliance(database, "BOOT_AUDIT")
	}()

	ticker := time.NewTicker(15 * time.Minute)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			slog.Info("compliance watchdog: shutting down")
			return
		case source := <-triggerChan:
			slog.Info("compliance watchdog: executing reactive audit", "source", source)
			_ = EvaluateAllCompliance(database, source)
		case <-ticker.C:
			slog.Info("compliance watchdog: executing scheduled periodic audit")
			_ = EvaluateAllCompliance(database, "SCHEDULER")
		}
	}
}
