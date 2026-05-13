# Gubernator API Documentation

Gubernator provides a complete, automatically generated REST API using `swag` (Swagger). 

When the Manager node is running, you can access the interactive Swagger UI directly in your browser:

**URL:** `http://localhost:4000/swagger/index.html`

## Available Endpoints (Overview)

### 🏛 The Legion (Nodes)
* `GET /v1/node/ls` - List all registered nodes in the cluster.
* `POST /v1/node/join` - Join a new worker node to the cluster.
* `POST /v1/node/heartbeat` - Send a health ping from a worker node.
* `GET /v1/cluster/token` - Get the secure token required for new nodes to join.

### 📦 The Command (Stacks)
* `POST /v1/stack/deploy` - Submit a `docker-compose.yml` payload to schedule and deploy services across the cluster.

### ⚔️ The Executor (Tasks)
* `GET /v1/node/tasks/{node_id}` - Fetch pending containers assigned to a specific worker node.
* `POST /v1/node/tasks/{task_id}/status` - Report the state (running, dead) of a container back to the manager.
