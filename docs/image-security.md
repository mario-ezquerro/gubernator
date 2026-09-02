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

### 3. 🔏 Image Signatures & Keys (Cosign) & Signed Images Registry
* **In-Cluster Keypair Management**: Generate ECDSA P-256 Cosign-compatible keypairs directly in-cluster with secure SQLite persistence.
* **Signed Images Registry**: Catalog of all signed container images in the cluster, indicating the signer identity, algorithm (`ECDSA P-256`), digest (`sha256:...`), and physical host availability.
* **1-Click Signing & Quick Sign**: Sign container images with default or selected keypairs without manual PEM copy-pasting.
* **🌐 Multi-Host Image & Signature Distribution**: Stream and synchronize locally built or signed container images across all Centurion worker nodes via internal cluster bridge, ensuring immediate availability on any host without requiring an external registry.

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

Stacks can declare Zero-Trust container security rules directly in `docker-compose.yml`:

```yaml
version: '3.8'

services:
  payment-api:
    image: company/payment-api:2.1.0
    labels:
      # Require valid Cosign signature before allowing deployment
      gbnt.security.require-signature: "true"
      # Reject deployment if image contains CRITICAL vulnerabilities (CVSS >= 9.0)
      gbnt.security.max-cve-severity: "critical"
      # Reject deployment even if no upstream fix is available yet
      gbnt.security.allow-unfixed-cve: "false"
      # (Optional) Enforce signature by a specific key identity
      gbnt.security.signer: "Cluster Administrator"
    deploy:
      replicas: 2
```

### Supported Security Labels

| Label | Supported Values | Description |
| :--- | :--- | :--- |
| `gbnt.security.require-signature` | `"true"`, `"false"` | Enforces cryptographic Cosign verification before the container can start. |
| `gbnt.security.max-cve-severity` | `"critical"`, `"high"`, `"medium"`, `"none"` | Threshold above which deployments are rejected by Gatekeeper. |
| `gbnt.security.allow-unfixed-cve` | `"true"`, `"false"` | Rejects deployment on CVE detection even if unpatched upstream. |
| `gbnt.security.signer` | `string` | Restricts admission strictly to images signed by this signer identity. |

---

## 🌐 Multi-Host Image & Signature Distribution Engine

Gubernator allows distributing locally compiled or signed container images across the entire cluster without needing an external Docker registry (such as Docker Hub, Harbor, or ECR):

1. **Internal Cluster Bridge**: The Manager saves the image (`docker save`) and streams it over high-speed SSH pipes directly to target Centurion worker nodes (`docker load`).
2. **Cluster-Wide Synchronized Admission**: When a stack with `gbnt.security.require-signature=true` is scheduled, Gatekeeper validates the signature against the cluster's trusted key database and any Centurion worker can immediately execute the container.
3. **1-Click UI & CLI Execution**: Trigger distribution directly from the web dashboard with `Distribute` buttons or via `gbnt image distribute <image> [--node all|worker-id]`.

---

## 🔨 Image Lifecycle, Layer Inspector & The Imperial Forge

Gubernator provides full host image management directly from the dashboard and CLI:

1. **🧹 Host Disk Pruner (`docker image prune -a -f`)**: Removes unused and dangling images across all Centurion nodes, reporting exact reclaimed space.
2. **📜 Layer History & Dockerfile Reconstruction**: Inspects chronological layer commands (`docker history`), byte sizes, and reverse-engineers a valid `Dockerfile` with 1-click clipboard copy.
3. **🔨 The Imperial Forge**: In-browser Dockerfile builder with multi-stage blueprints, target Centurion selection, build arguments, and live streaming compilation terminal.

---

## 💻 CLI Command Reference

### Docker Host Images, Distribution & Build Forge
```bash
# List physical Docker images across cluster nodes
gbnt image ls [--node <node>]

# Distribute and load an image across all or specific Centurion worker nodes
gbnt image distribute <image> [--node all|worker-id]

# Inspect layer history and reverse-engineer Dockerfile
gbnt image history <image> [--node <node>]

# Remove an image from cluster hosts (docker rmi)
gbnt image rm <image> [--node <node>] [--force]

# Prune unused images and reclaim cluster disk space
gbnt image prune [--all] [--node <node>]

# Compile a new image from Dockerfile in The Forge
gbnt image build -t my-app:v1.0 -f Dockerfile [--node <node>]
```

### Scan Images & Vulnerabilities
```bash
# List all scanned images and severity metrics
gbnt scan

# Scan a specific image on-demand
gbnt scan postgres:16-alpine

# Prune stale scans for images no longer used in active stacks
gbnt scan prune
```

### Export SBOM (Software Bill of Materials)
```bash
# Export in CycloneDX JSON
gbnt sbom postgres:16-alpine --format cyclonedx-json

# Export in SPDX JSON
gbnt sbom postgres:16-alpine --format spdx-json
```

### Cryptographic Signing, Verification & Revocation (Cosign)
```bash
# Generate in-cluster ECDSA keypair (private key stored securely in SQLite)
gbnt security key generate --name "Imperial Cluster Authority"

# Sign an image using in-cluster key or manual private key
gbnt image sign company/app:1.0

# Verify image signature against trusted keys
gbnt image verify company/app:1.0

# Revoke / remove cryptographic signature from an image
gbnt image unsign company/app:1.0
```

---

## 📡 REST API Reference

| Endpoint | Method | Role | Description |
| :--- | :--- | :--- | :--- |
| `/v1/images/host-list` | `GET` | `all` | List physical Docker images on Manager and Centurion nodes |
| `/v1/images/history` | `GET` | `all` | Inspect layer timeline and reconstructed Dockerfile |
| `/v1/images/host-delete` | `DELETE` | `operator` | Delete physical image from target or all nodes |
| `/v1/images/prune` | `POST` | `operator` | Prune unused images across hosts and return reclaimed space |
| `/v1/images/build` | `POST` | `operator` | Compile Dockerfile in The Forge with streaming logs |
| `/v1/images/distribute` | `POST` | `operator` | Distribute and load image across Centurion worker nodes |
| `/v1/security/scans` | `GET` | `all` | List all image vulnerability scans and summary metrics |
| `/v1/security/scans/:id` | `GET` | `all` | Get detailed scan report with all CVEs |
| `/v1/security/scans/trigger` | `POST` | `operator` | Trigger immediate vulnerability scan |
| `/v1/security/scans/prune-orphans` | `POST` | `operator` | Purge scans for images not used in active stacks |
| `/v1/security/sbom?image=...` | `GET` | `all` | Retrieve or export image SBOM (CycloneDX / SPDX) |
| `/v1/security/keys` | `GET` | `all` | List trusted signing keys with in-cluster status |
| `/v1/security/keys/generate` | `POST` | `admin` | Generate new Cosign ECDSA keypair with persistent private key |
| `/v1/security/sign` | `POST` | `operator` | Cryptographically sign image with in-cluster or manual key |
| `/v1/security/unsign` | `POST` | `operator` | Revoke/remove cryptographic signature from image |
| `/v1/security/policy` | `GET` | `all` | Get active cluster admission policy |
| `/v1/security/policy` | `POST` | `admin` | Update cluster admission policy |
| `/v1/security/evaluate` | `POST` | `all` | Evaluate image admission against Gatekeeper rules |


