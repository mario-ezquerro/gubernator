# Gubernator Examples

This directory contains example `docker-compose.yml` stacks to test the full Gubernator orchestration workflow. 

## How to Test the Workflow

Follow these steps to experience the complete Gubernator lifecycle from starting the cluster to deploying containers onto specific nodes.

### 1. Start the Manager (The Senate)

Open your first terminal and start the Manager. This node handles the SQLite database, API, and the Scheduler.

```bash
cd gubernator
go build -o gbnt ./cmd/gbnt
./gbnt serve
```
*(Leave this terminal running. It exposes the CLI on `:4000`, Web UI on `:4001`, and Telemetry/Swagger on `:4002`)*

### 2. Initialize the Legion

Open a second terminal. You need to get the secret `JoinToken` to allow other nodes to join securely.

```bash
./gbnt legion init
```
*Copy the `gbnt legion join ...` command from the output.*

### 3. Start a Worker (The Centurion)

In that same second terminal (or a third one), run the `join` command you copied. It should look like this:

```bash
./gbnt legion join --token <YOUR_TOKEN> --manager 127.0.0.1:4000
```
*(Leave this terminal running. It will start sending heartbeats every 10s and polling for tasks every 5s).*

### 4. Deploy a Stack

Now that you have an active Manager and an active Worker, you can deploy a stack. Open a new terminal.

**Deploy the basic NGINX stack:**
```bash
./gbnt stack deploy -c examples/01-nginx-basic.yml frontend
```

### 5. Watch the Magic Happen

1. **The Scheduler** (in the Manager) will parse the `01-nginx-basic.yml` file.
2. It sees that `nginx:alpine` requires `node.labels.gbnt.node.role == worker`.
3. It finds your Worker node (which automatically registered with that label when you ran `join`).
4. It creates 2 `Tasks` in the database assigned to that Worker's ID.
5. **The Worker** (in the second terminal) polls the API, sees its assigned tasks, and will print:
   `⬇️ Pulling image nginx:alpine...`
6. The Worker calls the local Docker Engine and spins up the containers:
   `🚀 Starting container for task ...`

### 6. Verify

You can verify the containers are actually running on your machine by running standard Docker commands:

```bash
docker ps | grep gbnt
```

You should see your two NGINX containers running natively, managed entirely by Gubernator!
