#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# The stock boot ROM is rtl/apple3_rom.hex; APPLE3_ROM names another 4 KiB
# image, such as the soshdboot ROM.
mkdir -p sim/gen
if [[ -n ${APPLE3_ROM:-} ]]; then
	if [[ ! -f $APPLE3_ROM || $(wc -c < "$APPLE3_ROM" | tr -d " ") != 4096 ]]; then
		echo "APPLE3_ROM must be a 4096-byte boot ROM image (missing or wrong size: $APPLE3_ROM)" >&2
		exit 1
	fi
	xxd -p -c 1 "$APPLE3_ROM" > sim/gen/apple3.rom.hex
else
	cp rtl/apple3_rom.hex sim/gen/apple3.rom.hex
fi
./sim/gen_vhdl.sh >/dev/null

sources=(
	sim/coretest/core_tb.sv sim/gen/t65.v sim/gen/via6522.v
		rtl/disk/apple3_woz_drive.sv rtl/disk/woz/flux_drive.v rtl/disk/woz/woz_cell525.sv rtl/disk/woz/woz_bram.sv rtl/disk/woz/woz_floppy_controller.sv
	rtl/disk/apple3_p6.sv rtl/disk/apple3_disk_sequencer.sv rtl/apple3_mmu.sv rtl/apple3_timing.sv
	rtl/apple3_ram.sv rtl/apple3_rom.sv rtl/apple3_extaddr.sv
	rtl/apple3_keyboard.sv rtl/apple3_io.sv rtl/apple3_rtc.sv
	rtl/acia/gen_uart.v rtl/apple3_acia.sv rtl/apple3_disk.sv rtl/apple3_video.sv rtl/apple3_composite.sv
	rtl/apple3_slots.sv rtl/apple3_slot_rom.sv rtl/cards/apple3_block_card.sv
	rtl/cards/mouse/pia6821.v rtl/cards/mouse/jt6805/jt6805_alu.v rtl/cards/mouse/jt6805/jt6805_ctrl.v
	rtl/cards/mouse/jt6805/jt6805_regs.v rtl/cards/mouse/jt6805/jt6805.v
	rtl/cards/mouse/jt6805/jtframe_6805mcu.v rtl/cards/apple3_mouse_card.sv rtl/apple3_core.sv
	# Absolute: Verilator before 5.03x looks for it from --Mdir.
	"$PWD/sim/coretest/main.cpp"
)

verilator --cc --exe --build -j 4 -O2 --top-module core_tb \
	-CFLAGS "-O3" \
	-MAKEFLAGS "OPT_FAST=-O3 OPT_SLOW=-O3 OPT_GLOBAL=-O3" \
	-Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME \
	+incdir+rtl/cards/mouse/jt6805 \
	--Mdir sim/coretest/obj_dir "${sources[@]}" -o Vcore_tb
sim/coretest/obj_dir/Vcore_tb "$@"
