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

## 3. Caddy Ingress Routing

Gubernator automatically configures a reverse proxy (Caddy) for your containers. You don't need to manually expose ports to the host network (like `80:80`) for every web app.

Instead, define the `ingress.host` constraint in your service. Gubernator will automatically detect the internal IP of the running container and route traffic for that domain directly to it.

```yaml
services:
  webapp:
    image: my-web-app:latest
    deploy:
      placement:
        constraints:
          - ingress.host == myapp.gbnt.test
```

If your container exposes a port other than `80`, define it in the standard `ports` array. Gubernator will read the **first port** defined and route traffic to it:

```yaml
services:
  webapp:
    image: my-web-app:latest
    ports:
      - "8080" # Gubernator will route ingress traffic to port 8080
    deploy:
      placement:
        constraints:
          - ingress.host == myapp.gbnt.test
```

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
* `deploy.placement.constraints`: Used for Node affinity (e.g. `node.labels.gpu == nvidia`) and Gubernator features (`ingress.host`, `stack.name`).
