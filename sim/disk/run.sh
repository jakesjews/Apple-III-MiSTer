#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
out=sim/obj_dir/disk
mkdir -p "$out"
python3 sim/disk/make_fixture.py
iverilog -g2012 -s cell_tb -o "$out/cell" rtl/disk/woz/woz_cell525.sv sim/disk/cell_tb.sv
vvp "$out/cell"
prom=${APPLE3_DISK_PROM:-research/roms/archive.org_AppleIIIROMs/341-0028.bin}
if [[ -f "$prom" ]]; then
  xxd -p -c 1 "$prom" > "$out/p6.hex"
  iverilog -g2012 -s sequencer_tb -o "$out/sequencer" \
    rtl/disk/apple3_p6.sv rtl/disk/apple3_disk_sequencer.sv sim/disk/sequencer_tb.sv
  vvp "$out/sequencer" "+PROM=$out/p6.hex"
else
  echo "SKIP original P6 comparison: set APPLE3_DISK_PROM to a 256-byte 341-0028 dump"
fi
build() {
  local name=$1
  shift
  if ! verilator --binary --timing -j 4 -Wno-fatal -Wno-WIDTH \
    --top-module "${name}_tb" --Mdir "$out/$name" "$@" "sim/disk/${name}_tb.sv" \
    > "$out/$name.build.log" 2>&1; then
    cat "$out/$name.build.log"
    return 1
  fi
}
build woz_image rtl/disk/woz/woz_bram.sv rtl/disk/woz/woz_floppy_controller.sv
for version in 1 2 2-large; do
  if ! "$out/woz_image/Vwoz_image_tb" "+IMAGE=$out/fixture$version.woz" > "$out/woz$version.log" 2>&1; then
    cat "$out/woz$version.log"
    exit 1
  fi
  rg '^PASS' "$out/woz$version.log"
done
build drive rtl/disk/woz/flux_drive.v rtl/disk/woz/woz_cell525.sv
"$out/drive/Vdrive_tb"
build four_drive rtl/disk/apple3_woz_drive.sv rtl/disk/woz/flux_drive.v rtl/disk/woz/woz_cell525.sv rtl/disk/woz/woz_bram.sv rtl/disk/woz/woz_floppy_controller.sv
"$out/four_drive/Vfour_drive_tb" > "$out/four_drive.log" 2>&1 || { cat "$out/four_drive.log"; exit 1; }
rg '^PASS' "$out/four_drive.log"
