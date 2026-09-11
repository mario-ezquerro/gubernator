---
title: "Autoscaling Docker Containers Without Kubernetes: How Gubernator Scales CPU & GPU Workloads Automatically"
published: true
tags: devops, docker, go, cloud
series: Gubernator Orchestrator
cover_image: https://raw.githubusercontent.com/mario-ezquerro/gubernator/main/articles/images/gubernator_autoscaling_cover.jpg
canonical_url: https://github.com/mario-ezquerro/gubernator/blob/main/articles/autoscaling-docker-compose-gubernator.md
description: "Discover how Gubernator delivers declarative Horizontal Pod Autoscaling (HPA) for plain Docker Compose stacks with CPU and NVIDIA GPU metrics across multi-node clusters."
---

When running containerized workloads, every engineering team eventually faces the **scaling dilemma**:

1. **Vanilla Docker / Docker Compose** is lightweight, fast, and wonderfully simple to maintain—but it has **zero native autoscaling**. If your API traffic triples during a flash sale or your AI inference queue spikes, you must manually run `docker compose up --scale api=5`.
2. **Kubernetes (K8s)** provides Horizontal Pod Autoscaler (HPA)—but it introduces an overwhelming operational tax: `metrics-server`, complex CRDs, etcd clusters, steep learning curves, and hundreds of megabytes of baseline overhead per node.

What if you could keep the pure simplicity of standard **`docker-compose.yml`** files, but gain **true horizontal autoscaling** across multi-node clusters based on real-time **CPU and NVIDIA GPU utilization**?

