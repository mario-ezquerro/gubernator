# Gubernator (gbnt) CLI Reference

This document serves as the complete reference for the Gubernator CLI tool (`gbnt`). All commands listed here are fully implemented and functional.

Gubernator's CLI is heavily inspired by Docker Swarm and Nomad, providing an intuitive interface for managing clusters, nodes, stacks, and individual services.

---

## 🏛 The Legion (Cluster Management)

Commands for managing the cluster lifecycle and joining nodes.

- **`gbnt legion init`**
  Initializes a new Gubernator cluster, converting the current node into the local Manager and setting up the SQLite database state.

- **`gbnt legion join --token [token] --manager [ip:4000]`**
  Joins the current machine to an existing Gubernator cluster as a Worker node.

- **`gbnt legion join-token`**
  Prints the exact command and secure token needed to join new Worker nodes to the cluster.

- **`gbnt legion leave`**
  Gracefully leaves the cluster, marking the current node as `left` in the Manager's database.

---

## 🛡 The Centurions (Node Management)

Commands executed by the Manager to inspect and control the physical worker machines.

- **`gbnt node ls`**
  Lists all registered nodes in the cluster, displaying their ID, IP, Role, and current Status (e.g., active, down).

- **`gbnt node inspect [node_id]`**
  Displays detailed JSON information about a specific node, including its assigned labels and metadata.

- **`gbnt node promote [node_id]`**
  Promotes a Worker node to a Manager node within the cluster hierarchy.

- **`gbnt node demote [node_id]`**
  Demotes a Manager node back to a standard Worker role.

- **`gbnt node update --availability [active|pause|drain|maintenance] [node_id]`**
  Changes the scheduling state of a node (e.g., set to `maintenance` or `drain` to gracefully evacuate running tasks and prevent new tasks from being assigned).

- **`gbnt node reboot [node_id]`**
  Drains running tasks off the specified node, sets its status to `maintenance`, and initiates a host system reboot. When the machine powers back up, the worker agent automatically restores the node to `active` status.

---

## 📦 The Command (Stack Management)

Commands for deploying and managing complex multi-container applications via Docker Compose syntax.

- **`gbnt stack deploy -c [docker-compose.yml] [stack_name]`**
  El parámetro `[stack_name]` es opcional si el fichero incluye una propiedad `name:` en la raíz, o una constraint `stack.name == <nombre>`.
  Deploys or updates an entire stack of services based on a Compose file. Supports parsing `deploy.placement.constraints` for targeted scheduling.

- **`gbnt stack ls`**
  Lists all currently deployed stacks across the cluster.

- **`gbnt stack services [stack_id]`**
  Lists all the individual services that belong to a specific deployed stack.

- **`gbnt stack rm [stack_id]`**
  Removes a stack completely, cascading the deletion to stop and remove all associated services and tasks.

---

## ⚔️ The Cohorts (Service Management)

Commands for managing individual services (which are usually created via Stacks).

- **`gbnt service ls`**
  Lists all active services running across the cluster, along with their desired replica counts and image names.

- **`gbnt service ps [service_id]`**
  Lists the actual physical containers (Tasks) running for a specific service. It displays exactly which Node is running each task and its internal Container IP.

- **`gbnt service scale [service_id]=[replicas]`**
  Updates the desired replica count for a specific service.

- **`gbnt service rm [service_id]`**
  Deletes a specific service and forces the worker nodes to stop its associated containers.

---

## 🔧 System Commands

- **`gbnt serve`**
  Starts the Gubernator Manager daemon. Boots up the REST API (`:4000`), Flutter Web Dashboard (`:4001`), and Telemetry server (`:4002`).

- **`gbnt health`**
  Checks the health of the local Gubernator process by querying `http://localhost:4002/health`. Returns exit code `0` if healthy, `1` otherwise. Used as the native Docker `HEALTHCHECK` command.

---

## 🛡️ SRE Monitor (Observability Stack)

Commands for deploying and managing a production-grade SRE monitoring stack.

- **`gbnt monitor init`**
  Deploys the full observability stack on the Manager: cAdvisor (`:8081`), Node Exporter (`:9100`), Prometheus (`:9090`), Grafana (`:3000`), Loki (`:3100`), Promtail, and Jaeger (OTLP `:4317`/`:4318`, UI `:16686`). Config files are generated in `~/.gbnt/monitor/`.

- **`gbnt monitor status`**
  Shows the running status, IP address, and exposed ports of each monitoring container.

- **`gbnt monitor stop`**
  Stops and removes all monitoring containers and the `gbnt-monitor-net` Docker network.

---

## 🔒 Security & ENS Compliance (RD 311/2022)

Commands for security governance, automated compliance auditing against the Spanish National Security Framework (ENS), software supply-chain security, and cryptographic signing.

- **`gbnt security ens`**
  Executes an automated technical compliance evaluation across 11 controls of Annex II RD 311/2022 and prints an ANSI-formatted status scorecard for BÁSICO, MEDIO, and ALTO tiers.

- **`gbnt security ens --report`**
  Generates and exports the complete technical compliance evidence report in CommonMark Markdown format ready for official CCN-STIC auditor submissions.

- **`gbnt security siem status`**
  Displays live SIEM delivery metrics, transmission success/failure counters, intrusion detection statistics, and ENS `op.mon.2` compliance status.

