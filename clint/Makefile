VERILATOR = verilator
CXX = g++

VERILATOR_FLAGS = --cc --exe -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-CASEINCOMPLETE --build --trace -I. -I
CXX_FLAGS = -std=c++14

TOP_MODULE = clint

SOURCES = clint.sv

CPP_SRC = clint_tb.cpp

OBJ_DIR = obj_dir
EXE = $(OBJ_DIR)/V$(TOP_MODULE)

.PHONY: all build run clean

all: build run

build: $(EXE)

$(EXE): $(SOURCES) $(CPP_SRC)
	$(VERILATOR) $(VERILATOR_FLAGS) --top-module $(TOP_MODULE) $(CPP_SRC) $(SOURCES)

run: $(EXE)
	./$(EXE)

clean:
	rm -rf $(OBJ_DIR)
	rm -rf *.vcd
