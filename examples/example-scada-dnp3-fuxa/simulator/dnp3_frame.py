"""
dnp3_frame.py - IEEE 1815 (DNP3) Protocol Parser & Serializer
Compliant with IEEE 1815-2012 specifications.
Includes Data Link Layer (CRC-16 DNP3), Transport Layer, and Application Layer.
"""

import socket
import struct
import threading
import time
from typing import Dict, List, Optional, Tuple, Any

# Precompute standard DNP3 CRC-16 table (Generator polynomial 0xA653, bit-reversed)
# Reference: IEEE 1815-2012 Annex F
_CRC_TABLE = []
for _i in range(256):
    _val = _i
    for _ in range(8):
        if _val & 1:
            _val = (_val >> 1) ^ 0xA653
        else:
            _val = _val >> 1
    _CRC_TABLE.append(_val)


def compute_crc(data: bytes) -> int:
    """Computes the standard inverted 16-bit DNP3 CRC for the given octets."""
    crc = 0x0000
    for b in data:
        crc = (crc >> 8) ^ _CRC_TABLE[(crc ^ b) & 0xFF]
    return (~crc) & 0xFFFF


# DNP3 Function Codes
FC_READ = 0x01
FC_WRITE = 0x02
FC_SELECT = 0x03
FC_OPERATE = 0x04
FC_DIRECT_OPERATE = 0x05
FC_DIRECT_OPERATE_NR = 0x06
FC_RESPONSE = 0x81
FC_UNSOLICITED_RESPONSE = 0x82

# DNP3 Object Groups & Variations
GROUP_BINARY_INPUT = 1
VAR_BI_PACKED = 1
VAR_BI_WITH_FLAGS = 2

GROUP_CROB = 12
VAR_CROB = 1

GROUP_ANALOG_INPUT = 30
VAR_AI_32BIT = 1
VAR_AI_16BIT = 2
VAR_AI_FLOAT32 = 5
VAR_AI_FLOAT64 = 6

GROUP_CLASS_OBJECTS = 60
VAR_CLASS_0 = 1
VAR_CLASS_1 = 2
VAR_CLASS_2 = 3
VAR_CLASS_3 = 4

# DNP3 Qualifiers
QUAL_1OCTET_INDEX = 0x00
QUAL_2OCTET_INDEX = 0x01
QUAL_ALL_OBJECTS = 0x06

# CROB Control Codes
CROB_NUL = 0x00
CROB_PULSE_ON = 0x01
CROB_PULSE_OFF = 0x02
CROB_LATCH_ON = 0x03   # CLOSE breaker
CROB_LATCH_OFF = 0x04  # TRIP breaker

# Binary Input Flags (IEEE 1815 Table 11-1)
FLAG_ONLINE = 0x01
FLAG_RESTART = 0x02
FLAG_COMM_LOST = 0x04
FLAG_REMOTE_FORCED = 0x08
FLAG_LOCAL_FORCED = 0x10
FLAG_CHATTER_FILTER = 0x20
FLAG_RESERVED = 0x40
FLAG_STATE = 0x80      # 1 = ON/CLOSED, 0 = OFF/OPEN


def encode_data_link_frame(dest: int, src: int, user_data: bytes,
                           is_master: bool = True, prm: bool = True,
                           fcb: bool = False, fcv: bool = False,
                           func_code: int = 4) -> bytes:
    """
    Encodes an IEEE 1815 Data Link Layer Frame with 16-octet chunking & CRC-16.
    Header: 0x05 0x64 | Length | Control | Dest (2 LE) | Src (2 LE) | Header CRC (2 LE)
    Data: Chunks of up to 16 octets, each followed by 2 LE CRC octets.
    """
    # Control byte layout: DIR(7), PRM(6), FCB(5), FCV(4), FNC(3-0)
    ctrl = 0
    if is_master:
        ctrl |= 0x80  # DIR: 1 = Master to Outstation
    if prm:
        ctrl |= 0x40  # PRM: 1 = Initiating message
    if fcb:
        ctrl |= 0x20
    if fcv:
        ctrl |= 0x10
    ctrl |= (func_code & 0x0F)

    # Length field = 5 (ctrl + 2 dest + 2 src) + len(user_data)
    length = 5 + len(user_data)
    if length > 255:
        raise ValueError(f"DNP3 frame user data exceeds maximum length: {len(user_data)}")

    hdr_body = struct.pack("<BBHH", length, ctrl, dest, src)
    hdr_crc = compute_crc(bytes([0x05, 0x64]) + hdr_body)
    header = bytes([0x05, 0x64]) + hdr_body + struct.pack("<H", hdr_crc)

    # Chunk user data in blocks of max 16 bytes
    chunks = []
    offset = 0
    while offset < len(user_data):
        chunk = user_data[offset:offset + 16]
        chunk_crc = compute_crc(chunk)
        chunks.append(chunk + struct.pack("<H", chunk_crc))
        offset += len(chunk)

    return header + b"".join(chunks)


