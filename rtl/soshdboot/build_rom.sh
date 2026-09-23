#!/usr/bin/env bash
# Assemble the soshdboot ROM into the hex image simulation loads and the MIF
# Quartus loads, as upstream's winmake.bat does. Needs ca65 and ld65 (cc65).
# Writes to the directory given, or next to this script.
set -euo pipefail
out=$(cd "${1:-$(dirname "$0")}" && pwd)
cd "$(dirname "$0")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for part in diskio saratests monitor; do
	ca65 "$part.s" -o "$tmp/$part.o"
done
ld65 -C apple3hdboot.cfg "$tmp/diskio.o" "$tmp/saratests.o" "$tmp/monitor.o" -o "$tmp/apple3hdboot.rom"
xxd -p -c 1 "$tmp/apple3hdboot.rom" > "$out/apple3hdboot.hex"
python3 ../../tools/hex2mif.py "$out/apple3hdboot.hex" "$out/apple3hdboot.mif"
