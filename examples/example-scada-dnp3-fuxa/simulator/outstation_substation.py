#!/usr/bin/env python3
"""
outstation_substation.py - 25 kV Electrical Distribution Substation Alpha RTU
DNP3 (IEEE 1815) Outstation Server listening on TCP port 20000 (DNP3 Address: 10).
Simulates realistic substation physics:
- High-voltage busbar & transformer monitoring
- Circuit Breaker 52-1 status and Direct Operate CROB trip/close control
- Overcurrent protection relays
"""

import math
import os
import random
import select
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
DNP3_ADDRESS = int(os.environ.get("DNP3_ADDRESS", "10"))
MASTER_ADDRESS = int(os.environ.get("MASTER_ADDRESS", "1"))
STATION_NAME = os.environ.get("STATION_NAME", "Substation Alpha (25 kV)")


class SubstationSimulation:
    def __init__(self):
        self.lock = threading.Lock()
        # Physical device states
        self.breaker_52_1_closed = True     # BI 0: Main Feeder Breaker
        self.disconnector_89_1_closed = True # BI 1: Busbar Disconnector
        self.overcurrent_alarm = False       # BI 2: Relay 50/51 Trip Alarm
        self.sf6_gas_ok = True               # BI 3: SF6 Gas Pressure

        # Physical measurements
        self.voltage_kv = 25.0
        self.current_a = 150.0
        self.power_mw = 5.2
        self.power_mvar = 0.8
        self.frequency_hz = 50.00
        self.transformer_temp_c = 62.5
        self.step = 0

    def update_physics(self):
        with self.lock:
            self.step += 1
            t = self.step * 0.1

            # Grid frequency around 50 Hz with slight natural oscillation
            self.frequency_hz = round(50.00 + 0.02 * math.sin(t * 0.5) + random.uniform(-0.008, 0.008), 2)

            # If breaker is closed and disconnector closed, current flows
            if self.breaker_52_1_closed and self.disconnector_89_1_closed:
                # Voltage 25.0 kV +/- 0.15 kV
                self.voltage_kv = round(25.0 + 0.12 * math.sin(t * 0.2) + random.uniform(-0.05, 0.05), 2)
                # Load current fluctuates 130A - 170A
                self.current_a = round(150.0 + 15.0 * math.sin(t * 0.1) + random.uniform(-2.0, 2.0), 1)
                # Active power P = sqrt(3) * V * I * cos(phi) ~ 5.2 MW
                self.power_mw = round((math.sqrt(3) * self.voltage_kv * self.current_a * 0.92) / 1000.0, 2)
                # Reactive power Q ~ 0.8 MVAr
                self.power_mvar = round(self.power_mw * 0.16 + random.uniform(-0.02, 0.02), 2)
                # Transformer heating proportional to I^2
                target_temp = 58.0 + (self.current_a / 180.0) * 12.0
                self.transformer_temp_c = round(self.transformer_temp_c * 0.95 + target_temp * 0.05, 1)
            else:
                # Open circuit
                self.voltage_kv = 0.0
                self.current_a = 0.0
                self.power_mw = 0.0
                self.power_mvar = 0.0
                # Transformer cools down towards ambient
                self.transformer_temp_c = round(max(30.0, self.transformer_temp_c - 0.1), 1)

    def get_points(self):
        with self.lock:
            binary_inputs = {
                0: self.breaker_52_1_closed,
                1: self.disconnector_89_1_closed,
                2: self.overcurrent_alarm,
                3: self.sf6_gas_ok,
            }
            analog_inputs = {
                0: self.voltage_kv,
                1: self.current_a,
                2: self.power_mw,
                3: self.power_mvar,
                4: self.frequency_hz,
                5: self.transformer_temp_c,
            }
            return binary_inputs, analog_inputs

    def handle_crob(self, point_index: int, control_code: int) -> bool:
        """Executes a DNP3 CROB command (Trip / Close / Reset)."""
        with self.lock:
            if point_index == 0:
                # Main Feeder Breaker 52-1
                if control_code in (CROB_LATCH_OFF, CROB_PULSE_OFF):
                    self.breaker_52_1_closed = False
                    print(f"⚡ [DNP3 CROB] Breaker 52-1 TRIPPED (OPEN) via DNP3 Command!")
                    return True
                elif control_code in (CROB_LATCH_ON, CROB_PULSE_ON):
                    self.breaker_52_1_closed = True
                    self.overcurrent_alarm = False
                    print(f"⚡ [DNP3 CROB] Breaker 52-1 CLOSED (ENERGIZED) via DNP3 Command!")
                    return True
            elif point_index == 1:
                # Busbar Disconnector 89-1
                if control_code in (CROB_LATCH_OFF, CROB_PULSE_OFF):
                    self.disconnector_89_1_closed = False
                    print(f"⚡ [DNP3 CROB] Disconnector 89-1 OPENED via DNP3 Command!")
                    return True
                elif control_code in (CROB_LATCH_ON, CROB_PULSE_ON):
                    self.disconnector_89_1_closed = True
                    print(f"⚡ [DNP3 CROB] Disconnector 89-1 CLOSED via DNP3 Command!")
                    return True
            elif point_index == 2:
                # Protection Alarm Reset
                self.overcurrent_alarm = False
                print(f"⚡ [DNP3 CROB] Protection Alarms RESET via DNP3 Command!")
                return True
        return False