That is exactly why we built **[Gubernator (`gbnt`)](https://github.com/mario-ezquerro/gubernator)**—the "Goldilocks" container orchestrator that combines the dead-simple developer experience of Docker Swarm with the flexibility of Nomad and the enterprise governance of high-end platforms.

---

## 🏛️ The Architecture: How Gubernator Autoscaling Works

In Gubernator, nodes are called **Centurions** (Managers and Workers), and multi-container applications are deployed as **Legions** (Docker Compose stacks).

Under the hood, Gubernator's declarative autoscaling engine operates as an autonomous feedback loop:

```
                  ┌────────────────────────────────────────┐
                  │       Prometheus Metrics Collector     │
                  │   (cAdvisor CPU % + NVIDIA DCGM GPU %) │
                  └───────────────────┬────────────────────┘
                                      │ Telemetry Polling (10s)
                                      ▼
                  ┌────────────────────────────────────────┐
                  │    Gubernator Autoscaler Engine Core   │
                  │  - Parses 'gbnt.autoscaling.*' labels  │
                  │  - Evaluates Target vs Current Metric  │
                  │  - Applies Cooldown & Damping Windows  │
                  └───────────────────┬────────────────────┘
                                      │ Desired Replicas (±Δ)
                                      ▼
                  ┌────────────────────────────────────────┐
                  │         Centurion Scheduler            │
                  │   (Spread across nodes / GPU Affinity) │
                  └───────────────────┬────────────────────┘
                                      │ Docker Engine API
                                      ▼
            ┌─────────────────────────────────────────────────────┐
            │  Centurion Host 01          Centurion Host 02 (GPU) │
            │  [api-task-1] [api-task-2]  [api-task-3] [llm-task] │
            └─────────────────────────────────────────────────────┘
```

Every 10 to 15 seconds, the Gubernator Watchdog invokes `autoscaler.EvaluateAndAutoscale()`:
1. **Telemetry Ingestion:** Queries Prometheus / cAdvisor for real-time container CPU percentages and NVIDIA DCGM exporter for GPU compute load.
2. **Evaluation:** Averages utilization across all healthy running task replicas for that service.
3. **Threshold Calculation:**
   $$\text{Desired Replicas} = \left\lceil \text{Current Replicas} \times \left( \frac{\text{Current Metric Value}}{\text{Target Threshold}} \right) \right\rceil$$
4. **Guardrails & Cooldown:** Clamps desired replicas within `[min, max]` boundaries and verifies that the `cooldown` window (e.g. 60 seconds) has elapsed since the last scale event, preventing erratic flapping or thrashing.
5. **Intelligent Node Placement:** Uses Gubernator's hardware scheduler (`Spread` or `Binpack`) to assign new container instances to the least-loaded Centurion host—with automatic hardware affinity targeting nodes with physical NVIDIA GPUs when GPU metrics are configured.

---

## ⚡ Declarative Autoscaling via Compose Labels

You don't need proprietary manifests or extra YAML definitions. You declare autoscaling policies directly inside your standard `docker-compose.yml` service definition using the `gbnt.autoscaling.*` label prefix:

### 1. High-Traffic Web Service (CPU-Based Scaling)

```yaml
version: "3.8"

services:
  api:
    image: mycompany/fastapi-gateway:latest
    ports:
      - "8000:8000"
    deploy:
      replicas: 2
      labels:
        # Enable horizontal autoscaling
        - "gbnt.autoscaling.enable=true"
        # Scale based on CPU utilization
        - "gbnt.autoscaling.metric=cpu"
        # Target: scale up when average CPU exceeds 70%
        - "gbnt.autoscaling.target=70"
        # Boundary constraints
        - "gbnt.autoscaling.min=2"
        - "gbnt.autoscaling.max=10"
        # 60-second cooldown between scale events
        - "gbnt.autoscaling.cooldown=60"
        # Spread tasks across all cluster Centurions
        - "gbnt.autoscaling.scope=cluster"
        - "gbnt.autoscaling.strategy=spread"
```

### 2. AI Inference / LLM Service (NVIDIA GPU-Based Scaling)

For heavy AI and machine learning workloads (e.g., vLLM, Ollama, Hugging Face TGI), CPU load is often misleading because the compute bottleneck lives inside the GPU VRAM and Tensor Cores. 

Gubernator natively tracks **NVIDIA DCGM GPU utilization**:

```yaml
version: "3.8"

services:
  vllm-inference:
    image: vllm/vllm-openai:latest
    deploy:
      replicas: 1
      labels:
        - "gbnt.autoscaling.enable=true"
        # Target GPU Tensor Core load
        - "gbnt.autoscaling.metric=gpu"
        - "gbnt.autoscaling.target=80"
        - "gbnt.autoscaling.min=1"
        - "gbnt.autoscaling.max=4"
        - "gbnt.autoscaling.cooldown=120"
        # Target only Centurion nodes with GPU hardware
        - "gbnt.autoscaling.scope=cluster"
      placement:
        constraints:
          - "node.labels.gbnt.node.gpu == nvidia"
```

When load drops below the target threshold, Gubernator smoothly de-provisions excess containers in reverse order, ensuring zero data loss and respecting container graceful shutdown timeouts (`SIGTERM` followed by grace period).

---

## 🖥️ Full UI Control: Interactive Flutter Web Dashboard

Not a fan of editing raw YAML on the fly? Gubernator includes a full-screen **Material Design 3 Dashboard** written in Flutter Web:

1. **Interactive `AUTOSCALE` Badges:** In both the **Legions (Stacks)** overview and the **Containers (Tasks)** table, every service displays a live clickable chip:
   - ⚡ **`GPU • Cluster`** (Glowing amber/purple)
   - ⚡ **`CPU • Cluster`** (Electric cyan)
   - 💤 **`Off`** (Muted grey)
2. **Autoscale Control Dialog:** Clicking any chip opens a visual control modal where operators can:
   - Toggle autoscaling ON/OFF in 1 click
   - Switch metrics between CPU and GPU
   - Adjust the target percentage slider
   - Set minimum and maximum replica limits
   - Configure cooldown intervals
   - Choose cluster-wide vs single-host pinning
3. **Audit Trail & SIEM:** Every automatic scaling event is cryptographically sealed into Gubernator's immutable **Forensic Audit Log (ENS op.mon.1)** and forwarded to your enterprise SIEM (Splunk, Wazuh, Elastic) in CEF, RFC 5424 Syslog, or JSON.

---

## 🚀 Quickstart: Try It Yourself in 60 Seconds

Installing Gubernator takes a single binary or automated installer:

```bash
# Download the latest binary for your architecture (Linux AMD64/ARM64, macOS)
curl -sSL https://github.com/mario-ezquerro/gubernator/releases/latest/download/gbnt-linux-amd64 -o gbnt
chmod +x gbnt
sudo mv gbnt /usr/local/bin/

# Initialize the manager node and monitoring stack
gbnt legion init
gbnt monitor init
```

Open your browser at `http://localhost:4001` (Dashboard) and `http://localhost:4002/swagger/index.html` (REST API). Deploy your first compose stack and watch Gubernator seamlessly scale your tasks as traffic surges!

---

## 🌟 Wrapping Up

Container orchestration doesn't have to be a choice between the primitive limitations of a single Docker daemon and the crushing complexity of Kubernetes. 

With **Gubernator**, you get:
- Native Docker Compose compatibility
- Real-time CPU & NVIDIA GPU Horizontal Autoscaling
- Zero-CGO, single-binary Go engine
- Built-in Caddy Ingress, CoreDNS, GlusterFS storage, and OpenTelemetry SRE stack
- Enterprise Active Directory/LDAP, RBAC, and Spanish ENS forensic security

Give the project a star on GitHub and let us know your thoughts in the comments below!

👉 **GitHub Repository:** [https://github.com/mario-ezquerro/gubernator](https://github.com/mario-ezquerro/gubernator)
