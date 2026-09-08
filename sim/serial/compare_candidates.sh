#!/bin/bash
# Fetch pinned, unmodified candidates into ignored research/ and print the
# selection comparison. Expected failures are reported by the diagnostic bench.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=research/acia-candidates
mkdir -p "$work"
curl -fLsS --max-time 30 https://raw.githubusercontent.com/gyurco/apple2efpga/518f05fba289fa7effe9d7a46a38a856d01c06e0/gen_uart.v -o "$work/gen_uart.v"
for file in uart_6551.v 6551tx.v 6551rx.v; do
  curl -fLsS --max-time 30 "https://raw.githubusercontent.com/MiSTer-devel/Apple-II_MiSTer/96980455374321293dcbbb91ff9d08b116571772/rtl/ssc/$file" -o "$work/$file"
done
iverilog -g2012 -s candidate_tb -o "$work/new_tb" "$work/gen_uart.v" sim/serial/candidate_tb.sv
vvp "$work/new_tb"
iverilog -g2012 -DOLD -s candidate_tb -o "$work/old_tb" "$work/uart_6551.v" "$work/6551tx.v" "$work/6551rx.v" sim/serial/candidate_tb.sv
vvp "$work/old_tb"
