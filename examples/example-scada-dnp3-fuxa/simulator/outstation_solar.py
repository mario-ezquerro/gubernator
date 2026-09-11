#!/usr/bin/env python3
"""
outstation_solar.py - 3 MW Solar PV Farm Beta Central Inverter RTU
DNP3 (IEEE 1815) Outstation Server listening on TCP port 20000 (DNP3 Address: 20).
Simulates realistic renewable energy physics:
- Solar irradiance curve (W/m²) and photovoltaic conversion efficiency
- Inverter DC to AC conversion, active power (kW)
- Anti-islanding grid synchronization
- Curtailment / power limiting control via DNP3 CROB Direct Operate
"""

import math
import os
import random
import socket
import struct
import sys
import threading
import time
from typing import Tuple

from dnp3_frame import (
    CROB_LATCH_OFF,
    CROB_LATCH_ON,
    CROB_PULSE_OFF,
    CROB_PULSE_ON,
    FC_DIRECT_OPERATE,
    FC_DIRECT_OPERATE_NR,
    FC_READ,
    GROUP_CROB,
    QUAL_1OCTET_INDEX,
    VAR_CROB,
    build_outstation_response,
    decode_data_link_frame,
    encode_data_link_frame,
)

DNP3_PORT = int(os.environ.get("DNP3_PORT", "20000"))
DNP3_ADDRESS = int(os.environ.get("DNP3_ADDRESS", "20"))
MASTER_ADDRESS = int(os.environ.get("MASTER_ADDRESS", "1"))
STATION_NAME = os.environ.get("STATION_NAME", "Solar PV Farm Beta (3 MW)")


class SolarSimulation:
    def __init__(self):
        self.lock = threading.Lock()
        # Binary statuses
        self.inverter_exporting = True  # BI 0: Inverter generating power to grid
        self.grid_sync_ok = True        # BI 1: Sincronismo / Anti-islanding OK
        self.ground_fault = False       # BI 2: DC Ground fault alert

        # Analog measurements
        self.generation_kw = 2450.0     # AI 0: Active solar generation
        self.irradiance_wm2 = 820.0     # AI 1: Solar Irradiance (W/m2)
        self.dc_voltage_v = 750.0       # AI 2: DC Array Voltage (V)
        self.dc_current_a = 3300.0      # AI 3: DC Array Current (A)
        self.inverter_temp_c = 48.0     # AI 4: Inverter IGBT Temperature
        self.ambient_temp_c = 26.5      # AI 5: Ambient Temperature
        self.step = 0

    def update_physics(self):
        with self.lock:
            self.step += 1
            t = self.step * 0.05

            # Simulates realistic daylight bell curve with cloud passing fluctuations
            base_irradiance = 750.0 + 150.0 * math.sin(t * 0.3)
            cloud_factor = 1.0 - 0.15 * max(0.0, math.sin(t * 1.5))
            self.irradiance_wm2 = round(max(50.0, min(1000.0, (base_irradiance * cloud_factor) + random.uniform(-10.0, 10.0))), 1)
            self.ambient_temp_c = round(25.0 + 4.0 * math.sin(t * 0.1) + random.uniform(-0.2, 0.2), 1)

            if self.inverter_exporting and self.grid_sync_ok:
                # 3000 kW nominal maximum plant at 1000 W/m2 (efficiency 98%)
                max_kw = 3000.0 * (self.irradiance_wm2 / 1000.0) * 0.98
                self.generation_kw = round(max(0.0, max_kw + random.uniform(-15.0, 15.0)), 1)
                # DC Voltage ~750V with slight MPP tracking variation
                self.dc_voltage_v = round(750.0 + random.uniform(-5.0, 5.0), 1)
                # DC Current = Power / Voltage
                self.dc_current_a = round((self.generation_kw * 1000.0) / self.dc_voltage_v, 1)
                # Inverter temperature tracks generation load
                target_inv_temp = self.ambient_temp_c + (self.generation_kw / 3000.0) * 28.0
                self.inverter_temp_c = round(self.inverter_temp_c * 0.95 + target_inv_temp * 0.05, 1)
            else:
                # Inverter curtailed or stopped
                self.generation_kw = 0.0
                self.dc_current_a = 0.0
                # Open circuit voltage Voc ~ 850V
                self.dc_voltage_v = 850.0
                self.inverter_temp_c = round(max(self.ambient_temp_c, self.inverter_temp_c - 0.1), 1)

    def get_points(self):
        with self.lock:
            binary_inputs = {
                0: self.inverter_exporting,
                1: self.grid_sync_ok,
                2: self.ground_fault,
            }
            analog_inputs = {
                0: self.generation_kw,
                1: self.irradiance_wm2,
                2: self.dc_voltage_v,
                3: self.dc_current_a,
                4: self.inverter_temp_c,
                5: self.ambient_temp_c,
            }
            return binary_inputs, analog_inputs

    def handle_crob(self, point_index: int, control_code: int) -> bool:
        """Executes a DNP3 CROB command (Curtailment / Run / Reset)."""
        with self.lock:
            if point_index == 0:
                # Inverter Run / Curtailment
                if control_code in (CROB_LATCH_OFF, CROB_PULSE_OFF):
                    self.inverter_exporting = False
                    print(f"☀️ [DNP3 CROB] Solar Inverter CURTAILED (STOPPED) via DNP3 Command!")
                    return True
                elif control_code in (CROB_LATCH_ON, CROB_PULSE_ON):
                    self.inverter_exporting = True
                    print(f"☀️ [DNP3 CROB] Solar Inverter ENABLED (GENERATING) via DNP3 Command!")
                    return True
            elif point_index == 1:
                # Fault Reset
                self.ground_fault = False
                print(f"☀️ [DNP3 CROB] Solar Farm Faults RESET via DNP3 Command!")
                return True
        return False


