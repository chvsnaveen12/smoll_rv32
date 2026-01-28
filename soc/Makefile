# Verilator Makefile for SoC Simulation

# Tools
VERILATOR = verilator
CXX = g++

# Flags
VERILATOR_FLAGS = --cc --exe --build -j 0 --trace -I. -I../core -I../uart -I../cache -I../xip -I../spi --Wno-lint --timing --top-module soc_harness
CXX_FLAGS = -std=c++14 -Wall -fcoroutines

# Files
SV_SRCS = ../core/core_defs.sv soc_harness.sv soc.sv ../core/core_fsm.sv ../core/core_alu.sv ../core/core_lsu.sv ../core/core_regs.sv ../uart/uart.sv ../cache/cache.sv ../cache/axi_ram.v ../spi/spi.sv ../xip/xip.sv sim_flash.v
CPP_SRCS = soc_tb.cpp

# Targets
.PHONY: all build run clean

all: build

build: obj_dir/Vsoc_harness

obj_dir/Vsoc_harness: $(SV_SRCS) $(CPP_SRCS)
	$(VERILATOR) $(VERILATOR_FLAGS) $(SV_SRCS) $(CPP_SRCS)

run: build
	./obj_dir/Vsoc_harness

clean:
	rm -rf obj_dir
	rm -f *.vcd
