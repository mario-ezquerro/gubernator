# Image Security, SBOM & Cryptographic Signing (The Imperial Seal)

Gubernator features a native **Image Security & Supply Chain Subsystem** (*The Imperial Seal / The Armory / Armamentarium*) providing automated CVE vulnerability scanning, Software Bill of Materials (SBOM) generation in **CycloneDX** and **SPDX** formats, **Cosign** ECDSA image signing and verification, and pre-deployment **Gatekeeper** admission control.

---

## 🏛 Architecture & Security Pipeline

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

---

## 🎨 Web UI Visualization Suite

Access **Image Security & SBOM** in the Web Dashboard (Port 4001) to interact with 4 specialized tabs:

### 1. 🔍 Vulnerabilities (CVE Scanner)
* **Image Catalog**: Discovers all images deployed across Legions/Stacks.
* **Severity Breakdown**: Color-coded badges for `CRITICAL`, `HIGH`, `MEDIUM`, and `LOW` CVE counts.
* **CVE Inspection**: Detailed dialog displaying CVE IDs, CVSS scores, affected packages, fixed versions, descriptions, and direct links to NIST / NVD.
* **1-Click Scan**: Trigger on-demand security scans for any container image tag.

### 2. 📦 SBOM Explorer (Software Bill of Materials)
* **Dependency Tree**: Inspects base OS packages (musl, busybox, libssl, glibc) and language runtime libraries.
* **License Compliance**: Highlights software licenses (MIT, Apache-2.0, BSD, GPL) for legal audit compliance.
* **1-Click Export**: Export the full SBOM in **CycloneDX JSON** or **SPDX JSON** format.

### 3. 🔏 Image Signatures & Keys (Cosign)
* **Keypair Management**: Generate ECDSA P-256 Cosign-compatible keypairs directly in-cluster or import external public keys.
* **Verification Status**: Displays whether images are 🟢 *Verified* or 🟡 *Unsigned*.
* **1-Click Signing**: Sign container images with private keys stored or entered securely.

### 4. 📜 Gatekeeper Policies (Admission Controller)
* **Signature Enforcement**:
  - `Disabled`: Allow any container image.
  - `Audit / Warn Only`: Allow unsigned images but flag with warning badges in the dashboard.
  - `Strict Enforcement`: ⛔ Reject container deployments if the image is not cryptographically signed by a trusted key.
* **CVE Severity Admission Gate**:
  - `Allow All`: No vulnerability blocking.
  - `Block on CRITICAL`: ⛔ Block deployment if the image contains known Critical CVEs.
  - `Block on HIGH and CRITICAL`: ⛔ Strict compliance blocking High and Critical CVEs.
* **Unfixed CVE Allowance**: Toggle whether to allow images if no official patch/fix is available yet.

---

## 🚀 Docker Compose Security Labels Reference

Stacks can declare custom security rules in `docker-compose.yml`:

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

## 💻 CLI Command Reference

### Scan Images
```bash
# List all scanned images and severity metrics
gbnt scan

# Scan a specific image
gbnt scan postgres:16-alpine
```

### Export SBOM
```bash
# Export in CycloneDX JSON
gbnt sbom postgres:16-alpine --format cyclonedx-json

# Export in SPDX JSON
gbnt sbom postgres:16-alpine --format spdx-json
```

### Sign & Verify Images
```bash
# Generate a new Cosign signing keypair
gbnt security key generate --name "production-key"

# Sign an image
gbnt image sign company/app:1.0 --key /path/to/cosign.key

# Verify image signature against trusted keys
gbnt image verify company/app:1.0
```

### Manage Gatekeeper Policies
```bash
# View current policy
gbnt security policy

# List trusted public keys
gbnt security key ls
```

---

## 📡 REST API Reference

| Endpoint | Method | Role | Description |
| :--- | :--- | :--- | :--- |
| `/v1/security/scans` | `GET` | `all` | List all image vulnerability scans and summary metrics |
| `/v1/security/scans/:id` | `GET` | `all` | Get detailed scan report with all CVEs |
| `/v1/security/scans/trigger` | `POST` | `operator` | Trigger immediate vulnerability scan |
| `/v1/security/sbom?image=...` | `GET` | `all` | Retrieve or export image SBOM (CycloneDX / SPDX) |
| `/v1/security/keys` | `GET` | `all` | List trusted public signing keys |
| `/v1/security/keys/generate` | `POST` | `admin` | Generate new Cosign ECDSA keypair |
| `/v1/security/keys` | `POST` | `admin` | Import trusted public key |
| `/v1/security/keys/:id` | `DELETE` | `admin` | Delete trusted key |
| `/v1/security/sign` | `POST` | `operator` | Cryptographically sign image digest |
| `/v1/security/policy` | `GET` | `all` | Get active cluster admission policy |
| `/v1/security/policy` | `POST` | `admin` | Update cluster admission policy |
| `/v1/security/evaluate` | `POST` | `all` | Evaluate image admission against policies |
