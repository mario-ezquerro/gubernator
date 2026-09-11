# Industrial SCADA & DNP3 Simulation Subsystem (IEEE 1815-2012 + FUXA Web HMI)

Gubernator includes a production-grade **IoT & Industrial SCADA simulation environment** featuring the standard electric grid protocol **DNP3 (IEEE 1815-2012)**, dual industrial outstation devices (Substation Alpha RTU and Solar PV Farm Beta RTU), a DNP3 Master Station Bridge, an MQTT broker, and the modern web-based SCADA/HMI system **[FUXA](https://github.com/frangoteam/FUXA)**.

---

## 🏗️ Architecture Overview

The blueprint simulates a modern smart electric grid where field Remote Terminal Units (RTUs) and intelligent electronic devices (IEDs) communicate over native DNP3 TCP/IP with an automated Master Station, which ingests telemetry and bridges control to an intuitive HMI.

```
                    ┌────────────────────────────────────────────────────────┐
                    │                   GUBERNATOR CLUSTER                   │
                    │                                                        │
                    │   ┌────────────────────────────────────────────────┐   │
                    │   │               FUXA Web SCADA / HMI             │   │
                    │   │          http://fuxa.gbnt.local:1881           │   │
                    │   │      (Interactive Single-Line Diagram & UI)     │   │
                    │   └───────────────────────▲────────────────────────┘   │
                    │                           │ WebSockets                 │
                    │                           ▼                            │
                    │   ┌────────────────────────────────────────────────┐   │
                    │   │           Eclipse Mosquitto MQTT Broker        │   │
                    │   │                  (Port 1883)                   │   │
                    │   └───────────────▲─────────────────┬──────────────┘   │
                    │                   │ Telemetry       │ CROB Commands    │
                    │                   │ (JSON)          │ (Trip / Close)   │
                    │   ┌───────────────┴─────────────────▼──────────────┐   │
                    │   │           DNP3 Master Station Bridge           │   │
                    │   │     - Cyclic Class 0/1/2/3 Integrity Polls     │   │
                    │   │     - Direct Operate CROB Translator           │   │
                    │   └───────────────▲─────────────────▲──────────────┘   │
                    │                   │ DNP3 TCP:20000  │ DNP3 TCP:20000   │
                    │                   │ (IEEE 1815)     │ (IEEE 1815)      │
                    │         ┌─────────┴──────┐   ┌──────┴─────────┐        │
                    │         │ Substation     │   │ Solar PV Farm  │        │
                    │         │ Alpha RTU      │   │ Beta RTU       │        │
                    │         │ (DNP3 Addr 10) │   │ (DNP3 Addr 20) │        │
                    │         └────────────────┘   └────────────────┘        │
                    └────────────────────────────────────────────────────────┘
```

---

## ⚡ DNP3 Protocol Implementation (IEEE 1815-2012)

The simulation features a pure Python IEEE 1815-2012 engine (`dnp3_frame.py`) implementing:

1. **Data Link Layer (DLL):**
   - 10-octet Link Header: Sync `0x05 0x64`, Length, Link Control byte (`DIR`, `PRM`, `FCB`, `FCV`, `DFC`), 16-bit Destination Address, and 16-bit Source Address.
   - **CRC-16 Error Checking:** Polynomial `0xA653` (inverted output), recalculated every 16 octets of payload for frame integrity.
2. **Transport Layer (TL):**
   - 1-octet Transport Header with `FIN`, `FIR`, and 6-bit sequence numbering.
3. **Application Layer (AL):**
   - Application Control (`FIR`, `FIN`, `CON`, `UNS`, sequence number).
   - Function Codes:
     - `0x01` (READ): Class 0/1/2/3 Integrity Polls and specific object reads.
     - `0x81` (RESPONSE): Outstation internal indications (IIN) and typed object data.
     - `0x05` (DIRECT OPERATE): Control Relay Output Block (CROB) execution.
4. **DNP3 Object Groups:**
   - **Group 1 Variation 2:** Binary Input with status flags (`ONLINE`, `STATE`).
   - **Group 12 Variation 1:** Control Relay Output Block (CROB) with Code, Count, On-Time, Off-Time, and Status.
   - **Group 30 Variation 1 & 2:** 32-bit and 16-bit Analog Inputs with engineering unit scaling.

---

## 📊 Industrial Points Mapping

### 1. Substation Alpha RTU (25 kV Distribution Substation)
* **DNP3 Address:** `10`
* **Transport:** TCP Port `20000`

| Point Index | DNP3 Type | Description | Engineering Units / States |
|---|---|---|---|
| **BI 0** | Binary Input | Feeder Breaker 52-1 State | `0` = Open (Trip), `1` = Closed |
| **BI 1** | Binary Input | Disconnector Switch 89-1 | `0` = Open, `1` = Closed |
| **BI 2** | Binary Input | Overcurrent Relay 50/51 | `0` = Normal, `1` = TRIP Alarm |
| **BI 3** | Binary Input | SF6 Gas Pressure Gauge | `0` = Normal, `1` = Low Pressure |
| **AI 0** | Analog Input | Busbar Line Voltage | `24.8 – 25.2` kV (0 kV if tripped) |
| **AI 1** | Analog Input | Feeder Phase Current | `115.0 – 125.0` A |
| **AI 2** | Analog Input | Active Three-Phase Power | `4.8 – 5.4` MW |
| **AI 3** | Analog Input | Reactive Power | `0.7 – 0.9` MVAr |
| **AI 4** | Analog Input | Main Transformer Temperature | `55.0 – 62.0` °C |
| **CROB 0** | Binary Output | Direct Operate Breaker 52-1 | Code `0x41` (Trip) / Code `0x81` (Close) |

### 2. Solar PV Farm Beta RTU (3 MW Grid-Tied Inverter)
* **DNP3 Address:** `20`
* **Transport:** TCP Port `20000`

| Point Index | DNP3 Type | Description | Engineering Units / States |
|---|---|---|---|
| **BI 0** | Binary Input | 3 MW Central Inverter State | `0` = Stopped, `1` = Generating |
| **BI 1** | Binary Input | Grid Synchronism Relay | `0` = Out of sync, `1` = Synced |
| **BI 2** | Binary Input | Anti-Islanding Protection | `0` = Normal, `1` = Islanding Trip |
| **AI 0** | Analog Input | Active Solar Power Output | `0.0 – 3000.0` kW (solar curve) |
| **AI 1** | Analog Input | Solar Irradiance | `100.0 – 980.0` W/m² |
| **AI 2** | Analog Input | DC Array Voltage | `740.0 – 820.0` V |
| **AI 3** | Analog Input | DC Array Current | `2200.0 – 2600.0` A |
| **AI 4** | Analog Input | Daily Energy Yield | Accumulator in kWh |
| **CROB 0** | Binary Output | Direct Operate Inverter Run | Code `0x41` (Curtail) / Code `0x81` (Run) |

---

## 🖥️ FUXA SCADA / HMI Visual Workspace

The pre-configured FUXA project (`project.fuxap` / `project.fuxap.db`) provides an instant industrial control room:

1. **Substation Single-Line Diagram (SLD):**
   - Dynamic busbar indicators (Green when energized at 25 kV, Grey when de-energized).
   - Feeder Breaker 52-1 SVG symbol with live color state transitions (Red = Closed/Energized, Green = Open/Safe).
   - Interactive control buttons: **[TRIP 52-1]** and **[CLOSE 52-1]** with confirmation modal.
   - Analog gauge meters for Busbar Voltage (kV) and Power (MW).
2. **Solar PV Generation Center:**
   - Solar irradiance sensor widget (W/m²).
   - Central Inverter state indicator with DC voltage and active generation (kW).
   - Interactive control buttons: **[CURTAIL PV]** and **[ENABLE PV]**.
3. **Alarm & Event Banner:**
   - High-contrast visual banners tracking Overcurrent 50/51 trips and Low SF6 Gas Pressure.

---

## 🚀 How to Deploy in Gubernator

### Option A: 1-Click POC Catalog (Web Dashboard)
1. Open the Gubernator Web UI at `http://localhost:4001`.
2. Navigate to **Legions (Stacks)** and click **"Deploy POC"** (or open the POC Catalog).
3. Select the **"IoT & Industrial SCADA"** category.
4. Click on **"Industrial SCADA: DNP3 Grid & FUXA HMI"**.
5. Click **"Deploy Stack"**.
6. Access FUXA at **`http://fuxa.gbnt.local:1881`** or via Caddy Ingress.

### Option B: CLI Deployment
```bash
# Deploy the SCADA stack directly with the gbnt CLI
gbnt stack deploy -c examples/example-scada-dnp3-fuxa/docker-compose.yml

# Check container status
gbnt container ls
```

### Option C: Standalone Docker Compose
```bash
cd examples/example-scada-dnp3-fuxa
docker compose up -d
```

---

## 🧪 Verification & Wireshark Traffic Inspection

You can inspect the raw DNP3 protocol packets and verify bidirectional control from the terminal:

```bash
# Subscribe to MQTT telemetry stream
docker exec -it scada-mqtt mosquitto_sub -t "scada/dnp3/#" -v

# Issue a DNP3 Breaker TRIP command via MQTT
docker exec -it scada-mqtt mosquitto_pub -t "scada/dnp3/control/substation/breaker" -m "TRIP"

# Issue a DNP3 Breaker CLOSE command via MQTT
docker exec -it scada-mqtt mosquitto_pub -t "scada/dnp3/control/substation/breaker" -m "CLOSE"
```

To capture and inspect DNP3 packets in Wireshark:
```bash
# Filter by DNP3 TCP port
tcp.port == 20000 and dnp3
```
You will observe IEEE 1815 frames containing:
- `Function Code: Response (0x81)` with `Group 1 Var 2` and `Group 30 Var 1`.
- `Function Code: Direct Operate (0x05)` with `Group 12 Var 1` (CROB Trip/Close).
