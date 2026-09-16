# Apple /// for MiSTer

Experimental Apple /// core with 256 KiB RAM, two floppy drives, joystick,
audio and serial support. Tested with SOS 1.3 System Utilities and Business BASIC.

This is an AI-generated, human-directed project; compatibility is still being tested.

## Setup

1. Copy the core's `.rbf` file to `/media/fat/_Computer/`.
2. Copy the matching companion Main binary to `/media/fat/MiSTer_AppleIII_WOZ`.
3. Add this to `MiSTer.ini`:

   ```ini
   [Apple-III]
   main=MiSTer_AppleIII_WOZ
   ```

4. Supply a 4,096-byte Apple /// boot ROM as
   `/media/fat/games/Apple-III/boot.rom`. ROMs are not included.
5. Put disk images in `/media/fat/games/Apple-III/`, launch the core, and use
   **Mount Drive 1** to select a boot disk. **Mount Drive 2** is the external drive.

Use matching core and Main builds. The custom Main is selected only for this
core. [Build instructions and Main patch](docs/MAIN_STORAGE.md).

## Disk images

Supported: **WOZ, DSK, DO, PO, NIB and 2MG**.

- Use **WOZ2** for writable disks. Writes require existing track allocations;
  formatting cannot create missing tracks.
- WOZ1, flux-encoded WOZ and all other formats are **read-only**.
- Raw `.dsk`/`.do` files use DOS sector order; `.po` uses ProDOS order.
  For 2MG files, the header determines the order.

To make a writable WOZ copy, see the [conversion instructions](docs/MAIN_STORAGE.md#tests-and-conversion-utility).

## Controls

| Key | Action |
|---|---|
| Win + F12 or OSD button | MiSTer menu |
| Ctrl + F12 | Hardware reset |
| F12 | Apple /// RESET key (NMI) |
| Windows / Command | Open Apple |
| Alt | Solid Apple |
| Caps Lock | Alpha Lock |

Serial uses MiSTer's UART. Leave **Serial CTS** at **Always ready** unless
using host hardware flow control. [Serial details](docs/DEVELOPMENT.md#serial-port).

## Known limitations

- Expansion cards, ProFile hard disks, Silentype and the optional 512 KiB
  memory expansion are not implemented.
- The Confidence Program's **Machine Configuration** screen hangs.
- Broad software and copy-protection compatibility has not been established.

[Development](docs/DEVELOPMENT.md) · [Hardware design](docs/DESIGN.md) ·
[Disk validation](docs/DISK_FIDELITY_2026-09-16.md) · [License](LICENSE)

## Credits

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

- **Alan Steremberg** for the WOZ drive and media implementation from
  Apple-II_MiSTer. See its [provenance and license](rtl/disk/woz/README.md).

Imported components retain their own license notices, including the
[GPL-3.0-or-later WOZ implementation](rtl/disk/woz/README.md).
