# Gubernator Compose Reference

Gubernator uses standard `docker-compose.yml` files to deploy stacks, but it extends their functionality by dynamically parsing certain fields for cluster scheduling, auto-naming, and Ingress routing.

This guide explains how to properly write and adjust your `docker-compose.yml` files for Gubernator.

---

## 1. Auto-Naming Stacks

Gubernator allows you to define the name of your stack directly inside the `docker-compose.yml` file. This means you can deploy your stack without specifying the name in the CLI (`gbnt stack deploy -c file.yml`) or the Web UI.

Gubernator resolves the stack name in the following order:

1. **`stack.name` constraint** (Highest Priority - Overrides all other methods).
2. **Explicit argument** (e.g., CLI `[name]` argument or Web UI input).
3. **Top-level `name` property** (Native Docker Compose standard).

### Option A: The `stack.name` constraint (Recommended)
Because Gubernator makes heavy use of placement constraints for its engine, the recommended way to name your stack is within the first service's placement constraints using `stack.name == <name>`:
```yaml
services:
  web:
    image: nginx
    deploy:
      placement:
        constraints:
          - stack.name == my-app-stack
```

### Option B: Top-level `name`
Alternatively, you can use the standard Compose `name` attribute at the root level of your file:
```yaml
name: my-app-stack
services:
  web:
    image: nginx
```

---

## 2. Dynamic Stack Variables `{{stack.name}}`

Gubernator includes a real-time templating engine for Compose files. Any occurrence of `{{stack.name}}` inside your `docker-compose.yml` will be **automatically replaced** by the resolved stack name at deployment time.

This is highly useful for internal DNS resolution and naming volumes, ensuring that multiple deployments of the same file don't collide.

```yaml
services:
  db:
    image: postgres:16
    hostname: postgres
    environment:
      POSTGRES_USER: user
  
  app:
    image: my-backend
    environment:
      # Automatically resolves to the internal CoreDNS record (e.g., postgres.my-stack.gbnt)
      DB_HOST: postgres.{{stack.name}}.gbnt
    volumes:
      # Ensures this volume is unique per stack
      - data_{{stack.name}}:/app/data

volumes:
  data_{{stack.name}}:
```

---

## 3. Caddy Ingress Routing & Automatic HTTPS

Gubernator automatically configures a high-performance reverse proxy (**Caddy**) across all cluster nodes. You don't need to manually expose host ports (`80:80`) for web applications.

Instead, define the `ingress.host` constraint (or label) in your service. Gubernator dynamically resolves the internal container IPs, configures upstream load balancing, and manages SSL/TLS certificates.

### A. Local Domains (`*.gbnt.local`) — Internal TLS
For development and local testing, use a `.local`, `.internal`, or `*.gbnt.local` domain. Gubernator will instruct Caddy to use its internal self-signed Root Certificate Authority (`tls internal`):

```yaml
version: '3.8'

services:
  webapp:
    image: nginxdemos/hello:latest
    ports:
      - "80"
    deploy:
      replicas: 2
      placement:
        constraints:
          - stack.name == dev-app
          - ingress.host == myapp.gbnt.local
```

> [!TIP]
> To trust local certificates in your browser without security warnings, download the Root CA (`root.crt`) from the Web Dashboard (**Caddy Ingress ➔ TLS Certs**) or via `http://<manager-ip>:4000/v1/caddy/ca.crt`.

---

### B. Public Domains (`demo.fiware.app`) — Automatic Let's Encrypt SSL/TLS
When you provide a real, public FQDN (e.g., `demo.fiware.app`, `api.mycompany.com`), Gubernator automatically enables **Caddy Automatic HTTPS**:

1. **Zero-Touch Provisioning**: Caddy contacts **Let's Encrypt** / **ZeroSSL** via the ACME protocol.
2. **Instant Verification**: Caddy validates domain ownership over ports `80`/`443` (HTTP-01 / TLS-ALPN-01 challenges).
3. **Official X.509 Certificate**: A valid, globally trusted certificate is issued, installed, and HTTPS is activated in seconds.
4. **Automatic HTTP ➔ HTTPS Redirect**: Port 80 traffic is redirected to port 443 automatically.
5. **Background Auto-Renewal**: Certificates are automatically renewed 30 days before expiration.

#### Example: Deploying a Public Domain Stack
```yaml
version: '3.8'

services:
  frontend:
    image: nginxdemos/hello:latest
    ports:
      - "80" # Target container port
    deploy:
      replicas: 2
      placement:
        constraints:
          - stack.name == production-demo
          # Public domain for Automatic Let's Encrypt HTTPS:
          - ingress.host == demo.fiware.app
          # (Optional) ACME email for certificate expiration alerts:
          - ingress.email == admin@fiware.app
```

#### Alternative Format with Service Labels
You can also use standard Docker Compose `labels`:
```yaml
version: '3.8'

services:
  frontend:
    image: nginxdemos/hello:latest
    ports:
      - "80"
    labels:
      gbnt.ingress.host: "demo.fiware.app"
      gbnt.ingress.email: "admin@fiware.app"
```

---

### C. Ingress Constraints & Labels Reference

| Constraint / Label | Description | Example |
| :--- | :--- | :--- |
| `ingress.host == <domain>` | Domain to route to this service | `- ingress.host == demo.fiware.app` |
| `ingress.email == <email>` | ACME contact email for Let's Encrypt | `- ingress.email == admin@fiware.app` |
| `ingress.tls == internal` | Force Caddy internal self-signed CA | `- ingress.tls == internal` |
| `ingress.tls == off` | Disable TLS (plain HTTP on port 80 only) | `- ingress.tls == off` |
| `gbnt.ingress.host` | Label equivalent of `ingress.host` | `gbnt.ingress.host: "demo.fiware.app"` |
| `gbnt.ingress.email` | Label equivalent of `ingress.email` | `gbnt.ingress.email: "admin@fiware.app"` |

---

### D. Prerequisites for Public HTTPS Domains

1. **DNS Record**: In your DNS provider (Cloudflare, Route53, GoDaddy, OVH, etc.), configure an `A` record pointing `demo.fiware.app` to the **public IP** of your Gubernator Manager or Ingress node:
   ```text
   demo.fiware.app.   300   IN   A   <YOUR_PUBLIC_SERVER_IP>
   ```
2. **Firewall / Security Group**: Ensure inbound traffic on ports **`80` (HTTP)** and **`443` (HTTPS)** is open to the internet (`0.0.0.0/0`).

---

## 4. Supported Compose Fields

Gubernator's parser focuses on the fields necessary for container scheduling and networking. The following fields are actively parsed and applied:

* `image`: The container image to pull and run.
* `ports`: Ports to expose (also used for Ingress target detection).
* `environment`: Environment variables (supports both map and array formats).
* `volumes`: Local and named volume mounts.
* `command`: Overrides the default container command.
* `depends_on`: Ensures proper startup ordering of services.
* `deploy.replicas`: Number of container instances to spawn.
* `deploy.placement.constraints`: Used for Node affinity (e.g. `node.labels.gpu == nvidia`) and Gubernator features (`ingress.host`, `ingress.email`, `stack.name`).