- **`gbnt security siem test [--host H] [--port P] [--proto UDP|TCP|TLS] [--format RFC5424|CEF|JSON]`**
  Dispatches a diagnostic test probe to verify SIEM ingestion and measures exact network roundtrip latency in milliseconds.

- **`gbnt security siem enable --host <IP> [--port <port>] [--proto <proto>] [--format <format>]`**
  Enables real-time SIEM event forwarding and elevates the ENS measure `op.mon.2` to 100% COMPLIANT.

- **`gbnt security siem disable`**
  Disables real-time SIEM event forwarding.

- **`gbnt scan [image]`**
  Scans container images for CVE vulnerabilities and displays CVSS severity metrics.

- **`gbnt sbom [image]`**
  Generates Software Bill of Materials in CycloneDX JSON or SPDX JSON.

- **`gbnt image sign [image] --key [key_file]`**
  Cryptographically signs a container image digest using ECDSA P-256 (Cosign compatible).

- **`gbnt security policy [audit|enforce]`**
  Configures the Gatekeeper admission controller mode for verifying image signatures before container scheduling.

---

## 💾 Persistent Storage & Encrypted Backups

Commands for managing multi-node storage pools, Docker volumes, and encrypted backups.

- **`gbnt volume ls`**
  Lists all discovered volumes across Centurion nodes with their physical host residency, mountpoints, and disk usage.

- **`gbnt backup create [volume_or_stack] [--name NAME] [--encrypt] [--password PASS] [--pause]`**
  Creates a point-in-time compressed backup. When `--encrypt` is passed, encrypts the payload using AES-256-GCM authenticated streaming with PBKDF2 key derivation (ENS `mp.si.2`).

- **`gbnt backup ls`**
  Displays catalog of all backups, sizes, SHA-256 digests, and encryption status (`🔒 AES-256` or `Plain`).

- **`gbnt backup restore [backup_id] --target [path] [--password PASS]`**
  Restores a backup into the target directory. If the archive is encrypted, validates the password and checks AEAD block integrity before decompressing.

- **`gbnt backup schedule ls`**
  Lists automated recurring backup cron policies and retention rotations with encryption status.

- **`gbnt backup schedule add --name <name> --cron <cron> [--type stack|volume|path] [--target <t>] [--dest <d>] [--retention <n>] [--encrypt] [--password <p>] [--pause]`**
  Registers an automated periodic backup schedule. Supports `--encrypt` with `--password` for AES-256-GCM encryption in repose (ENS `op.exp.10` / `mp.si.2`).

- **`gbnt backup schedule rm <schedule_id>`**
  Deletes an automated backup schedule and stops its periodic execution.

---

## 🛡️ Security, Gatekeeper & ENS Compliance Subsystem

Complete CLI suite for software supply chain security, admission control, SIEM forwarding, and Esquema Nacional de Seguridad (ENS RD 311/2022) compliance auditing.

### Admission Policies & Gatekeeper (`mp.sw.2`)
- **`gbnt security policy`**
  Displays current cluster admission security policy (enforce signatures, block CVE severity, allow unfixed CVEs, trusted registries).

- **`gbnt security policy set [--signatures enforce|audit|disabled] [--block-cve critical|high|none] [--allow-unfixed] [--registries <list>]`**
  Configures admission gatekeeper policy. Mode `enforce` blocks unsigned images or images with critical/high CVEs.

### Cryptographic Keys Management (Cosign ECDSA P-256)
- **`gbnt security key ls`**
  Lists trusted public signing keys configured in the cluster.

- **`gbnt security key generate [--name <name>] [--default]`**
  Generates a new ECDSA P-256 keypair in the cluster and prints its public key PEM.

- **`gbnt security key rm <key_id>`**
  Removes a trusted signing key from the cluster.

### Image Signing, Verification & SBOM
- **`gbnt image sign <image> [--key <key.pem>] [--signer <name>]`**
  Cryptographically signs a container image digest using an in-cluster or external ECDSA key.

- **`gbnt image verify <image>`**
  Verifies the cryptographic signature of an image against trusted keys and policy.

- **`gbnt image unsign <image>`**
  Revokes/removes the cryptographic signature from an image.

- **`gbnt sbom <image> [--format cyclonedx-json|spdx-json]`**
  Generates a Software Bill of Materials in CycloneDX or SPDX format.

- **`gbnt scan <image>`**
  Triggers vulnerability scanning and CVE inspection for a container image.

### ENS Compliance Audit & SIEM
- **`gbnt security ens [--report] [--format table|json|markdown]`**
  Audits the cluster against the 11 technical measures of ENS RD 311/2022 (BÁSICO, MEDIO, ALTO). Pass `--report` for full Markdown export.

- **`gbnt security siem status`**
  Displays real-time SIEM event forwarding metrics, intrusion alerts, and collector link state.

- **`gbnt security siem test [--host <h>] [--port <p>] [--proto UDP|TCP|TLS] [--format RFC5424|CEF|JSON]`**
  Dispatches an active probe to the SIEM receiver and measures roundtrip network latency in milliseconds.

- **`gbnt security siem enable --host <h> [--port <p>] [--proto UDP|TCP|TLS] [--format RFC5424|CEF|JSON]`**
  Activates real-time SIEM forwarding, elevating measure `op.mon.2` to 100% COMPLIANT.

- **`gbnt security siem disable`**
  Disables real-time SIEM forwarding.


