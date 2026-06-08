# Jupyter AI Notebook in Gubernator

This example demonstrates how to deploy a fully featured **Jupyter Notebook** environment optimized for AI, Machine Learning, and Deep Learning on Gubernator.

It utilizes the official **Jupyter PyTorch Notebook** image, which comes loaded with PyTorch, Scikit-Learn, Pandas, NumPy, and other essential data science libraries.

---

## Features

- **JupyterLab**: Modern interactive development environment for notebooks, code, and data.
- **PyTorch Pre-installed**: Ready for training and running neural networks.
- **Data Science Toolkit**: Matplotlib, Scipy, Pandas, and NumPy preloaded.
- **Persistent Workspace**: A dedicated named volume (`jupyter_workspace`) ensures notebooks survive container restarts.
- **Caddy Ingress Integration**: Automatically exposes the Jupyter interface via `jupyter.gbnt.local` over HTTPS.

---

## Prerequisites

- **Gubernator** installed and running with Caddy Ingress active.
- Map the ingress domain in your host's `/etc/hosts` file:
  ```bash
  127.0.0.1 jupyter.gbnt.local
  ```

---

## Usage

1. **Deploy the Stack**
   From this directory, deploy the Jupyter stack to your Gubernator cluster:
   ```bash
   gbnt stack deploy jupyter-stack -c docker-compose.yml
   ```

2. **Retrieve Access Token**
   By default, the stack is configured with a secure token:
   - **Token**: `gubernator-secret`
   - You can modify the `JUPYTER_TOKEN` environment variable in `docker-compose.yml` before deploying if you wish to change it.

3. **Access JupyterLab**
   Open your browser and navigate to:
   ```
   https://jupyter.gbnt.local
   ```
   *Note: Log in by entering `gubernator-secret` in the Password or Token field.*

---

## How it works

The `docker-compose.yml` defines the `jupyter` service using the `quay.io/jupyter/pytorch-notebook:latest` image.

Gubernator's placement engine parses:
```yaml
    deploy:
      placement:
        constraints:
          - ingress.host == jupyter.gbnt.local
```
This tells Gubernator to configure Caddy to automatically route external requests for `jupyter.gbnt.local` to this container on its internal port `8888`.
