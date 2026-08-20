# SPEC-edit-compose.md — Gubernator Advanced Compose Editor Subsystem

## 1. Overview & Vision

The **Advanced Compose Editor** provides a rich, intelligent `docker-compose.yml` authoring experience directly within the Gubernator Flutter Web UI. Instead of relying on a plain text area, the editor acts as a "Compose IDE" tailored for Gubernator. It understands the orchestrator's unique ecosystem (Caddy Ingress, SLO tracking, Security Gatekeeper, Node Placement, and Storage Pools) and actively assists the user in configuring them.

> [!TIP]
> **Goal:** Eliminate configuration syntax errors and ensure users discover and correctly implement all of Gubernator's powerful enterprise features (e.g. Sloth SLOs, Cosign Security, Shared Volumes) via smart autocompletion and GUI wizards.

---

## 2. Editor UI/UX Architecture

The Editor will replace the standard text field in the "Deploy Stack" and "Edit Stack" views with a highly interactive component:

### 2.1 Core Editor Component
*   **Syntax Highlighting:** Full YAML syntax highlighting.
*   **Line Numbers & Error Linting:** Instant visual feedback for invalid YAML.
*   **IntelliSense / Autocomplete (Ctrl+Space):** Context-aware suggestions depending on the cursor's position within the `docker-compose.yml` structure.

### 2.2 The "Gubernator Copilot" Side Panel (Wizard)
Next to the code editor, a dynamic side panel will offer GUI-based configuration for the currently selected service in the YAML. This is crucial for users who don't want to memorize labels. The wizard injects the correct YAML labels into the editor automatically.

---

## 3. Supported Gubernator Autocompletions & Wizards

The editor MUST explicitly support, suggest, and validate the following Gubernator ecosystems:

### 3.1 🌐 Caddy Ingress Suite (`ingress` / `gbnt.caddy.*`)
*When inside a service's `deploy.labels` or through the Wizard:*
*   **Suggests:** `ingress.host`, `gbnt.caddy.port`, `gbnt.caddy.tls`
*   **Wizard Action:** "Expose to Web". Asks for domain name and target port, automatically injecting the routing labels.
*   **Validation:** Warns if `ingress.host` is defined but the service has no internal port exposed.

### 3.2 📈 SLO Engine (Sloth) (`gbnt.slo.*`)
*When configuring SRE metrics:*
*   **Suggests:**
    *   `gbnt.slo.enable=true`
    *   `gbnt.slo.target=99.9` (Offers 99.0, 99.9, 99.99 dropdowns)
    *   `gbnt.slo.window=30d`
    *   `gbnt.slo.indicator` (Offers `latency`, `error-rate`)
    *   `gbnt.slo.latency.threshold` (e.g., `200ms`, `500ms`)
    *   `gbnt.slo.template` (Offers `caddy-http`, `grpc`, `custom`)
    *   `gbnt.slo.journey` (e.g., `UserCheckout`)
*   **Wizard Action:** "Add Service Level Objective". A form that builds the complex multi-burn-rate alerting rules without writing YAML.

### 3.3 🛡️ Security & Gatekeeper (`gbnt.security.*`)
*To enforce image signing and CVE thresholds:*
*   **Suggests:**
    *   `gbnt.security.require-signature=true|false`
    *   `gbnt.security.max-cve-severity` (Offers `critical`, `high`, `medium`, `none`)
    *   `gbnt.security.allow-unfixed=true|false`
*   **Wizard Action:** "Set Security Policy". Checkboxes to lock down the specific service against unverified or vulnerable images.

### 3.4 🏛️ Node Placement Constraints & Hardware affinity
*When configuring `deploy.placement.constraints`:*
*   **Suggests Built-ins:** `node.role == manager`, `node.role == worker`
*   **Suggests Custom Labels (from DB):** Fetches actual labels from the Nodes database (e.g., `node.labels.gpu == nvidia`, `node.labels.zone == europe-1`).
*   **Wizard Action:** "Pin to Node/Hardware". A visual dropdown showing all active cluster nodes and available hardware tags to generate the exact constraint syntax.

### 3.5 💾 Storage Granaries & Mobility (`/var/contenedores`)
*When defining `volumes`:*
*   **Suggests:** Auto-prepends `/var/contenedores/` for host bind mounts to ensure volume mobility across Centurions.
*   **Validation:** Warns if a host path outside of `/var/contenedores/` is used, reminding the user that backups and mobility might not work properly.
*   **Wizard Action:** "Attach Persistent Storage". Dropdown to select existing shared pools or create a new named volume.

---

## 4. Technical Implementation Steps (Flutter Web)

1.  **Code Editor Widget:** Replace standard `TextField` with `flutter_code_editor` or `code_text_field` (or a web-native JS interop like Monaco Editor for full IntelliSense).
2.  **YAML Parser & AST:** Implement a lightweight YAML parser to understand the cursor context (e.g., "Is the user currently typing inside `services.api.deploy.labels`?").
3.  **API Integration:** The editor must fetch live data from the backend while typing:
    *   Fetch active nodes & labels for placement suggestions.
    *   Fetch active Caddy domains for ingress routing.
    *   Fetch storage pools for volume suggestions.
4.  **UI Layout Layout:** Split screen. Left side: 60% YAML Editor. Right side: 40% "Gubernator Assistant" providing GUI toggles that mutate the YAML on the left.
