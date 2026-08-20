# SPEC-image-security.md — Gubernator Image Security, SBOM & Signing Subsystem Specification

## 1. Overview & Vision

Gubernator's **Image Security & Supply Chain Subsystem** (*The Imperial Seal / The Armory / Armamentarium*) provides native DevSecOps capabilities directly within the orchestrator:
1. **Vulnerability Scanner (CVEs)**: Automated scanning of container images for known Common Vulnerabilities and Exposures (CVEs) with CVSS scoring and remediation tracking.
2. **Software Bill of Materials (SBOM)**: Deep dependency analysis and package/license extraction in standard **CycloneDX** and **SPDX** formats.
3. **Cryptographic Image Signing & Verification (Cosign / Sigstore)**: In-cluster ECDSA keypair management, container image signing, and OCI signature verification.
4. **Security Admission Controller (Gatekeeper)**: Pre-deployment policy enforcement capable of blocking unverified images or containers with unpatched critical vulnerabilities.

---

## 2. Architectural Design

```
                                [ Stack Deploy / Container Run Request ]
                                                 │
                                                 ▼
                        ┌─────────────────────────────────────────────────┐
                        │    GUBERNATOR ADMISSION GATEKEEPER (Port 4000)   │
                        │    - Evaluates Cluster & Stack Security Policy  │
                        └───────────────────────┬─────────────────────────┘
                                                │
                 ┌──────────────────────────────┴──────────────────────────────┐
                 ▼                                                             ▼
    ┌──────────────────────────┐                                ┌───────────────────────────┐
    │ 🔏 1. Check de Firma     │                                │ 🔍 2. Check de CVEs       │
    │    (Cosign / Sigstore)   │                                │    (Trivy / Grype)        │
    ├──────────────────────────┤                                ├───────────────────────────┤
    │ ¿Está la imagen firmada  │                                │ ¿Tiene la imagen CVEs     │
    │ por una clave de confianza?                               │ CRITICAL o HIGH?          │
    └────────────┬─────────────┘                                └─────────────┬─────────────┘
                 │                                                            │
                 ├───────── ❌ No firmada / Firma inválida                    ├───────── ❌ Supera umbral de severidad
                 │          (Si política = 'ENFORCE')                         │          (Si política = 'BLOCK_CRITICAL')
                 │                                                            │
                 ▼                                                            ▼
    ╔══════════════════════════╗                                 ╔═══════════════════════════╗
    ║  ⛔ DESPLIEGUE RECHAZADO ║                                 ║   ⛔ DESPLIEGUE BLOQUEADO ║
    ║ "Image signature missing"║                                 ║ "Found 2 Critical CVEs"   ║
    ╚══════════════════════════╝                                 ╚═══════════════════════════╝
                 │                                                            │
                 └───────────────────────┬────────────────────────────────────┘
                                         │ ✅ Pasa todas las políticas activas
                                         ▼
                        ╔═════════════════════════════════╗
                        ║ 🚀 Despliegue Permitido en Nodos║
                        ╚═════════════════════════════════╝
```

### Key Components:
- **Image Scanner Engine**: Scans container layers against vulnerability databases (NVD, OSV, Alpine SecDB, Debian Security Tracker) extracting CVE ID, severity, CVSS score, affected package, and fixed version.
- **SBOM Catalog**: Generates comprehensive inventories of OS packages (apk, dpkg, rpm) and language-level dependencies (npm, pip, go, maven, gem, cargo) alongside software licenses.
- **Cosign Signing Engine**: Generates and manages public/private keypairs, signs OCI artifacts, and verifies payload digests and signatures before execution.
- **Gatekeeper Admission Engine**: Intercepts `gbnt stack deploy` and REST API container creation requests, verifying compliance against configured security thresholds.

---

## 3. Feature Matrix (4 Specialized Modules)

| Module | Features & Capabilities |
| --- | --- |
| **1. Vulnerabilities (CVE Scanner)** | Discovers all container images across active stacks; displays summary badges (`CRITICAL`, `HIGH`, `MEDIUM`, `LOW`); detailed table with CVE IDs, CVSS scores, affected packages, fix versions, and external NVD links; 1-click on-demand scan. |
| **2. SBOM Explorer** | Full dependency tree of OS packages and runtime libraries; license compliance auditor (MIT, Apache-2.0, GPL, etc.); export SBOM in standard **CycloneDX JSON** or **SPDX JSON**. |
| **3. Image Signatures & Keys** | Signature status verification (🟢 *Verified*, 🟡 *Unsigned*, 🔴 *Invalid/Tampered*); keypair management (generate/import ECDSA Cosign keys); 1-click image signing dialog. |
| **4. Gatekeeper & Security Policies** | Configurable cluster policies: enforce signatures (`Disabled`, `Audit/Warn`, `Enforce/Block`), CVE severity threshold (`Allow All`, `Block Critical`, `Block High+Critical`, `Allow if No Fix Available`); Compose label overrides (`gbnt.security.*`). |

---

## 4. SQLite Database Schema

