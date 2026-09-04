#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p sim/obj_dir
iverilog -g2012 -Wall -s mmu_tb -o sim/obj_dir/mmu_tb \
	rtl/apple3_mmu.sv sim/mmu_tb.sv
vvp sim/obj_dir/mmu_tb

iverilog -g2012 -Wall -s timing_tb -o sim/obj_dir/timing_tb \
	rtl/apple3_timing.sv sim/timing_tb.sv
vvp sim/obj_dir/timing_tb
