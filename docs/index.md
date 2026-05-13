# <img src="gubernator-icon.png" alt="Gubernator Icon" width="40" style="vertical-align: middle;"> Gubernator (gbnt)

Gubernator is a powerful "Goldilocks" orchestrator that combines the **simplicity of Docker Swarm** (native Compose support, easy cluster joining) with the **flexibility of Nomad** (task-based logic, labels for hardware/AI targeting).

Themed around the **Roman Empire**, Gubernator aims to manage your containers robustly across a fleet of nodes ("Centurions") managed by a central API ("The Senate").

---

## 🏛 Architecture Overview

Gubernator operates using a single, portable binary (`gbnt`) that can run as either a Manager or a Worker. 
* **API & CLI:** Built with Gin and Cobra.
* **State:** Powered by SQLite and GORM.
* **Container Engine:** Direct communication with the Docker Engine.
* **Ingress & DNS:** Built-in hooks for CoreDNS (internal resolution) and Caddy (external ingress).

*(See [architecture.md](architecture.md) for a deeper dive).*

---

## 🚀 Getting Started

### Installation

Currently, Gubernator is compiled directly from source. You will need **Go 1.24+**.

```bash
git clone https://github.com/mario-ezquerro/gubernator.git
cd gubernator
go build -o gbnt ./cmd/gbnt
```

Alternatively, you can run Gubernator using Docker via the included multi-stage `Dockerfile`.

**1. Build the Docker Image:**
```bash
docker build -t gbnt:latest .
```

**2. Run the Manager API via Docker:**
Because Gubernator manages Docker containers, it needs access to the local Docker socket. We also expose ports `4000` (API) and `4001` (Metrics/Prometheus).

```bash
docker run -d \
  --name gbnt-manager \
  -p 4000:4000 \
  -p 4001:4001 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  gbnt:latest serve
```

**3. Run CLI Commands via Docker:**
You can execute CLI commands directly through the running container:

```bash
docker exec -it gbnt-manager /app/gbnt node ls
```

### Starting the Manager (The Senate)

To initialize the centralized API server on port `4000`:

```bash
./gbnt serve
```

The server will output:
```text
[GIN-debug] Listening and serving HTTP on :4000
```

---

## 💻 CLI Usage & Examples

Once the server is running, you can interact with the cluster using the `gbnt` CLI.

### List Nodes
To see all nodes (Centurions) currently registered in the cluster:

```bash
./gbnt node ls
```

**Output Example:**
```text
ID      IP         ROLE     STATUS 
node-1  127.0.0.1  manager  active 
```
*(Note: Data is currently mocked while we implement the DB layer).*

### Clustering (The Legion)

To form a cluster, you must initialize the "Legion" from the Manager node to retrieve the secure Join Token.

```bash
./gbnt legion init
```
*Output:*
```text
🏛 Gubernator Legion Initialized!

To add a worker to this swarm, run the following command on the worker node:
  gbnt legion join --token <TOKEN_STRING> --manager <MANAGER-IP>:4000
```

Once you have the token, you can join any other node as a "Centurion" (Worker) by simply running:

```bash
./gbnt legion join --token <TOKEN_STRING> --manager 192.168.1.100:4000
```

*This will authenticate the node, register it in the Manager's SQLite DB, and start a background heartbeat service.*

### Stack Deploy (The Command)

You can deploy standard `docker-compose.yml` files. The built-in Scheduler will parse the file, look for placement constraints, and assign tasks to the appropriate Centurions.

Create a sample `docker-compose.yml`:
```yaml
services:
  web:
    image: nginx:latest
    deploy:
      replicas: 2
      placement:
        constraints:
          - node.labels.gbnt.node.role == worker
```

Deploy the stack:
```bash
./gbnt stack deploy -c docker-compose.yml mystack
```

*Output:*
```text
🚀 Stack 'mystack' deployed successfully!
The Governor has dispatched the Centurions to schedule the tasks.
```

### Telemetry & Metrics (The Watchtowers)

Gubernator comes with built-in Prometheus metrics. When the manager starts, a dedicated telemetry server is exposed on port `4001`.

You can view the raw metrics or point your Prometheus scraper to:
```bash
curl http://localhost:4001/metrics
```

*These metrics include real-time counts of nodes, tasks, and system performance.*

### The Executor (Docker Bridge)

Gubernator runs native Docker containers. Once a stack is deployed, the Centurions (Worker nodes) pull their assigned tasks and talk directly to the local Docker socket to:
1. `docker pull` the required images.
2. `docker run -d` the containers, labeling them automatically with the Gubernator Task ID.

You don't need any special runners; if the machine has `dockerd` running, Gubernator can orchestrate it.

### Ingress & Service Discovery (The Aqueducts)

Gubernator actively manages its own internal DNS and external ingress routing by dynamically writing configuration files for **CoreDNS** and **Caddy**.

When a task starts, the worker extracts its internal Docker IP. Gubernator then generates two files automatically in its working directory:
1. `gubernator.hosts` - A file you can configure CoreDNS (using the `hosts` plugin) to auto-load. It creates internal domains like `web.mystack.gbnt` pointing directly to the active containers.
2. `Caddyfile` - If a service is deployed with the constraint `ingress.host == api.example.com`, Gubernator writes a Caddyfile configuring Caddy to reverse-proxy `api.example.com` to the internal `gbnt` DNS name.

To complete the Empire Trifecta, simply run Caddy and CoreDNS in the same directory alongside the Manager, and they will pick up these auto-generated routing tables!

### Web Dashboard (The Forum)

Gubernator includes a secure, built-in Web UI to visualize the state of your cluster. It is disabled by default to keep the binary lightweight and secure.

To activate the Web UI on **port 4001**, you must pass the `GBNT_WEB=true` flag and credentials when starting the Manager:
```bash
GBNT_WEB=true GBNT_WEB_USER=admin GBNT_WEB_PASSWORD=supersecreto ./gbnt serve
```
Or, if running via Docker:
```bash
docker run -d -p 4000:4000 -p 4001:4001 \
  -e GBNT_WEB=true -e GBNT_WEB_USER=admin -e GBNT_WEB_PASSWORD=supersecreto \
  gubernator:latest serve
```

Access the dashboard at `http://localhost:4001` and authenticate with the credentials you provided to manage nodes, view running containers, and stop tasks dynamically!

---

## 📚 API Documentation (Swagger)

Gubernator features auto-generated Swagger documentation. 
While `./gbnt serve` is running, navigate to the following URL in your browser:

👉 **[http://localhost:4000/swagger/index.html](http://localhost:4000/swagger/index.html)**

From the Swagger UI, you can directly test endpoints like `GET /v1/node/ls`.

---

## 🗺 Current Roadmap State
- [x] **Phase 1: The Foundation ("Veni" Sprint)** - CLI setup, Gin API, Swagger, Dockerfile.
- [x] **Phase 1.5: The Granaries Foundation** - SQLite state persistence, GORM ORM integration, API hooking.
- [x] **Phase 2: The Legion** - Clustering, Join Tokens, Heartbeats.
- [x] **Phase 3: The Command** - Compose Stack Parser, Labels.
- [x] **Phase 4: The Watchtowers** - Telemetry, Healthchecks.
- [x] **Phase 5.1: The Executor** - Direct Docker daemon container spawning from Tasks.
- [x] **Phase 5.2: The Aqueducts** - CoreDNS hosts generation, Caddyfile Ingress routing.
