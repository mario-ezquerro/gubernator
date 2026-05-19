# Gubernator (gbnt) CLI Reference

This document serves as the complete reference for the Gubernator CLI tool (`gbnt`). All commands listed here are fully implemented and functional.

Gubernator's CLI is heavily inspired by Docker Swarm and Nomad, providing an intuitive interface for managing clusters, nodes, stacks, and individual services.

---

## The Forum (Context Configuration)

The Gubernator CLI acts as a remote client (`gbntctl`). It stores connection contexts in `~/.gbntctl/config`.

- **`gbnt config get-contexts`**
  Lists all configured remote clusters and highlights the currently active one.

- **`gbnt config use-context [name]`**
  Switches the active connection context to another manager.

---

## The Legion (Cluster Management)

Commands for managing the cluster lifecycle and joining nodes.

- **`gbnt legion init`**
  Initializes a new Gubernator cluster, converting the current node into the local Manager and setting up the SQLite database state.

- **`gbnt legion join --token [token] --manager [ip:4000]`**
  Joins the current machine to an existing Gubernator cluster as a Worker node.

- **`gbnt legion join-token`**
  Prints the exact command and secure token needed to join new Worker nodes to the cluster.

- **`gbnt legion leave`**
  Gracefully leaves the cluster, marking the current node as `left` in the Manager's database.

---

## The Centurions (Node Management)

Commands executed by the Manager to inspect and control the physical worker machines.

- **`gbnt node ls`**
  Lists all registered nodes in the cluster, displaying their ID, IP, Role, and current Status (e.g., active, down).

- **`gbnt node inspect [node_id]`**
  Displays detailed JSON information about a specific node, including its assigned labels and metadata.

- **`gbnt node promote [node_id]`**
  Promotes a Worker node to a Manager node within the cluster hierarchy.

- **`gbnt node demote [node_id]`**
  Demotes a Manager node back to a standard Worker role.

- **`gbnt node update --availability [active|pause|drain] [node_id]`**
  Changes the scheduling state of a node. (e.g., set to `drain` for maintenance, preventing new tasks from being scheduled there).

---

## The Command (Stack Management)

Commands for deploying and managing complex multi-container applications via Docker Compose syntax.

- **`gbnt stack deploy -c [docker-compose.yml] [stack_name]`**
  Deploys or updates an entire stack of services based on a Compose file. Parses `image`, `ports`, `environment`, `volumes`, `command`, `deploy.replicas`, and `deploy.placement.constraints`. Containers start automatically via the built-in local executor (no separate worker needed for single-node mode).

- **`gbnt stack ls`**
  Lists all currently deployed stacks across the cluster.

- **`gbnt stack services [stack_id]`**
  Lists all the individual services that belong to a specific deployed stack.

- **`gbnt stack rm [stack_id]`**
  Removes a stack completely: stops and removes all running Docker containers (`docker stop` + `docker rm`), then deletes tasks, services, and the stack record from the database.

---

## The Cohorts (Service Management)

Commands for managing individual services (which are usually created via Stacks).

- **`gbnt service ls`**
  Lists all active services running across the cluster, along with their desired replica counts and image names.

- **`gbnt service ps [service_id]`**
  Lists the actual physical containers (Tasks) running for a specific service. It displays exactly which Node is running each task and its internal Container IP.

- **`gbnt service scale [service_id]=[replicas]`**
  Updates the desired replica count for a specific service.

- **`gbnt service rm [service_id]`**
  Deletes a specific service and forces the worker nodes to stop its associated containers.

---

## System Commands

- **`gbnt serve`**
  Starts the Gubernator Manager daemon. Boots up the REST API (`:4000`), Flutter Web Dashboard (`:4001`), and Telemetry server (`:4002`).

- **`gbnt health`**
  Checks the health of the local Gubernator process by sending a request to `http://localhost:4002/health`. Returns exit code `0` if healthy, `1` otherwise. This is used as the native Docker `HEALTHCHECK` command inside the container, eliminating the need for `curl` or `wget`.
