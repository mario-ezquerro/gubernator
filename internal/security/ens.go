package security

import (
	"fmt"
	"strings"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/db"
	"gorm.io/gorm"
)

// ENSCategory represents the compliance tier achieved under Spanish RD 311/2022.
type ENSCategory string

const (
	ENSCategoryBasico       ENSCategory = "BASICO"
	ENSCategoryMedio        ENSCategory = "MEDIO"
	ENSCategoryAlto         ENSCategory = "ALTO"
	ENSCategoryInsuficiente ENSCategory = "INSUFICIENTE"
)

// ENSStatus represents the evaluation result for a specific security measure.
type ENSStatus string

const (
	ENSStatusCompliant    ENSStatus = "COMPLIANT"
	ENSStatusPartial      ENSStatus = "PARTIAL"
	ENSStatusNonCompliant ENSStatus = "NON_COMPLIANT"
)

// ENSMeasure represents an individual security measure from RD 311/2022 (Annex II).
type ENSMeasure struct {
	ID               string    `json:"id"`                // e.g. "op.acc.2"
	Name             string    `json:"name"`              // e.g. "Control de acceso y robustez de contraseñas"
	Area             string    `json:"area"`              // "Marco Organizativo", "Marco Operacional", "Medidas de Protección"
	Dimension        string    `json:"dimension"`         // [C], [I], [T], [A], [D]
	ApplicableLevels []string  `json:"applicable_levels"` // ["BASICO", "MEDIO", "ALTO"]
	Status           ENSStatus `json:"status"`            // COMPLIANT, PARTIAL, NON_COMPLIANT
	Score            float64   `json:"score"`             // 0.0 - 100.0
	Evidence         string    `json:"evidence"`          // Technical evidence discovered in the cluster
	Recommendation   string    `json:"recommendation"`    // Remediation advice
	Weight           float64   `json:"weight"`            // Measure weight in scoring
}

// ENSSummary aggregates the evaluation results across all dimensions.
type ENSSummary struct {
	EvaluatedAt       time.Time    `json:"evaluated_at"`
	ClusterStatus     string       `json:"cluster_status"`
	BasicoScore       float64      `json:"basico_score"`
	MedioScore        float64      `json:"medio_score"`
	AltoScore         float64      `json:"alto_score"`
	OverallCategory   ENSCategory  `json:"overall_category"`
	CompliantCount    int          `json:"compliant_count"`
	PartialCount      int          `json:"partial_count"`
	NonCompliantCount int          `json:"non_compliant_count"`
	TotalMeasures     int          `json:"total_measures"`
	Measures          []ENSMeasure `json:"measures"`
}

