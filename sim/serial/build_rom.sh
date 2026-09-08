#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p sim/serial/obj_dir
ca65 sim/serial/echo.s -o sim/serial/obj_dir/echo.o
ld65 -C sim/serial/rom.cfg sim/serial/obj_dir/echo.o -o sim/serial/obj_dir/echo.rom
# Both 4 KiB ROM banks must be loaded by MiSTer's F2 ROM download.
python3 - <<'PY'
from pathlib import Path
rom = Path('sim/serial/obj_dir/echo.rom').read_bytes()
assert len(rom) == 4096
Path('sim/serial/obj_dir/echo.bin').write_bytes(rom * 2)
Path('sim/serial/obj_dir/echo.hex').write_text(''.join(f'{b:02x}\n' for b in rom))
PY
