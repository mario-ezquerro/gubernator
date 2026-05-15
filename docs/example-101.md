# Example 101 — Getting Started with Gubernator

This is the **first example** to run. It demonstrates the complete basic workflow of Gubernator on a **single node** (your local machine), without requiring external infrastructure.

You will deploy three progressively complex stacks and learn the full Gubernator lifecycle.

---

## What You Will Deploy

| Stack | Image | Port | What it shows |
|-------|-------|------|---------------|
| `nginx-demo` | `nginx:alpine` | 8080 | Basic single-service deployment |
| `redis-demo` | `redis:alpine` | 6379 | Service with port binding |
| `api-demo` | `traefik/whoami` | 8081 | API service + verification |

---

## Prerequisites

- **Docker** running on your machine
- **Go 1.24+** installed (or download the pre-built `gbnt` binary from [Releases](https://github.com/mario-ezquerro/gubernator/releases))

---

## Step 1: Start Gubernator

Open a terminal at the **repository root** and compile (once):

```bash
go build -o gbnt ./cmd/gbnt
```

Start the Manager with Web UI enabled:

```bash
GBNT_API_TOKEN=admin \
GBNT_WEB=true \
GBNT_WEB_USER=admin \
GBNT_WEB_PASSWORD=admin \
./gbnt serve
```

Leave this terminal running. You will see executor logs here as containers start.

!!! tip "Open the dashboard"
    Navigate to [http://localhost:4001](http://localhost:4001) (admin/admin) to watch tasks appear live as you deploy stacks.

---

## Step 2: Register the Local Node

Gubernator needs at least one active node. Initialize the legion and register the local machine as its own worker:

```bash
# Terminal 2
export GBNT_API_TOKEN=admin

# Initialize the cluster and get the join token
./gbnt legion init
```

Copy the join command from the output and run it:

```bash
./gbnt legion join --token <YOUR_TOKEN> --manager 127.0.0.1:4000
```

Leave this terminal running. You will see pull and start logs here.

---

## Step 3: Deploy Stack 1 — NGINX

```bash
# Terminal 3
export GBNT_API_TOKEN=admin

./gbnt stack deploy -c examples/example-101/01-nginx-basic.yml nginx-demo
```

**Verify:**
```bash
curl http://localhost:8080
# → NGINX Welcome page

./gbnt task ls
# → nginx-demo task shows status=running
```

---

## Step 4: Deploy Stack 2 — Redis

```bash
./gbnt stack deploy -c examples/example-101/02-constrained-redis.yml redis-demo
```

**Verify:**
```bash
redis-cli -h localhost -p 6379 ping
# → PONG

docker ps | grep gbnt
# → Both gbnt-<uuid> containers visible
```

---

## Step 5: Deploy Stack 3 — Whoami API

```bash
./gbnt stack deploy -c examples/example-101/03-ingress-api.yml api-demo
```

**Verify:**
```bash
curl http://localhost:8081
# → Hostname, IP, and request headers from whoami

./gbnt stack ls
# → All three stacks listed
```

---

## Step 6: Inspect the Cluster

```bash
# All nodes
./gbnt node ls

# All stacks
./gbnt stack ls

# All tasks (containers)
./gbnt task ls
```

---

## Step 7: Edit & Redeploy from the Web UI

1. Open [http://localhost:4001](http://localhost:4001)
2. Find the `nginx-demo` stack → click **Edit YAML**
3. Change `replicas: 1` to `replicas: 2`
4. Click **Save & Redeploy**

Gubernator will stop the old container and start two new ones.

---

## Step 8: Clean Up

```bash
# List stacks to get their IDs
./gbnt stack ls

# Remove each stack (stops and removes containers)
./gbnt stack rm <stack_id>
```

Or click **Delete** on each stack in the Web UI.

---

## What You Learned

| Concept | What happened |
|---------|--------------|
| **Single binary** | `gbnt serve` is both the API and the executor |
| **Stack deploy** | Compose YAML → parsed → SQLite → containers |
| **Local executor** | Manager runs containers directly without a separate worker |
| **Ports/Env/Volumes** | Passed directly from YAML to `docker run` |
| **Web UI** | Live view, editor, redeploy, and stop — all in the browser |
| **Lifecycle** | `stack rm` gracefully stops and removes containers |

---

## Source Files

All YAML files are in [`examples/example-101/`](https://github.com/mario-ezquerro/gubernator/tree/main/examples/example-101) in the repository.
