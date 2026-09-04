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
- Mounted sector images (`DSK`/`DO`/`PO`) are read only; use a `NIB` for writing.
- The optional third-party 512 KiB memory expansion is not enabled. The RTL MMU
  remains parameterized for 128/256/512 KiB configurations.

## Keyboard

F12 is the Apple /// RESET key: Ctrl+F12 performs a hardware reset and F12 on
its own raises the NMI, both gated by the environment register as on the real
machine. Because the core claims F12, the MiSTer menu opens with Win+F12 (or
the OSD button). Caps Lock toggles Alpha Lock, the Windows/Command keys are
Open Apple and Alt is Solid Apple.

## ROM

Copyrighted ROMs are not distributed in this repository. Set `APPLE3_ROM` to a
4096-byte stock ROM or an 8192-byte dual-bank ROM when building:

```sh
APPLE3_ROM=/path/to/apple3.rom ./build.sh compile
```

The resulting RBF contains that ROM. A 4 KiB or 8 KiB `.bin` can also be loaded
at runtime from the MiSTer menu.

## Disk images

Both the 232,960-byte `NIB` format and 143,360-byte `DSK`/`DO`/`PO` sector
images can be mounted directly. MiSTer's own host-side sector-to-nibble
translation is gated on the core being named Apple II or TK2000, so the core
nibblizes sector images itself: `rtl/disk/dsk_nibblizer.sv` converts a track at
a time as it is loaded, reproducing the 6-and-2 field layout and the
address-field volume key that SOS's synchronized-track check reads from tracks
9 to 16. `sim/nib_tb.sv` checks it byte-for-byte against the reference
implementation in `sim/coretest/dsk2nib.h`.

Sector images are mounted read only, because writing back would require
de-nibblization. `NIB` images stay writable.

Images are auto-detected by size, but the sector order cannot be: MiSTer does
not tell the core which extension matched. `.dsk` and `.do` files are almost
always DOS 3.3 order, which is the default; set **Sector order** to ProDOS in
the menu for `.po` images and for the occasional ProDOS-order `.dsk`.

An offline converter using the same layout is still included if a `NIB` is
wanted, for example to make a writable copy:

```sh
c++ -std=c++17 -O2 tools/dsk2nib.cpp -o /tmp/apple3-dsk2nib
/tmp/apple3-dsk2nib system.dsk system.nib
```

For an automated MGL boot, follow the MiSTer MGL conventions exactly. The `rbf`
path is relative to the SD root with both the extension and the date stamp
removed, and the `file` path is relative to the *core's games folder*
(`/media/fat/games/Apple-III`), not to the SD root. An SD-root-relative or
absolute `rbf` path loads nothing, and a file path written relative to the SD
root silently mounts nothing because MiSTer appends it to the games folder. The
mount must also come before the reset, so the boot ROM restarts with the disk
already present:

```xml
<mistergamedescription>
  <rbf>_Computer/Apple-III</rbf>
  <file delay="2" type="s" index="0" path="system.nib"/>
  <reset delay="1"/>
</mistergamedescription>
```

`sim/Apple-III-Hardware-Test.mgl` contains this tested sequence, which boots SOS
to the System Utilities menu on hardware. Passing a NIB as the second argument
to `deploy.sh` installs it as `system.nib`, copies the MGL, and launches the
hardware test automatically.

## Build and test

Quartus Prime 17.0.x is required, following MiSTer conventions. `build.sh` is
configured for the local Quartus 17 CrossOver bottle:

```sh
./sim/run_tests.sh
./sim/run_core_boot.sh 30000000
./sim/run_core_boot.sh 2000000000 /path/to/system.dsk
./sim/run_core_boot.sh 2000000000 /path/to/system.nib --buffered
./sim/run_core_boot.sh 2000000000 /path/to/system.dsk --rawdsk
./sim/run_core_boot.sh 1400000000 /path/to/sysutils.dsk --buffered --keytest
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
13-block track cache, including track changes while a load is in progress. `--keytest` waits for the System
Utilities menu, injects PS/2 key events (letters, Escape, Return, arrows, Shift)
and decodes the text page after each so keyboard behaviour can be checked
without hardware.
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
