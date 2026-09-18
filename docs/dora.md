# 🏛️ Digital Operational Resilience Act — EU DORA (Regulation 2022/2554)

The **Digital Operational Resilience Act (DORA)**, officially designated as **Regulation (EU) 2022/2554**, establishes a binding, comprehensive regulatory framework for the digital operational resilience of the European financial sector. Entering into full statutory enforcement on **January 17, 2025**, DORA imposes stringent obligations on financial entities (banks, investment firms, payment providers, insurance companies) and critical third-party information and communication technology (ICT) service providers.

Gubernator (`gbnt`) is the **first and only sovereign container orchestrator** to natively embed real-time auditing, compliance scoring, and automated supervisory reporting for Regulation (EU) 2022/2554 directly into its core engine.

---

## 🛡️ 1. Core Philosophy: Statutory Resilience by Design

Unlike legacy orchestration stacks that require fragile meshes of external agents, Gubernator embeds an autonomous DORA compliance engine within a single sovereign Go binary. It continuously benchmarks cluster state, container workloads, network ingress, and persistent storage against all **5 Statutory Pillars** of Regulation (EU) 2022/2554:

```
 ┌───────────────────────────────────────────────────────────────────────────────────────────────────┐
 │                       GUBERNATOR EU DORA REGULATION 2022/2554 RESILIENCE SUITE                    │
 ├───────────────────────────────────────────────────────────────────────────────────────────────────┤
 │  🏛️ Pillar 1: ICT Risk Management Framework (Articles 5 - 16)                                     │
 │     • Protection & Prevention (CIS Docker Benchmark daemon & container hardening)                 │
 │     • IAM & Authentication Governance (LDAPS:636, Granular RBAC, Mandatory TOTP MFA)             │
 │     • Cryptographic Protection in Repose & Transit (Caddy automated TLS, Cosign ECDSA P-256)      │
 │     • Backup Policies & Point-in-Time Recovery (Granaries /var/contenedores, Gzip + SHA-256)      │
 ├───────────────────────────────────────────────────────────────────────────────────────────────────┤
 │  🚨 Pillar 2: ICT-Related Incident Management, Classification & Reporting (Articles 17 - 23)      │
 │     • High-Resolution Forensic Audit Trails with User Attribution                                 │
 │     • Tamper-Evident SHA-256 Cryptographic Hash Chain Audit Ledger (Non-Repudiation)              │
 │     • Real-Time SIEM Streaming (Syslog RFC 5424 / CEF over UDP, TCP, TLS)                         │
 ├───────────────────────────────────────────────────────────────────────────────────────────────────┤
 │  🧪 Pillar 3: Digital Operational Resilience Testing (Articles 24 - 27)                           │
 │     • Multi-Node High Availability & Distributed Quorum (Zero Single Point of Failure)            │
 │     • Automated Task Self-Healing & Healthcheck Recovery Watchdogs                                │
 │     • Continuous Compliance Watchdog (15m evaluation & >1.0% degradation alerting)                │
 ├───────────────────────────────────────────────────────────────────────────────────────────────────┤
 │  🤝 Pillar 4: Managing ICT Third-Party Risk (Articles 28 - 44)                                    │
 │     • Cloud Exit Strategy & Technological Sovereignty (Native Docker Compose, Zero Vendor Lock-in)│
 │     • Software Supply Chain Verification (In-Cluster Cosign ECDSA P-256 Keypair Signatures)       │
 │     • Third-Party Dependency Analysis (CycloneDX & SPDX JSON SBOMs with CVE Vulnerability Audits) │
 │     • Admission Control & Gatekeeper Policy Enforcement                                           │
 ├───────────────────────────────────────────────────────────────────────────────────────────────────┤
 │  📊 Pillar 5: Information & Intelligence Sharing Arrangements (Article 45)                        │
 │     • Automated Supervisory Audit Report Export (Markdown & JSON for competent authorities)       │
 │     • Continuous Operational Telemetry & Prometheus Metric Export (:4002/metrics)                 │
 └───────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 📋 2. The 16 Statutory Technical Measures

Gubernator evaluates 16 technical measures spanning the 5 pillars, calculating an overall resilience score and readiness rating (`HIGH`, `MEDIUM`, `BASIC`, `INSUFFICIENT`):

| Article | Pillar | Statutory Requirement | Gubernator Subsystem & Verification Method | Default Weight |
| :--- | :--- | :--- | :--- | :---: |
| **Art. 9(1)** | P1 ICT Risk | Protection & Prevention: Workload Hardening | CIS Docker Benchmark Level 1 & 2 daemon and runtime container hardening | High |
| **Art. 9(4)** | P1 ICT Risk | Identification & Access Management (IAM) | Enterprise LDAPS/Active Directory, least privilege RBAC, and TOTP MFA | High |
| **Art. 9(2)** | P1 ICT Risk | Cryptographic Protection & Ingress TLS | Multi-node Caddy proxy with automated Let's Encrypt / ZeroSSL TLS & internal Root CA | Medium |
| **Art. 12(1)** | P1 ICT Risk | Backup Policies & Data Restoration | Granaries persistent volume snapshots (`/var/contenedores`), gzip compression & SHA-256 | High |
| **Art. 17** | P2 Incidents | ICT Incident Logging & High-Res Auditing | Immutable forensic logging of all lifecycle, authentication, and configuration events | High |
| **Art. 18** | P2 Incidents | Tamper-Evident Forensic Audit Ledger | Cryptographic SHA-256 hash chains (`prev_hash` $\to$ `hash`) ensuring non-repudiation | High |
| **Art. 19** | P2 Incidents | Real-Time SIEM Event Forwarding | Live streaming to central SIEM via Syslog RFC 5424, CEF, or JSON (UDP/TCP/TLS) | Medium |
| **Art. 24** | P3 Testing | Cluster High Availability & Fault Tolerance | Multi-Centurion quorum, distributed SQLite architecture, zero single point of failure | High |
| **Art. 25** | P3 Testing | Automated Task Self-Healing & Recovery | Proactive container healthchecks and autonomous task restart loops | High |
| **Art. 26** | P3 Testing | Continuous Compliance & Resilience Testing | Autonomous 15-minute background watchdog with reactive re-evaluation triggers | High |
| **Art. 28(8)** | P4 3rd-Party | Cloud Exit Strategy & Workload Portability | Standard `docker-compose.yml` specs allowing instant migration across bare metal & clouds | High |
| **Art. 30(2)** | P4 3rd-Party | Supply Chain Verification: Cryptographic Signatures | In-cluster Cosign ECDSA P-256 signature generation and image verification | Medium |
| **Art. 30(3)** | P4 3rd-Party | Third-Party Dependencies: Software Bill of Materials | Native CycloneDX and SPDX JSON SBOM generator with vulnerability scoring | Medium |
| **Art. 30(4)** | P4 3rd-Party | Admission Control: Pre-Deployment Policy Engine | In-cluster Gatekeeper enforcing signature validation and blocking critical CVEs | High |
| **Art. 45(1)** | P5 Reporting | Technical Operational Resilience Reporting | One-click export of formal supervisory compliance reports in Markdown and JSON | Medium |
| **Art. 45(2)** | P5 Reporting | Continuous Telemetry & Prometheus Discovery | Native Prometheus gauge `gbnt_compliance_score{framework="dora"}` on port 4002 | Low |

---

## 🖥️ 3. Web UI DORA Dashboard

The DORA Compliance Dashboard is accessible in the Flutter Web UI under **Security & Directory** ➔ **🏛️ EU DORA (Reg. 2022/2554)**:

* **Watchdog Header Mini-KPI:** Live amber chip displaying the real-time DORA readiness percentage (e.g., `93.5%`) and instant status indication.
* **5 Pillar Cards:** High-density metric tiles visualizing compliance scores for P1 ICT Risk, P2 Incident Management, P3 Resilience Testing, P4 Third-Party Risk, and P5 Information Sharing.
* **Interactive Controls Explorer:** Filter the 16 statutory measures by Pillar (All, P1, P2, P3, P4, P5) and Status (All, Compliant, Partial, Non-Compliant, Action Required).
* **Detailed Measure Inspection:** Each card renders the Regulation Article, Pillar tag, current percentage, discovered cluster technical evidence, and copyable remediation commands.
* **Supervisory Report Modal:** Generates an official, publication-ready audit document in CommonMark and JSON formatted for national competent authorities (EBA, EIOPA, ESMA, Banco de España, CNMV).

---

## 💻 4. CLI Parity: `gbnt dora`

Gubernator provides full terminal parity for inspecting and reporting DORA posture:

### Interactive Terminal Audit
```bash
gbnt dora
```
Outputs a colored overview of the 5 statutory pillars, overall readiness rating, and an itemized table of all 16 evaluated measures with status flags and live cluster evidence.

### Supervisory Report Generation
```bash
# Output full formal supervisory report to stdout in Markdown
gbnt dora --report

