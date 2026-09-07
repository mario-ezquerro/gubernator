# Private GitOps & CI/CD Pipeline Suite

Self-hosted Git repository and automated containerized CI/CD workflow pipeline for Gubernator, combining **Gitea** (Lightweight Git Forge) with **Woodpecker CI v3** (Distributed Pipeline Controller & Worker Agents).

---

## 🏛️ Components Architecture

```text
       ┌────────────────────────────────────────────────────────┐
       │                 Caddy Ingress (Port 80)                │
       └──────────────┬──────────────────────────┬──────────────┘
                      │                          │
                      ▼                          ▼
    ┌────────────────────────────────┐  ┌────────────────────────────────┐
    │          Gitea Forge           │  │      Woodpecker CI Server      │
    │   git.devops.gbnt.local:3000   │  │   ci.devops.gbnt.local:8000    │
    │   (Web UI & SSH Port 2222)     │  │      (gRPC Port 9000)          │
    └────────────────────────────────┘  └───────────────▲────────────────┘
                                                        │ gRPC Auth Handshake
                                                        │ (WOODPECKER_AGENT_SECRET)
                                        ┌───────────────┴────────────────┐
                                        │    Woodpecker Runner Agent     │
                                        │ (Centurion Worker Node Daemon) │
                                        │  /var/run/docker.sock Builder  │
                                        └────────────────────────────────┘
```

1. **`gitea`**: Fast, lightweight Git web platform with repository hosting, pull requests, issue tracking, and automated webhook triggers.
2. **`woodpecker-server`**: Modern container-native pipeline controller (`woodpeckerci/woodpecker-server:v3`) orchestrating builds and tracking pipeline runs.
3. **`woodpecker-agent`**: Runner daemon (`woodpeckerci/woodpecker-agent:v3`) scheduled strictly onto Centurion worker nodes via placement constraints (`gbnt.node.role == worker`) to isolate build workloads from the manager node.

---

## 🚀 Key Gubernator Features Utilized

* **Caddy Ingress Routing**: Automatic zero-config reverse proxy routing with local TLS:
  * Gitea Web UI: `http://git.devops.gbnt.local` (proxied to port `3000`)
  * Woodpecker CI Dashboard: `http://ci.devops.gbnt.local` (proxied to port `8000`)
  * Gitea SSH Access: Direct port mapping `2222:22`
* **CoreDNS Cluster Aliases & Service Discovery**:
  * Distributed agents resolve the controller across nodes via `woodpecker-server.gitea-woodpecker.gbnt.local:9000` or bare `woodpecker-server:9000`.
  * Woodpecker server reaches Gitea webhooks via `http://git.devops.gbnt.local:3000`.
* **The Granaries (`/var/contenedores`)**:
  * Gitea repositories and user data stored in `/var/contenedores/gitea/data`.
  * Woodpecker server SQLite database and pipeline history stored in `/var/contenedores/woodpecker/server`.
* **Centurion Worker Placement Constraints**:
  * `woodpecker-agent` enforces `gbnt.node.role == worker` to protect control-plane stability during intensive build and test pipelines.

---

## 💻 Quick Deployment

Deploy directly from the Gubernator CLI:
```bash
gbnt examples deploy gitea-woodpecker
```

Or author and modify interactively in **Gubernator Compose Studio**:
1. Open Dashboard ➔ **Compose Studio**.
2. Select **GitOps CI/CD (Gitea + Woodpecker)** blueprint.
3. Click **Deploy / Redeploy**.

---

## 🔍 Verification & Usage

1. **Verify Services Status**:
   ```bash
   gbnt task ls
   ```
   Confirm all three tasks (`gitea`, `woodpecker-server`, `woodpecker-agent`) report `running`.

2. **Access Ingress URLs**:
   * Gitea Forge: [http://git.devops.gbnt.local](http://git.devops.gbnt.local)
   * Woodpecker CI: [http://ci.devops.gbnt.local](http://ci.devops.gbnt.local)

3. **Link Gitea OAuth to Woodpecker**:
   * In Gitea, navigate to **Settings ➔ Applications ➔ Create OAuth2 Application**.
   * Set Redirect URI to `http://ci.devops.gbnt.local/authorize`.
   * Add Client ID & Secret to `woodpecker-server` environment variables (`WOODPECKER_GITEA_CLIENT` and `WOODPECKER_GITEA_SECRET`).
