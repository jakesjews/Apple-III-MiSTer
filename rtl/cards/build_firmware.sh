#!/usr/bin/env bash
# Assemble the block card's ProDOS firmware into the hex image the RTL loads.
# Needs ca65 and ld65 (cc65). Run from any directory.
set -euo pipefail
out=$(cd "$(dirname "${1:-.}")" && pwd)/$(basename "${1:-apple3_block_firmware.hex}")
cd "$(dirname "$0")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ca65 apple3_block_firmware.s -o "$tmp/firmware.o" -l "$tmp/firmware.lst"
ld65 -C apple3_block_firmware.cfg "$tmp/firmware.o" -o "$tmp/firmware.bin"
xxd -p -c 1 "$tmp/firmware.bin" > "$out"
