# Apple /// for MiSTer

An FPGA implementation of the 1980 Apple /// for the MiSTer platform.

> **This repository is AI-generated.** The hardware model, simulation harness,
> tests and documentation were written by Claude, Anthropic's AI model, working
> through Claude Code. A human directed the work, reviewed it and tested it on a
> DE10-Nano, but did not write the code. Read it with that in mind: it boots SOS
> and runs the software tried so far, and it has had far less real-world use
> than a mature core.

The core is an original hardware model. It was built from Apple's Level 2
Service Reference Manual and motherboard schematics, decoded logic PROMs,
Apple's patents, the SOS 1.3 and console driver sources, and programs known to
run on real machines. MAME's driver was used as a cross-check rather than as the
specification. The design notes in [docs/DESIGN.md](docs/DESIGN.md) map each
behaviour to its source.

## Status

SOS 1.3 boots to System Utilities and Business BASIC. Apple's Confidence Program
passes its memory test and renders all ten video tests, and the Apple II
emulation disk reaches its loader. Broad software compatibility has not been
established, and a few things are known not to work; see below.

## What is implemented

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
- The internal Disk /// drive and one external drive on the Disk II compatible
  controller.
- A 6551 ACIA on the serial port, connected to MiSTer's HPS UART.

## Known limitations

- Slots 1 to 4 and their peripheral cards are absent, so nothing that needs a
  card works. Only drives 1 and 2 are exposed; the controller could select four.
- The Silentype printer interface shared with joystick port A is not
  implemented.
- Sector images (`DSK`, `DO`, `PO`) are read only. Use a `NIB` when software
  needs to write.
- Copy-protected disks that rely on flux-level tricks cannot be represented by
  the supported image formats.
- The Confidence Program's Machine Configuration screen hangs. The cause has not
  been found.
- The optional 512 KiB third-party memory expansion is not enabled.

## Installation

1. Copy `Apple-III_<date>.rbf` to `/media/fat/_Computer/`.
2. Supply the boot ROM as `/media/fat/games/Apple-III/boot.rom` (see below).
3. Put disk images in `/media/fat/games/Apple-III/` and mount them from the OSD.

## Boot ROM

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

## Disk images