def decode_data_link_frame(buf: bytes) -> Optional[Tuple[int, int, int, bytes, bytes]]:
    """
    Decodes the first valid IEEE 1815 DNP3 Data Link frame from buffer.
    Returns (dest, src, ctrl, user_data, remaining_buffer) or None if incomplete.
    """
    while len(buf) >= 10:
        # Search for sync bytes 0x05 0x64
        sync_idx = buf.find(b"\x05\x64")
        if sync_idx == -1:
            return None
        if sync_idx > 0:
            buf = buf[sync_idx:]

        if len(buf) < 10:
            return None

        # Parse header
        length, ctrl, dest, src = struct.unpack("<BBHH", buf[2:8])
        hdr_crc = struct.unpack("<H", buf[8:10])[0]
        expected_hdr_crc = compute_crc(buf[0:8])

        if hdr_crc != expected_hdr_crc:
            # Bad CRC, skip sync and retry
            buf = buf[2:]
            continue

        user_data_len = length - 5
        if user_data_len < 0:
            buf = buf[2:]
            continue

        # Calculate expected frame length including chunk CRCs
        full_chunks = user_data_len // 16
        remainder = user_data_len % 16
        total_data_with_crc = full_chunks * 18 + (remainder + 2 if remainder > 0 else 0)
        total_frame_len = 10 + total_data_with_crc

        if len(buf) < total_frame_len:
            # Incomplete frame, wait for more data
            return None

        # Extract user data blocks and verify chunk CRCs
        user_data = bytearray()
        offset = 10
        valid = True

        for _ in range(full_chunks):
            chunk = buf[offset:offset + 16]
            chunk_crc = struct.unpack("<H", buf[offset + 16:offset + 18])[0]
            if compute_crc(chunk) != chunk_crc:
                valid = False
                break
            user_data.extend(chunk)
            offset += 18

        if valid and remainder > 0:
            chunk = buf[offset:offset + remainder]
            chunk_crc = struct.unpack("<H", buf[offset + remainder:offset + remainder + 2])[0]
            if compute_crc(chunk) != chunk_crc:
                valid = False
            else:
                user_data.extend(chunk)
                offset += remainder + 2

        if not valid:
            buf = buf[2:]
            continue

        remaining = buf[total_frame_len:]
        return dest, src, ctrl, bytes(user_data), remaining

    return None


def build_read_integrity_request(app_seq: int = 0) -> bytes:
    """
    Builds a Class 0, 1, 2, 3 Read Request (Integrity Poll).
    Transport layer: 0xC0 | (seq & 0x3F)
    Application layer: App Control (0xC0 | seq), Function (0x01 READ),
    Object headers for Group 60 Vars 1, 2, 3, 4 (Qualifier 0x06 All).
    """
    transport_hdr = bytes([0xC0 | (app_seq & 0x3F)])
    app_ctrl = 0xC0 | (app_seq & 0x0F)
    app_header = bytes([app_ctrl, FC_READ])

    # Request Class 1, 2, 3 (events) and Class 0 (static current values)
    objects = bytes([
        GROUP_CLASS_OBJECTS, VAR_CLASS_1, QUAL_ALL_OBJECTS,
        GROUP_CLASS_OBJECTS, VAR_CLASS_2, QUAL_ALL_OBJECTS,
        GROUP_CLASS_OBJECTS, VAR_CLASS_3, QUAL_ALL_OBJECTS,
        GROUP_CLASS_OBJECTS, VAR_CLASS_0, QUAL_ALL_OBJECTS,
    ])

    return transport_hdr + app_header + objects


def build_direct_operate_crob(point_index: int, control_code: int,
                              count: int = 1, on_time_ms: int = 1000,
                              off_time_ms: int = 0, app_seq: int = 0) -> bytes:
    """
    Builds a Direct Operate request for a CROB point (Group 12 Variation 1).
    Used to TRIP (0x04 or 0x02) or CLOSE (0x03 or 0x01) circuit breakers.
    """
    transport_hdr = bytes([0xC0 | (app_seq & 0x3F)])
    app_ctrl = 0xC0 | (app_seq & 0x0F)
    app_header = bytes([app_ctrl, FC_DIRECT_OPERATE])

    # Object Header: Group 12 Var 1, Qualifier 0x00 (1-octet index start/stop)
    obj_hdr = bytes([GROUP_CROB, VAR_CROB, QUAL_1OCTET_INDEX, point_index, point_index])
    crob_payload = struct.pack("<BBIIB", control_code, count, on_time_ms, off_time_ms, 0x00)

    return transport_hdr + app_header + obj_hdr + crob_payload


