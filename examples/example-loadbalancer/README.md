# Example 102 — Load Balancing with Caddy Ingress

This example demonstrates how to configure **round-robin load balancing** across multiple replicas of a service using Gubernator's integrated **CoreDNS** and **Caddy Ingress**.

You will deploy a stack containing 2 replicas of a lightweight HTTP server. Each container will serve its own hostname. You will then access the app via Caddy using a custom domain (`hello.gbnt.local`), and watch Caddy route your requests to both containers alternately.

---

## Prerequisites

- **Docker** running on your local machine.
- **Gubernator compiled** (`gbnt` binary) or running in a container.
- If running Gubernator as a Docker container, ensure the control plane is started (like in "Example Empire" or the default setup).

---

## Step 1: Deploy the Load Balanced Stack

From the root of the repository, deploy the stack using the Gubernator CLI:

```bash
export GBNT_API_TOKEN=admin

./gbnt stack deploy -c examples/example-loadbalancer/01-hello-loadbalancer.yml hello-lb
```

This will:
1. Parse the compose file.
2. Spin up **2 replicas** of the `busybox` container.
3. Automatically connect them to `gbnt-net`.
4. Configure CoreDNS to register both container IPs under the domain: `hello-app.hello-lb.gbnt`.
5. Write a Caddyfile directing traffic for `hello.gbnt.local` to `hello-app.hello-lb.gbnt` and reload Caddy.

---

## Step 2: Verify the Containers

Check that both tasks are running and connected to `gbnt-net`:

```bash
./gbnt task ls
```

You should see two tasks for the service `hello-app` with active IPs on the `172.23.0.x` network range.

---

## Step 3: Test Load Balancing via Caddy Ingress

Caddy usa `tls internal` (certificado autofirmado local), por lo que todas las peticiones deben ir a **HTTPS (puerto 443)**. Hay dos formas de probarlo:

---

### Opción A — CLI con `curl` (sin modificar nada en el sistema)

Usa el flag `--resolve` para que `curl` mapee el dominio sin tocar `/etc/hosts`:

```bash
# Una petición
curl -k --resolve hello.gbnt.local:443:127.0.0.1 https://hello.gbnt.local

# Diez peticiones en bucle para ver el round-robin
for i in {1..10}; do curl -k -s --resolve hello.gbnt.local:443:127.0.0.1 https://hello.gbnt.local; done
```

Resultado esperado (alternando entre los dos contenedores):
```
hola contenedor c09f8b60a8fa
hola contenedor 31fdc29c9d6f
hola contenedor c09f8b60a8fa
hola contenedor 31fdc29c9d6f
...
```

---

### Opción B — Navegador Web (requiere modificar `/etc/hosts`)

> **IMPORTANTE**: Sin esta entrada en `/etc/hosts`, el dominio `hello.gbnt.local` no resolverá en el navegador ni en `curl` sin el flag `--resolve`.

**1. Añade la entrada DNS local** (requiere sudo / contraseña de administrador):

```bash
sudo sh -c "echo '127.0.0.1 hello.gbnt.local' >> /etc/hosts"
```

**2. Verifica que se ha añadido:**
```bash
grep "hello.gbnt.local" /etc/hosts
# → 127.0.0.1 hello.gbnt.local
```

**3. Prueba con `curl` (sin `--resolve`):**
```bash
curl -k https://hello.gbnt.local
```

**4. Accede con el navegador:**
- Abre `https://hello.gbnt.local` en Chrome/Firefox/Safari.
- Verás una advertencia de seguridad por el certificado autofirmado de Caddy — es normal.
  - **Chrome**: Haz clic en *"Configuración avanzada"* → *"Acceder a hello.gbnt.local (no seguro)"*, o escribe `thisisunsafe` directamente sobre la pantalla de error.
  - **Firefox**: Haz clic en *"Avanzado"* → *"Aceptar el riesgo y continuar"*.
- Recarga la página varias veces (Cmd+R / F5) para observar el balanceo de carga: el identificador del contenedor alternará entre los dos activos.

---

## Example 2: Multi-Host Anti-Affinity & Physical Server Identification

When running a multi-node cluster (`gbnt-manager`, `gbnt-worker1`, `gbnt-worker2`, `gbnt-worker3`), you can spread container replicas across **different physical Centurion nodes** and have the web application display exactly which physical host is responding.

### Compose File: `02-multi-host-affinity.yml`

This stack uses:
- `deploy.placement.preferences: [spread: node.id]` to prevent container co-location.
- `gbnt.placement.strategy: spread` and `gbnt.caddy.lb: round_robin`.
- Automated injection of `$GBNT_NODE_ID`, `$GBNT_NODE_IP`, and `$GBNT_NODE_ROLE`.
- Bind-mount `/etc/hostname:/etc/host_hostname:ro` for bare-metal physical host verification.
- Active health check probes on `/health`.

```yaml
services:
  cluster-echo:
    image: python:3.11-alpine
    restart: unless-stopped
    volumes:
      - /etc/hostname:/etc/host_hostname:ro
    ports:
      - "8080:8080"
    deploy:
      replicas: 3
      placement:
        preferences:
          - spread: node.id
        constraints:
          - ingress.host == echo.gbnt.local
          - gbnt.caddy.lb == round_robin
          - gbnt.caddy.health_uri == /health
```

### Deploy to Cluster

```bash
./gbnt stack deploy -c examples/example-loadbalancer/02-multi-host-affinity.yml cluster-echo
```

Check task distribution across Centurion hosts:
```bash
./gbnt task ls
```
You will see replicas distributed across `gbnt-worker1`, `gbnt-worker2`, `gbnt-worker3`:
```
ID        SERVICE       NODE            STATUS    PORTS
a1b2c3d4  cluster-echo  gbnt-worker1    running   192.168.252.36:8080
e5f6g7h8  cluster-echo  gbnt-worker2    running   192.168.252.37:8080
i9j0k1l2  cluster-echo  gbnt-worker3    running   192.168.252.38:8080
```

### Test via CLI (Curl)

Send requests to see the physical host and container change with each request:

```bash
# JSON response showing node ID, IP, and container
for i in {1..6}; do
  curl -k -s --resolve echo.gbnt.local:443:192.168.252.35 https://echo.gbnt.local/json | grep -E '"node_id"|"node_ip"'
done
```

Output:
```json
  "node_id": "gbnt-worker1",
  "node_ip": "192.168.252.36",
  "node_id": "gbnt-worker2",
  "node_ip": "192.168.252.37",
  "node_id": "gbnt-worker3",
  "node_ip": "192.168.252.38",
```

### Test in Web Browser

1. Add to your workstation's `/etc/hosts` (replace with your manager IP):
   ```
   192.168.252.35 echo.gbnt.local whoami.gbnt.local
   ```
2. Open `https://echo.gbnt.local` in your browser.
3. You will see an interactive dashboard displaying:
   - **Centurion Badge**: Unique color per worker node (Green for Worker 1, Blue for Worker 2, Purple for Worker 3).
   - **Physical Host ID**: Machine hostname from `/etc/hostname`.
   - **Node IP**: Cluster overlay/LAN IP.
   - **Live Auto-Refresh**: Click "▶ Auto-Refresh (2s)" to watch requests seamlessly cycle through all cluster nodes!

---

## Clean Up

Stop and remove stacks:

```bash
./gbnt stack rm hello-lb
./gbnt stack rm cluster-echo
```
