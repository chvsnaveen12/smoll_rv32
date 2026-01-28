VERILATOR = verilator
CXX = g++

VERILATOR_FLAGS = --cc --exe --build --trace -I. -I..
CXXFLAGS = -std=c++14

TOP_MODULE = core_fsm

SOURCES = core_defs.sv \
	   core_alu.sv \
	   core_csrs.sv \
	   core_fsm.sv \
	   core_lsu.sv \
	   core_decoder.sv \
	   core_regs.sv

CPP_SRC = core_tb.cpp
SIM_SRC = core_sim.cpp

OBJ_DIR = obj_dir
EXE = $(OBJ_DIR)/V$(TOP_MODULE)
SIM_EXE = $(OBJ_DIR)/Vcore_sim

.PHONY: all build run sim sim_build clean

all: build run

build: $(EXE)

sim_build: $(SIM_EXE)

$(EXE): $(SOURCES) $(CPP_SRC)
	$(VERILATOR) $(VERILATOR_FLAGS) --top-module $(TOP_MODULE) $(CPP_SRC) $(SOURCES)

$(SIM_EXE): $(SOURCES) $(SIM_SRC)
	$(VERILATOR) $(VERILATOR_FLAGS) --top-module $(TOP_MODULE) $(SIM_SRC) $(SOURCES) -o Vcore_sim

run: $(EXE)
	./$(EXE) $(ARGS)

sim: $(SIM_EXE)
	./$(SIM_EXE) $(ARGS)

clean:
	rm -rf $(OBJ_DIR)
	rm -rf *.vcd
