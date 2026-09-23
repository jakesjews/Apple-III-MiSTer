#!/usr/bin/env bash
# Boot the built-in soshdboot ROM from the block card with no floppy. Block 0
# of the generated hard disk is a jump to itself at $A000, so the test needs
# no disk image; the harness fails unless the ROM read the card and ran it.
set -euo pipefail
cd "$(dirname "$0")/../.."
image=sim/blockdev/obj_dir/soshdboot.po
mkdir -p sim/blockdev/obj_dir
python3 -c 'import sys; open(sys.argv[1], "wb").write(bytes([0x4c, 0x00, 0xa0]).ljust(64 * 512, b"\0"))' "$image"
./sim/run_core_boot.sh 30000000 - --soshdboot --block-boot --hd1="$image"
