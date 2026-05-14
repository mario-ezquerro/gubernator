# SRE-01: The Ultimate Control Plane & Monitoring Stack

This example builds upon "The Empire" (Gubernator + CoreDNS + Caddy) and adds a complete Site Reliability Engineering (SRE) stack orchestrated entirely by Gubernator.

## Components

1. **The Core (Plano de Control)**:
   - `gubernator-manager`: The CLI (4000), Web UI (4001), and Telemetry/Swagger (4002).
   - `coredns`: Internal DNS resolution (port 5353).
   - `caddy`: Auto-HTTPS reverse proxy with `tls internal`.

2. **The SRE Stack (Super Ejemplo)**:
   Deployed via Gubernator's `stack deploy` to be scheduled and managed as containers.
   - `prometheus`: Scrapes metrics from Gubernator and nodes.
   - `grafana`: Visualizes the metrics.
   - `loki`: Aggregates logs.

## Step 1: Start the Base Empire

First, initialize the control plane:

```bash
docker-compose up -d
```

This will spin up Gubernator, Caddy, and CoreDNS.

## Step 2: Access the Web UI

Go to [http://localhost:4001](http://localhost:4001)
* **Username**: admin
* **Password**: admin

## Step 3: Deploy the SRE Stack

Use the Gubernator CLI to deploy the `monitoring-stack.yml` so that Gubernator schedules Prometheus, Grafana, and Loki dynamically:

```bash
gbnt stack deploy --name sre-monitoring -c monitoring-stack.yml
```

Since the containers have the `ingress.host` constraint, Gubernator will automatically instruct Caddy to generate HTTPS routes for them. 

You can then access them at:
- `https://prometheus.sre-monitoring.gbnt`
- `https://grafana.sre-monitoring.gbnt`
- `https://loki.sre-monitoring.gbnt`

*(Note: Ensure your OS is using CoreDNS for `.gbnt` domains, or map them in your `/etc/hosts`).*
