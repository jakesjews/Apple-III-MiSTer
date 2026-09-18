#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
out=sim/timing/obj_dir
mkdir -p "$out"
ca65 sim/timing/diagnostic.s -o "$out/diagnostic.o"
ld65 -C sim/serial/rom.cfg "$out/diagnostic.o" -o "$out/diagnostic.rom"
xxd -p -c 1 "$out/diagnostic.rom" > "$out/diagnostic.hex"
./sim/gen_vhdl.sh >"$out/vhdl.log"
if ! verilator --binary --timing -j 4 --top-module core_timing_tb \
  -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-TIMESCALEMOD \
  --Mdir "$out/core" \
  sim/gen/t65.v sim/gen/via6522.v \
  rtl/disk/apple3_p6.sv rtl/disk/apple3_disk_sequencer.sv rtl/apple3_mmu.sv \
  rtl/apple3_timing.sv rtl/apple3_ram.sv rtl/apple3_rom.sv rtl/apple3_extaddr.sv \
  rtl/apple3_keyboard.sv rtl/apple3_io.sv rtl/apple3_rtc.sv \
  rtl/acia/gen_uart.v rtl/apple3_acia.sv rtl/apple3_disk.sv rtl/apple3_video.sv \
  rtl/apple3_slots.sv rtl/apple3_slot_rom.sv rtl/apple3_core.sv \
  sim/timing/core_timing_tb.sv >"$out/build.log" 2>&1; then
  cat "$out/build.log"
  exit 1
fi
"$out/core/Vcore_timing_tb"
