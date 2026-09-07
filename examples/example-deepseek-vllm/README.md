# DeepSeek AI High-Performance Inference Stack

Production-ready, self-hosted LLM inference cluster with **DeepSeek R1** and an **Open-WebUI** chat interface on Gubernator.

Supports two deployment modes:
1. **Universal Multi-Arch (Default)**: Powered by **Ollama**, running seamlessly on CPU, Apple Silicon, ARM64, AMD64, and consumer GPUs with low footprint (~1.5 GB).
2. **Datacenter GPU High-Throughput (vLLM)**: Powered by **vLLM PagedAttention** for high-concurrency clusters with dedicated NVIDIA GPUs (`gbnt.node.gpu == nvidia`).

---

## 🏛️ Components Architecture

```text
       ┌────────────────────────────────────────────────────────┐
       │                 Caddy Ingress (Port 80)                │
       └──────────────┬──────────────────────────┬──────────────┘
                      │                          │
                      ▼                          ▼
    ┌────────────────────────────────┐  ┌────────────────────────────────┐
    │      Open-WebUI Chat UI        │  │     DeepSeek Inference API     │
    │   chat.deepseek.gbnt.local     │  │    api.deepseek.gbnt.local     │
    │   (Port 8080 - Web Interface)  │──┼▶  (Port 11434/8000 OpenAI API) │
    └────────────────────────────────┘  └────────────────────────────────┘
                                                        │
                                                        ▼
                                        ┌────────────────────────────────┐
                                        │  Granaries Storage Persistence │
                                        │  /var/contenedores/deepseek    │
                                        │  Cached Model Weights (GGUF)   │
                                        └────────────────────────────────┘
```

1. **`deepseek-engine`**: High-performance OpenAI-compatible serving engine (`ollama/ollama:latest` or `vllm/vllm-openai:latest`) serving `deepseek-r1:1.5b`.
2. **`chat-ui`**: Modern Open-WebUI interface (`ghcr.io/open-webui/open-webui:main`) with streaming tokens, web search, document RAG, and markdown chat rendering.

---

## 🚀 Key Gubernator Features Utilized

* **Caddy Ingress Routing**:
  * Chat Dashboard: `http://chat.deepseek.gbnt.local` (proxied to port `8080`)
  * OpenAI-Compatible API: `http://api.deepseek.gbnt.local` (proxied to port `11434`)
* **CoreDNS Inter-Container Discovery**:
  * `chat-ui` resolves `api.deepseek.gbnt.local:11434` or bare `deepseek-engine:11434` transparently across any Centurion worker node.
* **The Granaries (`/var/contenedores`)**:
  * Downloaded model weights persist in `/var/contenedores/deepseek/models` so models are never re-downloaded upon rescheduling or node reboot.
  * Open-WebUI chat history and settings persist in `/var/contenedores/open-webui/data`.
* **Hardware Affinity & Placement Constraints**:
  * Dedicated GPU stack (`docker-compose-vllm-gpu.yml`) enforces `gbnt.node.gpu == nvidia`, guaranteeing GPU workloads never schedule onto CPU nodes.

---

## 💻 Deployment Options

### Option A: Universal Multi-Arch (Default — CPU, ARM64, AMD64, Mac/Multipass)
Deploy the default multi-arch stack directly from the CLI:
```bash
gbnt examples deploy deepseek-vllm
```
Or with custom compose file:
```bash
gbnt stack deploy -f examples/example-deepseek-vllm/docker-compose.yml deepseek-vllm
```

To pull the DeepSeek R1 model:
```bash
# Pull model directly inside engine container
docker exec -it $(docker ps -qf "name=gbnt-.*deepseek-engine") ollama pull deepseek-r1:1.5b
```

### Option B: Datacenter NVIDIA GPU Clusters (vLLM PagedAttention)
For production NVIDIA A100/H100/L40/RTX4090 servers:
```bash
gbnt stack deploy -f examples/example-deepseek-vllm/docker-compose-vllm-gpu.yml deepseek-vllm
```

---

## 🔍 Verification & Usage

1. **Verify Services Status**:
   ```bash
   gbnt task ls
   ```
   Confirm `deepseek-engine` and `chat-ui` reach `running` state.

2. **Test Inference API**:
   ```bash
   curl http://api.deepseek.gbnt.local:11434/api/tags
   ```

3. **Open Chat UI**:
   Navigate to [http://chat.deepseek.gbnt.local](http://chat.deepseek.gbnt.local) in your browser.
