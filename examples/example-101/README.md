# Example 101 — Getting Started with Gubernator

This is the **first example** to run. It demonstrates the complete basic workflow of Gubernator on a **single node** (your local machine), without requiring any external workers.

You will deploy three progressively complex stacks to learn how Gubernator works.

---

## Prerequisites

- **Docker** running on your machine.
- **Gubernator compiled** (`gbnt` binary) or pulled from Docker Hub.

---

## Step 1: Start Gubernator

Open a terminal at the **root of the repository** and start the Manager. It will start listening on three ports simultaneously:

```bash
# Compile (only needed once)
go build -o gbnt ./cmd/gbnt

# Start the Manager
GBNT_API_TOKEN=admin GBNT_WEB=true GBNT_WEB_USER=admin GBNT_WEB_PASSWORD=admin ./gbnt serve
```

Gubernator is now running. Leave this terminal open. You will see its logs here.

| Port | Service |
|------|---------|
| `:4000` | REST API (CLI endpoint) |
| `:4001` | Web UI Dashboard |
| `:4002` | Swagger, Metrics, Health |

> **Tip**: Open [http://localhost:4001](http://localhost:4001) in your browser (admin/admin) to watch the dashboard live as you deploy stacks below.

---

## Step 2: Register the Local Node

Gubernator needs at least one active node to schedule tasks. Register your local machine:

```bash
export GBNT_API_TOKEN=admin

./gbnt legion init
```

This prints a join token. Now join the local manager as its own worker (single-node mode):

```bash
./gbnt legion join --token <YOUR_TOKEN> --manager 127.0.0.1:4000
```

Leave this terminal running. It will execute containers locally.

---

## Step 3: Deploy the Stacks

Open a third terminal. Set the token and deploy all three example stacks:

### Stack 1 — Basic NGINX (port 8080)

```bash
export GBNT_API_TOKEN=admin

./gbnt stack deploy -c examples/example-101/01-nginx-basic.yml nginx-demo
```

**Verify:**
```bash
curl http://localhost:8080
# → NGINX welcome page
docker ps | grep gbnt
```

---

### Stack 2 — Redis Cache (port 6379)

```bash
./gbnt stack deploy -c examples/example-101/02-constrained-redis.yml redis-demo
```

**Verify:**
```bash
redis-cli -h localhost -p 6379 ping
# → PONG
```

---

### Stack 3 — Whoami API (port 8081)

```bash
./gbnt stack deploy -c examples/example-101/03-ingress-api.yml api-demo
```

**Verify:**
```bash
curl http://localhost:8081
# → Shows request info (IP, headers, etc.)
```

---

## Step 4: Inspect the Cluster

```bash
# List all nodes
./gbnt node ls

# List deployed stacks
./gbnt stack ls

# List running services
./gbnt service ls

# List all tasks (containers)
./gbnt task ls
```

---

## Step 5: Clean Up

```bash
# Remove each stack (this stops and removes the containers)
./gbnt stack rm <stack_id>
```

Or remove all at once from the Web UI at [http://localhost:4001](http://localhost:4001).

---

## What You Learned

| Concept | What happened |
|---------|--------------|
| **Stack deploy** | Gubernator parsed your YAML and stored the desired state in SQLite |
| **Scheduler** | It found the active local node and assigned tasks to it |
| **Executor** | The built-in executor pulled the image and ran the container |
| **Lifecycle** | `stack rm` stopped and removed the containers cleanly |
