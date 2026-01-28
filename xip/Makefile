# Tools
VERILATOR = verilator
CXX = g++

# Flags
VERILATOR_FLAGS = --cc --exe --build -j 0 --trace -I.
CXX_FLAGS = -std=c++14

# Files
TOP_MODULE = spi_harness
SV_SOURCES = spi_harness.sv \
             xip.sv \
             sim_flash.v

CPP_TB = spi_tb.cpp

# Output
OBJ_DIR = obj_dir
EXE = $(OBJ_DIR)/V$(TOP_MODULE)

# Targets
.PHONY: all build run clean

all: build run

build: $(EXE)

$(EXE): $(SV_SOURCES) $(CPP_TB)
	$(VERILATOR) $(VERILATOR_FLAGS) --Wno-lint --timing --top-module $(TOP_MODULE) $(CPP_TB) $(SV_SOURCES)

run: $(EXE)
	./$(EXE) $(ARGS)

clean:
	rm -rf $(OBJ_DIR)
	rm -f *.vcd
