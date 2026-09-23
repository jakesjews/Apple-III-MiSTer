# Development notes

> The core, tests and documentation were developed with AI assistance under
> human direction and tested on a DE10-Nano. Most software tried so far runs
> well; the README lists what has been checked.

The core is an original hardware model. It was built from Apple's Level 2
Service Reference Manual and motherboard schematics, decoded logic PROMs,
Apple's patents, the SOS 1.3 and console driver sources, and programs known to
run on real machines. MAME's driver was used as a cross-check rather than as the
specification. The design notes in [design notes](DESIGN.md) map each
behaviour to its source.

## Hardware implemented

- 6502 with the Apple /// 1 MHz and 2 MHz cycle scheduling and video and
  refresh contention, delayed onboard peripheral accesses, card RDY and
  [extended-state timing](PERIPHERAL_TIMING.md).
- The stock 256 KiB memory board with the bank register, relocatable zero page
  and stack, sister-byte reads, write protection and extended addressing.
- 4 KiB boot ROM in either motherboard bank, or an 8 KiB dual-bank image;
  Apple's ROM and the soshdboot hard-disk boot ROM are built in.
- All native video modes: 40 and 80 column text, 280 and 560 pixel monochrome,
  140 pixel sixteen colour and 280 pixel foreground/background colour, plus the
  Apple II text, lores and hires modes used by the emulation disk.
- Downloadable character generator, inverse and flashing attributes, page
  selection, screen blanking and smooth vertical scrolling.
- The [three video outputs](VIDEO_SOURCES.md): RGB, the NTSC colour encoder
  with a decoding monitor, and the black-and-white output's grey scale; and
  the monitors on the composite ones: clean, green and amber tubes, and a
  colour television.
- The Apple /// Plus [text interlace](INTERLACE.md): its scan PROM's two
  fields and the page each one shows.
- The Euro system's [50 Hz scan PROM](PAL.md): 310 lines and its later sync.
- Both 6522 VIAs, the keyboard encoder with its two repeat rates, the cursor
  keys' second contacts and the optional /// Plus DELETE key, the MM58167
  clock, the joysticks' 9708 A/D converter, buttons and latching switches,
  speaker, bell and six-bit audio.
- The Disk /// controller's P6 sequencer, internal drive and three external drives,
  including native WOZ bitstreams and quarter-track mapping.
- A 6551 ACIA on the serial port, connected to MiSTer's HPS UART.
- [Reusable slots 1–4](SLOTS.md): private I/O and ROM pages, per-card expansion
  ROM latches, individual IRQ status, VIA interrupt delivery and masked NMIs.
- A [virtual block-storage card](BLOCK_STORAGE.md) in slot 1: ProDOS
  block-mode firmware and two hard-disk images, used by SOS through the
  Problock3 driver and bootable with the built-in soshdboot ROM.
- Apple's [mouse card](MOUSE.md) in slot 4, its 68705 running Apple's program.
  Slots 2 and 3 are empty.

## Boot ROM details

Apple's stock boot ROM is built into the core, as `rtl/apple3_rom.hex` for
simulation and `rtl/apple3_rom.mif` for Quartus (`tools/hex2mif.py` makes the
second from the first, and `sim/run_tests.sh` checks that it has). It is the
4,096-byte ROM MAME calls `apple3.rom`:

| Size | CRC32 | SHA-1 |
|---|---|---|
| 4096 | `1af7ec42` | `8043f914ebdcdab9838dbb78f8a2ee3867d210d2` |

A widely circulated copy differs in 48 bytes that sit underneath the VIA
registers and boots identically. An 8,192-byte image is treated as two 4 KiB
banks selected by environment register bit 1, which is how custom dual-bank
ROMs are laid out.

**Boot ROM** selects Rob Justice's soshdboot ROM instead, also built in, in
both banks: `rtl/soshdboot/apple3hdboot.hex` and `.mif`, which
`rtl/soshdboot/build_rom.sh` assembles from the upstream source kept beside
them ([provenance and license](../rtl/soshdboot/README.md)); `sim/run_tests.sh`
checks both against the source. The core takes the option at reset, like
**Memory**.

