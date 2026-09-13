# 🛡️ Compliance, Hardening & Regulatory Governance Suite

Gubernator features a comprehensive, multi-standard security and compliance engine built directly into the orchestrator. It bridges low-level kernel isolation (cgroups, Seccomp, AppArmor), supply-chain provenance, cryptographic identity, and audit logging with international cybersecurity frameworks.

---

## 🏛 1. Unified Compliance Matrix

Gubernator evaluates the cluster against three tier-1 regulatory and hardening frameworks:

| Standard / Framework | Scope & Jurisdictional Authority | Evaluation Method in Gubernator | Current Cluster Status |
| :--- | :--- | :--- | :---: |
| **CIS Docker Benchmark (v1.6.0)** | Global consensus hardening baseline (Center for Internet Security) | 35 prescriptive checks across 6 sections (Host, Daemon, Files, Images, Runtime, Ops) | **Posture Grade `A` (87.5%)** |
| **European NIS 2 Directive (EU 2022/2555)** | European Union critical entities cybersecurity regulation | 10 mandatory risk-management controls under Article 21(2) | **Readiness `HIGH` (92.5%)** |
| **Esquema Nacional de Seguridad (ENS RD 311/2022)** | National Security Scheme of Spain & CCN-STIC regulations | 11 operational and protection measures under Annex II (CCN-STIC 823/824) | **100% ALTO Certified** |

---

## 🔍 2. Framework Summaries

### 🔒 [CIS Docker Benchmark v1.6.0](cis-docker.md)
The global benchmark for Docker Engine, host operating systems, and runtime container isolation.
* **Level 1 Profile (Baseline):** Practical baseline controls preventing container breakouts, daemon exposure, and unauthenticated registries.
* **Level 2 Profile (Defense-in-Depth):** Advanced hardening including read-only root filesystems, Seccomp filtering, Content Trust, and systemd cgroups.
* **Continuous Auditing:** Live posture grade calculation (`A+` to `D`), audit procedures, and prescriptive remediation commands with one-click copying.

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

* **3-Way Segmented Pill Switcher:** Instantly toggle between **🇪🇺 NIS 2**, **🔒 CIS Docker Benchmark**, and **🇪🇸 Spanish ENS**.
* **Executive KPI Banners:** Live Posture Grades, overall compliance percentages, and tier breakdowns.
* **Drill-Down Filtering:** Filter controls by section, domain, profile level, or actionable issues.
* **Remediation & Audit Modals:** Inspect discovered technical evidence, step-by-step verification commands, and copyable remediation snippets.
* **Auditor Export:** One-click generation and download of CommonMark (`.md`) reports and structured JSON (`.json`).

---

## 💻 4. CLI Parity

| Action | CLI Command |
| :--- | :--- |
| **Audit CIS Docker Benchmark** | `gbnt cis` |
| **Filter CIS by Level / Section** | `gbnt cis --level 1` / `gbnt cis --section 5` |
| **Export CIS Audit Report** | `gbnt cis --report` or `gbnt cis --format json` |
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

1. **ISO/IEC 27001:2022 (Annex A Controls):** Information security management system controls specifically mapped to container lifecycle and DevOps pipelines.
2. **PCI-DSS v4.0 (Payment Card Industry):** Cardholder Data Environment (CDE) container network micro-segmentation and strict cryptographic key rotation.
3. **SOC 2 Type II (Trust Services Criteria):** Automated continuous evidence collection across Security, Availability, Processing Integrity, Confidentiality, and Privacy.
4. **1-Click Self-Healing Remediator:** Automated in-cluster remediation of detected misconfigurations (e.g. adding resource limits, dropping root capabilities, enforcing healthchecks).
