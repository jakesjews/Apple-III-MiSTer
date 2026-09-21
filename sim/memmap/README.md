# Memory-map tests

Run `./sim/memmap/run.sh` from the repository root; `make test-quick` includes
it. It needs Icarus Verilog, Verilator with timing support, ca65/ld65, Python 3
and the GHDL output the other whole-core tests use. Generated files stay in the
ignored `obj_dir/`.

`prom_reference.py` is a model of the main logic board's CPU-cycle decode with
either of Apple's memory boards, built from the PROM dumps and the schematic
wiring between them, not from the RTL. It checks the dumps' hashes, names every
DRAM cell through the documented map (262,144 on the 5 V / 256 KiB board,
131,072 on the 12 V / 128 KiB one), resolves every other kind of access to the
cells it reaches, and derives RAMEN, the RAM read and write enables and the
ROM, VIA and I/O selects from sheet 5's gates with 342-0045 and 342-0046.
`--report` prints the map it derives, `--board 128` for the 12 V board.

`memmap_prom_tb.sv` drives `apple3_mmu` with 171,160 vectors from it per board:
every page under every bank register value, zero page and both stacks for
every zero-page register value, every X byte, and the decode of `$A000` up in
every combination of ROM enable, stack, write protection and I/O enable, in
native and Apple II mode, with and without an X byte, and through a zero page
register that names I/O, the ROM or a VIA. Reads and writes both.

The dumps are not redistributed. Set `APPLE3_PROM_DIR` to the unpacked
[bitsavers `A3PROMs`](http://bitsavers.org/pdf/apple/apple_III/firmware/A3PROMs.zip)
directory; the archive.org and asimov file names are accepted too. The 12 V
board's `341-0042.bin` and `341-0044.bin` are only in
[archive.org `AppleIIIROMs`](https://archive.org/details/AppleIIIROMs): set
`APPLE3_PROM_12V_DIR` to that directory, or put them with the others. Without
the dumps this part, or its 128 KiB half, is skipped.

`core_memmap_tb.sv` runs `diagnostic.s` on the real CPU, VIAs, bank latch and
RAM, and needs no dumps. The program writes through one view of memory and
reads through another across each boundary: bank pairs and the byte where they
meet, `$8F` with the RAM under the VIAs, I/O and ROM, `$87` and `$8E` as Apple's
boards see them, the missing bank behind `$86:8000`, the three-bit bank
register, and the relocated zero page and stacks. It then runs the latch cases
that need a real 6502: the opcode after a store to the bank register coming
from the old bank, and a PLA at `$00FF` pulling through the X byte of its own
opcode fetch; reads a slot, the ROM and a VIA through the zero-page register;
and asks the bench for the 128 KiB board and a reset to check its absent banks.
It fails with its phase number.

See [the memory map](../../docs/MEMORY_MAP.md) for the sources, the findings and
what remains unverified.
