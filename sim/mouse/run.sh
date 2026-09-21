#!/usr/bin/env bash
# Mouse card bench: SOS's mouse driver sequences against the card.
set -euo pipefail
cd "$(dirname "$0")/../.."
out=sim/mouse/obj_dir
mkdir -p "$out"
if ! verilator --binary --timing -j 4 --top-module mouse_card_tb \
  -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-TIMESCALEMOD \
  +incdir+rtl/cards/mouse/jt6805 --Mdir "$out/card" \
  rtl/cards/mouse/pia6821.v rtl/cards/mouse/jt6805/jt6805.v \
  rtl/cards/mouse/jt6805/jt6805_alu.v rtl/cards/mouse/jt6805/jt6805_ctrl.v \
  rtl/cards/mouse/jt6805/jt6805_regs.v rtl/cards/mouse/jt6805/jtframe_6805mcu.v \
  rtl/cards/apple3_mouse_card.sv sim/mouse/mouse_card_tb.sv >"$out/build.log" 2>&1; then
  cat "$out/build.log"
  exit 1
fi
"$out/card/Vmouse_card_tb" | tee "$out/run.log"
grep -q "mouse_card_tb: PASS" "$out/run.log"
