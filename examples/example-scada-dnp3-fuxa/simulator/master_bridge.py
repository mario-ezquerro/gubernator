#!/usr/bin/env python3
"""
master_bridge.py - DNP3 (IEEE 1815) Master Station & SCADA Protocol Bridge
Acts as the central DNP3 Master Station in the cluster:
1. Connects via TCP to multiple DNP3 Outstations (Substation Alpha & Solar Farm Beta).
2. Issues cyclic IEEE 1815 Integrity Polls (Class 0/1/2/3).
3. Decodes binary inputs, analog measurements, and internal indications.
4. Bridges telemetry to Eclipse Mosquitto MQTT broker for FUXA Web SCADA ingestion.
5. Listens to MQTT control topics to dispatch DNP3 CROB Direct Operate commands (e.g. breaker trip/close).
"""

import json
import os
import socket
import sys
import threading
import time
from typing import Any, Dict, Optional

import paho.mqtt.client as mqtt

from dnp3_frame import (
    CROB_LATCH_OFF,
    CROB_LATCH_ON,
    CROB_PULSE_OFF,
    CROB_PULSE_ON,
    build_direct_operate_crob,
    build_read_integrity_request,
    decode_data_link_frame,
    encode_data_link_frame,
    parse_app_response,
)

# Configuration from environment variables
MQTT_BROKER = os.environ.get("MQTT_BROKER", "mqtt")
MQTT_PORT = int(os.environ.get("MQTT_PORT", "1883"))
POLL_INTERVAL = float(os.environ.get("POLL_INTERVAL", "1.0"))

SUBSTATION_HOST = os.environ.get("SUBSTATION_HOST", "dnp3-substation-alpha")
SUBSTATION_PORT = int(os.environ.get("SUBSTATION_PORT", "20000"))
SUBSTATION_DNP3_ADDR = int(os.environ.get("SUBSTATION_DNP3_ADDR", "10"))

SOLAR_HOST = os.environ.get("SOLAR_HOST", "dnp3-solar-farm")
SOLAR_PORT = int(os.environ.get("SOLAR_PORT", "20000"))
SOLAR_DNP3_ADDR = int(os.environ.get("SOLAR_DNP3_ADDR", "20"))

MASTER_DNP3_ADDR = int(os.environ.get("MASTER_DNP3_ADDR", "1"))


class DNP3DeviceConnection:
    """Manages a persistent TCP socket and DNP3 Master communications to an Outstation."""

    def __init__(self, name: str, host: str, port: int, dnp3_addr: int, master_addr: int):
        self.name = name
        self.host = host
        self.port = port
        self.dnp3_addr = dnp3_addr
        self.master_addr = master_addr
        self.sock: Optional[socket.socket] = None
        self.lock = threading.RLock()
        self.app_seq = 0
        self.connected = False

    def connect(self) -> bool:
        with self.lock:
            if self.sock:
                try:
                    self.sock.close()
                except Exception:
                    pass
                self.sock = None
                self.connected = False

            try:
                s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                s.settimeout(3.0)
                s.connect((self.host, self.port))
                self.sock = s
                self.connected = True
                print(f"✅ [DNP3 MASTER] Connected to {self.name} at {self.host}:{self.port} (Addr: {self.dnp3_addr})")
                return True
            except Exception as e:
                self.connected = False
                return False

    def send_and_receive(self, user_data: bytes, timeout: float = 2.5) -> Optional[Dict[str, Any]]:
        with self.lock:
            if not self.connected or not self.sock:
                if not self.connect():
                    return None

            try:
                frame = encode_data_link_frame(
                    dest=self.dnp3_addr,
                    src=self.master_addr,
                    user_data=user_data,
                    is_master=True,
                    prm=True,
                )
                self.sock.sendall(frame)

                self.sock.settimeout(timeout)
                rx_buf = bytearray()
                start_time = time.time()

                while time.time() - start_time < timeout:
                    try:
                        chunk = self.sock.recv(1024)
                        if not chunk:
                            break
                        rx_buf.extend(chunk)
                    except socket.timeout:
                        break

                    result = decode_data_link_frame(bytes(rx_buf))
                    if result is not None:
                        dest, src, ctrl, dec_user_data, remaining = result
                        if dest == self.master_addr and src == self.dnp3_addr:
                            return parse_app_response(dec_user_data)
            except Exception as e:
                print(f"⚠️ [DNP3 MASTER] Comm error with {self.name}: {e}")
                self.connected = False
                try:
                    if self.sock:
                        self.sock.close()
                except Exception:
                    pass
                self.sock = None
            return None

    def poll_integrity(self) -> Optional[Dict[str, Any]]:
        self.app_seq = (self.app_seq + 1) & 0x0F
        req = build_read_integrity_request(app_seq=self.app_seq)
        return self.send_and_receive(req)

    def send_crob(self, point_index: int, control_code: int) -> bool:
        self.app_seq = (self.app_seq + 1) & 0x0F
        req = build_direct_operate_crob(point_index=point_index, control_code=control_code, app_seq=self.app_seq)
        resp = self.send_and_receive(req)
        if resp and resp.get("crob_status") == 0x00:
            return True
        return False