def build_outstation_response(binary_inputs: Dict[int, bool],
                               analog_inputs: Dict[int, float],
                               app_seq: int = 0,
                               iin1: int = 0x00, iin2: int = 0x00) -> bytes:
    """
    Builds a complete DNP3 Application Response (0x81) containing:
    - Internal Indications IIN1, IIN2
    - Group 1 Var 2 (Binary Inputs with flags)
    - Group 30 Var 5 (Analog Inputs 32-bit float with flags)
    """
    transport_hdr = bytes([0xC0 | (app_seq & 0x3F)])
    app_ctrl = 0xC0 | (app_seq & 0x0F)
    app_header = bytes([app_ctrl, FC_RESPONSE, iin1, iin2])

    payload = bytearray(transport_hdr + app_header)

    # 1. Binary Inputs (Group 1 Var 2)
    if binary_inputs:
        num_bi = len(binary_inputs)
        # Qualifier 0x00: 1-octet range
        payload.extend([GROUP_BINARY_INPUT, VAR_BI_WITH_FLAGS, QUAL_1OCTET_INDEX, 0, num_bi - 1])
        for idx in range(num_bi):
            state = binary_inputs.get(idx, False)
            flag = FLAG_ONLINE | (FLAG_STATE if state else 0x00)
            payload.append(flag)

    # 2. Analog Inputs (Group 30 Var 5: 32-bit single precision IEEE float)
    if analog_inputs:
        num_ai = len(analog_inputs)
        payload.extend([GROUP_ANALOG_INPUT, VAR_AI_FLOAT32, QUAL_1OCTET_INDEX, 0, num_ai - 1])
        for idx in range(num_ai):
            val = float(analog_inputs.get(idx, 0.0))
            flag = FLAG_ONLINE  # 0x01
            payload.append(flag)
            payload.extend(struct.pack("<f", val))

    return bytes(payload)


def parse_app_response(user_data: bytes) -> Dict[str, Any]:
    """
    Parses a DNP3 Application Response frame from user data.
    Extracts IIN indications, Binary Inputs, and Analog Inputs.
    """
    res = {
        "function_code": None,
        "app_seq": None,
        "iin1": 0,
        "iin2": 0,
        "binary_inputs": {},
        "analog_inputs": {},
        "crob_status": None,
    }

    if len(user_data) < 4:
        return res

    # Skip Transport Header (1 byte)
    app_ctrl = user_data[1]
    func_code = user_data[2]
    res["app_seq"] = app_ctrl & 0x0F
    res["function_code"] = func_code

    if func_code != FC_RESPONSE and func_code != FC_UNSOLICITED_RESPONSE:
        return res

    res["iin1"] = user_data[3]
    res["iin2"] = user_data[4]

    offset = 5
    while offset < len(user_data):
        if offset + 3 > len(user_data):
            break

        grp = user_data[offset]
        var = user_data[offset + 1]
        qual = user_data[offset + 2]
        offset += 3

        if qual == QUAL_1OCTET_INDEX:
            if offset + 2 > len(user_data):
                break
            start_idx = user_data[offset]
            stop_idx = user_data[offset + 1]
            offset += 2

            count = (stop_idx - start_idx) + 1
            if count <= 0:
                continue

            # Group 1 Var 2 (Binary Input with flags)
            if grp == GROUP_BINARY_INPUT and var == VAR_BI_WITH_FLAGS:
                for pt in range(start_idx, stop_idx + 1):
                    if offset >= len(user_data):
                        break
                    flag = user_data[offset]
                    res["binary_inputs"][pt] = bool(flag & FLAG_STATE)
                    offset += 1

            # Group 30 Var 5 (Analog Input float32)
            elif grp == GROUP_ANALOG_INPUT and var == VAR_AI_FLOAT32:
                for pt in range(start_idx, stop_idx + 1):
                    if offset + 5 > len(user_data):
                        break
                    _flag = user_data[offset]
                    val = struct.unpack("<f", user_data[offset + 1:offset + 5])[0]
                    res["analog_inputs"][pt] = round(val, 3)
                    offset += 5

            # Group 30 Var 2 (Analog Input int16)
            elif grp == GROUP_ANALOG_INPUT and var == VAR_AI_16BIT:
                for pt in range(start_idx, stop_idx + 1):
                    if offset + 3 > len(user_data):
                        break
                    _flag = user_data[offset]
                    val = struct.unpack("<h", user_data[offset + 1:offset + 3])[0]
                    res["analog_inputs"][pt] = float(val)
                    offset += 3

            # Group 12 Var 1 (CROB response status)
            elif grp == GROUP_CROB and var == VAR_CROB:
                for _pt in range(start_idx, stop_idx + 1):
                    if offset + 11 > len(user_data):
                        break
                    _ctrl_code, _cnt, _on, _off, status = struct.unpack("<BBIIB", user_data[offset:offset + 11])
                    res["crob_status"] = status
                    offset += 11
            else:
                # Unknown group, cannot reliably determine size
                break
        else:
            # Non-1-octet qualifiers not handled in basic response parser
            break

    return res


class DNP3MasterClient:
    """Manages persistent TCP DNP3 Master communications to an Outstation."""

    def __init__(self, name: str, host: str, port: int, dnp3_addr: int, master_addr: int = 1):
        self.name = name
        self.host = host
        self.port = port
        self.dnp3_addr = dnp3_addr
        self.master_addr = master_addr
        self.sock = None
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
                return True
            except Exception:
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
            except Exception:
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

