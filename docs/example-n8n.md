# AI Automation Stack (n8n + PostgreSQL + Ollama + Qdrant)

This intermediate-to-advanced example demonstrates how to orchestrate a complete AI automation environment on Gubernator. 

It deploys **n8n** (workflow automation), **PostgreSQL** (n8n backend database), **Qdrant** (vector search engine for AI memory/RAG), and **Ollama** (for running local Large Language Models), showcasing Gubernator's dynamic Caddy Ingress configuration and CoreDNS service discovery.

---

## What You Will Deploy

The stack file `docker-compose.yml` located in `examples/example-n8n/` defines:
- **`postgres`**: A PostgreSQL 16 database storing data in a persistent Docker volume (`postgres_storage`).
- **`n8n`**: The workflow automation engine exposed to external traffic via Caddy Ingress.
- **`qdrant`**: Vector database for AI memory/RAG, exposed via Caddy Ingress.
- **`ollama`**: Runs local LLMs, exposed via Caddy Ingress.
- **`ollama-pull-llama`**: A transient container that automatically downloads the `llama3.2` model to the shared Ollama volume on startup.

---

## Prerequisites

- **Gubernator** running on your manager node with Caddy Ingress and CoreDNS enabled.
- Configure your host OS resolver to use Gubernator's DNS for `.gbnt` and `.gbnt.local` domains (see Installation guide). No `/etc/hosts` modifications needed!

---

## Step 1: Deploy the Stack

Deploy the stack using the CLI from the root of the Gubernator repository:

```bash
# Set your API token if authentication is enabled
export GBNT_API_TOKEN=admin

# Deploy the stack and name it 'n8n-stack'
./gbnt stack deploy -c examples/example-n8n/docker-compose.yml
```

---

## Step 2: Verify the Deployment

Wait a few moments for Gubernator to schedule the tasks, pull the Docker images, and start the containers.

### 1. Check Tasks Status
Run the task list command to verify all containers are running:
```bash
./gbnt task ls
```
You should see all 5 tasks (`postgres`, `n8n`, `qdrant`, `ollama`, `ollama-pull-llama`) listed as `running` and assigned container IPs.

### 2. Verify Caddy Ingress
Gubernator's Ingress engine auto-detects the internal container ports and configures Caddy to reverse proxy external requests to the correct targets:
* **n8n**: Routes traffic for `n8n.gbnt.local` to the container's port `5678`.
* **qdrant**: Routes traffic for `qdrant.gbnt.local` to the container's port `6333`.
* **ollama**: Routes traffic for `ollama.gbnt.local` to the container's port `11434`.

Test the connections with curl:
```bash
# Verify n8n
curl -k -i https://n8n.gbnt.local --resolve n8n.gbnt.local:443:127.0.0.1 --head

# Verify Qdrant API
curl -k -i https://qdrant.gbnt.local --resolve qdrant.gbnt.local:443:127.0.0.1

# Verify Ollama API
curl -k -i https://ollama.gbnt.local --resolve ollama.gbnt.local:443:127.0.0.1
```

### 3. Verify Model Download
The `ollama-pull-llama` service triggers a script to download `llama3.2` as soon as Ollama is ready. You can inspect its logs to monitor download progress:
```bash
# Find the task ID for 'ollama-pull-llama' from 'gbnt task ls'
docker logs gbnt-<task_id>-...
```

---

## Step 3: Accessing the Web Interfaces

- **n8n Workflow Editor**: Open [https://n8n.gbnt.local](https://n8n.gbnt.local) in your browser. Complete the initial setup screen to start building workflows.
- **Qdrant Dashboard**: Open [https://qdrant.gbnt.local/dashboard](https://qdrant.gbnt.local/dashboard) in your browser to inspect collections.

---

## Step 4: Connecting Services inside n8n

When configuring credentials or nodes inside your n8n workflow editor:
1. **Ollama Connection**:
   - Host: `http://ollama.n8n-stack.gbnt:11434`
   - Model Name: `llama3.2`
2. **Qdrant Connection**:
   - Host: `qdrant.n8n-stack.gbnt`
   - Port: `6333`

Gubernator's CoreDNS service discovery automatically handles resolution of `<service>.<stack>.gbnt` internal addresses across all containers connected to the shared stack network.

---

## Step 5: Clean Up

To tear down the stack and remove all running containers and volumes:

```bash
# Get the stack ID
./gbnt stack ls

# Remove the stack
./gbnt stack rm <stack_id>
```

---

## What You Learned

- **Dynamic Ingress Port Auto-detection**: How Gubernator automatically inspects `svc.Ports` to configure the Caddy reverse proxy for non-standard ports (like `5678` or `6333`).
- **AI/RAG Service Discovery**: Connecting multiple independent services (Postgres, n8n, Ollama, Qdrant) via secure internal DNS hostnames on a shared bridge network.
- **Transient Task Automation**: Running curl commands inside a sidecar container (`ollama-pull-llama`) to run setup scripts after dependencies are running.
