# 🇪🇺 European NIS 2 Directive (EU 2022/2555) Compliance Suite

Gubernator incorporates a native compliance assessment and evidence generation engine tailored to the requirements of the **European Union Directive on Security of Network and Information Systems (NIS 2 — Directive (EU) 2022/2555)**.

---

## 🏛 1. Regulatory Context & Scope

The **NIS 2 Directive** establishes harmonized cybersecurity obligations across the European Union for organizations providing critical services:

* **Essential Entities (EE):** Energy, transport, banking, financial market infrastructures, health, drinking water, waste water, digital infrastructure (cloud computing, data centres, DNS), ICT service management (B2B), and public administration. Supervisory threshold: **85%**.
* **Important Entities (IE):** Postal and courier services, waste management, chemicals, food, manufacturing of critical products (medical, electronics, machinery), digital providers (marketplaces, search engines, social networks), and research organizations. Supervisory threshold: **75%**.

Gubernator provides automated heuristic mapping between cluster state and the **10 mandatory cybersecurity risk-management measures** defined in **Article 21(2)** of the Directive.

---

## 📋 2. Article 21(2) Mandatory Risk-Management Measures

Gubernator automatically evaluates and monitors technical compliance for all 10 controls:

| Control ID | Article 21(2) Measure | Technical Domain | Verification Mechanism in Gubernator |
| :--- | :--- | :--- | :--- |
| **`nis2.art21.2a`** | Risk analysis & information security policies | Risk Governance | Pre-deployment Admission Gatekeeper, signature policies (`enforce`), and CVE severity thresholds. |
| **`nis2.art21.2b`** | Incident handling & SIEM telemetry | Incident Response | Real-time SIEM event streaming via Syslog (RFC 5424), CEF, and JSON over UDP, TCP, and TLS. |
| **`nis2.art21.2c`** | Business continuity & disaster recovery | Business Continuity | Multi-node high-availability clustering, streaming AES-256-GCM backups, automated cron schedules, and point-in-time recovery. |
| **`nis2.art21.2d`** | Supply chain security & container provenance | Supply Chain | CycloneDX & SPDX SBOM generation, Cosign ECDSA P-256 digital signatures, and signature enforcement. |
| **`nis2.art21.2e`** | Vulnerability handling & disclosure | Vulnerability Handling | Continuous CVE vulnerability scanning, CVSS scoring, and assisted zero-downtime container patch remediation. |
| **`nis2.art21.2f`** | Cybersecurity effectiveness assessment | Effectiveness & Audit | Tamper-evident SHA-256 chained forensic audit logging with non-repudiation verification. |
| **`nis2.art21.2g`** | Basic cyber hygiene & credential management | Cyber Hygiene | Automatic account lockouts (5 failed attempts), strong password complexity (CCN-STIC 823), and session timeouts. |
| **`nis2.art21.2h`** | Cryptography & encryption | Cryptography | Ingress Caddy with automated TLS 1.3 encryption and AES-256-GCM encrypted backup storage. |
| **`nis2.art21.2i`** | Human resources, access control & RBAC | Access Control | 4-tier Role-Based Access Control (`admin`, `operator`, `auditor`, `readonly`) with Enterprise LDAP & SSO OIDC federation. |
| **`nis2.art21.2j`** | Multi-factor authentication (MFA / TOTP) | Authentication | Mandatory RFC 6238 TOTP two-factor authentication for privileged accounts (`admin`, `operator`). |

---

## 📊 3. Readiness Scoring & Classification

Gubernator calculates separate compliance scores for Essential and Important entities based on control weighting:

$$\text{Score (\%)} = \left( \frac{\sum (\text{Measure Score} \times \text{Weight})}{\sum \text{Weight}} \right) \times 100$$

### Readiness Categories
* **`HIGH` (Score $\ge 85\%$):** Fully compliant with baseline requirements for Essential Entities (EE) and Important Entities (IE).
* **`MEDIUM` (Score $75\% - 84\%$):** Meets supervisory thresholds for Important Entities; minor enhancements needed for Essential Entities.
* **`BASIC` (Score $50\% - 74\%$):** Fundamental controls active; substantial gaps in incident response, encryption, or supply chain.
* **`INSUFFICIENT` (Score $< 50\%$):** Critical non-compliance requiring immediate intervention.

---

## 🖥️ 4. Flutter Web UI Dashboard

Located under **Security & Directory** ➔ **Compliance & Regulatory Suite** ➔ **🇪🇺 NIS 2 Directive (EU 2022/2555)**:

### Features
1. **Header Banner:** Displays directive version, overall readiness badge, and direct report export triggers.
2. **Executive KPI Cards:**
   - **OVERALL READINESS:** Real-time classification (`HIGH`, `MEDIUM`, `BASIC`, `INSUFFICIENT`).
   - **ESSENTIAL ENTITIES (EE):** Weighted readiness score against the 85% supervisory threshold.
   - **IMPORTANT ENTITIES (IE):** Weighted readiness score against the 75% supervisory threshold.
   - **ARTICLE 21 CONTROLS:** Breakdown of Compliant, Partial, and Non-compliant measures.
3. **Domain Filtering:** Filter measures by domain (*Risk Governance*, *Incident Response*, *Business Continuity*, *Supply Chain*, *Vulnerability Handling*, *Effectiveness & Audit*, *Cyber Hygiene*, *Cryptography*, *Access Control*, *Authentication*).
4. **Interactive Measure Cards:** Displays article references, domain tags, discovered technical evidence, and prescriptive remediation guidance.
5. **Technical CommonMark Report Modal:** Full audit document formatted for submission to National Competent Authorities (NCAs) and CSIRTs.

---

## 💻 5. CLI Parity (`gbnt nis2`)

```bash
# Run interactive audit summary
gbnt nis2
```

Output:
```text
=========================================================================================
🇪🇺  DIRECTIVE (EU) 2022/2555 (NIS 2) | CYBERSECURITY READINESS AUDIT
=========================================================================================
  Overall Readiness:     HIGH
  Essential Entities:    92.5%
  Important Entities:    92.5%
  Measures Evaluated:    10 (9 Compliant, 1 Partial, 0 Non-Compliant)
-----------------------------------------------------------------------------------------
ARTICLE         MEASURE                          STATUS         SCORE    TECHNICAL EVIDENCE            
-----------------------------------------------------------------------------------------
Art. 21.2(a)    Policies on Risk Analysis...     ✅ Compliant    100%     Cluster security admission ...
Art. 21.2(b)    Incident Handling & SIEM...      ✅ Compliant    100%     Real-time SIEM event strea...
...
=========================================================================================
Tip: Run 'gbnt nis2 --report' to display the full official technical audit report.
```

### Exporting Reports
```bash
# Generate full Markdown report
gbnt nis2 --report > nis2-report.md

# Generate structured JSON
gbnt nis2 --format json > nis2-report.json
```

---

## 📡 6. REST API Endpoints

| Method | Path | Required Role | Description |
| :--- | :--- | :--- | :--- |
| `GET` | `/v1/security/nis2/status` | `admin`, `auditor`, `operator`, `readonly` | Evaluates cluster compliance and returns full summary in JSON. |
| `GET` | `/v1/security/nis2/report` | `admin`, `auditor`, `operator`, `readonly` | Generates official audit report (`format=markdown` or `format=json`). |
| `GET` | `/api/security/nis2/status` | `admin`, `auditor`, `operator`, `readonly` | Web server proxy for dashboard integration. |
| `GET` | `/api/security/nis2/report` | `admin`, `auditor`, `operator`, `readonly` | Web server proxy for downloading audit reports. |