Another ROM goes in over Apple's, until the core is reloaded:
`games/Apple-III/boot.rom`, which MiSTer sends every time the core starts, or
**Load Boot ROM** in the OSD. The machine is held in reset while one arrives.
Choosing soshdboot still selects soshdboot: setups from before Apple's ROM was
built in keep Apple's ROM as `boot.rom`, and it must not undo that choice.

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

Formatting also excludes all vendored files in `rtl/acia/`, `rtl/disk/woz/` and
`rtl/cards/mouse/` to preserve readable diffs against upstream. Explicit file selection uses the same scope,
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

## Linting

With Verilator, GHDL (with synthesis support), Zsh and Perl on `PATH`, run
from the repository root:

```sh
make lint
```

This regenerates the VHDL dependencies using `sim/gen_vhdl.sh`, creates a
deterministic lint-only build ID, then runs:

```sh
verilator --lint-only -Wall --top-module emu -f lint/rtl.f
```

For direct invocation, run `make lint-prepare` first and repeat it after any
VHDL edits. `lint/rtl.f` lists the Verilog/SystemVerilog sources from `files.qip`;
update both when adding synthesis sources. `.v` files are parsed as Verilog 2005.
Modules without an explicit timescale use `1ns/1ps`.

The MiSTer `sys/` modules are loaded to check their connections, with diagnostics
suppressed by `lint/exclusions.vlt`. The GHDL-generated T65/VIA code and lint-only
PLL stub are also excluded from diagnostics. Vendored Verilog in `rtl/acia/`,
`rtl/disk/woz/` and `rtl/cards/mouse/`, including local modifications, has lint
warnings suppressed.
Those modules remain loaded to check connections from project RTL. The formatter
also excludes these directories. Diagnostics involving both project and excluded
vendor code can also be suppressed, such as the disk engine's mixed-reset warning.

The warning policy disables filename/case/shadowing style checks, explicitly
disconnected-port warnings and declaration-initializer warnings (FPGA power-up
values). Known unused HPS ports and project debug outputs have file/message
waivers; missing required connections still warn. Width, multiple-driver,
unused-signal, combinational-order and reset checks remain enabled.
Reviewed FPGA initialization, bounded-width expressions and unused interface
signals have documented file/message waivers in `lint/exclusions.vlt`. These
match the known diagnostics rather than disabling those rules for project RTL.

Lint uses the existing behavioral RAM/ROM branches and a port-only PLL stub,
so it does not validate Intel primitives, PLL behavior or timing. No ROM image,
Quartus build or MiSTer connection is needed. Generated files remain ignored.

Warnings are fatal: any diagnostic outside the reviewed waivers fails `make lint`.
The lint command does not change RTL. This setup was validated with
Verilator 5.052 and GHDL 6.0.0.

## Testing

The simulation flow needs Icarus Verilog, Verilator 5, GHDL with synthesis,
cc65, a C++ compiler, `make`, Python 3 and `xxd`. GHDL converts the VHDL
components to Verilog so Verilator can simulate the whole machine. The scripts
run under bash, including the 3.2 that macOS ships. Everything below was run on
macOS (Icarus 13, Verilator 5.052, GHDL 6.0) and on Ubuntu 24.04 with its own
packages (Icarus 12, Verilator 5.020, GHDL 4.1).

```sh
make check-tools   # what is installed, and the brew/apt line for what is not
make test-quick    # unit, disk, memory map, slot, block card, mouse card and timing benches, about a minute
make test          # everything that needs no disk image, about ten minutes
make boot                                   # stock ROM to the disk bootstrap (also a step of make test)
make boot DISK=system.woz ARGS=--to-menu    # SOS to the Utilities menu, about five minutes
make boot ARGS=--soshdboot ...              # the built-in soshdboot ROM
make boot ROM=other.rom ...                 # another 4 KiB boot ROM
```

