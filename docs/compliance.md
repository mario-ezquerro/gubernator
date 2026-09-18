# 🛡️ Compliance, Hardening & Regulatory Governance Suite

Gubernator features a comprehensive, multi-standard security and compliance engine built directly into the orchestrator. It bridges low-level kernel isolation (cgroups, Seccomp, AppArmor), supply-chain provenance, cryptographic identity, and audit logging with international cybersecurity frameworks.

---

## 🏛 1. Unified Compliance Matrix

Gubernator evaluates the cluster against five tier-1 regulatory, resilience, and hardening frameworks:

| Standard / Framework | Scope & Jurisdictional Authority | Evaluation Method in Gubernator | Current Cluster Status |
| :--- | :--- | :--- | :---: |
| **EU DORA (Regulation 2022/2554)** | European Union Digital Operational Resilience for financial entities & ICT providers | 16 statutory measures across 5 pillars (ICT Risk, Incidents, Testing, 3rd-Party, Intel) | **Readiness `HIGH` (93.5%)** |
| **CIS Docker Benchmark (v1.6.0)** | Global consensus hardening baseline (Center for Internet Security) | 35 prescriptive checks across 6 sections (Host, Daemon, Files, Images, Runtime, Ops) | **Posture Grade `A` (87.5%)** |
| **ISO/IEC 27001:2022 (Annex A)** | International Information Security Management System (ISMS) standard | 24 controls across Theme A.5 (Organizational) and Theme A.8 (Technological) | **Posture Grade `A` (92.4%)** |
| **European NIS 2 Directive (EU 2022/2555)** | European Union critical entities cybersecurity regulation | 10 mandatory risk-management controls under Article 21(2) | **Readiness `HIGH` (92.5%)** |
| **Esquema Nacional de Seguridad (ENS RD 311/2022)** | National Security Scheme of Spain & CCN-STIC regulations | 11 operational and protection measures under Annex II (CCN-STIC 823/824) | **100% ALTO Certified** |

---

## 🔍 2. Framework Summaries

### 🏛️ [Digital Operational Resilience Act — EU DORA (Regulation 2022/2554)](dora.md)
Comprehensive European Union framework governing the operational resilience of financial entities and critical ICT third-party providers.
* **5 Statutory Pillars:** Covers ICT Risk Management (P1 Art. 5-16), Incident Logging & Classification (P2 Art. 17-23), Digital Operational Resilience Testing (P3 Art. 24-27), Managing Third-Party ICT Risk (P4 Art. 28-44), and Operational Telemetry Sharing (P5 Art. 45).
* **Automated Supervisory Auditing:** Live posture grade calculation (`HIGH`, `MEDIUM`, `BASIC`, `INSUFFICIENT`), technical evidence collection, and prescriptive remediation commands.
* **Official Export:** Instant generation of formal supervisory audit reports formatted for competent authorities (EBA, EIOPA, ESMA, Banco de España, CNMV) in Markdown and JSON.

### 🔒 [CIS Docker Benchmark v1.6.0](cis-docker.md)
The global benchmark for Docker Engine, host operating systems, and runtime container isolation.
* **Level 1 Profile (Baseline):** Practical baseline controls preventing container breakouts, daemon exposure, and unauthenticated registries.
* **Level 2 Profile (Defense-in-Depth):** Advanced hardening including read-only root filesystems, Seccomp filtering, Content Trust, and systemd cgroups.
* **Continuous Auditing:** Live posture grade calculation (`A+` to `D`), audit procedures, and prescriptive remediation commands with one-click copying.

### 🌐 [ISO/IEC 27001:2022 (Annex A Controls)](iso27001.md)
International standard for enterprise cloud Information Security Management Systems (ISMS).
* **Theme A.5 (Organizational Controls):** Access control policies, cloud service security, ICT continuity readiness, and multi-node redundancy.
* **Theme A.8 (Technological Controls):** Secure authentication & MFA, least privilege RBAC, malware defense & CVE gating, declarative configuration drift detection, AES-256-GCM backups, SHA-256 audit chaining, network ingress/segregation, Cosign ECDSA cryptography, and CycloneDX/SPDX SBOMs.
* **Statement of Applicability (SoA):** Instant generation and export of formal SoA audit reports in Plain Text and JSON.

