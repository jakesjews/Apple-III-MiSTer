# Apple III for MiSTer

An FPGA implementation of Apple's 1980 Apple III computer for the MiSTer
platform. This core is an original hardware model built from Apple service
documentation, schematics and software sources, decoded motherboard PROMs,
patents, and programs tested on original machines. MAME is used as one
cross-check, not as the implementation specification.

The core is under active development. The stock ROM completes diagnostics and
disk bootstrap, SOS 1.3 loads its interpreter, kernel, and drivers in the
integrated RTL/CPU simulation, and the same image reaches the System Utilities
selector on MiSTer hardware. Broad Apple III software compatibility is not yet
established.

## Implemented hardware

- 6502 CPU with Apple III 1/2 MHz cycle scheduling and video/refresh contention.
- Stock 256 KiB 5 V memory organization, bank register, relocatable zero page and
  stack, sister-byte reads, write protection, and Apple III extended addressing.
- 4 KiB stock boot ROM and optional 8 KiB dual-bank ROM images.
- Native Apple III text and graphics modes: 40/80-column text, 280/560-pixel
  monochrome, 140-pixel 16-colour, and 280-pixel foreground/background colour.
- Downloadable character generator RAM, inverse/flash attributes, page selection,
  screen blanking, and smooth vertical scrolling.
- Two 6522 VIAs, keyboard encoder and repeat behavior, MM58167-style clock,
  joystick switches and analog inputs, speaker toggle, bell, and six-bit audio.
- Internal Disk III plus one external drive through the Disk II-compatible
  controller path. MiSTer mounts `NIB` images with write protection.
- A minimal 6551-compatible register model sufficient for the startup path.

## Current limitations

- Slots 1-4 and their peripheral cards are not implemented.
- The RS-232 ACIA is not connected to MiSTer's UART and is not yet cycle-complete.
- The Silentype serial/printer functions shared with joystick port A are not
  implemented.
- Only drives 1 and 2 are exposed; the original controller could select four.
- Copy-protected software requiring flux-level media cannot be represented by the
  currently supported sector/track formats.
- The optional third-party 512 KiB memory expansion is not enabled. The RTL MMU
  remains parameterized for 128/256/512 KiB configurations.

## ROM

Copyrighted ROMs are not distributed in this repository. Set `APPLE3_ROM` to a
4096-byte stock ROM or an 8192-byte dual-bank ROM when building:

```sh
APPLE3_ROM=/path/to/apple3.rom ./build.sh compile
```

The resulting RBF contains that ROM. A 4 KiB or 8 KiB `.bin` can also be loaded
at runtime from the MiSTer menu.

## Disk images

MiSTer's host currently enables its transparent `DSK`/`DO`/`PO`-to-`NIB`
translation only for cores named Apple II or TK2000. Apple III therefore
advertises the native 232,960-byte `NIB` format instead of silently treating a
140 KiB sector image as nibble data. A small converter using the same 6-and-2
layout as the integration test is included:

```sh
c++ -std=c++17 -O2 tools/dsk2nib.cpp -o /tmp/apple3-dsk2nib
/tmp/apple3-dsk2nib system.dsk system.nib
```

For Apple III system disks, the converter also reconstructs the address-field
volume key used by SOS's synchronized-track check. Use `.do` for DOS-order
sector images and `.po` for ProDOS-order images.

For an automated MGL boot, name the deployed RBF by its absolute path. MiSTer's
version-family shorthand (for example `_Computer/Apple-III`) resolves the dated
RBF but did not reliably initialize the disk mount in hardware testing. The
following deterministic sequence also resets before mounting and allows the
track cache time to initialize:

```xml
<mistergamedescription>
  <rbf>/media/fat/Apple-III.rbf</rbf>
  <reset delay="1" hold="1"/>
  <file delay="3" type="s" index="0" path="/media/fat/games/Apple-III/system.nib"/>
</mistergamedescription>
```

`sim/Apple-III-Hardware-Test.mgl` contains this tested sequence. Passing a NIB
as the second argument to `deploy.sh` installs it as `system.nib`, copies the
MGL, and launches the hardware test automatically.

## Build and test

Quartus Prime 17.0.x is required, following MiSTer conventions. `build.sh` is
configured for the local Quartus 17 CrossOver bottle:

```sh
./sim/run_tests.sh
./sim/run_core_boot.sh 30000000
./sim/run_core_boot.sh 2000000000 /path/to/system.dsk
./sim/run_core_boot.sh 2000000000 /path/to/system.nib --buffered
./build.sh map
./build.sh compile
./deploy.sh output_files/Apple-III.rbf /path/to/system.nib
```

The first command runs focused Icarus Verilog testbenches for the MMU, timing,
memory, video, keyboard, I/O, clock/ACIA, and floppy controller. The second uses
Verilator, the T65 CPU, the stock ROM, and the integrated machine to verify that
reset, memory sizing, reconfiguration, and the disk boot path execute together.
With a disk-image argument it also converts sector media to NIB in memory,
requires the ROM to read block 0 and jump to its `$A000` bootstrap, follows SOS
past an instruction-boundary enhanced-addressing regression, and waits for SOS
to return successfully to the user/interpreter environment. The `--buffered`
variant additionally models MiSTer's 512-byte HPS transfers and the synthesized
13-block track cache, including track changes while a load is in progress.
`deploy.sh` copies the generated core to `root@mister`; with no disk argument it
launches the bare core, and with a NIB it uses the reset-then-mount MGL above.

## Accuracy sources

The implementation is intentionally source-diverse. The detailed mapping from
hardware behavior to evidence is in [docs/DESIGN.md](docs/DESIGN.md). Principal
sources include:

- Apple III Level 2 Service Reference Manual and motherboard schematics.
- Apple's SOS 1.3 kernel, console, disk-driver, formatter, and boot-ROM sources.
- Decoded equations for the timing, status, address, video, and DRAM-control PROMs.
- Apple patents US4383296, US4278972, and US4533909.
- John Jeppson's contemporary Apple III hardware articles and Apple's 1981
  “Funny Mode and SOS” engineering memo.
- `diskhero`, Rob Justice's Apple III tools and software, and other programs known
  to run on original hardware.
- Stephen A. Edwards' schematic-derived FPGA reconstruction of the Woz clock
  generator, used to cross-check the 65th-cycle HPE stretch.
- MAME's Apple III driver and the historical Sara emulator as secondary behavioral
  comparisons.
- The current Apple II MiSTer core for MiSTer framework and disk-image integration,
  not for Apple III motherboard behavior.

The research inventory and source-specific notes live under `research/` in the
development checkout and are excluded from release artifacts.

## License

See [LICENSE](LICENSE). Imported T65, VIA, MiSTer framework, and floppy support
retain their respective source notices.
