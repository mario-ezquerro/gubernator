# Gubernator SCADA: Entorno IoT Industrial con Protocolo DNP3 (IEEE 1815) y FUXA Web HMI

Blueprint de simulación y supervisión para infraestructuras críticas (subestaciones eléctricas y generación renovable) integrando **DNP3 (Distributed Network Protocol / IEEE 1815-2012)**, múltiples dispositivos RTU/IED de campo, estación maestra DNP3, broker MQTT y la plataforma de visualización web **[FUXA](https://github.com/frangoteam/FUXA)** en Gubernator.

---

## 🏛️ Arquitectura del Sistema

```
                  ┌────────────────────────────────────────────────────────┐
                  │                    GUBERNATOR CLUSTER                  │
                  │                                                        │
                  │   ┌────────────────────────────────────────────────┐   │
                  │   │        FUXA Web SCADA / HMI (Port 1881)        │   │
                  │   │   Ingress: fuxa.gbnt.local (Caddy Proxy)       │   │
                  │   │   - Unifilar Subestación 25 kV con Breakers    │   │
                  │   │   - Telemetría Fotovoltaica en Tiempo Real     │   │
                  │   │   - Mandos CROB Trip/Close desde el Navegador  │   │
                  │   └───────────────────────▲────────────────────────┘   │
                  │                           │ MQTT / WebSocket           │
                  │                           ▼                            │
                  │   ┌────────────────────────────────────────────────┐   │
                  │   │     Eclipse Mosquitto Broker (Port 1883)       │   │
                  │   └───────────────────────▲────────────────────────┘   │
                  │                           │ Pub/Sub Telemetría & CROB  │
                  │                           ▼                            │
                  │   ┌────────────────────────────────────────────────┐   │
                  │   │         DNP3 Master Station Bridge             │   │
                  │   │   - Polling cíclico integridad Class 0/1/2/3   │   │
                  │   │   - Decodificación frames IEEE 1815            │   │
                  │   │   - Inyección CROB Direct Operate (Breakers)   │   │
                  │   └───────────────▲────────────────▲───────────────┘   │
                  │                   │                │                   │
                  │      IEEE 1815    │ TCP            │ IEEE 1815         │
                  │      DNP3 TCP     │ Port 20000     │ DNP3 TCP          │
                  │                   ▼                ▼                   │
                  │   ┌───────────────────┐  ┌─────────────────────────┐   │
                  │   │  Outstation RTU 1 │  │    Outstation RTU 2     │   │
                  │   │ Subestación 25 kV │  │ Planta Solar PV 3 MW    │   │
                  │   │  (DNP3 Addr: 10)  │  │    (DNP3 Addr: 20)      │   │
                  │   └───────────────────┘  └─────────────────────────┘   │
                  └────────────────────────────────────────────────────────┘
```

---

## ⚡ Estándar DNP3 (IEEE 1815-2012) Implementado

El protocolo **DNP3** es el estándar de facto en Norteamérica y utilities globales para telecontrol de redes de energía eléctrica, subestaciones, plantas de generación y redes de distribución de fluidos.

En este ejemplo se implementa una pila de comunicación DNP3 pura y rigurosa en Python:

1. **Capa de Enlace de Datos (Data Link Layer):**
   - Sincronismo estándar `0x05 0x64`.
   - Longitud de trama y campo de control con bits DIR, PRM, FCB, FCV.
   - Direccionamiento de 16 bits (Little Endian).
   - Cálculo de integridad **CRC-16 DNP3** según especificación IEEE 1815 Anexo F (Polinomio invertido `0xA653`, valor inicial `0x0000`, resultado invertido `~crc`).
   - Fragmentación en bloques de hasta 16 octetos, cada uno protegido por su propio CRC-16 de 2 octetos.
2. **Capa de Transporte:** Octeto individual con bits FIN (7), FIR (6) y número de secuencia (5-0).
3. **Capa de Aplicación:**
   - Cabecera de control con FIR, FIN, CON, UNS y secuencia de aplicación.
   - Códigos de función:
     - `0x01` (READ): Peticiones cíclicas de integridad (Clases 0, 1, 2 y 3).
     - `0x05` (DIRECT_OPERATE): Mandos de accionamiento sin selección previa.
     - `0x81` (RESPONSE): Tramas de respuesta con indicaciones internas IIN1 e IIN2.
   - Grupos y variaciones de objetos:
     - **Grupo 1 Variación 2:** Entradas Digitales (Binary Inputs) con octeto de flags (Online, Estado).
     - **Grupo 30 Variación 5:** Entradas Analógicas (Analog Inputs) en coma flotante IEEE 754 float32.
     - **Grupo 12 Variación 1:** Control Relay Output Block (CROB) con códigos `LATCH_ON` (cierre), `LATCH_OFF` (apertura/disparo), tiempos de pulso y estado de ejecución.

---

## 📋 Mapa de Puntos DNP3

### 1. Subestación Eléctrica Alpha 25 kV (DNP3 Address: 10)
| Punto | Tipo | Nombre | Unidad / Rango | Descripción |
| :--- | :--- | :--- | :--- | :--- |
| **AI 0** | Analog Input | Tensión de Barra A | `kV` (24.8 - 25.2 kV) | Tensión fase-fase de media tensión |
| **AI 1** | Analog Input | Corriente de Línea | `A` (120 - 180 A) | Corriente de carga en el alimentador 1 |
| **AI 2** | Analog Input | Potencia Activa | `MW` (~5.2 MW) | Potencia activa entregada a la red |
| **AI 3** | Analog Input | Potencia Reactiva | `MVAr` (~0.8 MVAr) | Potencia reactiva de la red |
| **AI 4** | Analog Input | Frecuencia de Red | `Hz` (49.97 - 50.03 Hz)| Frecuencia sincrónica de 50 Hz |
| **AI 5** | Analog Input | Temp. Transformador | `°C` (55 - 72 °C) | Temperatura en devanado de potencia |
| **BI 0** | Binary Input | Interruptor 52-1 | `1`=Cerrado, `0`=Abierto | Estado del interruptor general de cabecera |
| **BI 1** | Binary Input | Seccionador 89-1 | `1`=Cerrado, `0`=Abierto | Posición del seccionador de barra A |
| **BI 2** | Binary Input | Relé Sobrecorriente | `0`=Normal, `1`=Disparo | Relé de protección ANSI 50/51 |
| **BI 3** | Binary Input | Presión Gas SF6 | `1`=Normal, `0`=Baja | Presión del gas dieléctrico del interruptor |
| **BO 0** | CROB | Mando Interruptor 52-1 | `LATCH_ON` / `LATCH_OFF` | Disparo / Cierre telecontrolado del breaker |

### 2. Planta Solar Fotovoltaica Beta 3 MW (DNP3 Address: 20)
| Punto | Tipo | Nombre | Unidad / Rango | Descripción |
| :--- | :--- | :--- | :--- | :--- |
| **AI 0** | Analog Input | Potencia Solar Activa | `kW` (0 - 3000 kW) | Generación AC vertida a la red |
| **AI 1** | Analog Input | Irradiancia Solar | `W/m²` (0 - 1000 W/m²) | Piranómetro de campo (campana solar diurna) |
| **AI 2** | Analog Input | Tensión String DC | `V` (~750 V) | Tensión de seguimiento MPP en corriente continua |
| **AI 3** | Analog Input | Corriente DC Array | `A` (0 - 4000 A) | Corriente total de los campos fotovoltaicos |
| **AI 4** | Analog Input | Temp. Inversor IGBT | `°C` (40 - 58 °C) | Temperatura de los semiconductores de potencia |
| **AI 5** | Analog Input | Temp. Ambiente | `°C` (20 - 35 °C) | Estación meteorológica de planta |
| **BI 0** | Binary Input | Inversor Exportando | `1`=Generando, `0`=Parado | Estado de operación del inversor central |
| **BI 1** | Binary Input | Sincronismo de Red | `1`=Sincronizado, `0`=Fallo | Protección anti-isla (Loss of Mains) |
| **BI 2** | Binary Input | Fuga a Tierra DC | `0`=OK, `1`=Fuga | Vigilante de aislamiento de strings |
| **BO 0** | CROB | Mando Curtailment | `LATCH_ON` / `LATCH_OFF` | Limitación / Habilitación de vertido solar |

---

## 🚀 Despliegue Rápido en Gubernator

### Opción A: Despliegue en 1-Click desde la Web UI
1. Abre el panel de Gubernator en `http://localhost:4001`.
2. Dirígete a **Legions (Stacks)** o pulsa **New Stack**.
3. Haz clic en **POC Catalog** o **Load from Catalog**.
4. Selecciona la categoría **"IoT & Industrial SCADA"** y elige **"SCADA IoT Substation & Solar PV Grid (DNP3 IEEE 1815 + FUXA HMI)"**.
5. Pulsa **Deploy Stack**. ¡Listo!

### Opción B: Despliegue mediante CLI `gbnt`
```bash
# Desplegar el stack en el cluster
gbnt stack deploy scada-dnp3 examples/example-scada-dnp3-fuxa/docker-compose.yml

# Verificar estado de los contenedores
gbnt task ls
```

### Opción C: Despliegue independiente con Docker Compose
```bash
cd examples/example-scada-dnp3-fuxa
docker compose up -d --build
```

---

## 🖥️ Acceso a la Interfaz Web SCADA (FUXA)

Una vez desplegado el stack:
- **URL Directa:** [http://localhost:1881](http://localhost:1881)
- **Caddy Ingress:** [http://fuxa.gbnt.local](http://fuxa.gbnt.local) (o mediante CoreDNS interno)

El entorno incluye el proyecto **`project.fuxap`** cargado automáticamente:
1. **Diagrama Unifilar:** Observa la barra de 25 kV, el transformador y el interruptor 52-1 con semáforo dinámico en tiempo real.
2. **Acción de Apertura (TRIP):** Haz clic sobre el botón rojo **`🛑 TRIP 52-1 (DISPARAR)`**.
   - FUXA publicará un evento MQTT.
   - La estación maestra DNP3 codificará un frame `Group 12 Var 1` (CROB `LATCH_OFF`) y lo enviará por TCP a la Outstation.
   - El interruptor se abrirá inmediatamente, la corriente y potencia caerán a 0.0, y el semáforo cambiará a verde (abierto/seguro).
3. **Acción de Cierre (CLOSE):** Haz clic sobre el botón verde **`⚡ CLOSE 52-1 (ENERGIZAR)`** para restablecer el servicio eléctrico.
4. **Curtailment Solar:** Pulsa **`⚠️ CURTAIL / STOP`** en el panel solar para limitar la exportación fotovoltaica y **`☀️ ENABLE INVERTER`** para reanudar la inyección a red.

---

## 🔬 Verificación con Wireshark y Diagnóstico DNP3

Las Outstations exponen sus puertos directamente en el host (`20000` para Subestación y `20001` para Planta Solar). Puedes capturar el tráfico con Wireshark para analizar los frames nativos IEEE 1815:

```bash
# Captura de paquetes DNP3 en interfaz loopback o bridge docker
sudo tcpdump -i any port 20000 -X
```

Filtro recomendado en Wireshark:
```wireshark
dnp3
```
Verás la estructura completa:
- `DNP 3.0 (Data Link Layer): Len=27, Source=1, Destination=10, Func=Unconfirmed User Data (4)`
- `DNP 3.0 (Application Layer): Func=Read (1)`
- `DNP 3.0 (Application Layer): Func=Response (129), IIN=0x0000`
- `Group 30 (Analog Inputs), Variation 5 (Single-precision floating point with flags)`
- `Group 12 (Control Relay Output Block), Variation 1`

### Verificación de Mensajería MQTT
Para monitorizar el flujo de telemetría DNP3 traducido a MQTT en tiempo real:
```bash
# Instalar mosquitto-clients si no lo tienes: apt-get install mosquitto-clients
mosquitto_sub -h localhost -p 1883 -t "scada/dnp3/#" -v
```
Salida en tiempo real:
```text
scada/dnp3/substation_alpha/voltage_kv 25.04
scada/dnp3/substation_alpha/current_a 148.6
scada/dnp3/substation_alpha/power_mw 5.18
scada/dnp3/substation_alpha/freq_hz 50.01
scada/dnp3/substation_alpha/breaker_status 1
scada/dnp3/solar_farm/generation_kw 2432.8
scada/dnp3/solar_farm/irradiance_wm2 824.5
```

---

## 🛡️ Estructura del Directorio

```
example-scada-dnp3-fuxa/
├── docker-compose.yml         # Definición de servicios para Gubernator
├── mosquitto.conf             # Configuración MQTT sin autenticación previa
├── generate_fuxa_project.py   # Generador del proyecto HMI (JSON y SQLite)
├── README.md                  # Este documento
├── fuxa-appdata/              # Volumen persistente de FUXA montado en /_appdata
│   ├── project.fuxap          # Definición de proyecto HMI en JSON
│   └── project.fuxap.db       # Base de datos SQLite preconfigurada de FUXA
└── simulator/                 # Microservicios DNP3 IEEE 1815 en Python
    ├── Dockerfile             # Imagen Python 3.11 optimizada
    ├── requirements.txt       # Dependencias (paho-mqtt)
    ├── dnp3_frame.py          # Parser/Encoder DNP3 con CRC-16 y capas 2, 4 y 7
    ├── outstation_substation.py # RTU Subestación Eléctrica 25 kV (Addr: 10)
    ├── outstation_solar.py    # RTU Planta Solar Fotovoltaica 3 MW (Addr: 20)
    └── master_bridge.py       # DNP3 Master Station y Gateway MQTT
```
