# manifold

In-Vehicle Network (IVN) Central Gateway, CAN FD / SOME/IP / LIN Router, ISO 14229 UDS & ISO 13400 DoIP Diagnostic Stack, and ASAM XCP Calibration Engine in eC with C fastpath acceleration.

## Overview

Modern software-defined vehicles integrate multiple heterogeneous network domains: high-throughput Ethernet backbones (100/1000BASE-T1 running AUTOSAR SOME/IP), deterministically scheduled chassis/powertrain buses (CAN FD up to 5 Mbps), legacy body electronics networks (CAN 2.0B at 500 kbps, LIN 2.2 at 19.2 kbps), and diagnostic interfaces (ISO 14229 UDS over ISO-TP and ISO 13400 DoIP).

`manifold` is an industrial-grade in-vehicle central gateway and vehicle computing kernel written in eC with C fastpath acceleration. It provides wire-speed frame switching, signal-level repackaging, multi-session diagnostic routing, dynamic flash calibration, and cryptographic payload authentication.

```
       +-----------------------------------------------------------+
       |                  Central Gateway (CGW)                    |
       |                                                           |
       |  +--------------------+   +----------------------------+  |
       |  |  Routing & PDU     |   |  Diagnostic & Calibration  |  |
       |  |  Repackaging Core  |   |  Engine (UDS, DoIP, XCP)   |  |
       |  +---------+----------+   +--------------+-------------+  |
       |            |                             |                |
       |  +---------+----------+   +--------------+-------------+  |
       |  | Signal Engine &    |   | Security & Freshness       |  |
       |  | Motorola/Intel DBC |   | Manager (SecOC AES-CMAC)   |  |
       |  +---------+----------+   +--------------+-------------+  |
       +------------|-----------------------------|----------------+
                    |                             |
      +-------------+-------------+---------------+-------------+
      |                           |                             |
+-----+------+              +-----+------+               +------+-----+
|   CAN FD   |              |   SOME/IP  |               |    DoIP    |
| Powertrain |              |  Ethernet  |               | Diagnostic |
|   Subnet   |              |   Domain   |               |  Ethernet  |
+------------+              +------------+               +------------+
```

## Key Capabilities

1. **CAN 2.0B and CAN FD Framing Engine**: 
   Standard 11-bit and extended 29-bit arbitration, flexible data rate payloads (up to 64 bytes), Bit Rate Switch (BRS), Error State Indicator (ESI), and CRC-15/17/21 computation.
2. **ISO 15765-2 (ISO-TP) Transport Layer**:
   Single Frame (SF, including CAN FD large SF), First Frame (FF), Consecutive Frame (CF), and Flow Control (FC) with Block Size (BS) and Separation Time (STmin) adaptation.
3. **ISO 14229-1 (UDS) Diagnostic Stack**:
   Session control (0x10), ECU reset (0x11), Security Access (0x27) with cryptographic challenge-response, Read/Write DIDs (0x22, 0x2E), DTC retrieval (0x19), Clear DTCs (0x14), IO Control (0x2F), Routine Control (0x31), and firmware transfer (0x34, 0x36, 0x37).
4. **ISO 13400-2 (DoIP) Diagnostic over IP**:
   Vehicle announcement and discovery, routing activation with client authentication, alive check supervision, and diagnostic message dispatch to internal ECU clusters.
5. **AUTOSAR SOME/IP & Service Discovery**:
   RPC request/response, fire-and-forget, event notifications, type-safe serializers, and SOME/IP-SD offer/find/subscribe state machines.
6. **ASAM XCP Calibration & DAQ**:
   Universal Measurement and Calibration Protocol server, Command Transfer Objects (CTO), Data Transfer Objects (DTO), dynamic DAQ list allocation, microsecond event-triggered measurement streaming, and flash/RAM page switching.
7. **AUTOSAR SecOC Message Authentication**:
   Freshness Value Manager (FVM), anti-replay protection, and truncated AES-128 CMAC authentication.
8. **DBC Signal Database & Bitfield Codec**:
   High-performance Motorola (big endian) and Intel (little endian) bit extraction and physical value scaling.
9. **DTC & Fault Memory Manager**:
   ISO 14229 status byte debouncing, qualification thresholds, snapshot freeze-frame capture, fault aging counters, and simulated non-volatile storage.

## Building and Running

Prerequisites: A standard C/C++ compiler toolchain (`clang` or `gcc`) and GNU `make`.

```bash
# Build the entire manifold project
make all

# Run the comprehensive test suite
make test

# Launch the interactive in-vehicle diagnostic and bus terminal
./bin/manifold_terminal

# Run performance and latency benchmarks
make bench
```
