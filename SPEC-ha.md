# Gubernator High Availability (HA) Specification (`SPEC-ha.md`)

## 🏛️ "The Senate" — Multi-Manager High Availability Architecture

Gubernator features a native **High Availability (HA)** architecture named **"The Senate"** (El Senado). It transforms Gubernator from a single-manager deployment into a resilient, fault-tolerant cluster capable of surviving manager hardware failures, network partitions, and host reboots with **zero downtime for running containers** and **automatic failover in under 3 seconds**.

---

## 📐 1. Architecture Overview & Principles

```
                              ┌───────────────────────────────────────────────────────────┐
                              │     Virtual IP (VIP Keepalived) o Balanceador Externo     │
                              │           192.168.1.9 : 4000 (API) / 4001 (Web)           │
                              └─────────────────────────────┬─────────────────────────────┘
                                                            │
                     ┌──────────────────────────────────────┼──────────────────────────────────────┐
                     │                                      │                                      │
                     ▼                                      ▼                                      ▼
     ┌───────────────────────────────┐      ┌───────────────────────────────┐      ┌───────────────────────────────┐
     │      MANAGER 1 (LÍDER)        │      │     MANAGER 2 (SEGUIDOR)      │      │     MANAGER 3 (SEGUIDOR)      │
     │        192.168.1.10           │      │        192.168.1.11           │      │        192.168.1.12           │
     ├───────────────────────────────┤      ├───────────────────────────────┤      ├───────────────────────────────┤
     │ • API REST (:4000) [RW]       │      │ • API REST (:4000) [RO/Proxy] │      │ • API REST (:4000) [RO/Proxy] │
     │ • Web UI Dashboard (:4001)    │      │ • Web UI Dashboard (:4001)    │      │ • Web UI Dashboard (:4001)    │
     │ • Telemetría (:4002)          │      │ • Telemetría (:4002)          │      │ • Telemetría (:4002)          │
     │ • CoreDNS + Caddy Ingress     │      │ • CoreDNS + Caddy Ingress     │      │ • CoreDNS + Caddy Ingress     │
     │ • Reconciliador Watchdogs     │      │   (Watchdogs en Espera)       │      │   (Watchdogs en Espera)       │
     │ • Executor & Autoscaler       │      │   (Executor en Espera)        │      │   (Executor en Espera)        │
     │ • Base de Datos SQLite Local  │      │ • Base de Datos SQLite Local  │      │ • Base de Datos SQLite Local  │
     │   ▲                           │      │   ▲                           │      │   ▲                           │
     │   │ FSM Apply                 │      │   │ FSM Apply                 │      │   │ FSM Apply                 │
     │ ┌─┴─────────────────────────┐ │      │ ┌─┴─────────────────────────┐ │      │ ┌─┴─────────────────────────┐ │
     │ │   HashiCorp Raft Node 1   │ │◄────►│ │   HashiCorp Raft Node 2   │ │◄────►│ │   HashiCorp Raft Node 3   │ │
     │ │       (Líder Raft)        │ │      │ │      (Seguidor Raft)      │ │      │ │      (Seguidor Raft)      │ │
     │ └───────────────────────────┘ │      │ └───────────────────────────┘ │      │ └───────────────────────────┘ │
     │      Puerto Raft :4003        │      │      Puerto Raft :4003        │      │      Puerto Raft :4003        │
     └───────────────▲───────────────┘      └───────────────▲───────────────┘      └───────────────▲───────────────┘
                     │                                      │                                      │
                     └──────────────────────────────────────┴──────────────────────────────────────┘
                                          ▲  Heartbeats & Task Fetch (Failover Automático)
                                          │
                     ┌────────────────────┴────────────────────┐
                     │                                         │
     ┌───────────────┴───────────────┐         ┌───────────────┴───────────────┐
     │      CENTURIÓN WORKER 1       │         │      CENTURIÓN WORKER 2       │
     │         192.168.1.20          │         │         192.168.1.21          │
     ├───────────────────────────────┤         ├───────────────────────────────┤
     │ • Agent Daemon                │         │ • Agent Daemon                │
     │ • Conoce lista de 3 Managers  │         │ • Conoce lista de 3 Managers  │
     │ • Caddy Ingress Local         │         │ • Caddy Ingress Local         │
     │ • Docker Contenedores         │         │ • Docker Contenedores         │
     └───────────────────────────────┘         └───────────────────────────────┘
```

### Principios Fundamentales
1. **Zero External Daemons (Pure Go)**: Consenso distribuido embebido mediante **HashiCorp Raft** (`github.com/hashicorp/raft`), preservando la compilación estática `CGO_ENABLED=0` y la independencia de bases de datos externas pesadas.
2. **Replicación Transaccional SQLite (FSM)**: Cada Manager mantiene una réplica local completa en SQLite. Las operaciones de lectura se ejecutan a velocidad de memoria/NVMe local sin latencia de red. Las mutaciones de escritura pasan por el quórum de Raft antes de ser aplicadas en la base de datos de cada nodo.
3. **Desacoplamiento Plano de Control / Plano de Datos**: Si todos los Managers se detienen simultáneamente, los contenedores Docker en ejecución en los Workers continúan funcionando sin interrupción.
4. **Separación de Responsabilidades (Líder vs Seguidores)**: Solo el Líder ejecuta reconciliaciones activas (Watchdog, Executor, Autoscaler). Los seguidores mantienen el estado sincronizado y atienden lecturas de la API o redirigen escrituras al Líder.

---

## ⚙️ 2. Componentes Técnicos y Puertos

