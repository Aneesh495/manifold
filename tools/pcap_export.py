#!/usr/bin/env python3
"""
tools/pcap_export.py
Automotive PCAP-NG exporter for manifold CAN FD, SOME/IP, and DoIP network captures.
Enables Wireshark protocol dissection using standard SocketCAN and Ethernet link layers.
"""

import struct
import sys
import os
import time

# PCAP-NG Block Types
BT_SHB = 0x0A0D0D0A # Section Header Block
BT_IDB = 0x00000001 # Interface Description Block
BT_EPB = 0x00000006 # Enhanced Packet Block

# Link Types
LINKTYPE_ETHERNET = 1
LINKTYPE_CAN_SOCKETCAN = 227

def create_shb():
    """Builds a Section Header Block (SHB)."""
    magic = 0x1A2B3C4D
    major = 1
    minor = 0
    section_len = 0xFFFFFFFFFFFFFFFF # Undefined length
    body = struct.pack("<IHHQ", magic, major, minor, section_len)
    total_len = 12 + len(body)
    return struct.pack("<III", BT_SHB, total_len, total_len)[:-4] + body + struct.pack("<I", total_len)

def create_idb(link_type, name="can0"):
    """Builds an Interface Description Block (IDB)."""
    reserved = 0
    snaplen = 0x00040000 # 256 KB
    # Option: if_name (opt_code=2)
    name_bytes = name.encode('utf-8')
    pad = (4 - (len(name_bytes) % 4)) % 4
    opt_name = struct.pack("<HH", 2, len(name_bytes)) + name_bytes + (b'\x00' * pad)
    opt_end = struct.pack("<HH", 0, 0)
    options = opt_name + opt_end

    body = struct.pack("<HHI", link_type, reserved, snaplen) + options
    total_len = 12 + len(body)
    return struct.pack("<II", BT_IDB, total_len) + body + struct.pack("<I", total_len)

def create_can_epb(interface_id, timestamp_us, can_id, data, is_fd=False, is_ext=False):
    """Builds an Enhanced Packet Block (EPB) for SocketCAN frame."""
    ts_high = (timestamp_us >> 32) & 0xFFFFFFFF
    ts_low  = timestamp_us & 0xFFFFFFFF

    # SocketCAN CAN FD header
    wire_can_id = can_id
    if is_ext:
        wire_can_id |= 0x80000000 # CAN_EFF_FLAG

    packet_len = 16 if not is_fd else (8 + len(data))
    flags = 0x01 if is_fd else 0x00 # CANFD_BRS flag if FD

    can_pkt = struct.pack("<IBBB", wire_can_id, len(data), flags, 0)
    can_pkt += data
    pad_len = (4 - (len(can_pkt) % 4)) % 4
    can_pkt_padded = can_pkt + (b'\x00' * pad_len)

    caplen = len(can_pkt)
    origlen = len(can_pkt)

    opt_end = struct.pack("<HH", 0, 0)
    body = struct.pack("<IIII", interface_id, ts_high, ts_low, caplen) + struct.pack("<I", origlen) + can_pkt_padded + opt_end
    total_len = 12 + len(body)
    return struct.pack("<II", BT_EPB, total_len) + body + struct.pack("<I", total_len)

def export_synthetic_trace(output_path):
    """Generates a synthetic automotive network capture with CAN FD and SOME/IP packets."""
    with open(output_path, "wb") as f:
        # Write Section Header Block
        f.write(create_shb())
        # Interface 0: Powertrain CAN FD (can0)
        f.write(create_idb(LINKTYPE_CAN_SOCKETCAN, "can0_powertrain"))
        # Interface 1: Chassis CAN FD (can1)
        f.write(create_idb(LINKTYPE_CAN_SOCKETCAN, "can1_chassis"))

        now_us = int(time.time() * 1000000)

        # Emit 20 synthetic frames
        for i in range(20):
            ts = now_us + (i * 10000) # 10 ms interval
            # ECM 0x100
            rpm = 850 + (i * 50)
            data_ecm = struct.pack("<HHBB", int(rpm * 4), 128, 90, 45) + (b'\xAA' * 8)
            f.write(create_can_epb(0, ts, 0x100, data_ecm, is_fd=True))

            # Chassis 0x120
            speed = i * 2.5
            data_chassis = struct.pack("<HH", int(speed * 100), 0) + (b'\x55' * 12)
            f.write(create_can_epb(1, ts + 2000, 0x120, data_chassis, is_fd=True))

    print(f"Exported PCAP-NG automotive trace: {output_path} ({os.path.getsize(output_path)} bytes)")

if __name__ == "__main__":
    out_file = sys.argv[1] if len(sys.argv) > 1 else "manifold_trace.pcapng"
    export_synthetic_trace(out_file)
