#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
out=sim/memmap/obj_dir
mkdir -p "$out"

# The PROM dumps are not redistributed; without them only the real-CPU
# diagnostic runs.  The 12 V board's two PROMs are not in the bitsavers set.
proms=${APPLE3_PROM_DIR:-research/docs/bitsavers/A3PROMs}
proms_12v=${APPLE3_PROM_12V_DIR:-research/roms/archive.org_AppleIIIROMs}
have() {
  local part=$1 dir
  shift
  for dir in "$@"; do
    [[ -f "$dir/$part-A.BIN" || -f "$dir/$part.bin" || -f "$dir/AppleIII_prom_$part.bin" ]] && return 0
  done
  return 1
}
: > "$out/vectors.txt"
if have 342-0061 "$proms" && have 342-0045 "$proms"; then
  python3 sim/memmap/prom_reference.py --prom-dir "$proms" --board 256 --vectors "$out/vectors-256.txt"
  cat "$out/vectors-256.txt" >> "$out/vectors.txt"
  if have 341-0044 "$proms" "$proms_12v"; then
    python3 sim/memmap/prom_reference.py --prom-dir "$proms" --prom-dir "$proms_12v" --board 128 \
      --vectors "$out/vectors-128.txt"
    cat "$out/vectors-128.txt" >> "$out/vectors.txt"
  else
    echo "SKIP 128 KiB PROM comparison: set APPLE3_PROM_12V_DIR to the 341-0042 and 341-0044 dumps"
  fi
  if ! iverilog -g2012 -s memmap_prom_tb -o "$out/memmap_prom_tb" \
    rtl/apple3_mmu.sv sim/memmap/memmap_prom_tb.sv >"$out/unit-build.log" 2>&1; then
    cat "$out/unit-build.log"
    exit 1
  fi
  vvp -n "$out/memmap_prom_tb" "+VECTORS=$out/vectors.txt"
else
  echo "SKIP decoder PROM comparison: set APPLE3_PROM_DIR to unpacked A3PROMs"
fi

ca65 sim/memmap/diagnostic.s -o "$out/diagnostic.o" -l "$out/diagnostic.lst"
ld65 -C sim/serial/rom.cfg "$out/diagnostic.o" -o "$out/diagnostic.rom"
xxd -p -c 1 "$out/diagnostic.rom" > "$out/diagnostic.hex"
if [[ ! -f sim/gen/t65.v || ! -f sim/gen/via6522.v ]]; then ./sim/gen_vhdl.sh; fi
if ! verilator --binary --timing -j 4 --top-module core_memmap_tb \
  -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-TIMESCALEMOD \
  --Mdir "$out/core" \
  sim/gen/t65.v sim/gen/via6522.v \
  rtl/disk/apple3_p6.sv rtl/disk/apple3_disk_sequencer.sv rtl/apple3_mmu.sv \
  rtl/apple3_timing.sv rtl/apple3_ram.sv rtl/apple3_rom.sv rtl/apple3_extaddr.sv \
  rtl/apple3_keyboard.sv rtl/apple3_io.sv rtl/apple3_rtc.sv \
  rtl/acia/gen_uart.v rtl/apple3_acia.sv rtl/apple3_disk.sv rtl/apple3_video.sv \
  rtl/apple3_slots.sv rtl/apple3_slot_rom.sv rtl/apple3_core.sv \
  sim/memmap/core_memmap_tb.sv >"$out/core-build.log" 2>&1; then
  cat "$out/core-build.log"
  exit 1
fi
"$out/core/Vcore_memmap_tb"
