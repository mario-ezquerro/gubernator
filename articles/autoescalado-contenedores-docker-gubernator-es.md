---
title: "Autoescalado de Contenedores Docker sin Kubernetes: Cómo Gubernator escala cargas CPU y GPU automáticamente"
published: true
tags: devops, docker, spanish, cloud
series: Gubernator Orchestrator
cover_image: https://raw.githubusercontent.com/mario-ezquerro/gubernator/main/articles/images/gubernator_autoscaling_cover.jpg
canonical_url: https://github.com/mario-ezquerro/gubernator
description: "Descubre cómo Gubernator ofrece escalado horizontal automático (HPA) declarativo para stacks de Docker Compose con métricas de CPU y GPUs NVIDIA en clústeres multi-nodo."
---

Al desplegar aplicaciones contenerizadas en producción, los equipos de desarrollo y DevOps tarde o temprano se enfrentan al **dilema del escalado**:

1. **Docker clásico / Docker Compose** es ligero, rápido y extraordinariamente fácil de operar, pero carece de **autoescalado nativo**. Si el tráfico de tu API se triplica o se llena la cola de inferencia de tu modelo de IA, tienes que ejecutar manualmente `docker compose up --scale api=5`.
2. **Kubernetes (K8s)** ofrece Horizontal Pod Autoscaler (HPA), pero impone un coste operativo monumental: `metrics-server`, CRDs engorrosos, mantenimiento de etcd y cientos de megabytes de sobrecarga base por cada nodo del clúster.

¿Y si pudieras mantener la sencillez absoluta de tus archivos **`docker-compose.yml`** habituales, pero con **verdadero autoescalado horizontal (HPA)** basado en el uso real de **CPU y GPUs NVIDIA** en un clúster de múltiples máquinas?

