# Apple /// for MiSTer

__Warning: This core is vibe coded.__

A complete [Apple ///](https://en.wikipedia.org/wiki/Apple_III) core, and a very
usable one: most software tried so far runs well.

## Features

- Apple /// or Apple /// Plus, with the Plus's DELETE key and 560 × 384
  interlaced text
- 256 or 128 KiB of RAM, mapped as on Apple's two memory boards
  ([details](docs/MEMORY_MAP.md))
- Every native video mode, and the Apple II modes for Apple II emulation
- Character-set changes and mid-screen updates display as on real hardware
- RGB, color composite with Apple II artifact color, or monochrome composite
- Monitor presets: clean RGB, Monitor /// green, amber or a color TV
- NTSC or PAL, Apple's 50 Hz "Euro system"
- MiSTer's aspect ratios, integer scaling and scandoubler effects, with weave
  or bob deinterlacing for interlaced text
- Four floppy drives, each with its own write protection
  ([details](docs/FOUR_DRIVES.md))
- WOZ, DSK, DO, PO, NIB and 2MG images, writable and formattable
- Copy-protected originals boot from plain sector dumps
- Two hard-disk drives for your own images, bootable with the built-in
  soshdboot ROM ([details](docs/BLOCK_STORAGE.md))
- Apple's mouse card in slot 4, driven by the MiSTer's mouse
- The real keyboard's auto-repeat and Solid Apple speed-up
- Two joysticks, each with its button and latching switch
- Speaker and 6-bit DAC sound
- Clock set from the MiSTer's time
- Serial port on the MiSTer's UART
- Apple's boot ROM built in, or load another from the OSD

For something to play, [apple-iii-games](https://github.com/jakesjews/apple-iii-games)
has native Apple /// games as ready-to-mount disk images.

## Setup

1. Copy the core's latest `.rbf` file in `releases/` to `/media/fat/_Computer/`.
2. Copy `releases/MiSTer_AppleIII` to `/media/fat/MiSTer_AppleIII`.
3. Add this to `MiSTer.ini`:

   ```ini
   [Apple-III]
   main=MiSTer_AppleIII
   ```

4. Put disk images in `/media/fat/games/Apple-III/`, launch the core, and use
   **Mount Drive 1** to select a boot disk. **Mount Drive 2–4** are the three
   external Disk III drives. Each drive has its own **Write Protect** option.
   **Mount Hard Disk 1** and **2** take ProDOS-order images for the block
   card in slot 1
5. If SOS lists only two drives, use System Utilities → **System Configuration
   Program**: read your `SOS.DRIVER`, set **Change System Parameters → Number of
   Disk III Drives** to **4**, then **Generate New System** to save `SOS.DRIVER`
   on your boot disk and reboot. Apple II emulation uses drives 1 and 2.

Use matching core and Main builds. The custom Main is selected only for this
core. The supplied `MiSTer_AppleIII` binary comes from
[jakesjews/Main_MiSTer](https://github.com/jakesjews/Main_MiSTer/tree/apple3-disk-storage)

## Disk images

Supported: **WOZ, DSK, DO, PO, NIB and 2MG**.

- **DSK, DO, PO, NIB and 2MG** are writable, A NIB track is saved only when all sixteen of its sectors read back
  cleanly.
- **WOZ2** is writable. Writes require existing track allocations; formatting
  cannot create missing tracks.
- WOZ1, flux-encoded WOZ and images inside a zip are **read-only**.
- A raw 140K image's sector order is detected from its SOS/ProDOS directory
  or DOS 3.3 VTOC, so a ProDOS-order file named `.dsk` works. Without either,
  `.dsk`/`.do` mean DOS order and `.po` ProDOS order. For 2MG files, the header
  determines the order.
- A DOS 3.3 image gets the volume number in its VTOC, which disks made with
  another volume than 254, such as Apple's dealer diagnostics, need to boot.
- Sector dumps of copy-protected originals (an encrypted `SOS.INTERP`) get the
  SOS protection key and synchronized tracks automatically. Deprotected disks,
  which is most of what circulates, are left without the key so SOS does not
  try to decrypt them.

Hard-disk images for the block card are **PO, HDV or ProDOS-order 2MG**, any
multiple of 512 bytes, written in place. Images beyond 32 MiB show their first
65,535 blocks. A read-only file, a write-protected 2MG, a DC42 container or a
zip member mounts read-only.

A2R flux captures are not supported; export them to WOZ with the free
[Applesauce client](https://applesaucefdc.com/software/), which runs on macOS
without the Applesauce hardware.

## Controls

| Key | Action |
|---|---|
| F2 | Apple /// RESET key (NMI) |
| Ctrl + F2 | CONTROL-RESET (hardware reset) |
| Windows / Command | Open Apple |
| Alt | Solid Apple |
| Caps Lock | Alpha Lock |
| Del | Keypad period, or DELETE with the /// Plus keymap |

Keys repeat at 10 cps after half a second. Pressing Solid Apple *while a key is
already held* raises that key to 30 cps, as on the real machine; holding Solid
Apple first suppresses the repeat instead, which is what keeps Solid Apple key
combinations to a single character. A held arrow key closes the second contact
that its keyswitch has on real hardware, so it speeds up the same way and reads
as Solid Apple while it is down.

**Model** in the OSD selects the Apple /// Plus. It adds that machine's one
extra key, DELETE, on the host Delete key, and its **Text Interlace** switch:
two fields half a line apart for 384 lines, showing pages 1 and 2 merged when
a program selects page 2, as on the real machine. [Details](docs/INTERLACE.md).

**Memory** in the OSD selects Apple's 256 KiB board or the earlier 128 KiB
one. Like a board swap, it takes effect at the next reset.

**Boot ROM** in the OSD selects Rob Justice's soshdboot ROM, which boots
**Hard Disk 1** if an image is mounted there and the floppy if not. The image
needs soshdboot's loader and kernel, as on
[his images](https://github.com/robjustice/soshdboot/tree/master/disks); with
any other, choose **Apple**, or turn on Alpha Lock and press Ctrl + F2 to boot
the floppy. It takes effect at the next reset. [Details](docs/BLOCK_STORAGE.md).

**Video** in the OSD selects the machine's RGB, NTSC color or black-and-white
output. Apple II hires is in color only on **Color Composite**, as on the real
machine. Text and monochrome graphics are white on black on all three. With
either composite output, **Display** chooses the monitor on it: **RGB Monitor**
for the clean picture, **Monitor /// Green** or **Amber**, or a **Color TV**
with its soft text and bleeding color. [Details](docs/VIDEO_SOURCES.md).

**Video Standard** in the OSD selects NTSC or PAL: Apple's 50 Hz "Euro
system", the same picture in a 310-line frame. [Details](docs/PAL.md).

**Mouse Card** in the OSD is Apple's mouse card in slot 4, where SOS mouse
drivers are usually configured to find it, and **Mouse Speed** sets how far
the MiSTer's mouse moves it; Normal is close to Apple's mouse.
[Details](docs/MOUSE.md).

**Aspect ratio** and **Scale** are MiSTer's usual ones: Original (4:3), Full
Screen or the custom ratios of `MiSTer.ini`, and integer scaling.

Controller 1 is the joystick in port B, which SOS and Business BASIC read as
joystick 0; **Joystick 1 on** in the OSD moves it to port A. Controller 2 uses
the other port. Button 1 is the joystick's pushbutton, and each press of button
2 flips its latching switch.

Serial uses MiSTer's UART. Leave **Serial CTS** at **Always ready** unless
using host hardware flow control. [Serial details](docs/DEVELOPMENT.md#serial-port).

## Building and simulation

Open `Apple-III.qpf` in Quartus Prime 17.0 and compile, or run
`./build.sh compile` on a Mac with Quartus under CrossOver. The simulation needs
Icarus Verilog, Verilator 5, GHDL and cc65:

```sh
make check-tools                  # lists what is missing and how to install it
make test                         # every test that needs no disk image, about ten minutes
make boot DISK=system.woz ARGS=--to-menu   # boot SOS in the simulator
```

Booting SOS needs a WOZ disk image.
[Details](docs/DEVELOPMENT.md#testing).

## Todo

Existing partial implementations are noted where they provide a starting point.

- [ ] **Validate audio** Verify implementation accuracy against research.

- [ ] **Organize OSD** Move OSD options to categories.

- [ ] **External memory and optional 512 KiB RAM.** Build on the parameterized
      RAM/MMU support with an external-memory backend and a usable 512 KiB option.
      Preserve paired-byte reads and guest-visible memory timing, and budget for
      future card RAM and disk buffers.

- [ ] **Microsoft SoftCard III.** Add it as a second CP/M option, including the
      required bus integration and storage-driver configuration.

- [ ] **Titan III+IIe.** Add support for this expansion.

- [ ] **Save States**

[Development](docs/DEVELOPMENT.md) · [Hardware design](docs/DESIGN.md) ·
[Disk validation](docs/DISK_FIDELITY_2026-09-16.md) · [License](LICENSE)

## Credits

This core stands on work from the MiSTer and Apple /// communities:

- **sorgelig** for the MiSTer framework and Main, the floppy track cache and
  the Apple II MiSTer core the disk integration follows.
- **alanswx** for the WOZ drive and media implementation from Apple-II_MiSTer
  (see its [provenance and license](rtl/disk/woz/README.md)), and for the
  Apple-family disk codec and DSK support in Main that the companion Main
  extends.
- **Newsdee** for Main's Apple II WOZ support and floppy fixes, which the
  companion Main builds on.
- **Stephen A. Edwards** for the Disk II drive model from his Apple II FPGA and
  for his article on the Apple II clock generator.
- **gyurco** for the 6551 UART core, Disk II write support, his T65 fixes and
  the Apple II core's mouse card, whose wiring this one follows.
- **jotego** for the jt6805 microcontroller core and **John E. Kent** for the
  6821 PIA (see their [provenance and license](rtl/cards/mouse/README.md)).
- **GideonZ** for the 6522 VIA.
- **Daniel Wallner, MikeJ, WoS and Morten Leikvoll** for the T65 6502 core.
- **harbaum** for the HPS I/O interface the MiSTer framework grew from.
- **robjustice** for the ca65 transcription of the boot ROM listing, the
  Problock3 driver and soshdboot ROM the block card runs, A3Driverutil and his
  Apple /// write-ups.
- **steven-a-wilson** and the **AppleWin** team for the ProDOS hard-disk
  interface the block card's registers follow.
- **paulhagstrom** for `diskhero`, whose commented source documents the display
  modes, character download and extended addressing on real hardware.
- **ThorstenBr** for the Apple /// custom ROM and Disk II interface
  documentation.
- **BBCNewBrain** for the Apple /// keyboard encoder replacement project, which
  documents the key matrix.
- **Patrick Schaefer** for decoding the motherboard logic PROMs.
- **John Jeppson** for his 1982 and 1983 Softalk articles on the Apple ///
  memory system.
- **npwoods, rb6502 and the MAME team** for the `apple3` driver, MOS 6551,
  CFFA and mouse card models used as cross-checks.
- **Klaus2m5** for the 6502 functional test suite.
- **Applesauce** for the WOZ format reference.
- The **AppleCommander** team for the disk-image tool behind the block-card
  test media.
- **wizzomafizzo** for Zaparoo, which drives the keystrokes and screenshots in
  the hardware tests.
- **david-schmidt** for apple3.org, and the bitsavers, Asimov and
  vintagecomputer.ca archives for the manuals, schematics and PROM dumps.

Imported components retain their own license notices, including the
GPL-3.0-or-later [WOZ implementation](rtl/disk/woz/README.md) and
[mouse card parts](rtl/cards/mouse/README.md), and the GPL-3.0
[soshdboot ROM](rtl/soshdboot/README.md).
