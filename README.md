# Apple /// for MiSTer

__Warning: This core is vibe coded.__

A complete [Apple ///](https://en.wikipedia.org/wiki/Apple_III) core, and a very
usable one: most software tried so far runs well.

- 256 KiB RAM, every native video mode and the Apple II modes
- RGB, color composite with Apple II artifact color, and monochrome composite,
  with clean, green, amber and color TV monitor presets
- Apple /// Plus model with its 560 × 384 text interlace
- Four floppy drives: WOZ, DSK, DO, PO, NIB and 2MG, writable and formattable
- A hard-disk card with two images, bootable without a floppy
- Keyboard, joysticks, clock, audio and serial

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

4. Supply the Apple /// boot ROM as
   `/media/fat/games/Apple-III/boot.rom`. It is the file MAME calls
   `apple3.rom`. ROMs are not included.

   | Name | Size | CRC32 | SHA-1 |
   |---|---|---|---|
   | `apple3.rom` | 4096 | `1af7ec42` | `8043f914ebdcdab9838dbb78f8a2ee3867d210d2` |

5. Put disk images in `/media/fat/games/Apple-III/`, launch the core, and use
   **Mount Drive 1** to select a boot disk. **Mount Drive 2–4** are the three
   external Disk III drives. Each drive has its own **Write Protect** option.
   **Mount Hard Disk 1** and **2** take ProDOS-order images for the block
   card in slot 1
6. If SOS lists only two drives, use System Utilities → **System Configuration
   Program**: read your `SOS.DRIVER`, set **Change System Parameters → Number of
   Disk III Drives** to **4**, then **Generate New System** to save `SOS.DRIVER`
   on your boot disk and reboot. Apple II emulation uses drives 1 and 2.

Use matching core and Main builds. The custom Main is selected only for this
core. The supplied `MiSTer_AppleIII` binary comes from
[jakesjews/Main_MiSTer](https://github.com/jakesjews/Main_MiSTer)

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
| Win + F12 or OSD button | MiSTer menu |
| Ctrl + F12 | Hardware reset |
| F12 | Apple /// RESET key (NMI) |
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

**Video** in the OSD selects the machine's RGB, NTSC color or black-and-white
output. Apple II hires is in color only on **Color Composite**, as on the real
machine. Text and monochrome graphics are white on black on all three. With
either composite output, **Display** chooses the monitor on it: **RGB Monitor**
for the clean picture, **Monitor /// Green** or **Amber**, or a **Color TV**
with its soft text and bleeding color. [Details](docs/VIDEO_SOURCES.md).

Controller 1 is the joystick in port B, which SOS and Business BASIC read as
joystick 0; **Joystick 1 on** in the OSD moves it to port A. Controller 2 uses
the other port. Button 1 is the joystick's pushbutton, and each press of button
2 flips its latching switch.

Serial uses MiSTer's UART. Leave **Serial CTS** at **Always ready** unless
using host hardware flow control. [Serial details](docs/DEVELOPMENT.md#serial-port).

## Todo

Existing partial implementations are noted where they provide a starting point.

- [x] **Keyboard accuracy and optional III Plus keymap.** Repeat activation
      ordering, the cursor keys' second contacts and the guest-visible solid
      Apple state they drive, and an optional Apple /// Plus keymap with its
      DELETE key.

- [x] **Display-fetch and character-download timing.** The scanner reads
      display memory in the video slot of every state, and character downloads
      follow the scan PROM's per-line windows. Tests cover writes during active
      display, the download boundaries and rendering in every mode.

- [x] **Native joystick accuracy.** The 9708 converter's charge, ramp and
      comparator follow the schematic's component values, with the joystick
      spanning SOS's GET_ANALOG window. Each port has a pushbutton and a
      latching switch, and port A's Silentype lines are wired as on the board.
      Tests run SOS's timer method and the polling loops of the emulation
      disk, a game and the boot ROM at every position.

- [x] **All four Disk III drives.** The internal drive and three external
      drives have independent mounts, write protection and media-change state.
      Disk II compatibility and shared disk-phase/fine-scroll behavior are
      retained. [Validation](docs/FOUR_DRIVES.md).

- [x] **Reusable slots 1–4.** Slot I/O, per-card ROM selection/deselection and
      individual IRQ/NMI routing are available through a reusable card bus.
      [Interface and tests](docs/SLOTS.md). Coprocessor bus ownership will be
      added when the first card needs it.

- [x] **Peripheral wait-state and boundary timing.** Delayed IOSTOP and VIA
      selects align onboard peripheral accesses; card RDY holds reads while
      allowing writes and interrupt detection. The extended horizontal state
      stretches CPU, VIA and Q3 timing together and retains refresh arbitration.
      [Timing model and tests](docs/PERIPHERAL_TIMING.md).

- [x] **One virtual block-storage interface.** A ProDOS block-mode card in
      slot 1, modeled on the Apple II core's hard-disk card with its own
      firmware, serves two images from Main's block assignments with reads,
      writes, status, capacity and error codes; Main writes the images in
      place. SOS uses it through the
      [Problock3](https://github.com/robjustice/Problock3) driver, and the
      [soshdboot](https://github.com/robjustice/soshdboot) ROM and kernel boot
      from it directly. Stock boot is unchanged.
      [Card and validation](docs/BLOCK_STORAGE.md).

- [x] **Video source modes.** Color-composite and monochrome-composite
      pictures alongside RGB, built from the schematic's two summing networks:
      Apple II artifact color, the ///'s own NTSC colors and color killer, and
      the monochrome output's sixteen-step gray scale.
      [Signal model and tests](docs/VIDEO_SOURCES.md).

- [x] **III Plus model with authentic interlace.** The Plus scan PROM's field
      flip-flop, its 263-line field and half-line sync, and the FORCPAGE wiring
      that shows page 1 in one field and the selected page in the other.
      [Hardware and tests](docs/INTERLACE.md).

- [x] **Neutral RGB output.** The 80-column-only green override is gone, so
      every monochrome RGB mode is white on black. Green phosphor is an optional
      monitor, shown by gray level in every mode.
      [Monitors and tests](docs/VIDEO_SOURCES.md#monitors).

- [x] **Display monitor presets.** The **Display** option puts a monitor on a
      composite output, separate from the signal: RGB Monitor (clean),
      Monitor /// Green, Amber and Color TV, each a preset with no tint,
      saturation or bandwidth controls. Monochrome tubes show the whole signal
      by level in every mode; the television keeps its chroma trap and narrow
      chroma. Generic softness, scanlines and masks are left to MiSTer, and
      every preset keeps sync and latency, so Direct Video stays clean.
      [Monitors and tests](docs/VIDEO_SOURCES.md#monitors).

- [ ] **PROM-backed memory-map validation.** Build an independent reference from
      the stock 5 V/256 KiB board's 342-0061 and 342-0063 decoder dumps, the
      342-0043 status and 342-0056 byte-selection logic, and schematic latch/mux
      wiring. Record dump hashes and test reads/writes across map boundaries,
      including the special $8F map and the hypothesized $87 alias, before changing
      the MMU. Separate documented behavior from unverified aliases and keep
      third-party 512 KiB decoding distinct from the stock board.

- [ ] **Apple II Mouse Interface card.** Use host mouse input and validate against
      an existing native mouse-driver configuration.

- [ ] **External memory and optional 512 KiB RAM.** Build on the parameterized
      RAM/MMU support with an external-memory backend and a usable 512 KiB option.
      Preserve paired-byte reads and guest-visible memory timing, and budget for
      future card RAM and disk buffers.

- [ ] **PCPI Appli-Card.** Add it as the first CP/M option and validate its disk
      services against the chosen storage configuration.

- [ ] **Microsoft SoftCard III.** Add it as a second CP/M option, including the
      required bus integration and storage-driver configuration.

- [ ] **Titan III+II.** Add support for this expansion.

- [ ] **Titan III+IIe.** Add support for this expansion.

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
- **gyurco** for the 6551 UART core, Disk II write support and his T65 fixes.
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
- **npwoods, rb6502 and the MAME team** for the `apple3` driver, MOS 6551 and
  CFFA card models used as cross-checks.
- **Klaus2m5** for the 6502 functional test suite.
- **Applesauce** for the WOZ format reference.
- The **AppleCommander** team for the disk-image tool behind the block-card
  test media.
- **wizzomafizzo** for Zaparoo, which drives the keystrokes and screenshots in
  the hardware tests.
- **david-schmidt** for apple3.org, and the bitsavers, Asimov and
  vintagecomputer.ca archives for the manuals, schematics and PROM dumps.

Imported components retain their own license notices, including the
[GPL-3.0-or-later WOZ implementation](rtl/disk/woz/README.md).
