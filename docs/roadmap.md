# Gubernator Roadmap

This document outlines the journey of Gubernator's development, divided into "Campaigns" or "Phases".

## Completed Phases

- [x] **Phase 1: The Foundation ("Veni" Sprint)** - CLI setup, Gin API, Swagger, Dockerfile.
- [x] **Phase 1.5: The Granaries Foundation** - SQLite state persistence, GORM ORM integration, API hooking.
- [x] **Phase 2: The Legion** - Clustering, Join Tokens, Heartbeats.
- [x] **Phase 3: The Command** - Compose Stack Parser, Labels.
- [x] **Phase 4: The Watchtowers** - Telemetry, Healthchecks.
- [x] **Phase 5.1: The Executor** - Direct Docker daemon container spawning from Tasks.
- [x] **Phase 5.2: The Aqueducts** - CoreDNS hosts generation, Caddyfile Ingress routing.
- [x] **Phase 6: The Senate Mandate** - Full CLI and CRUD implementations (Node, Stack, Service, Task commands).
- [x] **Phase 7: Security & Isolation** - Asymmetric security architecture (`GBNT_API_TOKEN` for port 4000, Basic Auth for Web UI on 4001, and completely isolated Telemetry/Swagger on port 4002).
- [x] **Phase 8: Universal Provisioning & Contexts** - CLI remote context management (`gbntctl`), native cross-platform installation scripts, and comprehensive SRE monitoring configurations.

## Upcoming Development (Future Plans)

- [ ] **Phase 9: High Availability (The Senate)** - Migrate to distributed SQLite (rqlite/dqlite) to eliminate single points of failure in multi-manager deployments.
- [ ] **Phase 10: Live Observability** - Implement WebSocket streaming for container logs directly in the Web UI.
- [ ] **Phase 11: Dynamic Editor** - Direct YAML editor for Stacks via the Web Dashboard.
- [ ] **Phase 12: Secret Management (The Praetorian Guard)** - Securely inject variables and certificates natively without plaintext Compose files.
