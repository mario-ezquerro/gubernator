# Testing Environments & Examples

Welcome to the Gubernator Examples Index. The `examples/` directory in the repository contains a variety of scenarios ranging from beginner basics to advanced, production-ready cluster environments. 

This page serves as a directory of these testing environments to help you understand Gubernator's capabilities.

---

## 1. Example 101 (`examples/example-101/`)
**Target Audience**: Beginners
**Focus**: Understanding Stack deployments, Replicas, and Constraints.

This directory contains standalone YAML files that you can use with `gbnt stack deploy` once your Manager and Workers are running. 

### What's Inside:
* `01-nginx-basic.yml`: The simplest deployment possible. Deploys 3 replicas of Nginx.
* `02-constrained-redis.yml`: Introduces **Scheduling Constraints**. Deploys Redis but forces Gubernator to only place tasks on nodes that have the `gbnt.node.role == worker` label.
* `03-ingress-api.yml`: Introduces **Ingress Labels**. Deploys an API image with the `ingress.host == my-api.local` constraint, instructing the Aqueducts engine to generate Caddy reverse-proxy rules.

---

## 2. The Empire (`examples/the-empire/`)
**Target Audience**: Intermediate / System Administrators
**Focus**: The Control Plane, Networking, and Internal DNS.

This environment demonstrates how to deploy the "Empire Trifecta", combining Gubernator with Caddy and CoreDNS for a fully-featured, auto-discovering cluster.

### What's Inside:
* `docker-compose.yml`: The foundational base. Starts the Gubernator Manager (with the Web UI enabled), Caddy (as the reverse proxy), and CoreDNS (for internal `.gbnt` resolution).
* `Corefile`: The configuration for CoreDNS to read the auto-generated `gubernator.hosts` file.
* `test-app.yml`: A sample stack containing Redis, a PostgreSQL Database, and Redis-Commander to test the ingress capabilities.

---

## 3. SRE-01 (`examples/SRE-01/`)
**Target Audience**: Advanced / DevOps / SRE
**Focus**: Telemetry, Monitoring, Log Aggregation, and Automatic HTTPS.

This environment builds upon *The Empire* and orchestrates a complete Site Reliability Engineering (SRE) stack. It showcases Gubernator's ability to seamlessly proxy HTTPS traffic internally using Caddy's Local CA (`tls internal`).

### What's Inside:
* `docker-compose.yml`: Starts the base control plane (Manager, CoreDNS, Caddy), identical to the one in The Empire but with `GBNT_WEB=true` injected.
* `monitoring-stack.yml`: The definitive monitoring triad:
  * **Prometheus**: For scraping Gubernator's `4000/metrics` endpoint and worker node metrics.
  * **Grafana**: For rich visualization dashboards.
  * **Loki**: For log aggregation across the cluster.
* All monitoring components are deployed via Gubernator, automatically receiving HTTPS internal endpoints (`https://prometheus.sre-monitoring.gbnt`, etc.).
