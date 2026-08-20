---
title: Building Enterprise Storage, Backups & Cosign Image Security in Go & Flutter with Google Antigravity
published: false
description: How we engineered multi-node shared storage mobility, automated point-in-time backups, CVE scanning, CycloneDX/SPDX SBOMs, and Cosign image signing in Gubernator with Google Antigravity AI.
tags: go, devops, security, docker, ai
cover_image: https://raw.githubusercontent.com/mario-ezquerro/gubernator/main/docs/images/banner.png
---

# 🏛️ Building Enterprise Storage, Point-in-Time Backups & Cosign Image Security in Go & Flutter with Google Antigravity

When architecting a modern container orchestrator like **[Gubernator (gbnt)](https://github.com/mario-ezquerro/gubernator)** — designed to strike the **Goldilocks balance** between the simplicity of Docker Swarm and the placement flexibility of Nomad — two major enterprise pillars stand between an MVP and true production readiness:

1. **State Persistence & Backup Mobility (*The Granaries / Horreum*)**: Moving stateful containers (PostgreSQL, MySQL, Redis, custom data volumes) across worker nodes without data loss, backed by compressed point-in-time snapshots and retention policies.
2. **Software Supply Chain Security & Admission Control (*The Imperial Seal / Armamentarium*)**: Detecting CVE vulnerabilities before deployment, cataloging dependencies via Software Bill of Materials (SBOM), signing container images with cryptographic keypairs (Cosign/Sigstore), and enforcing strict Gatekeeper admission policies.

In this article, we break down how we designed and implemented these two major subsystems in **Gubernator v2.24.0 & v2.25.0**, and how we leveraged **Google Antigravity (AGY)** as an autonomous AI engineering partner to architect, implement, test, and live-deploy Full-Stack features (Go + SQLite + Flutter Web + CLI) across a live 3-node multi-host cluster.

---

## 🏗️ Part 1: Persistent Storage & The Backup Subsystem (*The Granaries*)

Stateful container workloads present a fundamental orchestration challenge: **how can a container move between different physical hosts while maintaining access to its persistent disk storage?**

```
 ┌─────────────────────────────────────────────────────────────────────────┐
 │                   GUBERNATOR STORAGE & BACKUP ENGINE                     │
 ├─────────────────────────────────────────────────────────────────────────┤
 │  📁 /var/contenedores (Shared Mobility Pool: NFS, GlusterFS, CephFS)    │
 │  📦 Point-in-Time Compressed Tarballs (.tar.gz) + SHA-256 Checksums     │
 │  ⏱️ Background Cron Scheduler & Automated Retention Pruning            │
 │  ⏸️ Zero-Downtime Consistent Freeze (docker pause -> tar -> unpause)    │
 └─────────────────┬───────────────────────────────────┬───────────────────┘
                   │                                   │
                   ▼                                   ▼
      ┌─────────────────────────┐         ┌─────────────────────────┐
      │  Centurion 1 (Manager)  │         │  Centurion 2 (Worker 1) │
      │   IP: 192.168.252.27    │         │   IP: 192.168.252.25    │
      │  Mount: /var/contened.. │         │  Mount: /var/contened.. │
      └─────────────────────────┘         └─────────────────────────┘
```

### 1. Shared Storage Mobility (`/var/contenedores`)
Gubernator standardizes volume mobility by designating `/var/contenedores` across all cluster nodes. When backed by a distributed file system (NFS, GlusterFS, CephFS, CIFS) or localized volumes:
- The orchestrator can dynamically schedule database or application containers to any active Centurion host.
- The storage explorer inspects and displays disk utilization (`used / total`, percentage, and node read/write mount health).

### 2. Database-Consistent Snapshots with Docker Freeze
Backing up a running relational database (PostgreSQL, MariaDB, SQLite) while active transactions are in flight risks data corruption. 

We implemented an optional **Atomic Freeze Strategy**:
```go
// internal/storage/backup.go
func CreateBackup(name, targetPath, stackName, serviceName string, pauseContainer bool) (*db.Backup, error) {
    if pauseContainer && containerID != "" {
        slog.Info("backup: pausing container for consistent snapshot", "container", containerID)
        _ = dockerClient.ContainerPause(ctx, containerID)
        defer dockerClient.ContainerUnpause(ctx, containerID)
    }

    // Stream directory to tar.gz with SHA-256 calculation
    archiveFile, sha256Checksum, sizeBytes, err := archiveDirectory(targetPath, destFile)
    if err != nil {
        return nil, err
    }
    // ... Save record to SQLite ...
}
```

### 3. Automated Cron Policies & Retention Rotation
Gubernator's background backup daemon evaluates standard cron expressions (e.g. `0 2 * * *` for nightly 2:00 AM backups) and automatically prunes older snapshots according to a configured retention count (e.g. keep last 7 copies).

---

## 🛡️ Part 2: Image Security, SBOM & Cosign Cryptography (*The Imperial Seal*)

Deploying third-party container images blindly introduces severe supply-chain risks. In **v2.25.0**, we introduced a complete **Pre-Deployment Admission Gatekeeper**:

```
                         [ Stack Deploy / Container Run Request ]
                                          │
                                          ▼
                 ┌──────────────────────────────────────────────────┐
                 │     GUBERNATOR ADMISSION GATEKEEPER (Port 4000)   │
                 │     - Evaluates Cluster & Stack Security Policy  │
                 └────────────────────────┬─────────────────────────┘
                                          │
          ┌───────────────────────────────┴───────────────────────────────┐
          ▼                                                               ▼
 ┌───────────────────────────┐                                 ┌───────────────────────────┐
 │ 🔏 1. Cryptographic Sign  │                                 │ 🔍 2. CVE Vulnerability   │
 │    (Cosign / Sigstore)    │                                 │    Scanning & CVSS Scores │
 ├───────────────────────────┤                                 ├───────────────────────────┤
 │ Is the image signed with  │                                 │ Does image exceed Max     │
 │ a trusted cluster key?    │                                 │ Severity (Critical/High)? │
 └─────────────┬─────────────┘                                 └─────────────┬─────────────┘
               │                                                             │
               ├───────── ❌ Unsigned / Invalid                              ├───────── ❌ Exceeds Threshold
               │          (If policy = 'ENFORCE')                            │          (If policy = 'BLOCK')
               ▼                                                             ▼
 ╔═══════════════════════════╗                                 ╔═══════════════════════════╗
 ║  ⛔ DEPLOYMENT REJECTED   ║                                 ║   ⛔ DEPLOYMENT BLOCKED   ║
 ║ "Signature check failed"  ║                                 ║ "Found 2 Critical CVEs"   ║
 ╚═══════════════════════════╝                                 ╚═══════════════════════════╝
               │                                                             │
               └──────────────────────────┬──────────────────────────────────┘
                                          │ ✅ Passes All Admission Checks
                                          ▼
                         ╔═════════════════════════════════╗
                         ║ 🚀 Container Scheduled on Hosts ║
                         ╚═════════════════════════════════╝
```

### 1. Pure Go Cosign ECDSA Keypair Generation & Signing
To eliminate heavy external binary dependencies like `cosign` or CGO toolchains, we implemented the cryptographic signing engine using Go's standard library (`crypto/ecdsa`, `crypto/elliptic`, `crypto/x509`, `crypto/sha256`):

```go
// internal/security/signing.go
func GenerateCosignKeypair(name string) (pubPEM string, privPEM string, err error) {
    privKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
    if err != nil {
        return "", "", err
    }

    privBytes, _ := x509.MarshalECPrivateKey(privKey)
    privPEMBlock := &pem.Block{Type: "EC PRIVATE KEY", Bytes: privBytes}
    privPEM = string(pem.EncodeToMemory(privPEMBlock))

    pubBytes, _ := x509.MarshalPKIXPublicKey(&privKey.PublicKey)
    pubPEMBlock := &pem.Block{Type: "PUBLIC KEY", Bytes: pubBytes}
    pubPEM = string(pem.EncodeToMemory(pubPEMBlock))

    return pubPEM, privPEM, nil
}
```

### 2. Multi-Standard SBOM Generator (CycloneDX & SPDX)
For software inventory audits and compliance, Gubernator automatically analyzes container image layers, extracts packages and OS libraries (musl, glibc, OpenSSL, busybox), and exports standardized Software Bill of Materials in:
- **CycloneDX 1.5 JSON**
- **SPDX 2.3 JSON**

### 3. Cluster-Wide Auto-Discovery & Host Mapping
Rather than requiring users to register images manually, Gubernator continuously discovers all container images running across every node in the cluster (`Manager`, `Worker 1`, `Worker 2`). The UI dynamically renders **host badges and service tags** indicating where every container instance is hosted.

---

## 🎨 Part 3: The Flutter Web Dashboard Visualization

Gubernator's Web Dashboard (Port 4001) provides two rich Material Design 3 interfaces:

### Storage & Backups (The Granaries)
- **Volumes Table**: Displays Named Volumes, Shared Pools, and Host Bind Mounts with live disk usage calculations.
- **Snapshot Manager**: 1-click on-demand backup creation, direct `.tar.gz` browser downloads, and backup restore modals.
- **Pool Health Matrix**: Validates mount availability, read/write permissions, and free disk space across all cluster hosts.

### Image Security & SBOM (The Imperial Seal)
- **🔍 Vulnerabilities Tab**: Real-time image catalog displaying Critical, High, Medium, Low CVE counts, verified signature badges, and host mappings (`Used in: caddy, promtail on Manager, Worker 1, Worker 2`).
- **📦 SBOM Explorer Tab**: Component dependency tree with license compliance auditing and 1-click CycloneDX/SPDX downloads.
- **🔏 Signatures & Keys Tab**: In-cluster Cosign ECDSA keypair generator and image signing terminal.
- **📜 Gatekeeper Policies Tab**: Interactive admission policy switches (`Audit / Warn Only` vs `Strict Enforcement`, CVE severity threshold blocking).

---

## ⚡ Part 4: Full CLI Parity

Every capability is accessible directly through the `gbnt` CLI:

```bash
# === Storage & Backups ===
gbnt volume ls
gbnt backup ls
gbnt backup create --name "postgres-nightly" --pause /var/contenedores/postgres
gbnt backup restore <backup-id> --target /var/contenedores/postgres

# === Image Security & SBOM ===
gbnt scan
gbnt scan postgres:16-alpine
gbnt sbom postgres:16-alpine --format cyclonedx-json > sbom.json

# === Cosign Signing & Verification ===
gbnt security key generate --name "prod-release-key"
gbnt image sign company/payments:2.1.0 --key /path/to/private.key
gbnt image verify company/payments:2.1.0

# === Cluster Gatekeeper Policy ===
gbnt security policy
```

---

## 🤖 Part 5: How We Built This with Google Antigravity (AGY)

Building a distributed orchestrator with state synchronization, cryptographic operations, cross-compilation, and Full-Stack Web UIs is an intricate endeavor. Here is how **Google Antigravity** accelerated development:

### 1. Specification-Driven Engineering
Before writing code, we used Antigravity to formalize comprehensive architectural blueprints:
- [`SPEC-storage-backups.md`](https://github.com/mario-ezquerro/gubernator/blob/main/SPEC-storage-backups.md)
- [`SPEC-image-security.md`](https://github.com/mario-ezquerro/gubernator/blob/main/SPEC-image-security.md)

Having structured specifications allowed the AI to implement the entire pipeline (GORM database schemas, pure Go cryptography, REST API routes, Flutter Dart models, and CLI flags) with complete architectural alignment.

### 2. Autonomous Root-Cause Debugging
During initial testing of the backup scheduler, we encountered a recursive mutex deadlock: `StartBackupScheduler()` was holding `cronMutex.Lock()` while calling `SyncSchedules()`, which also attempted to acquire `cronMutex.Lock()`. Antigravity inspected the call graph, refactored `syncSchedulesLocked()`, and verified thread-safety without human intervention.

### 3. Live Cluster Deployment & Verification
Antigravity seamlessly built Linux ARM64 binaries (`CGO_ENABLED=0 GOOS=linux GOARCH=arm64`), transferred them to a live 3-node Multipass virtualized cluster (`gbnt-manager`, `gbnt-worker1`, `gbnt-worker2`), and executed live HTTP and CLI verification checks against Port 4000, 4001, and 4002.

---

## 🏁 Conclusion & What's Next

With **Storage & Backups (v2.24.0)** and **Image Security & Cosign (v2.25.0)**, Gubernator bridges the gap between lightweight simplicity and enterprise-grade resilience.

Whether you are running a single-node homelab or an edge-distributed cluster, you can now:
- Run stateful databases with confidence using point-in-time compressed backups.
- Secure your software supply chain with automated CVE scanning and Cosign cryptographic signatures.

Explore the project on GitHub:
👉 **[GitHub: mario-ezquerro/gubernator](https://github.com/mario-ezquerro/gubernator)**
📖 **[Official Documentation & Guides](https://mario-ezquerro.github.io/gubernator/)**

*Have you implemented image signing or shared volume mobility in your container setups? Share your thoughts in the comments below!*
