#!/usr/bin/env bash
# Block-storage card tests: register/transfer bench, firmware image check and
# the whole-core diagnostic. Needs Icarus Verilog, Verilator, cc65 and GHDL.
set -euo pipefail
cd "$(dirname "$0")/../.."
out=sim/blockdev/obj_dir
mkdir -p "$out"
# The committed firmware hex must match its source.
rtl/cards/build_firmware.sh "$out/firmware.hex"
if ! cmp -s "$out/firmware.hex" rtl/cards/apple3_block_firmware.hex; then
  echo "rtl/cards/apple3_block_firmware.hex is stale; run rtl/cards/build_firmware.sh" >&2
  exit 1
fi
if ! iverilog -g2012 -s block_card_tb -o "$out/block_card_tb" \
  rtl/cards/apple3_block_card.sv sim/blockdev/block_card_tb.sv >"$out/unit-build.log" 2>&1; then
  cat "$out/unit-build.log"
  exit 1
fi
vvp "$out/block_card_tb"
ca65 sim/blockdev/diagnostic.s -o "$out/diagnostic.o" -l "$out/diagnostic.lst"
ld65 -C sim/serial/rom.cfg "$out/diagnostic.o" -o "$out/diagnostic.rom"
xxd -p -c 1 "$out/diagnostic.rom" > "$out/diagnostic.hex"
if [[ ! -f sim/gen/t65.v || ! -f sim/gen/via6522.v ]]; then ./sim/gen_vhdl.sh; fi
if ! verilator --binary --timing -j 4 --top-module core_block_tb \
  -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-TIMESCALEMOD \
  --Mdir "$out/core" \
  sim/gen/t65.v sim/gen/via6522.v \
  rtl/disk/apple3_p6.sv rtl/disk/apple3_disk_sequencer.sv rtl/apple3_mmu.sv \
  rtl/apple3_timing.sv rtl/apple3_ram.sv rtl/apple3_rom.sv rtl/apple3_extaddr.sv \
  rtl/apple3_keyboard.sv rtl/apple3_io.sv rtl/apple3_rtc.sv \
  rtl/acia/gen_uart.v rtl/apple3_acia.sv rtl/apple3_disk.sv rtl/apple3_video.sv \
  rtl/apple3_slots.sv rtl/apple3_slot_rom.sv rtl/cards/apple3_block_card.sv rtl/apple3_core.sv \
  sim/blockdev/core_block_tb.sv >"$out/core-build.log" 2>&1; then
  cat "$out/core-build.log"
  exit 1
fi
"$out/core/Vcore_block_tb"
