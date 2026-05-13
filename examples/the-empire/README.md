# The Empire: Gubernator + CoreDNS + Caddy

This example demonstrates the **"Empire Trifecta"**. By running Gubernator alongside CoreDNS and Caddy in a shared volume, you achieve zero-configuration Ingress and Service Discovery.

When Gubernator spins up a container, it automatically:
1. Writes the container's IP to `gubernator.hosts` (read by CoreDNS).
2. Writes an Ingress rule to `Caddyfile` (read by Caddy).

## 🚀 How to Run It

### 1. Spin up the Trifecta
Open a terminal in this directory (`examples/the-empire`) and run:
```bash
docker-compose up -d
```
*This starts the Manager (port 4000), CoreDNS (port 5353), and Caddy (port 80).*

### 2. Join a Worker Node
Since the Manager is running in Docker, we can join a local worker from your host machine (assuming you compiled `gbnt`).

First, get the Join Token by calling the Manager API:
```bash
curl -s http://localhost:4000/v1/cluster/token
```
*(Copy the token from the JSON output)*

Then, in your main repository folder, run the Worker:
```bash
./gbnt legion join --token <YOUR_TOKEN> --manager localhost:4000
```
*(Leave this running. It will execute containers on your Mac's Docker daemon).*

### 3. Deploy the Test App
Open a new terminal in the repository root and deploy the `test-app.yml` stack. Notice it has the `ingress.host == whoami.gubernator.local` label!

```bash
./gbnt stack deploy -c examples/the-empire/test-app.yml myapp
```

### 4. Witness the Magic

Wait a few seconds for the worker to pull the `traefik/whoami` image and start it.

1. **Check DNS:**
   Ask your local CoreDNS server (running on 5353) where the container is:
   ```bash
   dig @localhost -p 5353 whoami.myapp.gbnt +short
   ```
   *It will return the exact internal IP of the Docker container!*

2. **Check Ingress:**
   Since you requested `whoami.gubernator.local`, Caddy automatically reloaded to proxy it. Tell `curl` to resolve that fake domain to `localhost`:
   ```bash
   curl --resolve whoami.gubernator.local:80:127.0.0.1 http://whoami.gubernator.local
   ```
   *You will see the response from the `whoami` container, correctly routed by Caddy via Gubernator's dynamic Caddyfile!*
