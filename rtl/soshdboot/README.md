# soshdboot ROM

Rob Justice's hard-disk boot ROM for the Apple ///, from
[robjustice/soshdboot](https://github.com/robjustice/soshdboot/tree/154107c3dcf2e2084a60a1de1ade033d00fffb51),
commit `154107c` (2025-03-24). The ROM last changed in `4f7c6a2`
(2023-06-04), "attempt to boot floppy if error from blockdev". The OSD's
**Boot ROM** option selects it in place of Apple's ROM.

`diskio.s`, `saratests.s` and `monitor.s` are upstream's `src/rom/` and
`apple3hdboot.cfg` is its `build/apple3.cfg`, unchanged. They are Apple's
boot ROM listing with Rob's changes: the user memory test is gone, and the
freed space holds a search of slots 4 to 1 for a ProDOS block-mode card whose
block 0 is loaded and run. `build_rom.sh` assembles them as upstream's
`winmake.bat` does, into `apple3hdboot.hex` for simulation and
`apple3hdboot.mif` for Quartus. The result is byte for byte upstream's
`rom/apple3hdboot.rom`:

| Size | SHA-1 |
|---|---|
| 4096 | `7fb5fa601ced449fe88e3a9c4a12c83e825bfdd9` |

Upstream is GPL-3.0; see [COPYING](COPYING). Apple's code in it remains
Apple's. [Block card notes](../../docs/BLOCK_STORAGE.md) describe booting
from the card.
