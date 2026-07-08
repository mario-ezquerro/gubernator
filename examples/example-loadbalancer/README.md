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

## Step 4: Clean Up

Stop and remove the stack:

```bash
./gbnt stack rm hello-lb
```
