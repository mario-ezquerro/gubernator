# Gubernator (gbnt) - AI Rules

## Project Context
You are working on **Gubernator (gbnt)**, a Goldilocks orchestrator that combines the simplicity of Docker Swarm with the flexibility of Nomad. The project is heavily themed around the **Roman Empire**. 

## Tech Stack & Conventions
1. **Language:** Go (Golang) 1.24+.
2. **Frameworks:**
   - CLI: `github.com/spf13/cobra`
   - API: `github.com/gin-gonic/gin`
   - ORM: `gorm.io/gorm` with `gorm.io/driver/sqlite`
   - Documentation: `github.com/swaggo/swag` (Swagger)
3. **Database:** SQLite. Do NOT use PostgreSQL or MySQL. The Manager stores global state, and Workers store a local cache ("Draft mode").
4. **Networking:** CoreDNS and Caddy (Ingress).
5. **Observability:** OpenTelemetry and Prometheus.

## Naming Conventions & Theming
- Keep the Roman Empire theme in mind for architectural concepts:
  - **Manager:** "The Senate" or "Forum".
  - **Workers:** "Centurions".
  - **Services/Stacks:** "Legions".
  - **Networking/Ingress:** "Aqueducts".
  - **Security:** "Praetorian Guard".
- Labels should use the `gbnt.` prefix, e.g., `gbnt.node.role`, `gbnt.node.gpu`.

## Architectural Rules
1. **Single Binary:** The `gbnt` binary MUST act as both the Manager (API + DB) and the Worker (Agent) depending on the executed command or configuration.
2. **Container Engine:** The orchestrator interacts directly with the local Docker Engine API.
3. **API Documentation:** All API endpoints MUST be documented with Swagger annotations.
4. **Resilience:** The system must avoid Single Points of Failure where possible. High Availability (HA) plans involve using `rqlite`/`dqlite` in the future. Keep the DB layer cleanly abstracted.

## Coding Style
- Write idiomatic Go.
- Use explicit error handling.
- Keep packages focused and small (`cmd/gbnt`, `internal/api`, `internal/cli`, `internal/db`, `internal/core`).
- Always run `swag init` after modifying API routes.
- Always ensure the project compiles statically for Docker (`CGO_ENABLED=0`).

## Testing & Execution Rules
1. **Containerized Testing:** Always run and test the Gubernator Manager/Worker environment inside a Docker container (mapping `/var/run/docker.sock` to allow container management) rather than running it directly as a host process.