# Export structured JSON report for automated compliance pipelines
gbnt dora --report --format json > dora-audit-report.json

# Export clean plain text report
gbnt dora -r -f text
```

---

## 🌐 5. REST API Endpoints

| Method | Endpoint | Description | Auth Required |
| :--- | :--- | :--- | :---: |
| `GET` | `/api/security/dora/status` | Returns complete DORA summary, pillar scores, readiness grade, and 16 granular measure checks | Bearer / Session |
| `GET` | `/api/security/dora/report` | Generates official supervisory audit report (`?format=markdown\|json\|text`) | Bearer / Session |
| `GET` | `/v1/security/dora/status` | Core API v1 alias for automated CI/CD pipelines | Bearer Token |
| `GET` | `/v1/security/dora/report` | Core API v1 alias for report generation | Bearer Token |

---

## 🔄 6. Continuous Compliance Watchdog & Degradation Alerts

The Gubernator **Continuous Compliance Watchdog** runs as an autonomous background daemon on a 15-minute scheduler:
* Continuously evaluates DORA alongside ENS, NIS 2, CIS Docker, and ISO 27001 in parallel goroutines.
* Reactively triggers instant re-evaluations whenever a security configuration changes (MFA toggle, Gatekeeper policy update, SIEM change, new backup created).
* Detects any compliance score degradation exceeding **1.0%** and immediately records a `COMPLIANCE_DEGRADED` event in the immutable SHA-256 forensic audit ledger.
* Exports live gauges to Prometheus:
  ```promql
  gbnt_compliance_score{framework="dora"}
  ```
