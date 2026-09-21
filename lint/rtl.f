// Run from the repository root after make lint-prepare.
// Match Quartus VERILOG_FILE parsing for .v sources.
+1364-2005ext+v
// Supply a default for modules without a timescale; preserve explicit ones.
--timescale 1ns/1ps

// Read the warning policy and dependency exclusions before sources.
lint/exclusions.vlt
+incdir+lint/gen
+incdir+sys
-y sys
// The Hq2x module name does not match its lowercase library filename.
sys/hq2x.sv
// sys_umul and sys_udiv, which video_freak uses, live in math.sv.
sys/math.sv

// Lint-only PLL boundary and GHDL-converted VHDL dependencies.
lint/pll.sv
sim/gen/t65.v
sim/gen/via6522.v

// Verilog/SystemVerilog sources from files.qip; keep this list in sync.
// RAM/ROM use their existing behavioral branches, as in simulation.
rtl/disk/apple3_p6.sv
rtl/disk/apple3_disk_sequencer.sv
rtl/disk/apple3_woz_drive.sv
rtl/disk/woz/flux_drive.v
rtl/disk/woz/woz_cell525.sv
rtl/disk/woz/woz_bram.sv
rtl/disk/woz/woz_floppy_controller.sv
rtl/apple3_timing.sv
rtl/apple3_mmu.sv
rtl/apple3_ram.sv
rtl/apple3_rom.sv
rtl/apple3_extaddr.sv
rtl/apple3_keyboard.sv
rtl/apple3_rtc.sv
rtl/acia/gen_uart.v
rtl/apple3_acia.sv
rtl/apple3_io.sv
rtl/apple3_disk.sv
rtl/apple3_video.sv
rtl/apple3_composite.sv
rtl/apple3_slots.sv
rtl/apple3_slot_rom.sv
rtl/cards/apple3_block_card.sv
rtl/apple3_core.sv
Apple-III.sv