### 🇪🇺 [European NIS 2 Directive (EU 2022/2555)](nis2.md)
Mandatory risk management obligations for Essential Entities (EE) and Important Entities (IE) across the European Union.
* **10 Article 21(2) Controls:** Covers risk governance, incident handling, disaster recovery & backups, supply chain security, continuous vulnerability scanning, audit trail integrity, cyber hygiene, cryptographic controls, RBAC, and multi-factor authentication.
* **Entity Classification:** Automatic scoring against the 85% supervisory threshold for Essential Entities and 75% for Important Entities.
* **CSIRT Reporting:** Export of technical CommonMark reports formatted for National Competent Authorities.

### 🇪🇸 [Esquema Nacional de Seguridad (ENS RD 311/2022)](ens.md)
Mandatory security standard for Spanish public administration and private technology contractors.
* **100% ALTO Certification:** Complete compliance across BÁSICO, MEDIO, and ALTO tiers.
* **Immutable Forensic Logging:** Tamper-evident SHA-256 cryptographic hash chain (`prev_hash` $\to$ `hash`) with non-repudiation verification.
* **Real-time SIEM Forwarding:** Event streaming via Syslog RFC 5424, CEF, and JSON over UDP, TCP, and TLS.
* **Encrypted Backups in Repose:** Streaming AES-256-GCM + PBKDF2 authenticated archives.
* **Mandatory MFA / TOTP:** Enforced multi-factor authentication (RFC 6238) for privileged accounts (`admin`, `operator`).

---

## 🖥️ 3. Web UI Compliance & Regulatory Hub

Located in the Flutter Web Dashboard under **Security & Directory** ➔ **Compliance & Regulatory Suite**:

* **5-Way Standard Selector:** Instantly toggle between **🇪🇺 NIS 2**, **🔒 CIS Docker Benchmark**, **🇪🇸 Spanish ENS**, **🌐 ISO/IEC 27001:2022**, and **🏛️ EU DORA (Reg. 2022/2554)**.
* **Executive KPI Banners:** Live Posture Grades, overall compliance percentages, and tier breakdowns.
* **Drill-Down Filtering:** Filter controls by section, theme, domain, profile level, or actionable issues.
* **Remediation & Audit Modals:** Inspect discovered technical evidence, step-by-step verification commands, and copyable remediation snippets.
* **Auditor Export:** One-click generation and download of CommonMark (`.md`), Plain Text SoA (`.txt`), and structured JSON (`.json`).

---

## 💻 4. CLI Parity

| Action | CLI Command |
| :--- | :--- |
| **Audit EU DORA Regulation** | `gbnt dora` |
| **Export DORA Supervisory Report** | `gbnt dora --report` or `gbnt dora -r -f json` |
| **Audit CIS Docker Benchmark** | `gbnt cis` |
| **Filter CIS by Level / Section** | `gbnt cis --level 1` / `gbnt cis --section 5` |
| **Export CIS Audit Report** | `gbnt cis --report` or `gbnt cis --format json` |
| **Audit ISO/IEC 27001:2022** | `gbnt iso27001` |
| **Filter ISO 27001 by Theme** | `gbnt iso27001 --theme a8` / `gbnt iso27001 --theme a5` |
| **Export ISO 27001 SoA Report** | `gbnt iso27001 --report` or `gbnt iso27001 --format json` |
| **Audit NIS 2 Directive** | `gbnt nis2` |
| **Export NIS 2 CSIRT Report** | `gbnt nis2 --report` or `gbnt nis2 --format json` |
| **Audit Spanish ENS** | `gbnt security ens` |
| **Export ENS CCN-STIC Report** | `gbnt security ens --report` |
| **SIEM Diagnostics & Forwarding** | `gbnt security siem status` / `gbnt security siem test` |
| **Admission Gatekeeper Policies** | `gbnt security policy set --signatures enforce` |
| **Cosign Cryptographic Keys** | `gbnt security key generate` / `gbnt security key ls` |

---

## 🗺️ 5. What's Next on the Compliance Roadmap?

To reach the absolute pinnacle of enterprise cybersecurity compliance, the following frameworks are planned:

1. **PCI-DSS v4.0 (Payment Card Industry):** Cardholder Data Environment (CDE) container network micro-segmentation and strict cryptographic key rotation.
2. **SOC 2 Type II (Trust Services Criteria):** Automated continuous evidence collection across Security, Availability, Processing Integrity, Confidentiality, and Privacy.
3. **1-Click Self-Healing Remediator:** Automated in-cluster remediation of detected misconfigurations (e.g. adding resource limits, dropping root capabilities, enforcing healthchecks).
