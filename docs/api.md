# Gubernator API Documentation

Gubernator provides a complete, automatically generated REST API using `swag` (Swagger). 

When the Manager node is running, you can access the interactive Swagger UI directly in your browser:

**URL:** `http://localhost:4000/swagger/index.html`

## Available Endpoints (Overview)

### The Legion & Centurions (Nodes)
* `GET /v1/node/ls` - List all registered nodes in the cluster.
* `GET /v1/node/{id}` - Inspect specific node details.
* `POST /v1/node/join` - Join a new worker node to the cluster.
* `POST /v1/node/heartbeat` - Send a health ping from a worker node.
* `POST /v1/node/{id}/role` - Promote or demote a node.
* `POST /v1/node/{id}/availability` - Pause or drain a node.
* `POST /v1/node/{id}/leave` - Mark a node as having left the cluster.
* `GET /v1/cluster/token` - Get the secure token required for new nodes to join.

### The Command (Stacks)
* `POST /v1/stack/deploy` - Submit a `docker-compose.yml` payload to schedule and deploy services across the cluster.
* `GET /v1/stack/ls` - List all stacks.
* `GET /v1/stack/{id}/services` - List services for a specific stack.
* `DELETE /v1/stack/{id}` - Remove a stack and all its services/tasks.

### The Cohorts (Services)
* `GET /v1/service/ls` - List all services.
* `GET /v1/service/{id}/tasks` - List running containers for a service.
* `POST /v1/service/{id}/scale` - Change desired replicas of a service.
* `DELETE /v1/service/{id}` - Remove a service and its tasks.

### The Executor (Tasks)
* `GET /v1/node/tasks/{node_id}` - Fetch pending containers assigned to a specific worker node.
* `POST /v1/node/tasks/{task_id}/status` - Report the state (running, dead) of a container back to the manager.
