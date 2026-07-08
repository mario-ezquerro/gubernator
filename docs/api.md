# Gubernator API Reference

Gubernator provides a complete REST API with auto-generated Swagger documentation. All API calls on port 4000 require a Bearer token header.

## Authentication

```bash
curl -H "Authorization: Bearer <GBNT_API_TOKEN>" http://localhost:4000/v1/node/ls
```

Set `GBNT_API_TOKEN` as an environment variable when starting the Manager (default: `admin`).

## Interactive Swagger UI

While `./gbnt serve` is running:

**[http://localhost:4002/swagger/index.html](http://localhost:4002/swagger/index.html)**

---

## Endpoints

### Cluster & Nodes

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/v1/node/ls` | List all registered nodes |
| `GET` | `/v1/node/{id}` | Inspect a specific node |
| `POST` | `/v1/node/join` | Register a new worker node |
| `POST` | `/v1/node/heartbeat` | Worker heartbeat ping |
| `POST` | `/v1/node/{id}/role` | Promote or demote a node |
| `POST` | `/v1/node/{id}/availability` | Set node state (active/pause/drain) |
| `POST` | `/v1/node/{id}/leave` | Remove a node from the cluster |
| `GET` | `/v1/cluster/token` | Get the join token |

### Stacks

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/v1/stack/deploy` | Deploy a Compose stack |
| `GET` | `/v1/stack/ls` | List all stacks |
| `GET` | `/v1/stack/{id}/services` | List services for a stack |
| `DELETE` | `/v1/stack/{id}` | Delete stack + stop containers |

### Services

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/v1/service/ls` | List all services |
| `GET` | `/v1/service/{id}/tasks` | List tasks for a service |
| `POST` | `/v1/service/{id}/scale` | Scale service replicas |
| `DELETE` | `/v1/service/{id}` | Remove a service |

### Tasks

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/v1/task/ls` | List all tasks |
| `GET` | `/v1/node/tasks/{node_id}` | Fetch pending tasks for a worker node |
| `POST` | `/v1/node/tasks/{task_id}/status` | Worker reports task status |
| `DELETE` | `/v1/task/{id}` | Remove a task record |

---

## Stack Deploy Payload

```json
{
  "name": "mystack",
  "compose_raw": "services:\n  web:\n    image: nginx:alpine\n    ports:\n      - \"8080:80\"\n    deploy:\n      replicas: 1\n"
}
```

The `compose_raw` field accepts the full YAML content of a `docker-compose.yml` file. Gubernator parses:

- `services.<name>.image`
- `services.<name>.ports`
- `services.<name>.environment`
- `services.<name>.volumes`
- `services.<name>.command`
- `services.<name>.deploy.replicas`
- `services.<name>.deploy.placement.constraints`

---

## Task Status Update Payload

Workers call this endpoint after starting a container:

```json
{
  "status": "running",
  "container_ip": "172.17.0.5",
  "container_name": "gbnt-550e8400-e29b"
}
```

---

## Example: Deploy via curl

```bash
COMPOSE=$(cat examples/example-wordpress/docker-compose.yml)

curl -s -X POST http://localhost:4000/v1/stack/deploy \
  -H "Authorization: Bearer admin" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"wp\", \"compose_raw\": $(echo "$COMPOSE" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}"
```
