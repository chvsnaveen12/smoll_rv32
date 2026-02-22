VERILATOR = verilator
VERILATOR_FLAGS = --binary --timing --trace -j 4 --top-module plic_tb -Wall -Wno-fatal

SV_SRCS = plic.sv plic_tb.sv

.PHONY: all run clean

all: obj_dir/Vplic_tb

obj_dir/Vplic_tb: $(SV_SRCS)
	$(VERILATOR) $(VERILATOR_FLAGS) $(SV_SRCS)

run: obj_dir/Vplic_tb
	./obj_dir/Vplic_tb

clean:
	rm -rf obj_dir *.vcd