| Componente | Puerto | Protocolo | Descripción |
| :--- | :--- | :--- | :--- |
| **REST API Server** | `4000` | HTTP / JSON | API de orquestación y control (autenticada vía Bearer token). |
| **Web UI Dashboard** | `4001` | HTTP / WS | Dashboard Flutter Web, Terminal SSH y WebSocket de telemetría. |
| **Observabilidad & Health** | `4002` | HTTP | Métricas Prometheus (`/metrics`), Swagger UI y Healthcheck (`/health`). |
| **Consenso Raft (The Senate)** | `4003` | TCP / Raft RPC | Tráfico interno de quórum, latidos de elección y replicación de log. |
| **CoreDNS Ingress** | `53` | UDP / TCP | Resolución de nombres de servicio internos (`*.gbnt.local`). |
| **Caddy Ingress Suite** | `80`, `443` | HTTP / HTTPS | Reverse proxy inverso con certificados automáticos y balanceo. |

---

## 👑 3. Ciclo de Vida y Elección de Liderazgo

### 3.1. Quórum y Tolerancia a Fallos
El Senado requiere un número impar de Managers para garantizar mayoría estricta y evitar particiones de red (*split-brain*):
* **3 Managers**: Quórum de 2. Tolera **1 caída** simultánea.
* **5 Managers**: Quórum de 3. Tolera **2 caídas** simultáneas.

### 3.2. Transición y Reconciliación
* **Heartbeat Timeout**: 1000 ms.
* **Election Timeout**: 1500 – 3000 ms (aleatorizado para evitar empates).
* Cuando un nuevo Líder es elegido:
  1. Adquiere el candado de liderazgo de la FSM.
  2. Arranca de forma no bloqueante los bucles de orquestación:
     - `startWatchtowers`: Detección de Workers inactivos (> 45s).
     - `startLocalExecutor`: Despacho de tareas pendientes.
     - `StartSelfHealingWatchdog`: Reconciliación de réplicas cada 15s.
     - `autoscaler.EvaluateAndAutoscale`: Evaluación de métricas y escalado.
     - `slo.SyncSLORulesToPrometheus`: Sincronización de alertas Google SRE.
  3. El líder saliente (si se recupera) transiciona a rol de Seguidor, apaga sus bucles de reconciliación y continúa sirviendo lecturas.

---

## 🔄 4. Máquina de Estados Finita (Raft FSM) & Persistencia

La replicación de datos se gestiona mediante una FSM personalizada que interactúa con SQLite:

```go
type RaftFSM struct {
    db *gorm.DB
    mu sync.RWMutex
}

// Apply ejecuta las transacciones confirmadas por el quórum en la base de datos local
func (f *RaftFSM) Apply(l *raft.Log) interface{} { ... }

// Snapshot genera un volcado consistente de SQLite (VACUUM INTO)
func (f *RaftFSM) Snapshot() (raft.FSMSnapshot, error) { ... }

// Restore restaura la base de datos completa cuando un nodo se une o sincroniza
func (f *RaftFSM) Restore(rc io.ReadCloser) error { ... }
```

### Snapshots y Truncado de Logs
* Se genera un snapshot cada **10,000 transacciones** o cada **24 horas**.
* El snapshot utiliza la primitiva nativa `VACUUM INTO '/data/gubernator_snapshot.db'` sin bloquear lecturas concurrentes.
* Nuevos nodos que se unen reciben el snapshot en streaming mediante HTTP/gRPC de Raft y se sincronizan en segundos.

---

## 📡 5. Resiliencia de Agentes Centurión (Workers)

### 5.1. Descubrimiento Dinámico de Managers
En cada respuesta de `/v1/node/heartbeat`, el Manager incluye el estado del Senado:
```json
{
  "status": "ok",
  "server_timestamp": 1757934000,
  "cluster_ha": {
    "enabled": true,
    "leader": "node-manager-1",
    "leader_addr": "http://192.168.1.10:4000",
    "peers": [
      "http://192.168.1.10:4000",
      "http://192.168.1.11:4000",
      "http://192.168.1.12:4000"
    ]
  }
}
```

### 5.2. Failover sin Desconexión
* El worker mantiene en memoria el pool de endpoints de Managers ordenados por prioridad (Líder primero).
* Si una petición de heartbeat o consulta de tareas falla (timeout de 2 segundos), el worker intenta inmediatamente con el siguiente Manager de la lista.
* Las cargas de trabajo en Docker continúan operando con normalidad.

---

## 💻 6. Comandos CLI (`gbnt ha`)

```bash
# Inicializar cluster en modo HA (Bootstrap Leader)
gbnt legion init --ha --raft-bind 0.0.0.0:4003 --raft-advertise 192.168.1.10:4003

# Unir un nuevo Manager al Senado
gbnt legion join --role manager \
                 --manager http://192.168.1.10:4000 \
                 --token <JOIN_TOKEN> \
                 --raft-bind 0.0.0.0:4003 \
                 --raft-advertise 192.168.1.11:4003

# Inspeccionar estado del quórum y réplicas
gbnt ha status

# Forzar una conmutación controlada de liderazgo
gbnt ha failover

# Recuperación de desastres de emergencia (quórum perdido)
gbnt ha recover-single
```

---

## 🌐 7. Ingress y Balanceo de Carga

Para unificar el acceso al cluster, se admiten dos patrones:
1. **Virtual IP (VIP Keepalived / VRRP)**: Una IP flotante (`192.168.1.9`) asignada al nodo que ostente el liderazgo, con failover por ARP en < 1 segundo.
2. **Reverse Proxy / Balanceador L4 (HAProxy / Cloud LB)**: Balanceo activo hacia los puertos 4000 y 4001 con health checks HTTP en `/health` (puerto 4002).