class MasterBridge:
    def __init__(self):
        self.substation = DNP3DeviceConnection(
            "Substation Alpha", SUBSTATION_HOST, SUBSTATION_PORT, SUBSTATION_DNP3_ADDR, MASTER_DNP3_ADDR
        )
        self.solar = DNP3DeviceConnection(
            "Solar Farm Beta", SOLAR_HOST, SOLAR_PORT, SOLAR_DNP3_ADDR, MASTER_DNP3_ADDR
        )

        self.mqtt_client = mqtt.Client(client_id="gbnt-dnp3-master-bridge")
        self.mqtt_client.on_connect = self.on_mqtt_connect
        self.mqtt_client.on_message = self.on_mqtt_message

    def on_mqtt_connect(self, client, userdata, flags, rc):
        if rc == 0:
            print(f"✅ [MQTT] Connected to broker at {MQTT_BROKER}:{MQTT_PORT}")
            # Subscribe to control topics for breaker actions
            client.subscribe("scada/dnp3/control/substation_alpha/breaker")
            client.subscribe("scada/dnp3/control/solar_farm/inverter")
            client.subscribe("scada/dnp3/control/#")
            print("📡 [MQTT] Subscribed to SCADA control topics: scada/dnp3/control/#")
        else:
            print(f"❌ [MQTT] Connection failed with code {rc}")

    def on_mqtt_message(self, client, userdata, msg):
        topic = msg.topic
        payload = msg.payload.decode("utf-8", errors="ignore").strip()
        print(f"📥 [MQTT COMMAND] Received on {topic}: '{payload}'")

        try:
            # Substation Breaker 52-1 control
            if "substation_alpha/breaker" in topic:
                val = payload.upper()
                if val in ("TRIP", "OPEN", "0", "OFF", "FALSE"):
                    print("⚡ [DNP3 MASTER] Sending CROB TRIP (LATCH_OFF) to Substation Breaker 52-1...")
                    ok = self.substation.send_crob(point_index=0, control_code=CROB_LATCH_OFF)
                    print(f"⚡ [DNP3 MASTER] CROB Trip Result: {'SUCCESS' if ok else 'FAILED'}")
                elif val in ("CLOSE", "1", "ON", "TRUE", "ENERGIZED"):
                    print("⚡ [DNP3 MASTER] Sending CROB CLOSE (LATCH_ON) to Substation Breaker 52-1...")
                    ok = self.substation.send_crob(point_index=0, control_code=CROB_LATCH_ON)
                    print(f"⚡ [DNP3 MASTER] CROB Close Result: {'SUCCESS' if ok else 'FAILED'}")

            # Solar Farm Inverter run/curtail control
            elif "solar_farm/inverter" in topic:
                val = payload.upper()
                if val in ("CURTAIL", "STOP", "0", "OFF", "FALSE"):
                    print("☀️ [DNP3 MASTER] Sending CROB CURTAIL (LATCH_OFF) to Solar Inverter...")
                    ok = self.solar.send_crob(point_index=0, control_code=CROB_LATCH_OFF)
                    print(f"☀️ [DNP3 MASTER] CROB Curtail Result: {'SUCCESS' if ok else 'FAILED'}")
                elif val in ("ENABLE", "RUN", "1", "ON", "TRUE"):
                    print("☀️ [DNP3 MASTER] Sending CROB ENABLE (LATCH_ON) to Solar Inverter...")
                    ok = self.solar.send_crob(point_index=0, control_code=CROB_LATCH_ON)
                    print(f"☀️ [DNP3 MASTER] CROB Enable Result: {'SUCCESS' if ok else 'FAILED'}")
        except Exception as e:
            print(f"❌ [MQTT COMMAND] Error processing command: {e}")

    def run(self):
        print("=" * 70)
        print("🏛️  Gubernator DNP3 (IEEE 1815) Master Station & Protocol Bridge")
        print(f"   MQTT Broker:     {MQTT_BROKER}:{MQTT_PORT}")
        print(f"   Substation RTU:  {SUBSTATION_HOST}:{SUBSTATION_PORT} (DNP3: {SUBSTATION_DNP3_ADDR})")
        print(f"   Solar Farm RTU:  {SOLAR_HOST}:{SOLAR_PORT} (DNP3: {SOLAR_DNP3_ADDR})")
        print(f"   Poll Interval:   {POLL_INTERVAL}s")
        print("=" * 70)

        # Connect to MQTT with auto-reconnect
        while True:
            try:
                self.mqtt_client.connect(MQTT_BROKER, MQTT_PORT, 60)
                self.mqtt_client.loop_start()
                break
            except Exception as e:
                print(f"⏳ Waiting for MQTT broker ({MQTT_BROKER}:{MQTT_PORT})... {e}")
                time.sleep(2)

        # Main DNP3 cyclic polling loop
        while True:
            try:
                # 1. Poll Substation Alpha
                sub_resp = self.substation.poll_integrity()
                if sub_resp:
                    bi = sub_resp.get("binary_inputs", {})
                    ai = sub_resp.get("analog_inputs", {})

                    # Extract Substation measurements
                    v_kv = ai.get(0, 0.0)
                    curr_a = ai.get(1, 0.0)
                    p_mw = ai.get(2, 0.0)
                    q_mvar = ai.get(3, 0.0)
                    freq_hz = ai.get(4, 50.0)
                    temp_c = ai.get(5, 25.0)

                    brk_status = 1 if bi.get(0, False) else 0
                    disc_status = 1 if bi.get(1, False) else 0
                    oc_alarm = 1 if bi.get(2, False) else 0
                    sf6_ok = 1 if bi.get(3, True) else 0

                    # Publish individual scalar topics (compatible with simple FUXA tags)
                    pfx = "scada/dnp3/substation_alpha"
                    self.mqtt_client.publish(f"{pfx}/voltage_kv", str(v_kv))
                    self.mqtt_client.publish(f"{pfx}/current_a", str(curr_a))
                    self.mqtt_client.publish(f"{pfx}/power_mw", str(p_mw))
                    self.mqtt_client.publish(f"{pfx}/power_mvar", str(q_mvar))
                    self.mqtt_client.publish(f"{pfx}/freq_hz", str(freq_hz))
                    self.mqtt_client.publish(f"{pfx}/trafo_temp", str(temp_c))
                    self.mqtt_client.publish(f"{pfx}/breaker_status", str(brk_status))
                    self.mqtt_client.publish(f"{pfx}/disconnector_status", str(disc_status))
                    self.mqtt_client.publish(f"{pfx}/alarm_overcurrent", str(oc_alarm))
                    self.mqtt_client.publish(f"{pfx}/sf6_gas_ok", str(sf6_ok))

                    # Composite JSON telemetry
                    sub_doc = {
                        "station": "Substation Alpha",
                        "dnp3_address": SUBSTATION_DNP3_ADDR,
                        "timestamp": int(time.time()),
                        "breaker_closed": bool(brk_status),
                        "disconnector_closed": bool(disc_status),
                        "overcurrent_alarm": bool(oc_alarm),
                        "sf6_gas_ok": bool(sf6_ok),
                        "voltage_kv": v_kv,
                        "current_a": curr_a,
                        "power_mw": p_mw,
                        "power_mvar": q_mvar,
                        "frequency_hz": freq_hz,
                        "transformer_temp_c": temp_c,
                    }
                    self.mqtt_client.publish(f"{pfx}/telemetry", json.dumps(sub_doc))

                # 2. Poll Solar Farm Beta
                sol_resp = self.solar.poll_integrity()
                if sol_resp:
                    bi = sol_resp.get("binary_inputs", {})
                    ai = sol_resp.get("analog_inputs", {})

                    gen_kw = ai.get(0, 0.0)
                    irr_wm2 = ai.get(1, 0.0)
                    dc_v = ai.get(2, 0.0)
                    dc_a = ai.get(3, 0.0)
                    inv_temp = ai.get(4, 25.0)
                    amb_temp = ai.get(5, 20.0)

                    inv_running = 1 if bi.get(0, False) else 0
                    sync_ok = 1 if bi.get(1, True) else 0
                    gf_alarm = 1 if bi.get(2, False) else 0

                    pfx_sol = "scada/dnp3/solar_farm"
                    self.mqtt_client.publish(f"{pfx_sol}/generation_kw", str(gen_kw))
                    self.mqtt_client.publish(f"{pfx_sol}/irradiance_wm2", str(irr_wm2))
                    self.mqtt_client.publish(f"{pfx_sol}/dc_voltage_v", str(dc_v))
                    self.mqtt_client.publish(f"{pfx_sol}/dc_current_a", str(dc_a))
                    self.mqtt_client.publish(f"{pfx_sol}/inverter_temp", str(inv_temp))
                    self.mqtt_client.publish(f"{pfx_sol}/ambient_temp", str(amb_temp))
                    self.mqtt_client.publish(f"{pfx_sol}/inverter_running", str(inv_running))
                    self.mqtt_client.publish(f"{pfx_sol}/sync_ok", str(sync_ok))
                    self.mqtt_client.publish(f"{pfx_sol}/alarm_ground_fault", str(gf_alarm))

                    sol_doc = {
                        "station": "Solar PV Farm Beta",
                        "dnp3_address": SOLAR_DNP3_ADDR,
                        "timestamp": int(time.time()),
                        "inverter_running": bool(inv_running),
                        "sync_ok": bool(sync_ok),
                        "ground_fault": bool(gf_alarm),
                        "generation_kw": gen_kw,
                        "irradiance_wm2": irr_wm2,
                        "dc_voltage_v": dc_v,
                        "dc_current_a": dc_a,
                        "inverter_temp_c": inv_temp,
                        "ambient_temp_c": amb_temp,
                    }
                    self.mqtt_client.publish(f"{pfx_sol}/telemetry", json.dumps(sol_doc))

            except Exception as e:
                print(f"⚠️ [DNP3 MASTER] Cycle exception: {e}")

            time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    bridge = MasterBridge()
    bridge.run()
