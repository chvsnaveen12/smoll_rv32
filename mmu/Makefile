# Verilator Makefile for SoC Simulation

# Tools
VERILATOR = verilator
CXX = g++

# Flags
VERILATOR_FLAGS = --cc --exe --build -j 4 --trace -I. -I../core --timing --top-module mmu_tb --x-initial unique
CXX_FLAGS = -std=c++14 -O3 -Wall -fcoroutines

# Files
SV_SRCS = ../core/core_defs.sv mmu_tb.sv ../core/core_fsm.sv ../core/core_alu.sv ../core/core_lsu.sv ../core/core_regs.sv
CPP_SRCS = mmu_tb.cpp

# Targets
.PHONY: all build run clean

all: build

build: obj_dir/Vsoc_harness

obj_dir/Vsoc_harness: $(SV_SRCS) $(CPP_SRCS)
	$(VERILATOR) $(VERILATOR_FLAGS) $(SV_SRCS) $(CPP_SRCS)

run: build
	./obj_dir/Vmmu_tb

clean:
	rm -rf obj_dir
	rm -f *.vcd