def client_handler(sock: socket.socket, addr: Tuple[str, int], sim: SolarSimulation):
    print(f"🔌 [DNP3] New Master connection from {addr[0]}:{addr[1]}")
    rx_buf = bytearray()
    sock.settimeout(5.0)

    try:
        while True:
            try:
                data = sock.recv(1024)
                if not data:
                    break
                rx_buf.extend(data)
            except socket.timeout:
                continue

            while True:
                result = decode_data_link_frame(bytes(rx_buf))
                if result is None:
                    break

                dest, src, ctrl, user_data, remaining = result
                rx_buf = bytearray(remaining)

                if dest != DNP3_ADDRESS:
                    continue

                if len(user_data) < 3:
                    continue

                app_ctrl = user_data[1]
                func_code = user_data[2]
                app_seq = app_ctrl & 0x0F

                # 1. Handle READ
                if func_code == FC_READ:
                    bi, ai = sim.get_points()
                    resp_ud = build_outstation_response(bi, ai, app_seq=app_seq)
                    resp_frame = encode_data_link_frame(
                        dest=src,
                        src=DNP3_ADDRESS,
                        user_data=resp_ud,
                        is_master=False,
                        prm=False,
                        func_code=0x00,
                    )
                    sock.sendall(resp_frame)

                # 2. Handle DIRECT_OPERATE (CROB)
                elif func_code in (FC_DIRECT_OPERATE, FC_DIRECT_OPERATE_NR):
                    success = False
                    crob_point = 0
                    crob_code = 0
                    if len(user_data) >= 8:
                        offset = 3
                        grp = user_data[offset]
                        var = user_data[offset + 1]
                        qual = user_data[offset + 2]
                        if grp == GROUP_CROB and var == VAR_CROB and qual == QUAL_1OCTET_INDEX:
                            crob_point = user_data[offset + 3]
                            crob_code = user_data[offset + 5]
                            success = sim.handle_crob(crob_point, crob_code)

                    transport_hdr = bytes([0xC0 | (app_seq & 0x3F)])
                    app_header = bytes([0xC0 | (app_seq & 0x0F), 0x81, 0x00, 0x00])
                    status_code = 0x00 if success else 0x04
                    crob_echo = bytes([GROUP_CROB, VAR_CROB, QUAL_1OCTET_INDEX, crob_point, crob_point])
                    crob_data = struct.pack("<BBIIB", crob_code, 1, 1000, 0, status_code)
                    resp_ud = transport_hdr + app_header + crob_echo + crob_data
                    resp_frame = encode_data_link_frame(
                        dest=src,
                        src=DNP3_ADDRESS,
                        user_data=resp_ud,
                        is_master=False,
                        prm=False,
                    )
                    sock.sendall(resp_frame)
    except Exception as e:
        print(f"⚠️ [DNP3] Connection closed with {addr[0]}: {e}")
    finally:
        sock.close()
        print(f"🔌 [DNP3] Master disconnected: {addr[0]}:{addr[1]}")


def physics_loop(sim: SolarSimulation):
    while True:
        sim.update_physics()
        time.sleep(1.0)


def main():
    print("=" * 70)
    print(f"☀️  Gubernator DNP3 (IEEE 1815) Outstation Simulator")
    print(f"   Station:      {STATION_NAME}")
    print(f"   DNP3 Address: {DNP3_ADDRESS}")
    print(f"   Listening on: TCP 0.0.0.0:{DNP3_PORT}")
    print("=" * 70)

    sim = SolarSimulation()

    phys_t = threading.Thread(target=physics_loop, args=(sim,), daemon=True)
    phys_t.start()

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", DNP3_PORT))
    server.listen(5)
    print(f"✅ Solar Farm RTU online and awaiting DNP3 Master requests...")

    try:
        while True:
            client_sock, addr = server.accept()
            client_t = threading.Thread(target=client_handler, args=(client_sock, addr, sim), daemon=True)
            client_t.start()
    except KeyboardInterrupt:
        print("\nStopping Solar Outstation...")
    finally:
        server.close()


if __name__ == "__main__":
    main()
