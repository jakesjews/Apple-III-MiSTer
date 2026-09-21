#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p sim/obj_dir
iverilog -g2012 -Wall -s mmu_tb -o sim/obj_dir/mmu_tb \
	rtl/apple3_mmu.sv sim/mmu_tb.sv
vvp sim/obj_dir/mmu_tb

iverilog -g2012 -Wall -s timing_tb -o sim/obj_dir/timing_tb \
	rtl/apple3_timing.sv sim/timing_tb.sv
vvp sim/obj_dir/timing_tb

iverilog -g2012 -Wall -s storage_tb -o sim/obj_dir/storage_tb \
	rtl/apple3_ram.sv rtl/apple3_extaddr.sv sim/storage_tb.sv
vvp sim/obj_dir/storage_tb

iverilog -g2012 -Wall -s video_tb -o sim/obj_dir/video_tb \
	rtl/apple3_video.sv sim/video_tb.sv
vvp sim/obj_dir/video_tb

iverilog -g2012 -Wall -s composite_tb -o sim/obj_dir/composite_tb \
	rtl/apple3_composite.sv sim/composite_tb.sv
vvp sim/obj_dir/composite_tb

iverilog -g2012 -Wall -s keyboard_tb -o sim/obj_dir/keyboard_tb \
	rtl/apple3_keyboard.sv sim/keyboard_tb.sv
vvp sim/obj_dir/keyboard_tb

iverilog -g2012 -Wall -s io_tb -o sim/obj_dir/io_tb \
	rtl/apple3_io.sv sim/io_tb.sv
vvp sim/obj_dir/io_tb

iverilog -g2012 -Wall -s rtc_acia_tb -o sim/obj_dir/rtc_acia_tb \
	rtl/apple3_rtc.sv rtl/acia/gen_uart.v rtl/apple3_acia.sv sim/rtc_acia_tb.sv
vvp sim/obj_dir/rtc_acia_tb

iverilog -g2012 -Wall -s disk_tb -o sim/obj_dir/disk_tb \
	rtl/disk/apple3_p6.sv rtl/disk/apple3_disk_sequencer.sv rtl/apple3_disk.sv sim/disk_tb.sv
vvp sim/obj_dir/disk_tb

iverilog -g2012 -Wall -s acia_tb -o sim/obj_dir/acia_tb \
	rtl/acia/gen_uart.v rtl/apple3_acia.sv sim/acia_tb.sv
vvp sim/obj_dir/acia_tb

iverilog -g2012 -Wall -s acia_baud_tb -o sim/obj_dir/acia_baud_tb \
	rtl/acia/gen_uart.v rtl/apple3_acia.sv sim/acia_baud_tb.sv
vvp sim/obj_dir/acia_baud_tb

./sim/disk/run.sh
./sim/memmap/run.sh
./sim/slots/run.sh
./sim/blockdev/run.sh
./sim/mouse/run.sh
./sim/timing/run.sh
