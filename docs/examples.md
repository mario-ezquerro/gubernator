# Examples Overview

This page is your index to the progressive tutorials included with Gubernator. Each example builds upon the previous, teaching you Gubernator concepts step by step.

---

## Learning Path

```
┌────────────────────┐     ┌────────────────────┐     ┌────────────────────┐     ┌────────────────────┐     ┌────────────────────┐
│   Single Node      │     │   Cluster + Ingress │     │   Full SRE Stack   │     │   AI & Automation  │     │   AI Notebook Stack│
│   Basic stacks     │     │   CoreDNS + Caddy   │     │   Prometheus/Grafana│     │   n8n+Ollama+Qdrant│     │   Jupyter + PyTorch│
│   10 min           │     │   30 min            │     │   60 min           │     │   40 min           │     │   15 min           │
└────────────────────┘     └────────────────────┘     └────────────────────┘     └────────────────────┘     └────────────────────┘
  Beginner                   Intermediate                Advanced / DevOps          Advanced / AI              Advanced / AI
```

---

## Example WordPress — Getting Started

**Target**: Beginner  
**Goal**: Learn the basic Gubernator workflow on a single machine

[Start Example WordPress →](example-wordpress.md)

- Deploy a WordPress + MySQL stack
- Learn how persistent volumes, multi-service dependencies, and internal DNS work
- Verify containers with `docker ps | grep gbnt`
- Explore automatic Caddy Ingress reverse proxying


---

## Example SRE — Full Observability Stack

**Target**: Advanced / SRE  
**Goal**: A production-grade control plane managing Prometheus, Grafana, and Loki

[Start Example SRE →](example-sre.md)

- Complete SRE tooling orchestrated by Gubernator itself
- Prometheus scrapes Gubernator metrics
- Grafana dashboards + Loki log aggregation

---

## Example SLO — Service Level Objectives & Error Budget Tracking

**Target**: Advanced / SRE  
**Goal**: Deploy a microservice with native Sloth SLO labels and track real-time Error Budget consumption

[Start Example SLO →](example-slo.md)

- Define `gbnt.slo.target`, `gbnt.slo.window`, and `gbnt.slo.sli.*` labels in `docker-compose.yml`
- Auto-generate multi-window multi-burn-rate Prometheus recording and alerting rules with `gbnt slo sync`
- Monitor real-time Error Budget remaining % and burn rates with `gbnt slo ls`

---

## Example Jaeger — Distributed Tracing Stack

**Target**: Advanced / SRE  
**Goal**: Deploy a 3-tier microservice architecture sending OTLP traces to Jaeger with Caddy Ingress domain `jaeger.gbnt.local`

[Start Example Jaeger →](example-jaeger.md)

- Multi-microservice trace propagation (Frontend -> API -> Worker)
- Caddy Ingress reverse proxy domain binding (`jaeger.gbnt.local`)
- Automatic OTLP HTTP trace submission to `gbnt-monitor-jaeger`
- Real-time trace visualization in Gubernator Web UI Jaeger tab

---

## Jaeger Integration Guide — Container Tracing Setup

**Target**: All Developers / SREs  
**Goal**: Step-by-step guide on configuring any container application (Python, Node.js, Go) to send OpenTelemetry traces to Jaeger in Gubernator

[Read Jaeger Integration Guide →](how-use-jaeger.md)

- Comprehensive setup for OTLP HTTP (`:4318`) and OTLP gRPC (`:4317`)
- Docker network configuration (`gbnt-net`)
- Standard OpenTelemetry environment variables (`OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`)
- Code snippets for Python, Node.js, Go, and cURL
- Automated traffic generation with `generate_traces.py` and `send_traces.sh`

---

## Example n8n — AI & Automation Stack

**Target**: Advanced / AI  
**Goal**: Deploy a self-contained AI automation workflow engine with local LLMs and vector search

[Start Example n8n →](example-n8n.md)

- Deploy n8n workflow engine connected to a Postgres backend database
- Set up local LLMs via Ollama and a vector database via Qdrant
- Dynamic Caddy Ingress reverse proxying for custom/non-standard ports
- Autoloading local models (`llama3.2`) during container initialization

---

## Example Jupyter — AI Notebook Stack

**Target**: Advanced / AI  
**Goal**: Deploy a data science and machine learning notebook pre-loaded with PyTorch

[Start Example Jupyter →](example-jupyter.md)

- Deploy a pre-configured JupyterLab developer workspace
- Built-in support for PyTorch, NumPy, Pandas, Scipy, and Scikit-Learn
- Persistent volume workspace for code and notebooks
- Caddy Ingress configuration for secure external traffic mapping on port `8888`

---

## Example Public HTTPS — Automatic Let's Encrypt / ZeroSSL

**Target**: Intermediate / DevOps  
**Goal**: Deploy any web application with a real public domain (`demo.fiware.app`) and automatic SSL/TLS certificate issuance

[Start Example Public HTTPS →](example-public-https.md)

- Zero-touch Let's Encrypt / ZeroSSL ACME certificate issuance
- Automatic HTTP (`:80`) to HTTPS (`:443`) redirection
- Ingress constraints (`ingress.host`, `ingress.email`) and label equivalents
- Background certificate auto-renewal before expiration

---

## Example LLaMA-Factory — Visual LLM Fine-Tuning Studio

**Target**: Advanced / AI  
**Goal**: Deploy a visual no-code/low-code fine-tuning suite for Llama 3, Qwen 2.5, DeepSeek, and SmolLM with LoRA/QLoRA and GGUF export

[Start Example LLaMA-Factory →](example-llama-factory.md)

- Visual training web interface (`llama-factory.gbnt.local:7860`)
- Multi-dataset support (Alpaca, ShareGPT, custom JSON)
- Real-time loss tracking and stdout streaming in Loki Logs
- One-click GGUF quantization and model export

---

## Example JupyterLab PyTorch — LLM Training & Fine-Tuning Lab

**Target**: Advanced / AI  
**Goal**: Deploy an interactive PyTorch data science environment with SFTTrainer, LoRA adapters, and persistent cluster storage

[Start Example JupyterLab LLM Lab →](example-jupyter-llm.md)

- Step-by-step interactive notebook (`llm_lora_finetuning.ipynb`)
- Pre-configured Hugging Face `transformers`, `peft`, `trl`, and `datasets`
- Headless automated training script (`train_script.py`)
- Persistent shared storage mobility in `/var/contenedores/jupyter-llm`