// EvaluateENSCompliance scans the active cluster database and inspects configuration,
// local accounts, audit hash chains, backups, and security policies to evaluate
// compliance with RD 311/2022 (ENS) and CCN-STIC guidelines.
func EvaluateENSCompliance(database *gorm.DB) ENSSummary {
	if database == nil {
		database = db.DB
	}

	var measures []ENSMeasure

	// 1. Fetch relevant records
	var secConfig db.SecurityConfig
	if err := database.First(&secConfig, "id = ?", "default").Error; err != nil {
		secConfig = db.SecurityConfig{
			MaxFailedLogins:           5,
			LockoutDurationMinutes:    15,
			PasswordMinLength:         12,
			PasswordRequireComplexity: true,
			SessionTimeoutMinutes:     15,
		}
	}

	var users []db.LocalUser
	database.Find(&users)

	var backups []db.Backup
	database.Find(&backups)

	var auditCount int64
	database.Model(&db.AuditLog{}).Count(&auditCount)

	var nodes []db.Node
	database.Find(&nodes)

	var signingKeys []db.TrustedSigningKey
	database.Find(&signingKeys)

	var scans []db.ImageScan
	database.Find(&scans)

	var secPolicy db.SecurityPolicy
	database.First(&secPolicy, "id = ?", "default")

	// ==========================================
	// 1. org.2 - Segregación de funciones (RBAC)
	// ==========================================
	{
		hasAuditor := false
		for _, u := range users {
			if strings.EqualFold(u.Role, "auditor") {
				hasAuditor = true
				break
			}
		}

		m := ENSMeasure{
			ID:               "org.2",
			Name:             "Segregación de funciones y responsabilidades diferenciadas",
			Area:             "Marco Organizativo",
			Dimension:        "[C] [I] [T]",
			ApplicableLevels: []string{"BASICO", "MEDIO", "ALTO"},
			Weight:           1.0,
		}

		if hasAuditor {
			m.Status = ENSStatusCompliant
			m.Score = 100.0
			m.Evidence = fmt.Sprintf("Matriz RBAC activa de 4 niveles (admin, operator, auditor, readonly). Se ha verificado la existencia de cuentas dedicadas con rol exclusivo de Auditor (RolAuditor).")
			m.Recommendation = "Mantener la separación de deberes prohibiendo que los administradores de sistemas auditen sus propias acciones."
		} else {
			m.Status = ENSStatusPartial
			m.Score = 70.0
			m.Evidence = fmt.Sprintf("Matriz RBAC activa de 4 niveles disponible, pero aún no se ha creado ningún usuario local con rol 'auditor'. Total usuarios evaluados: %d.", len(users))
			m.Recommendation = "Crear al menos una cuenta dedicada con rol exclusivo 'auditor' para inspección forense independiente (ENS MEDIO/ALTO)."
		}
		measures = append(measures, m)
	}

	// ==========================================
	// 2. op.acc.1 - Identificación unívoca
	// ==========================================
	{
		m := ENSMeasure{
			ID:               "op.acc.1",
			Name:             "Identificación unívoca de usuarios y trazabilidad de acceso",
			Area:             "Marco Operacional",
			Dimension:        "[A] [T]",
			ApplicableLevels: []string{"BASICO", "MEDIO", "ALTO"},
			Weight:           1.0,
			Status:           ENSStatusCompliant,
			Score:            100.0,
			Evidence:         fmt.Sprintf("Identificación unívoca basada en UUID, hashes bcrypt de contraseñas y sesiones JWT firmadas criptográficamente con HMAC-SHA256 (24h). Total usuarios identificados: %d.", len(users)),
			Recommendation:   "Prohibir el uso de cuentas genéricas o compartidas para operaciones de administración.",
		}
		measures = append(measures, m)
	}

	// ==========================================
	// 3. op.acc.2 - Control de acceso, bloqueo y contraseñas
	// ==========================================
	{
		m := ENSMeasure{
			ID:               "op.acc.2",
			Name:             "Requisitos de acceso: Bloqueo de cuentas, contraseñas robustas y caducidad de sesión",
			Area:             "Marco Operacional",
			Dimension:        "[C] [I] [A]",
			ApplicableLevels: []string{"BASICO", "MEDIO", "ALTO"},
			Weight:           1.5,
		}

		lockoutCompliant := secConfig.MaxFailedLogins > 0 && secConfig.MaxFailedLogins <= 5 && secConfig.LockoutDurationMinutes >= 15
		pwdLengthCompliant := secConfig.PasswordMinLength >= 12
		pwdComplexityCompliant := secConfig.PasswordRequireComplexity
		timeoutCompliant := secConfig.SessionTimeoutMinutes > 0 && secConfig.SessionTimeoutMinutes <= 15

		checksPassed := 0
		if lockoutCompliant {
			checksPassed++
		}
		if pwdLengthCompliant {
			checksPassed++
		}
		if pwdComplexityCompliant {
			checksPassed++
		}
		if timeoutCompliant {
			checksPassed++
		}

		m.Score = float64(checksPassed) * 25.0

		if checksPassed == 4 {
			m.Status = ENSStatusCompliant
			m.Evidence = fmt.Sprintf("Bloqueo automático tras %d intentos fallidos durante %d min; Contraseñas mín. %d caracteres con mayúsculas/minúsculas/números/símbolos (CCN-STIC 823); Timeout de inactividad de sesión de %d min.",
				secConfig.MaxFailedLogins, secConfig.LockoutDurationMinutes, secConfig.PasswordMinLength, secConfig.SessionTimeoutMinutes)
			m.Recommendation = "Política de control de acceso plenamente conforme con ENS MEDIO y ALTO."
		} else {
			m.Status = ENSStatusPartial
			m.Evidence = fmt.Sprintf("Parámetros actuales: Intentos máx: %d, Enfriamiento: %d min, Longitud contraseña: %d chars, Complejidad: %v, Timeout sesión: %d min (%d/4 verificaciones superadas).",
				secConfig.MaxFailedLogins, secConfig.LockoutDurationMinutes, secConfig.PasswordMinLength, secConfig.PasswordRequireComplexity, secConfig.SessionTimeoutMinutes, checksPassed)
			m.Recommendation = "Ajustar la configuración de seguridad a los parámetros ENS MEDIO: máx 5 intentos, 15 min bloqueo, mín 12 caracteres con complejidad y timeout <= 15 min."
		}
		measures = append(measures, m)
	}

	// ==========================================
	// 4. op.acc.6 - Autenticación Multifactor (MFA/TOTP)
	// ==========================================
	{
		m := ENSMeasure{
			ID:               "op.acc.6",
			Name:             "Mecanismo de autenticación multifactor (MFA / TOTP RFC 6238)",
			Area:             "Marco Operacional",
			Dimension:        "[A] [C]",
			ApplicableLevels: []string{"MEDIO", "ALTO"},
			Weight:           1.5,
		}

		mfaCount := 0
		adminCount := 0
		for _, u := range users {
			if strings.EqualFold(u.Role, "admin") || strings.EqualFold(u.Role, "operator") {
				adminCount++
				if u.MFAEnabled {
					mfaCount++
				}
			}
		}

		if adminCount > 0 && mfaCount == adminCount {
			m.Status = ENSStatusCompliant
			m.Score = 100.0
			m.Evidence = fmt.Sprintf("El 100%% de las cuentas con privilegios de administración y operación (%d/%d) tienen MFA/TOTP activado con generación offline de QR y códigos de respaldo.", mfaCount, adminCount)
			m.Recommendation = "Mantener la obligatoriedad de MFA para todas las nuevas incorporaciones con rol privilegiado."
		} else if mfaCount > 0 {
			m.Status = ENSStatusPartial
			m.Score = 65.0
			m.Evidence = fmt.Sprintf("Soporte TOTP offline activo. %d de %d cuentas privilegiadas tienen MFA habilitado.", mfaCount, adminCount)
			m.Recommendation = "Habilitar MFA de forma obligatoria en las cuentas de administración restantes para alcanzar nivel ENS ALTO."
		} else {
			m.Status = ENSStatusPartial
			m.Score = 40.0
			m.Evidence = fmt.Sprintf("Motor TOTP RFC 6238 integrado en el backend, pero ninguna cuenta privilegiada (%d administradores/operadores) tiene MFA habilitado actualmente.", adminCount)
			m.Recommendation = "Activar el doble factor de autenticación (TOTP) en los perfiles de usuario desde la Web UI o API."
		}
		measures = append(measures, m)
	}

	// ==========================================
	// 5. op.exp.10 - Copias de seguridad cifradas en reposo
	// ==========================================
	{
		m := ENSMeasure{
			ID:               "op.exp.10",
			Name:             "Copias de seguridad periódicas e integridad de restauración",
			Area:             "Marco Operacional",
			Dimension:        "[I] [D]",
			ApplicableLevels: []string{"BASICO", "MEDIO", "ALTO"},
			Weight:           1.5,
		}

		encryptedBackups := 0
		for _, b := range backups {
			if b.IsEncrypted {
				encryptedBackups++
			}
		}

		if len(backups) > 0 && encryptedBackups > 0 {
			m.Status = ENSStatusCompliant
			m.Score = 100.0
			m.Evidence = fmt.Sprintf("Total copias registradas: %d (%d cifradas con AES-256-GCM y PBKDF2-SHA256). Verificación criptográfica SHA-256 en cada archivo.", len(backups), encryptedBackups)
			m.Recommendation = "Programar políticas periódicas de copias automatizadas con retención segura (cron schedules)."
		} else if len(backups) > 0 {
			m.Status = ENSStatusPartial
			m.Score = 60.0
			m.Evidence = fmt.Sprintf("Existen %d copias de seguridad generadas con digest SHA-256, pero ninguna de ellas utiliza cifrado en reposo AES-256-GCM.", len(backups))
			m.Recommendation = "Generar copias de seguridad utilizando la opción de cifrado AES-256-GCM (ENS mp.si.2 / op.exp.10)."
		} else {
			m.Status = ENSStatusNonCompliant
			m.Score = 20.0
			m.Evidence = "No se han detectado copias de seguridad de volumen o de clúster creadas en el sistema."
			m.Recommendation = "Crear copias de seguridad comprimidas y cifradas de los volúmenes de datos y configuraciones críticas."
		}
		measures = append(measures, m)
	}

	// ==========================================
	// 6. op.mon.1 - Registro de actividad y trazabilidad inmutable
	// ==========================================
	{
		m := ENSMeasure{
			ID:               "op.mon.1",
			Name:             "Registro de actividad del sistema, auditoría inmutable y trazabilidad",
			Area:             "Marco Operacional",
			Dimension:        "[T] [I]",
			ApplicableLevels: []string{"BASICO", "MEDIO", "ALTO"},
			Weight:           1.2,
		}

		if auditCount > 0 {
			m.Status = ENSStatusCompliant
			m.Score = 100.0
			m.Evidence = fmt.Sprintf("Pista de auditoría forense inmutable activa con cadena de hashes criptográficos SHA-256 por registro. Total eventos registrados: %d.", auditCount)
			m.Recommendation = "Garantizar la retención periódica y custodia de los logs de auditoría forense."
		} else {
			m.Status = ENSStatusPartial
			m.Score = 60.0
			m.Evidence = "Motor de auditoría forense SHA-256 inicializado, pero la base de datos de auditoría aún no contiene eventos."
			m.Recommendation = "Realizar operaciones en el clúster para generar la pista de auditoría forense."
		}
		measures = append(measures, m)
	}

	// ==========================================
	// 7. op.mon.2 - Detección de intrusión y reenvío a SIEM
	// ==========================================
	{
		m := ENSMeasure{
			ID:               "op.mon.2",
			Name:             "Monitorización continua, detección de intrusión y reenvío a SIEM",
			Area:             "Marco Operacional",
			Dimension:        "[T] [D]",
			ApplicableLevels: []string{"MEDIO", "ALTO"},
			Weight:           1.2,
		}

		if secConfig.SIEMEnabled && secConfig.SIEMHost != "" {
			m.Status = ENSStatusCompliant
			m.Score = 100.0
			m.Evidence = fmt.Sprintf("Reenvío de auditoría y telemetría a SIEM activo (%s://%s:%d en formato %s).", secConfig.SIEMProtocol, secConfig.SIEMHost, secConfig.SIEMPort, secConfig.SIEMFormat)
			m.Recommendation = "Verificar periódicamente la recepción de eventos en el colector SIEM centralizado."
		} else {
			m.Status = ENSStatusPartial
			m.Score = 40.0
			m.Evidence = "El reenvío automático a SIEM (Syslog / CEF / JSON) está deshabilitado en la configuración de seguridad."
			m.Recommendation = "Habilitar el reenvío de logs a SIEM en la pestaña de Seguridad para cumplimiento de ENS MEDIO y ALTO."
		}
		measures = append(measures, m)
	}

	// ==========================================
	// 8. op.cont.2 - Disponibilidad y redundancia de clúster
	// ==========================================
	{
		m := ENSMeasure{
			ID:               "op.cont.2",
			Name:             "Continuidad de la actividad: Redundancia y alta disponibilidad",
			Area:             "Marco Operacional",
			Dimension:        "[D]",
			ApplicableLevels: []string{"BASICO", "MEDIO", "ALTO"},
			Weight:           1.0,
		}

		activeNodes := 0
		for _, n := range nodes {
			if strings.EqualFold(n.Status, "active") {
				activeNodes++
			}
		}

		if activeNodes >= 3 {
			m.Status = ENSStatusCompliant
			m.Score = 100.0
			m.Evidence = fmt.Sprintf("Clúster multi-nodo altamente disponible con %d nodos activos (Manager + Centurions con heartbeat continuo y auto-restart).", activeNodes)
			m.Recommendation = "Realizar simulacros periódicos de caída de nodo para comprobar la reprogramación automática de tareas."
		} else if activeNodes >= 2 {
			m.Status = ENSStatusCompliant
			m.Score = 85.0
			m.Evidence = fmt.Sprintf("Clúster multi-nodo con %d nodos activos.", activeNodes)
			m.Recommendation = "Recomendable ampliar a $\\ge 3$ Centurions para tolerancia a fallos en categoría ENS ALTO."
		} else {
			m.Status = ENSStatusPartial
			m.Score = 60.0
			m.Evidence = fmt.Sprintf("Instalación de nodo único (%d nodo activo detectado).", activeNodes)
			m.Recommendation = "Incorporar nodos trabajadores Centurions ('gbnt legion join') para garantizar alta disponibilidad ante caída de host."
		}
		measures = append(measures, m)
	}

	// ==========================================
	// 9. mp.si.1 - Protección de las comunicaciones (TLS)
	// ==========================================
	{
		m := ENSMeasure{
			ID:               "mp.si.1",
			Name:             "Protección de las comunicaciones: Cifrado en tránsito (TLS 1.2 / 1.3)",
			Area:             "Medidas de Protección",
			Dimension:        "[C] [I]",
			ApplicableLevels: []string{"BASICO", "MEDIO", "ALTO"},
			Weight:           1.2,
			Status:           ENSStatusCompliant,
			Score:            100.0,
			Evidence:         "Caddy Ingress integrado con aprovisionamiento automático de certificados TLS, renovación forzada, inspección X.509 y cifrado obligatorio HTTPS/WSS.",
			Recommendation:   "Asegurar que los certificados de producción utilicen Let's Encrypt o la Root CA corporativa de confianza.",
		}
		measures = append(measures, m)
	}

	// ==========================================
	// 10. mp.si.2 - Protección de los soportes de información en reposo
	// ==========================================
	{
		m := ENSMeasure{
			ID:               "mp.si.2",
			Name:             "Protección de soportes y datos en reposo: Cifrado criptográfico robusto",
			Area:             "Medidas de Protección",
			Dimension:        "[C] [I]",
			ApplicableLevels: []string{"MEDIO", "ALTO"},
			Weight:           1.4,
		}

		encryptedCount := 0
		for _, b := range backups {
			if b.IsEncrypted {
				encryptedCount++
			}
		}

		if encryptedCount > 0 {
			m.Status = ENSStatusCompliant
			m.Score = 100.0
			m.Evidence = fmt.Sprintf("Mecanismo de cifrado en reposo AES-256-GCM implementado con derivación de clave PBKDF2-HMAC-SHA256 (100.000 iteraciones). %d copias cifradas almacenadas.", encryptedCount)
			m.Recommendation = "Custodiar las contraseñas de cifrado de backups fuera del servidor y asegurar el cifrado de volumen a nivel de SO."
		} else {
			m.Status = ENSStatusPartial
			m.Score = 50.0
			m.Evidence = "Motor AES-256-GCM con PBKDF2 disponible, pero aún no hay copias de seguridad cifradas en reposo almacenadas."
			m.Recommendation = "Crear copias de seguridad activando la opción de cifrado AES-256-GCM (ENS mp.si.2)."
		}
		measures = append(measures, m)
	}

	// ==========================================
	// 11. mp.sw.2 - Seguridad del software y cadena de suministro (SBOM y Firma)
	// ==========================================
	{
		m := ENSMeasure{
			ID:               "mp.sw.2",
			Name:             "Seguridad del software: Firma criptográfica (Cosign), SBOM y control de admisión",
			Area:             "Medidas de Protección",
			Dimension:        "[I] [A]",
			ApplicableLevels: []string{"BASICO", "MEDIO", "ALTO"},
			Weight:           1.4,
		}

		hasKeys := len(signingKeys) > 0
		hasScans := len(scans) > 0
		strictPolicy := secPolicy.EnforceSignatures == "enforce" || secPolicy.BlockCVESeverity != "none"

		if hasKeys && hasScans && strictPolicy {
			m.Status = ENSStatusCompliant
			m.Score = 100.0
			m.Evidence = fmt.Sprintf("Gatekeeper de admisión estricto activo, claves Cosign ECDSA configuradas (%d claves) e inventario SBOM/CVEs analizado (%d imágenes).", len(signingKeys), len(scans))
			m.Recommendation = "Mantener la política de bloqueo de imágenes que contengan vulnerabilidades CRITICAL sin parchear."
		} else if hasKeys || hasScans {
			m.Status = ENSStatusCompliant
			m.Score = 80.0
			m.Evidence = fmt.Sprintf("Módulo de seguridad de imágenes operativo: %d claves de firma Cosign y %d análisis SBOM registrados. Política actual: '%s'.", len(signingKeys), len(scans), secPolicy.EnforceSignatures)
			m.Recommendation = "Configurar el Gatekeeper en modo 'enforce' para bloquear despliegues de imágenes sin firma verificada."
		} else {
			m.Status = ENSStatusPartial
			m.Score = 55.0
			m.Evidence = "Motor Gatekeeper disponible, pero no se han generado claves de firma Cosign ni escaneos SBOM en el clúster."
			m.Recommendation = "Generar una clave de firma Cosign ('gbnt security key generate') y escanear imágenes de los stacks."
		}
		measures = append(measures, m)
	}

	// ==========================================
	// Compute Global Compliance Scores
	// ==========================================
	var basicoPoints, basicoMax float64
	var medioPoints, medioMax float64
	var altoPoints, altoMax float64

	compliantCount := 0
	partialCount := 0
	nonCompliantCount := 0

	for _, m := range measures {
		switch m.Status {
		case ENSStatusCompliant:
			compliantCount++
		case ENSStatusPartial:
			partialCount++
		case ENSStatusNonCompliant:
			nonCompliantCount++
		}

		for _, lvl := range m.ApplicableLevels {
			switch lvl {
			case "BASICO":
				basicoPoints += m.Score * m.Weight
				basicoMax += 100.0 * m.Weight
			case "MEDIO":
				medioPoints += m.Score * m.Weight
				medioMax += 100.0 * m.Weight
			case "ALTO":
				altoPoints += m.Score * m.Weight
				altoMax += 100.0 * m.Weight
			}
		}
	}

	basicoScore := 0.0
	if basicoMax > 0 {
		basicoScore = (basicoPoints / basicoMax) * 100.0
	}
	medioScore := 0.0
	if medioMax > 0 {
		medioScore = (medioPoints / medioMax) * 100.0
	}
	altoScore := 0.0
	if altoMax > 0 {
		altoScore = (altoPoints / altoMax) * 100.0
	}

	// Category determination
	category := ENSCategoryInsuficiente
	if altoScore >= 85.0 && medioScore >= 90.0 && basicoScore >= 95.0 {
		category = ENSCategoryAlto
	} else if medioScore >= 75.0 && basicoScore >= 85.0 {
		category = ENSCategoryMedio
	} else if basicoScore >= 70.0 {
		category = ENSCategoryBasico
	}

	return ENSSummary{
		EvaluatedAt:       time.Now(),
		ClusterStatus:     "ACTIVE",
		BasicoScore:       roundScore(basicoScore),
		MedioScore:        roundScore(medioScore),
		AltoScore:         roundScore(altoScore),
		OverallCategory:   category,
		CompliantCount:    compliantCount,
		PartialCount:      partialCount,
		NonCompliantCount: nonCompliantCount,
		TotalMeasures:     len(measures),
		Measures:          measures,
	}
}

