#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f research/roms/apple3.rom ]]; then
	echo "research/roms/apple3.rom is required for the ROM boot test" >&2
	exit 1
fi

mkdir -p sim/gen
xxd -p -c 1 research/roms/apple3.rom > sim/gen/apple3.rom.hex
./sim/gen_vhdl.sh >/dev/null

sources=(
	sim/coretest/core_tb.sv sim/gen/t65.v sim/gen/via6522.v
	sim/coretest/dpram_model.sv rtl/disk/floppy_track.sv
	rtl/disk/dsk_nibblizer.sv
	rtl/disk/drive_ii.v rtl/apple3_mmu.sv rtl/apple3_timing.sv
	rtl/apple3_ram.sv rtl/apple3_rom.sv rtl/apple3_extaddr.sv
	rtl/apple3_keyboard.sv rtl/apple3_io.sv rtl/apple3_rtc.sv
	rtl/apple3_acia.sv rtl/apple3_disk.sv rtl/apple3_video.sv
	rtl/apple3_core.sv sim/coretest/main.cpp
)

verilator --cc --exe --build -j 4 -O2 --top-module core_tb \
	-CFLAGS "-O3" \
	-MAKEFLAGS "OPT_FAST=-O3 OPT_SLOW=-O3 OPT_GLOBAL=-O3" \
	-Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME \
	--Mdir sim/coretest/obj_dir "${sources[@]}" -o Vcore_tb
sim/coretest/obj_dir/Vcore_tb "$@"
