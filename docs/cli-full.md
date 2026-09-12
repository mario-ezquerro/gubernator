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
  Lists automated recurring backup cron policies and retention rotations.

