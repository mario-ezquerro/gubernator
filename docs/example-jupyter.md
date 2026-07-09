# AI Development Stack (Jupyter Notebook)

This tutorial guides you through deploying a production-ready **Jupyter Notebook** environment optimized for AI, Machine Learning, and Deep Learning on Gubernator.

It showcases how Gubernator schedules large workloads, mounts persistent developer workspaces, and handles Caddy Ingress reverse proxying for custom container ports (Jupyter listens on `8888` by default).

---

## What You Will Deploy

The stack file `docker-compose.yml` located in `examples/example-jupyter/` defines:
- **`jupyter`**: A container running the official `quay.io/jupyter/pytorch-notebook` image, which includes:
  - **PyTorch** (deep learning framework)
  - **Pandas, NumPy, Scipy, Matplotlib** (data manipulation and plotting)
  - **Scikit-Learn** (classical machine learning)
  - **JupyterLab** (web dashboard interface)
  - A persistent Docker volume (`jupyter_workspace`) mounted at `/home/jovyan/work` to save notebooks and datasets.

---

## Prerequisites

- **Gubernator** running on your manager node with Caddy Ingress active.
- Configure your host OS resolver to use Gubernator's DNS for `.gbnt` and `.gbnt.test` domains (see Installation guide). No `/etc/hosts` modifications needed!

---

## Step 1: Deploy the Stack

Deploy the stack using the CLI from the root of the Gubernator repository:

```bash
# Set your API token if authentication is enabled
export GBNT_API_TOKEN=admin

# Deploy the stack and name it 'jupyter-stack'
./gbnt stack deploy -c examples/example-jupyter/docker-compose.yml
```

---

## Step 2: Verify the Deployment

Wait a few seconds for Gubernator to pull the large PyTorch image and schedule the task.

### 1. Check Tasks Status
Run the task list command to verify the task is running:
```bash
./gbnt task ls
```
You should see the `jupyter` task listed as `running` with an IP address assigned.

### 2. Verify Caddy Ingress
Gubernator's Ingress engine automatically reads the internal container port (`8888`) and configures Caddy to reverse proxy external requests to the correct target.

Verify the connection using curl:
```bash
curl -k -i https://jupyter.gbnt.test --resolve jupyter.gbnt.test:443:127.0.0.1 --head
```
You should receive an **HTTP 302 Found** or **HTTP 200 OK** redirecting to the Jupyter login screen.

---

## Step 3: Accessing the Notebook

1. Open your browser and navigate to [https://jupyter.gbnt.test](https://jupyter.gbnt.test).
2. Enter the default token **`gubernator-secret`** in the Password or Token field to log in.
3. You will be greeted by the JupyterLab dashboard. Any notebook or file created in the `work/` folder will be persisted inside the `jupyter_workspace` volume.

---

## Step 4: Verify the AI Environment

To verify that the AI libraries are fully operational:
1. Open a new Python 3 Notebook from the JupyterLab Launcher.
2. Enter and execute the following Python code:
   ```python
   import torch
   import numpy as np
   import pandas as pd
   
   print(f"PyTorch Version: {torch.__version__}")
   print(f"NumPy Version: {np.__version__}")
   print(f"Pandas Version: {pd.__version__}")
   print(f"CUDA Available: {torch.cuda.is_available()}")
   ```
3. Run the cell to verify that all imports are successful.

---

## Step 5: Clean Up

To tear down the stack and remove the running container:

```bash
# Get the stack ID
./gbnt stack ls

# Remove the stack
./gbnt stack rm <stack_id>
```

---

## Customization

### Alternative Images (TensorFlow)
If you prefer TensorFlow over PyTorch, you can edit `examples/example-jupyter/docker-compose.yml` to use the official TensorFlow notebook image:
```yaml
    image: quay.io/jupyter/tensorflow-notebook:latest
```

### Changing the Access Token
To secure your instance, update the `JUPYTER_TOKEN` environment variable under the `jupyter` service environment list:
```yaml
    environment:
      - JUPYTER_TOKEN=your-custom-secure-token
```
