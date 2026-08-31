---
title: Kubeflow Without Kubernetes? Deploy a Complete MLOps Suite in 60 Seconds with Gubernator
published: true
description: Run JupyterLab, MLflow, MinIO S3, and Ollama Inference on a lightweight cluster using pure Docker Compose and <2GB RAM.
tags: devops, machinelearning, docker, ai
series: MLOps Made Simple
canonical_url: https://github.com/mario-ezquerro/gubernator
---

# 🛑 The "Kubernetes Tax" on Modern Machine Learning

If you’ve ever tried setting up **Kubeflow** on Kubernetes, you know the drill:
- 30+ Custom Resource Definitions (CRDs)
- Istio Service Mesh + Knative + Cert-Manager + Dex
- 16 GB to 32 GB of RAM consumed **before you even write a single line of Python**
- Days spent debugging webhook admission controllers and Kustomize overlays.

Kubernetes is great at hyper-scale, but for 95% of engineering teams, researchers, and startups, **Kubernetes for MLOps is massive over-engineering**.

What if you could have the exact same capabilities — **Interactive JupyterLab with PyTorch, MLflow Experiment Tracking, MinIO S3 Object Storage, and High-Speed LLM Inference** — deployed in **60 seconds using a single `docker-compose.yml`**?

Enter **Gubernator (`gbnt`)**: the lightweight "Goldilocks" container orchestrator.

---

## 🏛️ What is Gubernator?

