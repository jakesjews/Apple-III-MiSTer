#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

# The Apple /// boot ROM is not distributed; point APPLE3_ROM at a 4 KiB image.
rom=${APPLE3_ROM:-research/roms/apple3.rom}
if [[ ! -f $rom || $(wc -c < "$rom" | tr -d " ") != 4096 ]]; then
	echo "set APPLE3_ROM to the 4096-byte Apple /// boot ROM (missing or wrong size: $rom)" >&2
	exit 1
fi

mkdir -p sim/gen
xxd -p -c 1 "$rom" > sim/gen/apple3.rom.hex
./sim/gen_vhdl.sh >/dev/null

sources=(
	sim/coretest/core_tb.sv sim/gen/t65.v sim/gen/via6522.v
		rtl/disk/apple3_woz_drive.sv rtl/disk/woz/flux_drive.v rtl/disk/woz/woz_cell525.sv rtl/disk/woz/woz_bram.sv rtl/disk/woz/woz_floppy_controller.sv
	rtl/disk/apple3_p6.sv rtl/disk/apple3_disk_sequencer.sv rtl/apple3_mmu.sv rtl/apple3_timing.sv
	rtl/apple3_ram.sv rtl/apple3_rom.sv rtl/apple3_extaddr.sv
	rtl/apple3_keyboard.sv rtl/apple3_io.sv rtl/apple3_rtc.sv
	rtl/acia/gen_uart.v rtl/apple3_acia.sv rtl/apple3_disk.sv rtl/apple3_video.sv
	rtl/apple3_slots.sv rtl/apple3_slot_rom.sv rtl/cards/apple3_block_card.sv rtl/apple3_core.sv
	sim/coretest/main.cpp
)

verilator --cc --exe --build -j 4 -O2 --top-module core_tb \
	-CFLAGS "-O3" \
	-MAKEFLAGS "OPT_FAST=-O3 OPT_SLOW=-O3 OPT_GLOBAL=-O3" \
	-Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME \
	--Mdir sim/coretest/obj_dir "${sources[@]}" -o Vcore_tb
sim/coretest/obj_dir/Vcore_tb "$@"
