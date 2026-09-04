# Private GitOps & CI/CD Pipeline Suite

Self-hosted Git repository and automated containerized CI/CD workflow pipeline for Gubernator.

## 🏛️ Components
1. **`gitea`**: Fast, lightweight Git web platform with pull requests, issue tracking, and webhook triggers.
2. **`woodpecker-server`**: Container-native CI pipeline controller triggering automated tests and builds.
3. **`woodpecker-agent`**: Runner agent scheduled onto Centurion worker nodes via placement constraints (`gbnt.node.role == worker`).

## 🚀 Gubernator Features Utilized
* **Caddy Ingress**: Web access at `http://git.devops.gbnt.local` and `http://ci.devops.gbnt.local`.
* **Worker Placement Targeting**: The CI execution agent is placed strictly on worker nodes to prevent CPU spikes on the manager.
* **Granaries Persistent Repositories**: Git repositories and build logs stored in `/var/contenedores/gitea` and `/var/contenedores/woodpecker`.

## 💻 Quick Deploy
```bash
gbnt examples deploy gitea-woodpecker
```