[Gubernator](https://github.com/mario-ezquerro/gubernator) is a single-binary container orchestrator written in Go that combines:
1. **The simplicity of Docker Swarm** (pure Docker Compose syntax, easy multi-node clustering).
2. **The power of Nomad** (intelligent task scheduling, worker-first load balancing, and GPU hardware targeting).
3. **Built-in Aqueducts**: Automatic CoreDNS service discovery + multi-node Caddy Ingress with automatic HTTPS/TLS.
4. **The Granaries**: Persistent shared storage mobility (`/var/contenedores`) across cluster nodes.

---

## ⚖️ Architecture: Kubernetes Kubeflow vs. Gubernator MLOps

```
┌─────────────────────────────────────────────────────────────┐
│              🌐 Data Scientist / AI Engineer                │
└──────────────────────────────┬──────────────────────────────┘
                               │ (https://*.kubeflow.gbnt.local)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│          🔒 Built-in Caddy Ingress & CoreDNS Gateway        │
└──────┬──────────────┬──────────────┬──────────────┬─────────┘
       │              │              │              │
       ▼              ▼              ▼              ▼
┌──────────────┐┌──────────────┐┌──────────────┐┌──────────────┐
│  JupyterLab  ││    MLflow    ││   MinIO S3   ││ Ollama / vLLM│
│  Workspace   ││   Tracking   ││ Artifacts &  ││  Inference   │
│   (PyTorch)  ││  & Registry  ││   Datasets   ││   Serving    │
│    (:8888)   ││    (:5000)   ││    (:9001)   ││   (:11434)   │
└──────────────┘└──────────────┘└──────────────┘└──────────────┘
```

| Capability | Kubernetes Kubeflow | Gubernator MLOps (`kubeflow-stack`) |
| :--- | :--- | :--- |
| **Control Plane Overhead** | 16 GB – 32 GB RAM (etcd, Istio, K8s) | **< 200 MB RAM** (Go binary) |
| **Configuration Format** | Helm / Kustomize / CRD manifests | **Standard `docker-compose.yml`** |
| **Deployment Time** | 30–45 minutes | **< 60 seconds** |
| **Experiment Tracking** | Katib + Kubeflow Metadata | **MLflow Tracking + Model Registry** |
| **Artifact Store** | MinIO on PVCs | **MinIO S3 with Granaries Storage** |
| **Inference Serving** | KServe + Knative + Istio | **Ollama / vLLM (OpenAI API compatible)** |
| **Domain Routing & TLS** | VirtualServices + IngressGateway | **Automatic Caddy Ingress (`*.local`)** |

---

## 🚀 The Blueprint: Single-File MLOps Platform

Here is the entire stack defined in standard Docker Compose syntax:

```yaml
version: "3.8"

services:
  # 1. MinIO S3 Object Storage (Datasets & Model Checkpoints)
  minio:
    image: minio/minio:latest
    restart: unless-stopped
    command: server /data --console-address ":9001"
    environment:
      - MINIO_ROOT_USER=kubeflow
      - MINIO_ROOT_PASSWORD=gubernator123
    ports:
      - "9000:9000"
      - "9001:9001"
    volumes:
      - /var/contenedores/kubeflow/minio_data:/data
    labels:
      - "ingress.host=minio.kubeflow.gbnt.local"
      - "gbnt.caddy.port=9001"
      - "gbnt.service.name=minio-s3"

  # 2. MLflow Tracking Server & Model Registry
  mlflow:
    image: ghcr.io/mlflow/mlflow:latest
    restart: unless-stopped
    command: >
      mlflow server
      --host 0.0.0.0
      --port 5000
      --workers 1
      --allowed-hosts "*"
      --backend-store-uri sqlite:////data/mlflow.db
      --default-artifact-root s3://mlflow-artifacts/
    environment:
      - AWS_ACCESS_KEY_ID=kubeflow
      - AWS_SECRET_ACCESS_KEY=gubernator123
      - MLFLOW_S3_ENDPOINT_URL=http://minio.kubeflow.gbnt.local
      - MLFLOW_S3_IGNORE_TLS=true
      - MLFLOW_ALLOWED_HOSTS=*
    ports:
      - "5000:5000"
    volumes:
      - /var/contenedores/kubeflow/mlflow_data:/data
    labels:
      - "ingress.host=mlflow.kubeflow.gbnt.local"
      - "gbnt.caddy.port=5000"
      - "gbnt.service.name=mlflow-tracking"

  # 3. Interactive JupyterLab & PyTorch Workspaces
  jupyter-workspace:
    image: quay.io/jupyter/pytorch-notebook:latest
    restart: unless-stopped
    environment:
      - JUPYTER_TOKEN=gubernator-secret
      - JUPYTER_ENABLE_LAB=yes
      - AWS_ACCESS_KEY_ID=kubeflow
      - AWS_SECRET_ACCESS_KEY=gubernator123
      - MLFLOW_TRACKING_URI=http://mlflow.kubeflow.gbnt.local
      - MLFLOW_S3_ENDPOINT_URL=http://minio.kubeflow.gbnt.local
    ports:
      - "8888:8888"
    volumes:
      - /var/contenedores/kubeflow/workspaces:/home/jovyan/work
      - /var/contenedores/kubeflow/cache:/home/jovyan/.cache
    labels:
      - "ingress.host=notebooks.kubeflow.gbnt.local"
      - "gbnt.caddy.port=8888"
      - "gbnt.service.name=jupyterlab"

  # 4. Model Serving & LLM Inference Gateway
  inference-engine:
    image: ollama/ollama:latest
    restart: unless-stopped
    ports:
      - "11434:11434"
    volumes:
      - /var/contenedores/kubeflow/models:/root/.ollama
    labels:
      - "ingress.host=inference.kubeflow.gbnt.local"
      - "gbnt.caddy.port=11434"
      - "gbnt.service.name=model-serving"
```

---

## 🛠️ Deploying in 1 Command

On your Gubernator cluster, run:

```bash
gbnt stack deploy kubeflow-stack -c docker-compose.yml
```

Or open the **Gubernator Web Dashboard** (`http://localhost:4001`), head over to **Compose Studio**, select the **Kubeflow MLOps Blueprint**, and click **Deploy Stack**.

Gubernator's scheduler automatically:
1. Prioritizes **Centurion Worker nodes** over the Manager.
2. Spreads the workloads evenly across available workers.
3. Automatically sets up internal DNS (`CoreDNS`) and reverse proxy routes (`Caddy Ingress`).
4. Generates instant TLS certificates for all services.

---

## 🌐 Instant Endpoints & Access

Immediately after deployment, your MLOps platform is ready:

- 📓 **JupyterLab Workspace**: `https://notebooks.kubeflow.gbnt.local` *(Token: `gubernator-secret`)*
- 📊 **MLflow Experiment Tracking**: `https://mlflow.kubeflow.gbnt.local`
- 📦 **MinIO S3 Console**: `https://minio.kubeflow.gbnt.local` *(User: `kubeflow` / Pass: `gubernator123`)*
- ⚡ **Ollama Inference Engine**: `https://inference.kubeflow.gbnt.local` *(OpenAI-compatible `/v1/chat/completions`)*

---

## 🧪 Testing the End-to-End Pipeline in Python

Data scientists can write normal Python code to log experiments, save models to MinIO S3, and serve predictions:

```python
import mlflow
import mlflow.sklearn
from sklearn.ensemble import RandomForestClassifier
from sklearn.datasets import load_iris
import os

# Connect to the cluster's MLflow server
os.environ["MLFLOW_S3_ENDPOINT_URL"] = "http://minio.kubeflow.gbnt.local"
os.environ["AWS_ACCESS_KEY_ID"] = "kubeflow"
os.environ["AWS_SECRET_ACCESS_KEY"] = "gubernator123"

mlflow.set_tracking_uri("http://mlflow.kubeflow.gbnt.local")
mlflow.set_experiment("iris-classification-demo")

with mlflow.start_run():
    X, y = load_iris(return_X_y=True)
    clf = RandomForestClassifier(n_estimators=100, max_depth=4)
    clf.fit(X, y)

    # Log metrics
    accuracy = clf.score(X, y)
    mlflow.log_param("n_estimators", 100)
    mlflow.log_metric("accuracy", accuracy)

    # Persist model to MinIO S3 and register
    mlflow.sklearn.log_model(clf, "model", registered_model_name="IrisProductionModel")
    print(f"✅ Training completed! Accuracy: {accuracy * 100:.2f}%")
```

---

## 🌟 Key Takeaways

1. **You don't always need Kubernetes**: If you are not running hundreds of parallel multi-step distributed DAG pipelines with Argo, Kubernetes adds unnecessary friction and cost.
2. **Standard Compose is enough**: With an orchestrator like Gubernator, you get clustering, load balancing, health checks, automated Ingress, and persistent storage using simple, familiar Docker Compose files.
3. **Resource Efficiency**: You save 10x-20x the RAM, allowing you to invest your hardware budget where it actually matters: **GPUs and model training**.

---

### 🔗 Project Links

- 🐙 **GitHub Repository**: [mario-ezquerro/gubernator](https://github.com/mario-ezquerro/gubernator)
- 📖 **Documentation**: [Gubernator Docs](https://github.com/mario-ezquerro/gubernator/tree/main/docs)
- ⭐ Give it a star on GitHub if you found this useful!
