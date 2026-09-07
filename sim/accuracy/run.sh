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
run_case keyboard_accuracy rtl/apple3_keyboard.sv
run_case disk_protection rtl/apple3_disk.sv rtl/disk/drive_ii.v
run_case rtc_accuracy rtl/apple3_rtc.sv

# Optional source-binary checks. PROM dumps are intentionally not redistributed.
proms=${APPLE3_PROM_DIR:-research/docs/bitsavers/A3PROMs}
if [[ -f "$proms/341-0030.BIN" && -f "$proms/342-0046-A.BIN" ]]; then
  xxd -p -c 1 "$proms/341-0030.BIN" > "$out/scan.hex"
  xxd -p -c 1 "$proms/342-0046-A.BIN" > "$out/timing.hex"
  if iverilog -g2012 -s timing_prom_tb -o "$out/timing_prom" \
      rtl/apple3_timing.sv sim/accuracy/timing_prom_tb.sv > "$out/timing_prom.compile.log" 2>&1; then
    if ! vvp "$out/timing_prom" "+SCAN=$out/scan.hex" "+TIMING=$out/timing.hex" > "$out/timing_prom.log" 2>&1; then
      failures=$((failures+1))
    fi
    cat "$out/timing_prom.log"
  else
    cat "$out/timing_prom.compile.log"
    failures=$((failures+1))
  fi
else
  echo "SKIP timing PROM comparison: set APPLE3_PROM_DIR to unpacked A3PROMs"
fi
echo "Accuracy test groups failing: $failures"
test "$failures" -eq 0
