# Examples Overview

This page is your index to the progressive tutorials included with Gubernator. Each example builds upon the previous, teaching you Gubernator concepts step by step.

---

## Learning Path

```
┌────────────────────┐     ┌────────────────────┐     ┌────────────────────┐     ┌────────────────────┐     ┌────────────────────┐
│   Example 101      │ ──► │   The Empire        │ ──► │    SRE-01          │ ──► │   Example n8n      │ ──► │   Example Jupyter  │
│   Single Node      │     │   Cluster + Ingress │     │   Full SRE Stack   │     │   AI & Automation  │     │   AI Notebook Stack│
│   Basic stacks     │     │   CoreDNS + Caddy   │     │   Prometheus/Grafana│     │   n8n+Ollama+Qdrant│     │   Jupyter + PyTorch│
│   10 min           │     │   30 min            │     │   60 min           │     │   40 min           │     │   15 min           │
└────────────────────┘     └────────────────────┘     └────────────────────┘     └────────────────────┘     └────────────────────┘
  Beginner                   Intermediate                Advanced / DevOps          Advanced / AI              Advanced / AI
```

---

## Example 101 — Getting Started

**Target**: Beginner  
**Goal**: Learn the basic Gubernator workflow on a single machine

[Start Example 101 →](example-101.md)

- Deploy a WordPress + MySQL stack
- Learn how persistent volumes, multi-service dependencies, and internal DNS work
- Verify containers with `docker ps | grep gbnt`
- Explore automatic Caddy Ingress reverse proxying

---

## The Empire — Cluster + Ingress

**Target**: Intermediate  
**Goal**: Run the full "Trifecta" — Gubernator + CoreDNS + Caddy

[Start The Empire →](example-empire.md)

- Launch the control plane with `docker compose up`
- Deploy apps with automatic DNS resolution and Caddy routing
- Use the Web UI compose editor to update and redeploy

---

## SRE-01 — Full Observability Stack

**Target**: Advanced / SRE  
**Goal**: A production-grade control plane managing Prometheus, Grafana, and Loki

[Start SRE-01 →](example-sre01.md)

- Complete SRE tooling orchestrated by Gubernator itself
- Prometheus scrapes Gubernator metrics
- Grafana dashboards + Loki log aggregation

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


