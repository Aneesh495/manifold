# Master Makefile for manifold In-Vehicle Network Central Gateway
# Professional build configuration for macOS and Linux

CC ?= clang
CFLAGS ?= -std=c11 -Wall -Wextra -Wpedantic -O3 -fPIC
INCLUDES = -Iinclude -Iruntime -Ic_fastpath -Isrc

# Output directories
BIN_DIR = bin
OBJ_DIR = obj

# Tooling
PYTHON ?= python3
ECTRANS = $(PYTHON) tools/ectrans.py

# Source discovery
C_FASTPATH_SRCS = $(wildcard c_fastpath/*.c)
RUNTIME_SRCS = $(wildcard runtime/*.c)
EC_SRCS = $(wildcard src/*/*.ec src/*.ec tests/*/*.ec tests/*.ec)

C_FASTPATH_OBJS = $(patsubst c_fastpath/%.c,$(OBJ_DIR)/c_fastpath/%.o,$(C_FASTPATH_SRCS))
RUNTIME_OBJS = $(patsubst runtime/%.c,$(OBJ_DIR)/runtime/%.o,$(RUNTIME_SRCS))

# Binaries
TARGET_APP = $(BIN_DIR)/manifold
TARGET_TERMINAL = $(BIN_DIR)/manifold_terminal
TARGET_TEST = $(BIN_DIR)/manifold_test
TARGET_BENCH = $(BIN_DIR)/manifold_bench

.PHONY: all clean test bench run dirs help

all: dirs $(TARGET_APP) $(TARGET_TERMINAL) $(TARGET_TEST) $(TARGET_BENCH)

dirs:
	@mkdir -p $(BIN_DIR) $(OBJ_DIR)/c_fastpath $(OBJ_DIR)/runtime $(OBJ_DIR)/src $(OBJ_DIR)/tests

# Core C Fastpath compilation
$(OBJ_DIR)/c_fastpath/%.o: c_fastpath/%.c
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

# Runtime compilation
$(OBJ_DIR)/runtime/%.o: runtime/%.c
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

# Build Main Gateway Daemon
$(TARGET_APP): dirs $(C_FASTPATH_OBJS) $(RUNTIME_OBJS) $(OBJ_DIR)/src/manifold_core.o $(OBJ_DIR)/src/main.o
	$(CC) $(CFLAGS) $(INCLUDES) $(OBJ_DIR)/src/main.o $(OBJ_DIR)/src/manifold_core.o $(C_FASTPATH_OBJS) $(RUNTIME_OBJS) -o $@

# Build Diagnostic Terminal
$(TARGET_TERMINAL): dirs $(C_FASTPATH_OBJS) $(RUNTIME_OBJS) $(OBJ_DIR)/src/manifold_core.o $(OBJ_DIR)/src/DiagTerminal.o
	$(CC) $(CFLAGS) $(INCLUDES) $(OBJ_DIR)/src/DiagTerminal.o $(OBJ_DIR)/src/manifold_core.o $(C_FASTPATH_OBJS) $(RUNTIME_OBJS) -o $@

# Build Test Runner
$(TARGET_TEST): dirs $(C_FASTPATH_OBJS) $(RUNTIME_OBJS) $(OBJ_DIR)/src/manifold_core.o $(OBJ_DIR)/tests/test_runner.o
	$(CC) $(CFLAGS) $(INCLUDES) $(OBJ_DIR)/tests/test_runner.o $(OBJ_DIR)/src/manifold_core.o $(C_FASTPATH_OBJS) $(RUNTIME_OBJS) -o $@

# Build Benchmark Harness
$(TARGET_BENCH): dirs $(C_FASTPATH_OBJS) $(RUNTIME_OBJS) $(OBJ_DIR)/src/manifold_core.o $(OBJ_DIR)/tests/bench_runner.o
	$(CC) $(CFLAGS) $(INCLUDES) $(OBJ_DIR)/tests/bench_runner.o $(OBJ_DIR)/src/manifold_core.o $(C_FASTPATH_OBJS) $(RUNTIME_OBJS) -o $@

# Translation and compilation of eC sources
$(OBJ_DIR)/src/manifold_core.o: $(EC_SRCS)
	@$(ECTRANS) --bundle-src -o $(OBJ_DIR)/src/manifold_core.c
	$(CC) $(CFLAGS) $(INCLUDES) -c $(OBJ_DIR)/src/manifold_core.c -o $@

$(OBJ_DIR)/src/main.o: src/main.ec
	@$(ECTRANS) -i $< -o $(OBJ_DIR)/src/main.c
	$(CC) $(CFLAGS) $(INCLUDES) -c $(OBJ_DIR)/src/main.c -o $@

$(OBJ_DIR)/src/DiagTerminal.o: src/app/DiagTerminal.ec
	@$(ECTRANS) -i $< -o $(OBJ_DIR)/src/DiagTerminal.c
	$(CC) $(CFLAGS) $(INCLUDES) -c $(OBJ_DIR)/src/DiagTerminal.c -o $@

$(OBJ_DIR)/tests/test_runner.o: $(EC_SRCS)
	@$(ECTRANS) --bundle-tests -o $(OBJ_DIR)/tests/test_runner.c
	$(CC) $(CFLAGS) $(INCLUDES) -c $(OBJ_DIR)/tests/test_runner.c -o $@

$(OBJ_DIR)/tests/bench_runner.o: tests/bench_runner.ec
	@$(ECTRANS) -i $< -o $(OBJ_DIR)/tests/bench_runner.c
	$(CC) $(CFLAGS) $(INCLUDES) -c $(OBJ_DIR)/tests/bench_runner.c -o $@

test: $(TARGET_TEST)
	@echo "Executing manifold verification suite..."
	@$(TARGET_TEST)

bench: $(TARGET_BENCH)
	@echo "Executing manifold latency and throughput benchmarks..."
	@$(TARGET_BENCH)

run: $(TARGET_APP)
	@$(TARGET_APP)

clean:
	rm -rf $(OBJ_DIR) $(BIN_DIR)

help:
	@echo "manifold build targets:"
	@echo "  all      - Build all executables (gateway, terminal, tests, benchmarks)"
	@echo "  test     - Build and run the complete test suite"
	@echo "  bench    - Build and run latency benchmarks"
	@echo "  run      - Run the central gateway daemon"
	@echo "  clean    - Remove build artifacts"
