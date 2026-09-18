#!/usr/bin/env bash
# Build the hardware test boot disks: sim/obj_dir/hwtest/<name>.po (140 KiB,
# ProDOS order, the program in block 0). Needs ca65 and ld65 from cc65.
set -euo pipefail
cd "$(dirname "$0")/../.."
out=sim/obj_dir/hwtest
mkdir -p "$out"
for source in sim/hwtest/*.s; do
	name=$(basename "$source" .s)
	ca65 -l "$out/$name.lst" -o "$out/$name.o" "$source"
	ld65 -C sim/hwtest/bootblock.cfg -o "$out/$name.bin" "$out/$name.o"
	cp "$out/$name.bin" "$out/$name.po"
	# Pad to 280 blocks. The ROM reads only block 0, so the rest can be empty.
	truncate -s 143360 "$out/$name.po"
	echo "$out/$name.po"
done
