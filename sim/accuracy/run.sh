#!/usr/bin/env bash
# Verification only: failed checks remain failures until the core is corrected.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
out=sim/obj_dir/accuracy
mkdir -p "$out"
failures=0
run_case() {
  local name=$1
  shift
  if ! iverilog -g2012 -s "${name}_tb" -o "$out/$name" "$@" \
      "sim/accuracy/${name}_tb.sv" > "$out/$name.compile.log" 2>&1; then
    cat "$out/$name.compile.log"
    failures=$((failures+1))
  elif ! vvp "$out/$name" > "$out/$name.log" 2>&1; then
    cat "$out/$name.log"
    failures=$((failures+1))
  else
    cat "$out/$name.log"
  fi
}
run_case video_accuracy rtl/apple3_video.sv
run_case video_fetch rtl/apple3_timing.sv rtl/apple3_ram.sv rtl/apple3_video.sv
run_case video_source rtl/apple3_timing.sv rtl/apple3_ram.sv rtl/apple3_video.sv rtl/apple3_composite.sv
run_case peripheral_timing rtl/apple3_timing.sv
run_case interlace rtl/apple3_timing.sv rtl/apple3_ram.sv rtl/apple3_video.sv
run_case keyboard_accuracy rtl/apple3_keyboard.sv
run_case disk_protection rtl/apple3_disk.sv rtl/disk/apple3_p6.sv rtl/disk/apple3_disk_sequencer.sv
run_case rtc_accuracy rtl/apple3_rtc.sv
run_case joystick_accuracy rtl/apple3_io.sv

# Optional source-binary checks. PROM dumps are intentionally not redistributed.
proms=${APPLE3_PROM_DIR:-research/docs/bitsavers/A3PROMs}
if [[ -f "$proms/341-0030.BIN" && -f "$proms/342-0046-A.BIN" ]]; then
  xxd -p -c 1 "$proms/341-0030.BIN" > "$out/scan.hex"
  xxd -p -c 1 "$proms/342-0046-A.BIN" > "$out/timing.hex"
  for name in timing_prom timing_control_prom; do
    if iverilog -g2012 -s "${name}_tb" -o "$out/$name" \
        rtl/apple3_timing.sv "sim/accuracy/${name}_tb.sv" > "$out/$name.compile.log" 2>&1; then
      if ! vvp "$out/$name" "+SCAN=$out/scan.hex" "+TIMING=$out/timing.hex" > "$out/$name.log" 2>&1; then
        failures=$((failures+1))
      fi
      cat "$out/$name.log"
    else
      cat "$out/$name.compile.log"
      failures=$((failures+1))
    fi
  done
else
  echo "SKIP timing PROM comparison: set APPLE3_PROM_DIR to unpacked A3PROMs"
fi

# The Apple /// Plus interlace scan PROM, against the stock one for the other field.
plus_prom=${APPLE3_PLUS_PROM:-research/roms/archive.org_AppleIIIROMs/342-0145-A.bin}
if [[ -f "$proms/341-0030.BIN" && -f "$plus_prom" ]]; then
  xxd -p -c 1 "$plus_prom" > "$out/plus.hex"
  if iverilog -g2012 -s interlace_prom_tb -o "$out/interlace_prom" rtl/apple3_timing.sv rtl/apple3_video.sv \
      sim/accuracy/interlace_prom_tb.sv > "$out/interlace_prom.compile.log" 2>&1; then
    if ! vvp "$out/interlace_prom" "+SCAN=$out/scan.hex" "+PLUS=$out/plus.hex" > "$out/interlace_prom.log" 2>&1; then
      failures=$((failures+1))
    fi
    cat "$out/interlace_prom.log"
  else
    cat "$out/interlace_prom.compile.log"
    failures=$((failures+1))
  fi
else
  echo "SKIP interlace PROM comparison: set APPLE3_PLUS_PROM to the 342-0145-A dump"
fi
echo "Accuracy test groups failing: $failures"
test "$failures" -eq 0
