# GenAI RAG Search & Vector Database Stack

Full-stack Retrieval-Augmented Generation (RAG) architecture with **local LLM inference** for Gubernator clusters. All AI processing runs on-premise — zero data leaves the cluster.

## 🏛️ Architecture

```
                    ┌─────────────────────────────────────────────────┐
                    │               Gubernator Cluster                 │
                    │                                                  │
  User Browser ───► │  search.rag.gbnt.local ──► rag-ui (Open-WebUI)  │
                    │                              │                   │
                    │            ┌─────────────────┼──────────────┐   │
                    │            │                 │              │   │
                    │      ollama-rag       postgres-vector    qdrant  │
                    │   (Manager Node)      (pgvector:pg16)  (Vector) │
                    │   nomic-embed-text       5433:5432      6333:6333│
                    │   llama3.2:latest                               │
                    │   11435:11434                                    │
                    └─────────────────────────────────────────────────┘
```

## 📦 Components

| Service | Image | Purpose | Port |
|---|---|---|---|
| **postgres-vector** | `pgvector/pgvector:pg16` | Relational DB + HNSW/IVFFlat similarity search | `5433` |
| **qdrant** | `qdrant/qdrant:latest` | High-performance Rust vector database (REST + gRPC) | `6333/6334` |
| **ollama-rag** | `ollama/ollama:latest` | Local LLM + embedding engine (Manager node) | `11435` |
| **ollama-init** | `curlimages/curl:latest` | One-shot sidecar: pulls `nomic-embed-text` + `llama3.2` | — |
| **rag-ui** | `ghcr.io/open-webui/open-webui:main` | Chat & document RAG interface | `8082` |

## 🚀 Quick Deploy

```bash
gbnt examples deploy pgvector-rag
```

Or using the compose file directly:
```bash
gbnt stack deploy -f examples/example-pgvector-rag/docker-compose.yml pgvector-rag
```

## 🤖 AI Models (auto-downloaded by `ollama-init`)

| Model | Size | Use |
|---|---|---|
| `nomic-embed-text` | ~274 MB | Text embeddings for document ingestion & RAG retrieval |
| `llama3.2` | ~2.0 GB | Conversational chat LLM for Open-WebUI interface |

> **Note:** Model download happens automatically at first deploy (15–20 min depending on bandwidth). The `ollama-init` container handles this and exits when complete.

## 🔍 Verification

```bash
# Check all services are running
gbnt task ls

# Verify Ollama models are loaded (after ~15 min)
curl http://ollama.rag.gbnt.local:11435/api/tags

# Verify Qdrant vector engine
curl http://qdrant.rag.gbnt.local

# Open RAG UI
open http://search.rag.gbnt.local
```

## 🌐 Ingress URLs (requires CoreDNS / `/etc/hosts`)

| URL | Service |
|---|---|
| `http://search.rag.gbnt.local` | Open-WebUI RAG interface |
| `http://qdrant.rag.gbnt.local` | Qdrant REST API |
| `http://ollama.rag.gbnt.local` | Ollama API (embeddings + inference) |
| `http://postgres.rag.gbnt.local` | PostgreSQL (internal) |

## 🛠️ Manual Model Management

```bash
# Pull additional models manually
curl -X POST http://ollama.rag.gbnt.local:11435/api/pull \
  -H 'Content-Type: application/json' \
  -d '{"name": "mistral"}'

# List available models
curl http://ollama.rag.gbnt.local:11435/api/tags

# Generate a test embedding
curl -X POST http://ollama.rag.gbnt.local:11435/api/embeddings \
  -H 'Content-Type: application/json' \
  -d '{"model": "nomic-embed-text", "prompt": "Hello, RAG!"}'
```

## 💾 Persistent Storage (Granaries)

| Path | Service | Contents |
|---|---|---|
| `/var/contenedores/pgvector/data` | postgres-vector | PostgreSQL database files |
| `/var/contenedores/qdrant/storage` | qdrant | Vector indexes and collections |
| `/var/contenedores/ollama-rag/models` | ollama-rag | Downloaded LLM model weights |
| `/var/contenedores/rag-ui/data` | rag-ui | Open-WebUI users, chats, settings |

## 🏗️ Gubernator Features Utilized

* **Caddy Ingress**: Automatic HTTPS for `search.rag.gbnt.local`, `qdrant.rag.gbnt.local`, and `ollama.rag.gbnt.local`.
* **CoreDNS Networking**: Inter-service DNS (`qdrant.rag.gbnt.local`, `postgres-vector`, `ollama.rag.gbnt.local`) across all Centurion nodes.
* **Node Placement**: `ollama-rag` pinned to Manager node (most RAM + cached image). Other services auto-scheduled.
* **Granaries Persistent Storage**: Zero-data-loss storage in `/var/contenedores/`.
* **Zero-Downtime Backups**: `gbnt backup create --freeze pgvector-rag` for consistent DB snapshots.