```sql
-- Security Policies & Admission Gatekeeper settings
CREATE TABLE security_policies (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    enforce_signatures TEXT NOT NULL DEFAULT 'audit', -- 'disabled', 'audit', 'enforce'
    block_cve_severity TEXT NOT NULL DEFAULT 'none',  -- 'none', 'critical', 'high', 'medium'
    allow_unfixed_cve BOOLEAN NOT NULL DEFAULT 1,
    trusted_registries TEXT,                          -- JSON array of allowed registries
    updated_at DATETIME
);

-- Trusted Public Signing Keys (Cosign / Sigstore)
CREATE TABLE trusted_signing_keys (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    public_key_pem TEXT NOT NULL,
    key_type TEXT NOT NULL DEFAULT 'cosign-ecdsa',
    is_default BOOLEAN NOT NULL DEFAULT 0,
    created_at DATETIME
);

-- Image Scan Reports
CREATE TABLE image_scans (
    id TEXT PRIMARY KEY,
    image_name TEXT NOT NULL,
    image_digest TEXT,
    scanned_at DATETIME NOT NULL,
    critical_count INTEGER NOT NULL DEFAULT 0,
    high_count INTEGER NOT NULL DEFAULT 0,
    medium_count INTEGER NOT NULL DEFAULT 0,
    low_count INTEGER NOT NULL DEFAULT 0,
    signature_status TEXT NOT NULL DEFAULT 'unsigned', -- 'verified', 'unsigned', 'invalid'
    signature_signer TEXT,
    signed_at DATETIME
);

-- Individual Vulnerabilities
CREATE TABLE image_vulnerabilities (
    id TEXT PRIMARY KEY,
    scan_id TEXT NOT NULL,
    cve_id TEXT NOT NULL,
    package_name TEXT NOT NULL,
    installed_version TEXT NOT NULL,
    fixed_version TEXT,
    severity TEXT NOT NULL, -- 'CRITICAL', 'HIGH', 'MEDIUM', 'LOW'
    cvss_score REAL,
    title TEXT,
    description TEXT,
    primary_url TEXT,
    FOREIGN KEY(scan_id) REFERENCES image_scans(id) ON DELETE CASCADE
);

-- Software Bill of Materials (SBOM)
CREATE TABLE image_sboms (
    id TEXT PRIMARY KEY,
    scan_id TEXT NOT NULL,
    format TEXT NOT NULL DEFAULT 'cyclonedx-json', -- 'cyclonedx-json', 'spdx-json'
    package_count INTEGER NOT NULL DEFAULT 0,
    raw_sbom_json TEXT NOT NULL,
    generated_at DATETIME NOT NULL,
    FOREIGN KEY(scan_id) REFERENCES image_scans(id) ON DELETE CASCADE
);
```

---

## 5. REST API Specification

### 5.1 Vulnerability Scans & Reports
* `GET /v1/security/scans` — List all image security scan reports and summary statistics.
* `GET /v1/security/scans/:id` — Get detailed scan report including all detected CVEs.
* `POST /v1/security/scans/trigger` — Trigger immediate vulnerability scan for a given image or stack.

### 5.2 SBOM Management
* `GET /v1/security/sbom/:image` — Retrieve SBOM dependency tree and license information.
* `GET /v1/security/sbom/:image/export?format=cyclonedx` — Export SBOM in CycloneDX or SPDX JSON.

### 5.3 Image Signing & Cosign Key Management
* `GET /v1/security/keys` — List trusted public signing keys.
* `POST /v1/security/keys/generate` — Generate a new Cosign ECDSA keypair.
* `POST /v1/security/keys` — Import an existing public signing key.
* `DELETE /v1/security/keys/:id` — Delete a trusted signing key.
* `POST /v1/security/sign` — Sign an image with an authorized private key.
* `POST /v1/security/verify` — Verify the cryptographic signature of an image.

### 5.4 Gatekeeper Policies & Admission
* `GET /v1/security/policy` — Get active cluster admission security policy.
* `PUT /v1/security/policy` — Update cluster admission security policy (requires `admin` role).

---

## 6. Docker Compose Security Labels Reference

Stacks and services can declare custom security overrides in `docker-compose.yml`:

```yaml
version: '3.8'

services:
  payment-api:
    image: company/payment-api:2.1.0
    deploy:
      labels:
        # Require valid Cosign signature before allowing deployment
        - gbnt.security.require-signature=true
        # Reject deployment if image contains CRITICAL vulnerabilities
        - gbnt.security.max-cve-severity=critical
        # Reject deployment even if no upstream fix is available yet
        - gbnt.security.allow-unfixed=false
```

---

## 7. CLI Command Reference

### Scan & Vulnerabilities
```bash
# Scan all images in active stacks
gbnt scan

# Scan a specific image
gbnt scan company/app:latest --severity CRITICAL,HIGH
```

### SBOM
```bash
# Generate and display SBOM summary
gbnt sbom company/app:latest

# Export SBOM to file
gbnt sbom company/app:latest --format cyclonedx --output sbom.json
```

### Image Signing & Verification
```bash
# Generate a new Cosign signing keypair
gbnt security key generate --name "release-key"

# Sign an image
gbnt image sign company/app:latest --key /path/to/cosign.key

# Verify image signature against trusted keys
gbnt image verify company/app:latest
```

### Gatekeeper Policy
```bash
# View current cluster security policy
gbnt security policy ls

# Enforce signature verification cluster-wide
gbnt security policy set --enforce-signatures true --max-cve critical
```
