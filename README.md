# smoll_rv32

RV32IMA RISC-V core. Boots Linux with BusyBox rootfs on a Nexys A7 100T FPGA.

## Demo

<video src="demo.mp4" controls width="640"></video>

Linux booting on the core on Nexys A7 100T.

## Features

- RV32IMA, machine + supervisor + user modes
- Sv32 MMU with 1-entry ITLB and 1-entry DTLB
- CLINT, PLIC, UART, SPI, XIP, cache, bootrom
- Verilator simulation and Vivado synthesis

## Repo layout

- `core/` CPU
- `mmu/` Sv32 MMU
- `cache/` cache
- `clint/` CLINT
- `plic/` PLIC
- `uart/` UART
- `spi/` SPI
- `xip/` XIP flash controller
- `bootrom/` boot ROM
- `soc/` SoC top, Verilator testbench
- `wrapper/` FPGA wrapper and constraints
- `riscof/` RISCOF compliance
- `prebuilt/` prebuilt binaries (see below)

## Quick start with prebuilts

You can skip rebuilding the software. Prebuilt binaries are in `prebuilt/`:

- `fw_dynamic.bin` OpenSBI firmware
- `Image` Linux kernel
- `dts.dtb` device tree blob
- `firmware.hex` bootrom image for Verilator sim
- `emu` RV32 emulator binary

### Run in Verilator

```
cd soc
cp ../prebuilt/firmware.hex firmware.hex
make run
```

### Run on emulator

```
./prebuilt/emu <firmware>
```

### Run on FPGA

Load `fw_dynamic.bin`, `Image`, and `dts.dtb` onto the SPI flash, synthesize the wrapper in Vivado, and program the Nexys A7 100T bitstream.

## Build from source

To rebuild the software stack (OpenSBI, Linux, device tree, emulator), see [smoll_rv32_sw](../smoll_rv32_sw).

## License

MIT. See `LICENSE`.