Both the 232,960-byte `NIB` format and 143,360-byte `DSK`, `DO` and `PO` sector
images mount directly. The core converts sector images to nibbles a track at a
time as they load, including the address-field volume key that SOS's
synchronized-track check reads from tracks 9 to 16, so the disks on
[apple3.org](https://www.apple3.org/iiisoftware.html) work as downloaded.

Images are recognised by size, so the sector order cannot be detected. Most
`.dsk` and `.do` files are DOS 3.3 order, which is the default. Set **Sector
order** to ProDOS for `.po` images and for the occasional ProDOS-order `.dsk`.

Sector images are read only because writing back would need de-nibblization. To
make a writable copy, convert to `NIB` with the bundled tool:

```sh
c++ -std=c++17 -O2 tools/dsk2nib.cpp -o dsk2nib
./dsk2nib system.dsk system.nib
```

## Keyboard

F12 is the Apple /// RESET key. Ctrl+F12 performs a hardware reset and F12
alone raises the NMI, both gated by the environment register as on the real
machine. Because the core claims F12, the MiSTer menu opens with Win+F12 or the
OSD button. Caps Lock is Alpha Lock, the Windows or Command keys are Open Apple
and Alt is Solid Apple.

## Serial port

The ACIA connects to MiSTer's HPS UART, `/dev/ttyS1`. Set the Apple /// software
and the host to the same baud rate and frame format; the MiSTer UART menu offers
the common rates and the ACIA implements all fifteen internal dividers.

**Serial CTS** defaults to **Always ready** so the stock ROM's self-test passes
when no host program has the UART open. Choose **Host RTS** for hardware flow
control; the host must assert RTS before the machine boots in that mode. MiSTer
has no separate carrier-detect line, so DCD is held asserted. See
[rtl/acia/README.md](rtl/acia/README.md) for the provenance of the 6551 core
and [sim/serial/README.md](sim/serial/README.md) for the serial tests.

## Building

Quartus Prime 17.0.x is required, as for every MiSTer core. `build.sh` drives
Quartus under CrossOver on macOS; on Windows or Linux open `Apple-III.qpf` in
Quartus and compile.

```sh
./build.sh map        # synthesis only
./build.sh compile    # full flow, writes output_files/Apple-III.rbf
```

The `sys/` directory is an unmodified copy of
[Template_MiSTer](https://github.com/MiSTer-devel/Template_MiSTer).

## Testing

The simulation flow needs Icarus Verilog, Verilator, GHDL, a C++ compiler and
`xxd`. GHDL converts the VHDL components to Verilog so Verilator can simulate the
whole machine. The boot tests read the ROM from `APPLE3_ROM`.

```sh
./sim/run_tests.sh                      # unit benches: MMU, timing, memory,
                                        # video, keyboard, I/O, RTC, ACIA, disk
bash sim/accuracy/run.sh                # documentation-derived checks
APPLE3_ROM=apple3.rom ./sim/run_core_boot.sh 30000000
APPLE3_ROM=apple3.rom ./sim/run_core_boot.sh 2000000000 system.dsk --rawdsk
APPLE3_ROM=apple3.rom ./sim/run_core_boot.sh 1400000000 sysutils.dsk --buffered --keytest
```

`run_core_boot.sh` runs the stock ROM on the integrated machine and checks that
reset, memory sizing, reconfiguration and the disk bootstrap happen. With a disk
image it follows SOS to the interpreter. `--buffered` models MiSTer's 512-byte
transfers and the track cache, `--rawdsk` feeds an unconverted sector image
through the core's own nibblizer, and `--keytest` drives System Utilities with
injected PS/2 keys and decodes the text page after each. See
[sim/accuracy/README.md](sim/accuracy/README.md) for the PROM-based timing
comparison and the 6502 functional test.

## Thanks

This core stands on work from the MiSTer and Apple /// communities:

- **Alexey Melnikov (Sorgelig)** for the MiSTer framework, the floppy track
  cache and the Apple II MiSTer core the disk integration follows.
- **Stephen A. Edwards** for the Disk II drive model from his Apple II FPGA and
  for his article on the Apple II clock generator.
- **Gyorgy Szombathelyi (gyurco)** for the 6551 UART core, Disk II write
  support and his T65 fixes.
- **Gideon Zweijtzer (GideonZ)** for the 6522 VIA.
- **Daniel Wallner, Mike Johnson (MikeJ), Wolfgang Scherr and Morten Leikvoll**
  for the T65 6502 core.
- **Till Harbaum** for the HPS I/O interface the MiSTer framework grew from.
- **Rob Justice (robjustice)** for the ca65 transcription of the boot ROM
  listing, SOS hard-disk boot work and his Apple /// tools and write-ups.
- **Paul Hagstrom** for `diskhero`, whose commented source documents the display
  modes, character download and extended addressing on real hardware.
- **ThorstenBr** for the Apple /// custom ROM and Disk II interface
  documentation.
- **BBC NewBrain** for the Apple /// keyboard encoder replacement project, which
  documents the key matrix.
- **Patrick Schaefer** for decoding the motherboard logic PROMs.
- **John Jeppson** for his 1982 and 1983 Softalk articles on the Apple ///
  memory system.
- **Nathan Woods, R. Belmont and the MAME team** for the `apple3` driver used as
  a cross-check.
- **Klaus Dormann** for the 6502 functional test suite.
- **David Schmidt** for apple3.org, and the bitsavers and Asimov archives for
  the manuals, schematics and PROM dumps.

## License

See [LICENSE](LICENSE). The imported T65, VIA, 6551, floppy and MiSTer framework
sources retain their own notices.
