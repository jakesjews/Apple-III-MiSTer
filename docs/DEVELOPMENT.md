# Development notes

> The core, tests and documentation were developed with AI assistance under
> human direction and tested on a DE10-Nano. Broad compatibility is still
> being established.

The core is an original hardware model. It was built from Apple's Level 2
Service Reference Manual and motherboard schematics, decoded logic PROMs,
Apple's patents, the SOS 1.3 and console driver sources, and programs known to
run on real machines. MAME's driver was used as a cross-check rather than as the
specification. The design notes in [design notes](DESIGN.md) map each
behaviour to its source.

## Hardware implemented

- 6502 with the Apple /// 1 MHz and 2 MHz cycle scheduling and video and
  refresh contention.
- The stock 256 KiB memory board with the bank register, relocatable zero page
  and stack, sister-byte reads, write protection and extended addressing.
- 4 KiB boot ROM in either motherboard bank, or an 8 KiB dual-bank image.
- All native video modes: 40 and 80 column text, 280 and 560 pixel monochrome,
  140 pixel sixteen colour and 280 pixel foreground/background colour, plus the
  Apple II text, lores and hires modes used by the emulation disk.
- Downloadable character generator, inverse and flashing attributes, page
  selection, screen blanking and smooth vertical scrolling.
- Both 6522 VIAs, the keyboard encoder with its repeat behaviour, the MM58167
  clock, joystick switches and analog inputs, speaker, bell and six-bit audio.
- The Disk /// controller's P6 sequencer, internal drive and one external drive,
  including native WOZ bitstreams and quarter-track mapping.
- A 6551 ACIA on the serial port, connected to MiSTer's HPS UART.

## Boot ROM details

Apple's boot ROM is copyrighted and is not included in the repository or the
core. MiSTer sends `games/Apple-III/boot.rom` to the core every time the core
starts, and the machine stays in reset until a ROM has arrived. The stock image
is the 4,096-byte ROM MAME calls `apple3.rom`:

| Size | CRC32 | SHA-1 |
|---|---|---|
| 4096 | `1af7ec42` | `8043f914ebdcdab9838dbb78f8a2ee3867d210d2` |

A widely circulated copy differs in 48 bytes that sit underneath the VIA
registers and boots identically. An 8,192-byte image is treated as two 4 KiB
banks selected by environment register bit 1, which is how custom dual-bank
ROMs are laid out. **Load Boot ROM** in the OSD replaces the ROM until the core
is reloaded.

## Serial port

The ACIA connects to MiSTer's HPS UART, `/dev/ttyS1`. Set the Apple /// software
and the host to the same baud rate and frame format; the MiSTer UART menu offers
the common rates and the ACIA implements all fifteen internal dividers.

**Serial CTS** defaults to **Always ready** so the stock ROM's self-test passes
when no host program has the UART open. Choose **Host RTS** for hardware flow
control; the host must assert RTS before the machine boots in that mode. MiSTer
has no separate carrier-detect line, so DCD is held asserted. See
[rtl/acia/README.md](../rtl/acia/README.md) for the provenance of the 6551 core
and [sim/serial/README.md](../sim/serial/README.md) for the serial tests.

## Building

The validated build uses Quartus Prime 17.0.2. `build.sh` drives
Quartus under CrossOver on macOS; on Windows or Linux open `Apple-III.qpf` in
Quartus and compile.

```sh
./build.sh map        # synthesis only
./build.sh compile    # full flow, writes output_files/Apple-III.rbf
```

The `sys/` directory is an unmodified copy of
[Template_MiSTer](https://github.com/MiSTer-devel/Template_MiSTer).

## Formatting

With `verible-verilog-format`, Python 3.9+ and Git on
`PATH`, run from the repository root:

```sh
make format-check                       # read-only; fails if formatting differs
make format                             # apply formatting
make format FILES='rtl/apple3_acia.sv'
```

`make` lists the commands. The same operations are available through
`python3 tools/verible.py format|format-check [files...]`; explicit paths
are relative to the calling directory. `format-check` returns nonzero when
formatting differs; both commands return nonzero on tool errors.

The project scope is the `Apple-III.sv` wrapper and Verilog/SystemVerilog sources
and headers under `rtl/` and `sim/`, including new, untracked files. Ignored files,
generated PLL/simulation output and VHDL are excluded. The MiSTer `sys/` framework
is always excluded.

Formatting also excludes all vendored files in `rtl/acia/` and `rtl/disk/woz/`
to preserve readable diffs against upstream. Explicit file selection uses the same scope,
so even `make format FILES='rtl/acia/gen_uart.v'` is rejected without changes.

The configuration follows the [MiSTer development principles](https://mister-devel.github.io/MkDocs_MiSTer/developer/principles/)
and [template source layout](https://github.com/MiSTer-devel/Template_MiSTer):
tab indentation and aligned declarations/ports/assignments. The formatter settings live in
`.verible-format.flags`, with a 120-column target and alignment groups separated
by blank lines or section comments. Use a current Verible release supporting
`--alignment_group_boundary` (validated with `v0.0-4219-g3275ab72`).

Verible emits spaces, so the wrapper expands leading tabs at four-column stops
before formatting and restores them afterward, retaining spaces for alignment.
It protects string/comment contents and `verilog_format: off/on` regions.
The long Quartus `defparam` tables in `apple3_ram.sv` and `apple3_rom.sv` use
these markers because Verible otherwise exhausts its line-wrapping search.
`.editorconfig` uses the same tab width. Use the wrapper for formatting; invoking
Verible directly with the flags file produces space indentation.

The simulations below check hardware behaviour. No Quartus build or MiSTer
connection is needed for formatting.

## Testing

The simulation flow needs Icarus Verilog, Verilator, GHDL, a C++ compiler and
`xxd`. GHDL converts the VHDL components to Verilog so Verilator can simulate the
whole machine. The boot tests read the ROM from `APPLE3_ROM`.

```sh
./sim/run_tests.sh                      # unit benches: MMU, timing, memory,
                                        # video, keyboard, I/O, RTC, ACIA, disk
bash sim/accuracy/run.sh                # documentation-derived checks
./sim/disk/run.sh                       # P6, WOZ parser/writeback, drive timing
APPLE3_ROM=apple3.rom ./sim/run_core_boot.sh 30000000
APPLE3_ROM=apple3.rom ./sim/run_core_boot.sh 400000000 system.woz --woz
APPLE3_ROM=apple3.rom ./sim/run_core_boot.sh 1400000000 sysutils.woz --keytest
```

`run_core_boot.sh` runs the stock ROM on the integrated machine and checks that
reset, memory sizing, reconfiguration and the disk bootstrap happen. With a WOZ
image it follows SOS to the interpreter through the real track cache.
`--drive2=blank.woz` mounts a second drive on the shared transfer bus;
`--sd-delay=71590` adds 5 ms of host latency per request. `--keytest` drives System Utilities with
injected PS/2 keys and decodes the text page after each. See
[sim/accuracy/README.md](../sim/accuracy/README.md) for the PROM-based timing
comparison and the 6502 functional test.

See [Main storage integration](MAIN_STORAGE.md) for the companion Main patch and
[Disk III validation](DISK_FIDELITY_2026-09-16.md) for the tested hardware build.