The two boot ROMs and the [mouse card's two ROMs](MOUSE.md) are the only
Apple images in the repository, so the tests that compare against Apple's PROMs take
their dumps from the environment and skip when one is missing; `make test`
passes on a fresh clone.

| Variable | File | Used by | Source |
|---|---|---|---|
| `APPLE3_ROM` (`ROM=` for `make boot`) | another 4,096-byte boot ROM in place of Apple's | `sim/run_core_boot.sh` | any 4 KiB Apple /// boot ROM image |
| `APPLE3_PROM_DIR` | unpacked `A3PROMs` directory | timing PROM comparison in `sim/accuracy/run.sh`, decoder PROM comparison in `sim/memmap/run.sh` | [bitsavers `A3PROMs.zip`](http://bitsavers.org/pdf/apple/apple_III/firmware/A3PROMs.zip) |
| `APPLE3_PROM_12V_DIR` | directory with `341-0042.bin` and `341-0044.bin` | the 128 KiB half of `sim/memmap/run.sh` | the archive.org item below |
| `APPLE3_DISK_PROM` | `341-0028.bin`, 256 bytes | P6 comparison in `sim/disk/run.sh` | [archive.org `AppleIIIROMs`](https://archive.org/details/AppleIIIROMs) |
| `APPLE3_PLUS_PROM` | `342-0145-A.bin` | interlace comparison in `sim/accuracy/run.sh` | the same archive.org item |
| `APPLE3_EURO_PROM` | `AppleIII_341-0060.bin` | 50 Hz comparison in `sim/accuracy/run.sh` | [asimov `rom_images/apple3`](https://mirrors.apple2.org.za/ftp.apple.asimov.net/emulators/rom_images/apple3/) |

The simulator mounts **WOZ images only**; on hardware Main converts the other
formats. Convert a DSK, PO or NIB with the companion Main's
[`storage_test --convert`](MAIN_STORAGE.md#tests-and-conversion-utility).

The individual runners, which `make` calls:

```sh
./sim/run_tests.sh                      # unit benches: MMU, timing, memory, boot ROMs,
                                        # video, keyboard, I/O, RTC, ACIA, disk
bash sim/accuracy/run.sh                # documentation-derived checks
./sim/disk/run.sh                       # P6, WOZ parser/writeback, drive timing
./sim/memmap/run.sh                     # memory map against the decoder PROMs, real-CPU boundary reads and writes
./sim/joystick/run.sh                   # joystick read methods at every position
./sim/timing/run.sh                     # CPU peripheral waits, RDY, RMW and NMI
./sim/blockdev/run.sh                   # block card registers, firmware, real-CPU driver calls
./sim/mouse/run.sh                      # mouse card under SOS's mouse driver sequences
./sim/run_core_boot.sh 30000000
./sim/blockdev/run_soshdboot.sh         # soshdboot ROM booting a generated hard disk
./sim/run_core_boot.sh 400000000 system.woz --woz
./sim/run_core_boot.sh 1400000000 sysutils.woz --keytest
```

`run_core_boot.sh` runs the stock ROM on the integrated machine and checks that
reset, memory sizing, reconfiguration and the disk bootstrap happen. With a WOZ
image it follows SOS to the interpreter through the real track cache.
`--drive2=blank.woz`, `--drive3=blank.woz` and `--drive4=blank.woz`
mount the three external drives on the shared transfer bus, and
`--hd1=hard.po`/`--hd2=hard.po` mount the block card's images
([block storage tests](../sim/blockdev/README.md)); `--soshdboot` sets
**Boot ROM** to soshdboot, and `--alpha-lock` turns Alpha Lock on as the
machine starts. `--frame-out=frame.ppm`
saves the rendered 560x192 picture at the end of a run, which is what a
MiSTer screenshot shows; the text dumps decode display memory instead.
`--audio-out=audio.wav` records the core's audio output through the run as a
16-bit mono WAV file at 47,727 Hz, one sample every 300 master clocks.
`--video=color` or `--video=mono` takes it from that [video source](VIDEO_SOURCES.md),
and `--monitor=green`, `amber` or `tv` from that monitor on it.
`--ram128k` runs the 128 KiB memory board.
`--mouse-card` puts the [mouse card](MOUSE.md) in slot 4, and the `--keys`
script then takes `mouse:DX:DY` for a host mouse report, `mouse:DX:DY:N` for N
of them a sixtieth of a second apart, and `button:1` or `button:0` for its
button. `--mouse-trace` prints the bytes that cross the card's PIA port A: the
driver's commands and the 68705's answers.
`--interlace` turns on the /// Plus [text interlace](INTERLACE.md) switch and
makes that picture two fields woven into 560x384.
`--pal` fits the Euro system's [50 Hz scan PROM](PAL.md).
`--wp-trace` logs each write-protect sense read with the motor timing and
drive 1's protect terms, and `--dump-mem=A000,2000` prints system-bank memory
for disassembling a loaded program;
`--sd-delay=71590` adds 5 ms of host latency per request. `--to-menu` keeps
going past the interpreter until the System Utilities menu is on screen, and
fails on any SOS system failure; use it for boot regressions, because a bad
interpreter entry only shows up after the loader hands over. `--check-font`
does the same and then compares the character generator with the set SOS keeps
at $0C00, which its console driver loads through the screen holes;
`--font-dump=01,02` prints chosen glyphs from the character generator at the
end of a run. `--mount-delay=8
--reset-delay=3` reproduces an MGL start: no disk at power-on, a mount after
each delay, then a reset. `--expect="Apple Writer"` waits for another title's
screen text instead of the Utilities menu. `--sd-byte-clocks=16` slows the host
transfer to roughly the real HPS link (the default of 4 is far quicker), which
together with `--sd-delay` shows how much track-load time a protection check
tolerates. `--rtc=YYMMDDWhhmmss` seeds the host clock as MiSTer does
(W = weekday, Sunday 0). `--disk-trace` prints a millisecond timeline of seeks,
ROM address-field reads, head movement and cache validity on tracks 8 to 17,
where SOS reads its protection key; `--disk-trace-all` covers every track
and adds write-mode bursts with their track positions. `--keys=` types a script
once `--keys-after=TEXT` is on screen, for example
`--keys=text:d,wait3,text:f,wait3,text:.d1,enter,text:wbfmt,enter,wait3,text:y,wait40,dump`
to run SOS's Format a Volume (tokens: `enter`, `esc`, `up`, `down`, `left`,
`right`, `del`, `bs`, `space`, `text:...`, `waitN` seconds, `dump` the text screen). `--writable` mounts images
read-write and `--sd-write-delay=N` slows saved blocks. `--keytest` drives System Utilities with
injected PS/2 keys and decodes the text page after each, and `--plus-keymap`
runs the machine with the Apple /// Plus keyboard selected. A `--keys` script
also prints each strobed encoder byte the guest reads at $C000, which is what
tells one key code from another when the screen shows the same glyph. See
[sim/accuracy/README.md](../sim/accuracy/README.md) for the PROM-based timing
comparison and the 6502 functional test, and
[sim/hwtest/README.md](../sim/hwtest/README.md) for boot disks that check the
character-download windows and display fetch timing by eye, and the three sound
sources by ear, on a MiSTer.

`sim/joystick/run.sh` runs a test ROM on the whole machine that reads the
joystick the ways shipped software does: SOS 1.3's GET_ANALOG, timed by the D
VIA's timer 2 through the boot ROM's ANALOG routine, at 2 MHz with the screen
off and on and at 1 MHz; the emulation disk's PREAD; Atomic Defense's own
polling loop; and the boot ROM's A/D self-test. The copied routines sit at their
original addresses, so their cycle counts match. The harness sets a new joystick
position before each batch, 256 in all, and checks every result and the
switches. It needs cc65 and Verilator but no ROM image.

See [Main storage integration](MAIN_STORAGE.md) for the companion Main patch and
[Disk III validation](DISK_FIDELITY_2026-09-16.md) for the tested hardware build.
