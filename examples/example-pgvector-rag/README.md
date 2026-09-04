# GenAI RAG Search & Vector Database Stack

Production-ready Retrieval-Augmented Generation (RAG) and Vector Search architecture for Gubernator clusters.

## 🏛️ Components
1. **`postgres-vector`**: PostgreSQL 16 relational database with official `pgvector` HNSW/IVFFlat similarity search indexing.
2. **`qdrant`**: High-performance Rust-based vector search engine with payload filtering and REST/gRPC endpoints.
3. **`rag-ui`**: Open-WebUI interface preconfigured for document upload, hybrid chunk search, and knowledge base querying.

## 🚀 Gubernator Features Utilized
* **Caddy Ingress**: `http://search.rag.gbnt.local` (UI) and `http://qdrant.rag.gbnt.local` (Qdrant API).
* **CoreDNS Networking**: Connects `rag-ui` to `qdrant.rag.gbnt.local:6333` and `postgres.rag.gbnt.local:5432` across worker nodes.
* **Granaries Persistent Storage**: Zero-data-loss storage in `/var/contenedores/pgvector` and `/var/contenedores/qdrant`.
* **Zero-Downtime Backups**: 100% consistent point-in-time database snapshots with `gbnt backup create --freeze`.

## 💻 Quick Deploy
```bash
gbnt examples deploy pgvector-rag
```
