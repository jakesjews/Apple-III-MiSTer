#!/bin/bash
# Joystick read methods on the whole machine; see sim/joystick/adc.s.
# Optional argument: the number of joystick positions (default 256).
set -euo pipefail
cd "$(dirname "$0")/../.."
out=sim/joystick/obj_dir
mkdir -p "$out"
ca65 -l "$out/adc.lst" -o "$out/adc.o" sim/joystick/adc.s
ld65 -C sim/joystick/rom.cfg -o "$out/adc.rom" "$out/adc.o"
xxd -p -c 1 "$out/adc.rom" > "$out/adc.hex"
if [[ ! -f sim/gen/t65.v || ! -f sim/gen/via6522.v ]]; then ./sim/gen_vhdl.sh >/dev/null; fi
verilator --cc --exe --build -j 4 -O2 --top-module core_tb \
  "-GROM_FILE=\"$out/adc.hex\"" \
  -CFLAGS '-O3 -std=c++17' -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME \
  --Mdir "$out" \
  sim/coretest/core_tb.sv sim/gen/t65.v sim/gen/via6522.v \
  rtl/disk/apple3_woz_drive.sv rtl/disk/woz/flux_drive.v rtl/disk/woz/woz_cell525.sv rtl/disk/woz/woz_bram.sv rtl/disk/woz/woz_floppy_controller.sv \
  rtl/disk/apple3_p6.sv rtl/disk/apple3_disk_sequencer.sv rtl/apple3_mmu.sv rtl/apple3_timing.sv rtl/apple3_ram.sv \
  rtl/apple3_rom.sv rtl/apple3_extaddr.sv rtl/apple3_keyboard.sv rtl/apple3_io.sv \
  rtl/apple3_rtc.sv rtl/acia/gen_uart.v rtl/apple3_acia.sv rtl/apple3_disk.sv \
  rtl/apple3_video.sv rtl/apple3_composite.sv rtl/apple3_slots.sv rtl/apple3_slot_rom.sv rtl/cards/apple3_block_card.sv rtl/apple3_core.sv sim/joystick/main.cpp -o Vcore_tb >"$out/build.log"
"$out/Vcore_tb" "$@"
