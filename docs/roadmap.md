# Gubernator Roadmap

This document tracks the development journey of Gubernator, divided into "Campaigns" (Phases).

---

## Completed Phases

- [x] **Phase 1 — The Foundation ("Veni" Sprint)**
  Go project setup, Gin REST API, Cobra CLI, Swagger integration, Dockerfile.

- [x] **Phase 1.5 — The Granaries**
  SQLite state persistence via GORM. Full DB schema: Nodes, Stacks, Services, Tasks.

- [x] **Phase 2 — The Legion (Clustering)**
  `legion init`, `legion join`, Join Tokens (JWT), Node registration, Heartbeat system.

- [x] **Phase 3 — The Command (Compose & Labels)**
  `gbnt stack deploy` — full `docker-compose.yml` parser, placement constraints engine, scheduler MVP.

- [x] **Phase 4 — The Watchtowers (Observability)**
  OpenTelemetry metrics, Prometheus export, `/health` endpoint — all isolated on port 4002.

- [x] **Phase 5.1 — The Executor (Docker Bridge)**
  Worker-side container execution: `docker pull` + `docker run` with automatic task-ID labeling.

- [x] **Phase 5.2 — The Aqueducts (Ingress & DNS)**
  CoreDNS hosts file generation. Caddy `Caddyfile` auto-generation from `ingress.host` labels.

- [x] **Phase 6 — The Senate Mandate (Full CLI Parity)**
  Complete CRUD for Nodes, Stacks, Services, and Tasks via CLI (`gbnt node ls/inspect/promote/demote/update`, `gbnt stack ls/rm`, `gbnt service ls/ps/scale/rm`, `gbnt task ls/rm`).

- [x] **Phase 7 — Security & Isolation**
  Asymmetric port security: Bearer Token auth on `:4000`, Basic Auth Web UI on `:4001`, public telemetry on `:4002`. CLI context management via `~/.gbntctl/config`.

- [x] **Phase 8 — Universal Provisioning & Contexts**
  CLI remote context management (`gbnt config use-context`), cross-platform binaries (GitHub Actions CI/CD), Docker Hub image publishing.

- [x] **Phase 9 — Full Compose Support (Single-Node Executor)**
  Built-in **local executor** in the Manager: containers now run automatically on the Manager node without a separate Worker. Full `ports`, `environment`, `volumes`, and `command` support passed through from Compose YAML to `docker run`. Proper `docker stop + docker rm` on `stack rm`. Task model extended with `container_name` for lifecycle management.

- [x] **Phase 10 — Web UI Compose Editor**
  Web Dashboard upgraded with: compose YAML editor, Save Changes, Save & Redeploy, Reset, Stack Redeploy button, real container stop (not just DB delete), `container_name` column in tasks table, status badges, toast notifications.

- [x] **Phase 10.5 — Flutter Web UI & Security Hardening**
  Complete Web Dashboard rewrite from plain HTML/JS to **Flutter Web** with **Material Design 3**. Added ⚙️ Settings gear icon with user profile, password change, and dark/light theme toggle. Native `gbnt health` CLI subcommand for Docker HEALTHCHECK (eliminating curl/wget/busybox dependencies). Container image hardened: base upgraded to `alpine:edge`, `curl` removed, `busybox` patched (CVE-2025-60876), `golang.org/x/net` upgraded to v0.54.0.

- [x] **Phase 11 — SRE Monitor (`gbnt monitor init`)**
  Built-in SRE observability stack with a single command. `gbnt monitor init` deploys **cAdvisor** (container metrics), **Prometheus** (metrics collection), **Grafana** (dashboards with pre-configured datasources), **Loki** (log aggregation), and **Promtail** (log shipping) — all on a dedicated Docker network (`gbnt-monitor-net`). `gbnt monitor status` and `gbnt monitor stop` for lifecycle management. Config files auto-generated in `~/.gbnt/monitor/`.

- [x] **Phase 12 — Sloth SLO Engine & Google SRE Alerts (`gbnt slo`)**
  Native integration of Sloth (`slok/sloth`) into Gubernator's core engine. Translates `gbnt.slo.*` Compose labels into production-grade Prometheus recording and alerting rules with multi-window burn rate alerts and real-time Error Budget tracking via Web UI and REST API.

- [x] **Phase 13 — Enterprise Active Directory, LDAP & Dynamic RBAC (`v2.20.0`)**
  Multi-server Active Directory / OpenLDAP SSO with LDAPS (`:636`) and StartTLS (`:389`), automated Bind searches, dynamic group mapping to 3-tier RBAC (`admin`, `operator`, `readonly`), cryptographic HMAC-SHA256 JWT tokens, emergency local administrator fallback, modern Flutter login screen with domain selector, and dedicated Security & AD management screen with live "Test Connection" diagnostic tool.

---

## Upcoming Development

- [ ] **Phase 14 — High Availability (The Senate)**
  Distributed SQLite via `rqlite` or `dqlite` (SQLite over Raft) for multi-manager fault tolerance. Eliminate the single point of failure.

- [ ] **Phase 15 — Live Observability**
  WebSocket streaming for container logs (`docker logs -f`) directly in the Web UI dashboard.

- [ ] **Phase 16 — Secret Management (The Praetorian Guard)**
  Encrypted variable injection from Gubernator's DB into containers — no plaintext secrets in Compose files.

- [ ] **Phase 17 — Rolling Updates**
  Zero-downtime deployments: update replicas sequentially, wait for health checks before removing old containers.

- [ ] **Phase 18 — Storage Affinity**
  Scheduler awareness of local persistent volumes — reschedule containers back to the same node where their data lives.

- [ ] **Phase 19 — Multi-arch Build Registry**
  Optional integrated lightweight image registry for air-gapped deployments.
