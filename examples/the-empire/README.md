# The Empire — Gubernator + CoreDNS + Caddy

This example demonstrates the **"Empire Trifecta"**: a full cluster control plane combining Gubernator, CoreDNS (internal DNS), and Caddy (Ingress/Reverse Proxy), **plus** a managed application stack deployed by Gubernator into that infrastructure.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Docker Host                          │
│                                                         │
│   ┌─────────────────┐   ┌──────────┐   ┌─────────────┐ │
│   │  Gubernator     │   │  CoreDNS │   │    Caddy    │ │
│   │  :4000 CLI      │──▶│  :5353   │   │  :80 / :443 │ │
│   │  :4001 Web UI   │──▶│ DNS zone │   │   Ingress   │ │
│   │  :4002 Swagger  │──▶│ Caddyfile│   │   (auto)    │ │
│   └─────────────────┘   └──────────┘   └─────────────┘ │
│                │                                        │
│                │ deploys via gbnt stack deploy          │
│                ▼                                        │
│   ┌─────────────────┐                                   │
│   │  whoami (x2)    │ ← managed containers              │
│   │  :8082          │                                   │
│   └─────────────────┘                                   │
└─────────────────────────────────────────────────────────┘
```

---

## Prerequisites

- Docker and Docker Compose installed.
- `gbnt` binary compiled (from the repository root: `go build -o gbnt ./cmd/gbnt`).

---

## Step 1: Launch the Empire Control Plane

Open a terminal **inside this directory** (`examples/the-empire`) and start the full trifecta:

```bash
cd examples/the-empire
docker compose up -d
```

This starts:
| Container | Port | Description |
|-----------|------|-------------|
| `gubernator-manager` | 4000 / 4001 / 4002 | The orchestrator |
| `coredns` | 5353/udp | Internal DNS resolver |
| `caddy` | 80 / 443 | Ingress / Reverse Proxy |

Check everything is healthy:
```bash
docker compose ps
curl http://localhost:4002/health
# → {"status":"healthy"}
```

---

## Step 2: Get the Join Token

The Manager is running inside Docker. Get its join token to register a worker:

```bash
curl -s -H "Authorization: Bearer admin" http://localhost:4000/v1/cluster/token
```

Copy the `token` value from the response.

---

## Step 3: Join a Local Worker

From the **repository root**, start a local worker that will execute containers on your machine's Docker daemon:

```bash
export GBNT_API_TOKEN=admin

./gbnt legion join --token <YOUR_TOKEN> --manager localhost:4000
```

Leave this terminal running. The worker polls for tasks every 5 seconds.

---

## Step 4: Deploy the Test Application

Open a new terminal at the **repository root** and deploy the test app:

```bash
export GBNT_API_TOKEN=admin

./gbnt stack deploy -c examples/the-empire/test-app.yml myapp
```

This deploys **2 replicas** of `traefik/whoami`, exposed on port `8082`.

---

## Step 5: Verify Everything Works

### Check the containers are running:
```bash
docker ps | grep gbnt
# → Two gbnt-<uuid> containers running
```

### Hit the application:
```bash
curl http://localhost:8082
# → Shows hostname, IP, and request headers
```

### Check the Web UI:
Open [http://localhost:4001](http://localhost:4001) → **admin / admin**

You will see your stack, services, and both running tasks live.

### Check DNS (CoreDNS):
```bash
dig @localhost -p 5353 whoami.myapp.gbnt +short
# → Internal IP of the container
```

### Check Ingress (Caddy):
```bash
curl http://localhost
# → Caddy is active and routes traffic
```

---

## Step 6: Update and Redeploy

You can edit `test-app.yml` directly in the Web UI at [http://localhost:4001](http://localhost:4001):
1. Click **Edit YAML** next to `myapp`.
2. Change the image or number of replicas.
3. Click **Save & Redeploy**.

Gubernator will stop the old containers and start new ones automatically.

---

## Step 7: Clean Up

```bash
# Via CLI
export GBNT_API_TOKEN=admin
./gbnt stack rm <stack_id_from_gbnt_stack_ls>

# Shut down the Empire
cd examples/the-empire
docker compose down -v
```
