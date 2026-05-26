# Gubernator (gbnt) CLI Reference

This document serves as the complete reference for the Gubernator CLI tool (`gbnt`). All commands listed here are fully implemented and functional.

Gubernator's CLI is heavily inspired by Docker Swarm and Nomad, providing an intuitive interface for managing clusters, nodes, stacks, and individual services.

---

## 🔐 Security Bootstrap (First Steps)

Commands to retrieve credentials and configure remote access. These should be your **first commands** after starting `gbnt serve`.

- **`gbnt legion info`** *(Localhost only)*
  Shows both the **Join Token** and the **API Token**, plus ready-to-use CLI commands to add workers and configure remote clients. Only accessible from the Manager host for security.

- **`gbnt config add-context [name] --server [url] --token [token]`**
  Adds a named remote Manager to `~/.gbntctl/config`. After this, all `gbnt` commands target that remote manager.
  ```bash
  gbnt config add-context production \
      --server http://192.168.1.10:4000 \
      --token <API_TOKEN>
  ```

- **`gbnt config current-context`**
  Displays the name of the currently active context.

- **`gbnt config get-contexts`**
  Lists all configured contexts with their server URLs.

- **`gbnt config use-context [name]`**
  Switches the active context to manage a different Manager.

---

## 🏛 The Legion (Cluster Management)

Commands for managing the cluster lifecycle and joining nodes.

- **`gbnt legion init`**
  Initializes a new Gubernator cluster on the local node. Retrieves the join token from the local API.

- **`gbnt legion join --token [join-token] --api-token [api-token] --manager [ip:4000]`**
  Joins the current machine to an existing Gubernator cluster as a Worker node.
  - `--token`: The Join Token from `gbnt legion info` or `gbnt legion join-token`
  - `--api-token`: The Bearer API Token required for all API communication
  - `--manager`: The Manager's address (e.g., `192.168.1.10:4000`)

- **`gbnt legion join-token`**
  Prints the worker join command with the current token (also shows the `--api-token` hint).

- **`gbnt legion leave`**
  Gracefully leaves the cluster, marking the current node as `left` in the Manager's database.

---

## 🛡 The Centurions (Node Management)

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

## 📦 The Command (Stack Management)

Commands for deploying and managing complex multi-container applications via Docker Compose syntax.

- **`gbnt stack deploy -c [docker-compose.yml] [stack_name]`**
  Deploys or updates an entire stack of services based on a Compose file. Supports parsing `deploy.placement.constraints` for targeted scheduling.

- **`gbnt stack ls`**
  Lists all currently deployed stacks across the cluster.

- **`gbnt stack services [stack_id]`**
  Lists all the individual services that belong to a specific deployed stack.

- **`gbnt stack rm [stack_id]`**
  Removes a stack completely, cascading the deletion to stop and remove all associated services and tasks.

---

## ⚔️ The Cohorts (Service Management)

Commands for managing individual services (which are usually created via Stacks).

- **`gbnt service ls`**
  Lists all active services running across the cluster, along with their desired replica counts and image names.

- **`gbnt service ps [service_id]`**
  Lists the actual physical containers (Tasks) running for a specific service. It displays exactly which Node is running each task and its internal Container IP.

- **`gbnt service scale [service_id]=[replicas]`**
  Updates the desired replica count for a specific service.

- **`gbnt service rm [service_id]`**
  Deletes a specific service and forces the worker nodes to stop its associated containers.
