# Web UI Dashboard

Gubernator includes a built-in **Web Dashboard** on port `:4001` that provides full lifecycle management of your cluster without requiring the CLI.

---

## Enabling the Dashboard

The Web UI is disabled by default. Enable it by setting environment variables before starting the Manager:

```bash
GBNT_WEB=true \
GBNT_WEB_USER=admin \
GBNT_WEB_PASSWORD=yourpassword \
GBNT_API_TOKEN=yourtoken \
./gbnt serve
```

Or via Docker:
```bash
docker run -d \
  -p 4000:4000 -p 4001:4001 -p 4002:4002 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e GBNT_WEB=true \
  -e GBNT_WEB_USER=admin \
  -e GBNT_WEB_PASSWORD=admin \
  -e GBNT_API_TOKEN=admin \
  marioezquerro/gubernator:latest serve
```

Then open: **[http://localhost:4001](http://localhost:4001)**

---

## Dashboard Sections

### Stats Bar

Displays real-time cluster summary (auto-refreshes every 5 seconds):

| Counter | Description |
|---------|-------------|
| Nodes | Total registered cluster nodes |
| Stacks | Total deployed stacks |
| Services | Total services across all stacks |
| Tasks | Total container instances |
| Running | Tasks currently in `running` state |

---

### Legions (Stacks)

Lists all deployed stacks with actions per row:

| Button | Action |
|--------|--------|
| **Edit YAML** | Opens the compose editor modal |
| **Redeploy** | Stops current containers and re-deploys immediately |
| **Delete** | Stops containers and removes stack from DB |

---

### Centurions (Nodes)

Lists all registered cluster nodes with their:
- **ID** (first 8 chars)
- **IP** address
- **Role** badge — `manager` (grey) or `worker` (blue)
- **Status** badge — `active` (green), `down` (red), `drain` (yellow)

---

### Cohorts & Tasks (Containers)

Lists all container instances with:

| Column | Description |
|--------|-------------|
| Task ID | First 8 chars of UUID |
| Service | Service name + Docker image |
| Container | Docker container name (`gbnt-<uuid>`) |
| Node | Node that is running this task |
| Status | `running` / `pending` / `starting` / `dead` |
| IP | Container's internal Docker network IP |
| Stop | Executes `docker stop + docker rm` and removes from DB |

---

## Compose Editor

Click **Edit YAML** on any stack to open the compose editor:

```
┌──────────────────────────────────────────────────────────┐
│  Edit Compose: mystack                               [×] │
├──────────────────────────────────────────────────────────┤
│  services:                                               │
│    web:                                                  │
│      image: nginx:alpine                                 │
│      ports:                                              │
│        - "8080:80"                                       │
│      deploy:                                             │
│        replicas: 2                                       │
│                                                          │
├──────────────────────────────────────────────────────────┤
│  [Save Changes]  [Save & Redeploy]  [Reset]              │
└──────────────────────────────────────────────────────────┘
```

### Editor Actions

| Button | What it does |
|--------|-------------|
| **Save Changes** | Saves the edited YAML to the database (no containers affected yet) |
| **Save & Redeploy** | Saves the YAML, stops existing containers, schedules new tasks |
| **Reset** | Reverts the editor to the last saved state |
| **Click backdrop** | Closes the modal without saving |

---

## Stack Redeploy Flow

When you click **Save & Redeploy** (or the **Redeploy** button on the table):

```
1. Save new YAML to DB
2. Find all running Tasks for this Stack
3. docker stop <container_name> + docker rm -f <container_name>
4. Delete Task records from DB
5. Call POST /v1/stack/deploy with the updated compose
6. Scheduler assigns new Tasks to active nodes
7. Local Executor picks up pending Tasks and starts new containers
```

---

## API Endpoints Used by the Dashboard

The Web UI communicates with the internal `/api` routes (on port 4001, protected by Basic Auth):

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/state` | Returns all nodes, stacks, services, tasks |
| `GET` | `/api/stack/:id/compose` | Fetches raw YAML for a stack |
| `PUT` | `/api/stack/:id/compose` | Updates raw YAML in DB |
| `POST` | `/api/stack/:id/redeploy` | Stop + redeploy a stack |
| `DELETE` | `/api/stack/:id` | Stop containers + delete stack |
| `DELETE` | `/api/task/:id` | Stop container + delete task record |

> These routes are separate from the CLI API on port 4000 and use Basic Auth instead of Bearer tokens.