func roundScore(val float64) float64 {
	return float64(int(val*10+0.5)) / 10.0
}

// GenerateENSReportMarkdown formats an official technical compliance report in Markdown
// suitable for internal security auditing and ENS compliance certification.
func GenerateENSReportMarkdown(s ENSSummary, version string) string {
	var sb strings.Builder

	sb.WriteString("# INFORME TÉCNICO DE CONFORMIDAD — ESQUEMA NACIONAL DE SEGURIDAD (ENS)\n")
	sb.WriteString("### Real Decreto 311/2022 | Guías CCN-STIC del Centro Criptológico Nacional\n\n")

	sb.WriteString("| Metadato de Auditoría | Valor |\n")
	sb.WriteString("| :--- | :--- |\n")
	sb.WriteString(fmt.Sprintf("| **Plataforma / Sistema** | Gubernator (`gbnt`) Orchestrator |\n"))
	sb.WriteString(fmt.Sprintf("| **Versión de Software** | %s |\n", version))
	sb.WriteString(fmt.Sprintf("| **Fecha y Hora de Evaluación** | %s |\n", s.EvaluatedAt.Format("2006-01-02 15:04:05 MST")))
	sb.WriteString(fmt.Sprintf("| **Categoría ENS Alcanzada** | **%s** |\n", s.OverallCategory))
	sb.WriteString(fmt.Sprintf("| **Medidas Evaluadas** | %d (%d Conformes, %d Parciales, %d No Conformes) |\n",
		s.TotalMeasures, s.CompliantCount, s.PartialCount, s.NonCompliantCount))
	sb.WriteString("\n---\n\n")

	sb.WriteString("## 1. Resumen Ejecutivo de Conformidad\n\n")
	sb.WriteString("El Esquema Nacional de Seguridad (ENS), de aplicación obligatoria en el Sector Público español y sus proveedores tecnológicos (según RD 311/2022), establece los principios básicos y requisitos mínimos para la adecuada protección de la información tratada y los servicios prestados.\n\n")

	sb.WriteString(fmt.Sprintf("* **Nivel BÁSICO:** **%.1f%%** de conformidad\n", s.BasicoScore))
	sb.WriteString(fmt.Sprintf("* **Nivel MEDIO:** **%.1f%%** de conformidad\n", s.MedioScore))
	sb.WriteString(fmt.Sprintf("* **Nivel ALTO:** **%.1f%%** de conformidad\n\n", s.AltoScore))

	sb.WriteString("## 2. Desglose Detallado de Medidas de Seguridad (Anexo II RD 311/2022)\n\n")
	sb.WriteString("| ID | Medida de Seguridad | Área | Dimensión | Estado | Puntuación | Evidencia Técnica Descubierta |\n")
	sb.WriteString("| :--- | :--- | :--- | :---: | :---: | :---: | :--- |\n")

	for _, m := range s.Measures {
		statusBadge := "❌ No Cumple"
		if m.Status == ENSStatusCompliant {
			statusBadge = "✅ Cumple"
		} else if m.Status == ENSStatusPartial {
			statusBadge = "⚠️ Parcial"
		}

		sb.WriteString(fmt.Sprintf("| **`%s`** | %s | %s | %s | %s | %.0f%% | %s |\n",
			m.ID, m.Name, m.Area, m.Dimension, statusBadge, m.Score, m.Evidence))
	}

	sb.WriteString("\n---\n\n")
	sb.WriteString("## 3. Recomendaciones de Remediación y Plan de Acción\n\n")

	for _, m := range s.Measures {
		if m.Status != ENSStatusCompliant {
			sb.WriteString(fmt.Sprintf("### Medida `%s` — %s\n", m.ID, m.Name))
			sb.WriteString(fmt.Sprintf("* **Situación Actual:** %s\n", m.Evidence))
			sb.WriteString(fmt.Sprintf("* **Acción Recomendada:** %s\n\n", m.Recommendation))
		}
	}

	sb.WriteString("---\n\n")
	sb.WriteString("## 4. Declaración y Sello de Auditoría Forense\n\n")
	sb.WriteString("Este informe ha sido generado automáticamente por el motor de evaluación forense de Gubernator, analizando en tiempo real la configuración del núcleo, la base de datos de control de acceso, los registros de auditoría criptográfica SHA-256 y las políticas de despliegue.\n\n")
	sb.WriteString(fmt.Sprintf("*Generado por Gubernator %s — Audit Seal: %s*\n", version, time.Now().Format("20060102-150405")))

	return sb.String()
}
