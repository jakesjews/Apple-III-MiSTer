// Run from the repository root after make lint-prepare.
// Match Quartus VERILOG_FILE parsing for .v sources.
+1364-2005ext+v

// Read exclusions before sources. These do not waive core RTL warnings.
lint/exclusions.vlt
+incdir+lint/gen
+incdir+sys
-y sys
// The Hq2x module name does not match its lowercase library filename.
sys/hq2x.sv

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
rtl/apple3_core.sv
Apple-III.sv