Esa es precisamente la razón de ser de **[Gubernator (`gbnt`)](https://github.com/mario-ezquerro/gubernator)**: el orquestador "Goldilocks" que combina la simplicidad de Docker Swarm con la flexibilidad de Nomad y la seguridad empresarial.

---

## 🏛️ La Arquitectura: ¿Cómo funciona el Autoescalado en Gubernator?

En Gubernator, los servidores del clúster se denominan **Centuriones** (Managers y Workers), y las aplicaciones multi-contenedor se despliegan como **Legiones** (stacks de Docker Compose).

El motor de autoescalado opera como un bucle continuo de retroalimentación:

```
                  ┌────────────────────────────────────────┐
                  │      Recolector de Métricas Prometheus │
                  │   (cAdvisor CPU % + NVIDIA DCGM GPU %) │
                  └───────────────────┬────────────────────┘
                                      │ Muestreo cada 10s
                                      ▼
                  ┌────────────────────────────────────────┐
                  │    Motor Core de Autoescalado Gubernator│
                  │  - Parsea labels 'gbnt.autoscaling.*'  │
                  │  - Evalúa Objetivo vs Métrica Real     │
                  │  - Aplica Ventanas de Cooldown         │
                  └───────────────────┬────────────────────┘
                                      │ Réplicas Deseadas (±Δ)
                                      ▼
                  ┌────────────────────────────────────────┐
                  │         Planificador de Centuriones    │
                  │   (Reparto 'Spread' / Afinidad de GPU) │
                  └───────────────────┬────────────────────┘
                                      │ Docker Engine API
                                      ▼
            ┌─────────────────────────────────────────────────────┐
            │  Centurión Host 01          Centurión Host 02 (GPU) │
            │  [api-task-1] [api-task-2]  [api-task-3] [llm-task] │
            └─────────────────────────────────────────────────────┘
```

Cada 10 segundos, el watchdog de Gubernator evalúa las políticas de servicio:
1. **Ingesta de telemetría:** Consulta Prometheus y cAdvisor para obtener el porcentaje de CPU del contenedor, y el exportador NVIDIA DCGM para cargas GPU.
2. **Evaluación:** Calcula la media entre todas las réplicas sanas en ejecución para ese servicio.
3. **Cálculo del umbral:**
   $$\text{Réplicas Deseadas} = \left\lceil \text{Réplicas Actuales} \times \left( \frac{\text{Métrica Actual}}{\text{Umbral Objetivo}} \right) \right\rceil$$
4. **Límites y Cooldown:** Aplica los límites `[min, max]` y comprueba que haya transcurrido el tiempo de `cooldown` (p. ej. 60 segundos) desde el último escalado para evitar oscilaciones o flapping errático.
5. **Colocación inteligente:** El planificador distribuye las nuevas réplicas en el nodo menos cargado mediante estrategias `Spread` o `Binpack`, asignando automáticamente nodos con hardware NVIDIA cuando la métrica es GPU.

---

## ⚡ Autoescalado Declarativo mediante Labels en Compose

No necesitas manifiestos complejos ni archivos externos. Defines la política de autoescalado directamente dentro de las etiquetas de tu `docker-compose.yml`:

### 1. API Web de Alto Tráfico (Escalado por CPU)

```yaml
version: "3.8"

services:
  api:
    image: miempresa/fastapi-gateway:latest
    ports:
      - "8000:8000"
    deploy:
      replicas: 2
      labels:
        # Activar autoescalado horizontal
        - "gbnt.autoscaling.enable=true"
        # Métrica de escalado: CPU
        - "gbnt.autoscaling.metric=cpu"
        # Escalar si la CPU media supera el 70%
        - "gbnt.autoscaling.target=70"
        # Límites de réplicas
        - "gbnt.autoscaling.min=2"
        - "gbnt.autoscaling.max=10"
        # Tiempo de enfriamiento entre escalados (segundos)
        - "gbnt.autoscaling.cooldown=60"
        # Distribuir entre todos los nodos del clúster
        - "gbnt.autoscaling.scope=cluster"
        - "gbnt.autoscaling.strategy=spread"
```

### 2. Microservicio de Inferencia IA / LLM (Escalado por GPU NVIDIA)

Para modelos de lenguaje e inferencia intensiva (vLLM, Ollama, Hugging Face), la CPU no es el factor determinante, sino el uso de los Tensor Cores y la memoria de la tarjeta gráfica.

Gubernator monitoriza de forma nativa la GPU mediante **NVIDIA DCGM**:

```yaml
version: "3.8"

services:
  vllm-inference:
    image: vllm/vllm-openai:latest
    deploy:
      replicas: 1
      labels:
        - "gbnt.autoscaling.enable=true"
        # Métrica: GPU NVIDIA
        - "gbnt.autoscaling.metric=gpu"
        - "gbnt.autoscaling.target=80"
        - "gbnt.autoscaling.min=1"
        - "gbnt.autoscaling.max=4"
        - "gbnt.autoscaling.cooldown=120"
        - "gbnt.autoscaling.scope=cluster"
      placement:
        constraints:
          - "node.labels.gbnt.node.gpu == nvidia"
```

Cuando la carga disminuye por debajo del umbral, Gubernator reduce réplicas de forma ordenada, respetando el periodo de gracia y la señal `SIGTERM` para garantizar un apagado sin pérdida de transacciones.

---

## 🖥️ Control Visual desde el Dashboard Web (Flutter)

Si prefieres no editar YAML directamente en el servidor, Gubernator integra un panel de control visual en tiempo real:

1. **Chips interactivos `AUTOSCALE`:** En la vista de Stacks y en la tabla de Tareas (Contenedores), cada servicio muestra una etiqueta en vivo:
   - ⚡ **`GPU • Cluster`** (Ámbar / Púrpura)
   - ⚡ **`CPU • Cluster`** (Azul cian)
   - 💤 **`Off`** (Gris inactivo)
2. **Modal de Control de Autoescalado:** Al pulsar sobre el chip, se abre un asistente donde puedes activar/desactivar el escalado con 1 clic, ajustar el porcentaje con un deslizador visual, fijar límites mínimo y máximo y configurar el tiempo de cooldown.
3. **Pista de Auditoría Forense:** Cada evento de autoescalado queda sellado criptográficamente con SHA-256 en la pista de auditoría forense (conforme al ENS español `op.mon.1`) y retransmitido a tu SIEM (Splunk, Wazuh, Elastic) en tiempo real.

---

## 🚀 Pruébalo en 60 Segundos

Desplegar Gubernator solo requiere descargar su binario único en Go:

```bash
# Descarga para tu arquitectura (Linux AMD64/ARM64, macOS)
curl -sSL https://github.com/mario-ezquerro/gubernator/releases/latest/download/gbnt-linux-amd64 -o gbnt
chmod +x gbnt
sudo mv gbnt /usr/local/bin/

# Inicia el nodo manager y la pila de monitorización
gbnt legion init
gbnt monitor init
```

Abre tu navegador en `http://localhost:4001` (Dashboard Web) y `http://localhost:4002/swagger/index.html` (API REST). ¡Despliega tu primer stack y disfruta de autoescalado real sin la sobrecarga de Kubernetes!

---

⭐ **Código abierto en GitHub:** [https://github.com/mario-ezquerro/gubernator](https://github.com/mario-ezquerro/gubernator)
