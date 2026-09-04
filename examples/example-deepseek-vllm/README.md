# DeepSeek & vLLM High-Throughput AI Inference Stack

This blueprint deploys a production-ready, self-hosted LLM inference cluster with **vLLM** and an **Open-WebUI** chat interface on Gubernator.

## 🏛️ Components
1. **`vllm-engine`**: High-performance OpenAI-compatible serving engine powered by PagedAttention running `DeepSeek-R1-Distill-Qwen-1.5B`.
2. **`chat-ui`**: Open-WebUI interface connected directly via internal CoreDNS service discovery.

## 🚀 Gubernator Features Utilized
* **Caddy Ingress**: Exposes `http://chat.deepseek.gbnt.local` (UI) and `http://api.deepseek.gbnt.local/v1` (API).
* **CoreDNS Discovery**: `http://api.deepseek.gbnt.local:8000/v1` resolved transparently between containers across nodes.
* **The Granaries (`/var/contenedores`)**: HuggingFace weights cached in `/var/contenedores/vllm/models` so models are never re-downloaded upon rescheduling.
* **Placement Constraints**: Hardware affinity for GPU nodes (`gbnt.node.gpu=nvidia`).

## 💻 Quick Deploy
```bash
gbnt examples deploy deepseek-vllm
```