def client_handler(sock: socket.socket, addr: Tuple[str, int], sim: SubstationSimulation):
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

            # Process all complete DNP3 frames in buffer
            while True:
                result = decode_data_link_frame(bytes(rx_buf))
                if result is None:
                    break

                dest, src, ctrl, user_data, remaining = result
                rx_buf = bytearray(remaining)

                if dest != DNP3_ADDRESS:
                    # Not addressed to this Outstation, ignore
                    continue

                if len(user_data) < 3:
                    continue

                app_ctrl = user_data[1]
                func_code = user_data[2]
                app_seq = app_ctrl & 0x0F

                # 1. Handle READ (Integrity / Class poll)
                if func_code == FC_READ:
                    bi, ai = sim.get_points()
                    resp_ud = build_outstation_response(bi, ai, app_seq=app_seq)
                    resp_frame = encode_data_link_frame(
                        dest=src,
                        src=DNP3_ADDRESS,
                        user_data=resp_ud,
                        is_master=False,
                        prm=False,
                        func_code=0x00,  # ACK response
                    )
                    sock.sendall(resp_frame)

                # 2. Handle DIRECT_OPERATE (CROB)
                elif func_code in (FC_DIRECT_OPERATE, FC_DIRECT_OPERATE_NR):
                    success = False
                    crob_point = 0
                    crob_code = 0
                    if len(user_data) >= 8:
                        # Extract Group 12 Var 1 point index and code
                        offset = 3
                        grp = user_data[offset]
                        var = user_data[offset + 1]
                        qual = user_data[offset + 2]
                        if grp == GROUP_CROB and var == VAR_CROB and qual == QUAL_1OCTET_INDEX:
                            crob_point = user_data[offset + 3]
                            crob_code = user_data[offset + 5]
                            success = sim.handle_crob(crob_point, crob_code)

                    # Build CROB echo response with status
                    transport_hdr = bytes([0xC0 | (app_seq & 0x3F)])
                    app_header = bytes([0xC0 | (app_seq & 0x0F), 0x81, 0x00, 0x00]) # Response, IIN=0
                    status_code = 0x00 if success else 0x04 # 0 = SUCCESS, 4 = NOT_SUPPORTED
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


def physics_loop(sim: SubstationSimulation):
    while True:
        sim.update_physics()
        time.sleep(1.0)


def main():
    print("=" * 70)
    print(f"🏛️  Gubernator DNP3 (IEEE 1815) Outstation Simulator")
    print(f"   Station:      {STATION_NAME}")
    print(f"   DNP3 Address: {DNP3_ADDRESS}")
    print(f"   Listening on: TCP 0.0.0.0:{DNP3_PORT}")
    print("=" * 70)

    sim = SubstationSimulation()

    # Start background physics thread
    phys_t = threading.Thread(target=physics_loop, args=(sim,), daemon=True)
    phys_t.start()

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", DNP3_PORT))
    server.listen(5)
    print(f"✅ Substation RTU online and awaiting DNP3 Master requests...")

    try:
        while True:
            client_sock, addr = server.accept()
            client_t = threading.Thread(target=client_handler, args=(client_sock, addr, sim), daemon=True)
            client_t.start()
    except KeyboardInterrupt:
        print("\nStopping Substation Outstation...")
    finally:
        server.close()


if __name__ == "__main__":
    main()
