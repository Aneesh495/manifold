# manifold Verification Suite & Benchmark Results

This document describes the verification methodology, test harness structure, test coverage matrix, and performance benchmark results for the `manifold` In-Vehicle Network Central Gateway.

---

## 1. Verification Strategy

The project employs a three-tier verification harness executed under strict compiler constraints (`-std=c11 -Wall -Wextra -Wpedantic`):

1. **Unit Tests (`tests/unit/`)**: Granular validation of core data structures, frame serialization, CRC algorithms, transport framing, UDS service dispatchers, DoIP session handshakes, SOME/IP serializers, and XCP memory navigation.
2. **Integration Tests (`tests/integration/`)**: End-to-end multi-bus cross-domain routing, DBC signal extraction, token bucket traffic shaping, priority egress queues, and SecOC cryptographic authentication.
3. **Performance Benchmarks (`tests/bench_runner.ec`)**: High-throughput microbenchmarks evaluating operations per second and latency percentiles.

---

## 2. Test Execution & Coverage Summary

Executing `make test` runs the comprehensive 39-test verification suite:

```
================================================================
       manifold In-Vehicle Gateway Verification Suite           
================================================================
  [RUN ] ByteBuffer dynamic append and bounds ... [PASS]
  [RUN ] RingBuffer push/pop and overrun telemetry ... [PASS]
  [RUN ] BitStream Intel/Motorola bit extraction and sign extension ... [PASS]
  [RUN ] CAN & CAN FD Frame initialization, padding, and candump ... [PASS]
  [RUN ] CAN CRC-15, CAN FD CRC-17, and CAN FD CRC-21 algorithms ... [PASS]
  [RUN ] CAN Controller mailbox filters, TEC/REC, and Bus-Off recovery ... [PASS]
  [RUN ] Virtual CAN Transceiver priority arbitration & loopback ... [PASS]
  [RUN ] LIN 2.2 PID parity generation and enhanced checksum ... [PASS]
  [RUN ] ISO-TP Single Frame (SF) transmission & reassembly ... [PASS]
  [RUN ] ISO-TP CAN FD Large Single Frame (SF_DL > 7) ... [PASS]
  [RUN ] ISO-TP Multi-Frame First Frame, Flow Control CTS & CF rollover ... [PASS]
  [RUN ] DTC status byte transitions and debounce qualification ... [PASS]
  [RUN ] UDS Service 0x19 (ReadDTC) and Service 0x14 (ClearDTC) ... [PASS]
  [RUN ] DTC non-volatile wear-leveling flash persistence ... [PASS]
  [RUN ] DoIP Generic Header encoding, decoding & pattern NACK ... [PASS]
  [RUN ] DoIP Vehicle Announcement and EID/VIN discovery filtering ... [PASS]
  [RUN ] DoIP Routing Activation handshake and alive check watchdog ... [PASS]
  [RUN ] DoIP Diagnostic Message encapsulation and logical routing ... [PASS]
  [RUN ] SOME/IP Header framing, byte swapping, and type-safe serializer ... [PASS]
  [RUN ] SOME/IP-SD Offer Service, Find Service, and Eventgroup subscription ... [PASS]
  [RUN ] SOME/IP RPC method dispatching and event notification publish ... [PASS]
  [RUN ] XCP CONNECT, DISCONNECT, GET_STATUS, and GET_ID state machine ... [PASS]
  [RUN ] XCP Memory MTA navigation, UPLOAD, DOWNLOAD, and CHECKSUM ... [PASS]
  [RUN ] XCP Calibration Page switching, ECU execution mapping & mirroring ... [PASS]
  [RUN ] XCP Dynamic DAQ/ODT allocation and microsecond timestamp streaming ... [PASS]
  [RUN ] Gateway multi-bus routing rules, frame translation, and filtering ... [PASS]
  [RUN ] Traffic shaper token bucket rate limiting and priority egress queue ... [PASS]
  [RUN ] DBC signal bitfield encoding/decoding (Intel/Motorola & physical scaling) ... [PASS]
  [RUN ] Cross-domain CAN FD to SOME/IP bridge with SecOC MAC authentication ... [PASS]
  [RUN ] Regression: CAN FD 29-bit identifier and stuff bit bounds ... [PASS]
  [RUN ] Regression: ISO-TP zero-length reject and FC overflow abort ... [PASS]
  [RUN ] Regression: UDS Security Access brute-force lockout threshold ... [PASS]
  [RUN ] Regression: DoIP concurrent socket limit and NACK recovery ... [PASS]
  [RUN ] Regression: XCP MTA boundary violations and checksum overflow ... [PASS]
  [RUN ] Regression: SecOC monotonic freshness rollover and verification ... [PASS]
  [RUN ] Catalog: Diagnostic Trouble Code (DTC) and UDS DID query resolution ... [PASS]
  [RUN ] Fuzzing: CAN FD CRC-17 and CRC-21 randomized bit corruption ... [PASS]
  [RUN ] Fuzzing: SOME/IP deserializer randomized corrupt payload safety ... [PASS]
  [RUN ] Fuzzing: DoIP generic header parser randomized payload safety ... [PASS]
----------------------------------------------------------------
Test Results: 39 passed, 0 failed in 2.40 ms
================================================================
```

---

## 3. High-Throughput Performance Benchmarks

Executing `make bench` runs the hardware-accelerated benchmark suite:

```
========================================================================================
           manifold High-Throughput In-Vehicle Gateway Benchmark Suite          
========================================================================================
  Benchmark Subsystem                Iterations   Elapsed Time         Throughput
  --------------------------------------------------------------------------------------
  CAN FD CRC-21 Engine                   500000      691.21 ms       0.72 Mops/s (  44.2 MB/s)
  SecOC AES-128 CMAC Signatures           50000      377.88 ms     132.32 Kops/s
  Gateway Bitmask Route Match           1000000       45.05 ms      22.20 Mops/s
  SOME/IP Type-Safe Serialization        500000       17.96 ms      27.84 Mops/s
========================================================================================
```

### Key Performance Highlights:
- **Routing Decision Throughput**: 22.20 million route decisions per second (<46 nanoseconds per packet).
- **SOME/IP Serialization**: 27.84 million serializations per second (<36 nanoseconds per packet).
- **SecOC Cryptographic Throughput**: 132,320 AES-128 CMAC signatures per second on bare metal.
- **CAN FD CRC-21 Calculation**: 44.2 MB/s throughput with Gray code stuff bit tracking.

---

## 4. Reproducing Results Locally

Any engineer can clone and verify the complete codebase in seconds with zero external dependencies:

```bash
# Clone the repository
git clone https://github.com/Aneesh495/manifold.git
cd manifold

# Build all binaries (daemon, terminal, test suite, benchmark harness)
make all

# Run complete 39-test verification suite
make test

# Run performance benchmarks
make bench

# Launch interactive diagnostic terminal
./bin/manifold_terminal

# Run simulated multi-ECU virtual vehicle gateway
./bin/manifold -n 50
```
