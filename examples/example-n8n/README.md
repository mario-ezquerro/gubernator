# N8N with Ollama and Qdrant in Gubernator

This example demonstrates how to deploy an `n8n` automation environment alongside `PostgreSQL`, `Ollama` (for LLMs), and `Qdrant` (for vector search) using Gubernator.

It utilizes Gubernator's Caddy Ingress configuration to easily expose `n8n` to your local network via a friendly domain name (`n8n.gbnt.local`).

## Features

- **n8n**: Workflow automation tool.
- **Postgres**: Database backend for n8n.
- **Qdrant**: Vector database for AI memory/RAG.
- **Ollama**: Local LLM execution (supports CPU, NVIDIA GPU, and AMD GPU profiles).
- **Auto-pull models**: A transient container automatically pulls the `llama3.2` model on startup.
- **Caddy Ingress Integration**: Automatically maps `n8n.gbnt.local` to the n8n service.

## Prerequisites

- You must have `gbnt` installed and running locally with the Caddy Ingress enabled.
- Ensure your DNS (like `CoreDNS` from `the-empire` example) is set up to resolve `*.gbnt.local` or map them in your `/etc/hosts` file:
  ```bash
  127.0.0.1 n8n.gbnt.local qdrant.gbnt.local ollama.gbnt.local
  ```

## Usage

1. **Configure Environment Variables**
   Copy the `.env.example` file to `.env`:
   ```bash
   cp .env.example .env
   ```
   Modify `.env` to set secure keys for your n8n instance.

2. **Deploy via Gubernator**
   To deploy the stack without GPU acceleration (CPU mode):
   ```bash
   gbnt stack deploy -c docker-compose.yml n8n-stack
   ```

   If you want to use the Ollama profiles for GPU, adjust the deploy command accordingly (if profiles are supported by your `gbnt` CLI version).

3. **Access n8n**
   Once deployed, open your browser and navigate to:
   ```
   http://n8n.gbnt.local
   ```
   *Note: It may take a few moments for Postgres and n8n to initialize on the first run.*

## Gubernator Ingress Magic
The key adaptation in this file is within the `n8n` service definition:

```yaml
    deploy:
      placement:
        constraints:
          - ingress.host == n8n.gbnt.local
```
This tells Gubernator to configure Caddy to automatically route traffic for `n8n.gbnt.local` to this container.
