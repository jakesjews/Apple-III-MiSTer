# Apple /// for MiSTer

__Warning: This core is vibe coded.__

A complete [Apple ///](https://en.wikipedia.org/wiki/Apple_III) core, and a very
usable one: most software tried so far runs well. That includes SOS 1.3 and its
System Utilities, Business BASIC, Apple Writer III, Selector /// booted from a
hard-disk image, and the Apple II emulation disk. Apple's Confidence Program
passes its memory, interrupt and four-drive disk tests.

- 256 KiB RAM, every native video mode and the Apple II modes
- Four floppy drives: WOZ, DSK, DO, PO, NIB and 2MG, writable and formattable
- A hard-disk card with two images, bootable without a floppy
- Keyboard, joysticks, clock, audio and serial

[Hardware validation](docs/PERIPHERAL_TIMING.md#confidence-program-11-on-2026-09-18) ·
[Four drives](docs/FOUR_DRIVES.md) · [Hard disk](docs/BLOCK_STORAGE.md#results-2026-09-18)

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

4. Supply the 4,096-byte Apple /// boot ROM as
   `/media/fat/games/Apple-III/boot.rom`. It is the file MAME calls
   `apple3.rom`. ROMs are not included.

   | Name | Size | CRC32 | SHA-1 |
   |---|---|---|---|
   | `apple3.rom` | 4096 | `1af7ec42` | `8043f914ebdcdab9838dbb78f8a2ee3867d210d2` |

5. Put disk images in `/media/fat/games/Apple-III/`, launch the core, and use
   **Mount Drive 1** to select a boot disk. **Mount Drive 2–4** are the three
   external Disk III drives. Each drive has its own **Write Protect** option.
   **Mount Hard Disk 1** and **2** take ProDOS-order images for the block
   card in slot 1; SOS reaches them through the
   [Problock3](https://github.com/robjustice/Problock3) driver, and the
   [soshdboot](https://github.com/robjustice/soshdboot) ROM boots from them
   without a floppy. [Details](docs/BLOCK_STORAGE.md).
6. If SOS lists only two drives, use System Utilities → **System Configuration
   Program**: read your `SOS.DRIVER`, set **Change System Parameters → Number of
   Disk III Drives** to **4**, then **Generate New System** to save `SOS.DRIVER`
   on your boot disk and reboot. Apple II emulation uses drives 1 and 2.

Use matching core and Main builds. The custom Main is selected only for this
core. The supplied `MiSTer_AppleIII` binary comes from
[jakesjews/Main_MiSTer](https://github.com/jakesjews/Main_MiSTer), with the complete
matching source changes included in this repository's Main patch.
[Build instructions and Main patch](docs/MAIN_STORAGE.md).

## Disk images

Supported: **WOZ, DSK, DO, PO, NIB and 2MG**.

- **DSK, DO, PO, NIB and 2MG** are writable, and SOS can format the sector
  images. A NIB track is saved only when all sixteen of its sectors read back
  cleanly. Saves go
  straight into the image you mounted, so keep a copy of anything you want to
  preserve, or make the file read-only on the SD card to protect it.
- **WOZ2** is writable. Writes require existing track allocations; formatting
  cannot create missing tracks.
- WOZ1, flux-encoded WOZ and images inside a zip are **read-only**.
- A raw 140K image's sector order is detected from its SOS/ProDOS directory
  or DOS 3.3 VTOC, so a ProDOS-order file named `.dsk` works. Without either,
  `.dsk`/`.do` mean DOS order and `.po` ProDOS order. For 2MG files, the header
  determines the order.
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

**Keyboard** in the OSD selects the Apple /// Plus keyboard, which adds that
machine's one extra key, DELETE, on the host Delete key.

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

- [ ] **Video source modes.** Add monochrome-composite and color-composite modes
      alongside the existing RGB output. Include Apple II artifact color, native
      III composite behavior and the dedicated monochrome signal's grayscale
      behavior.

- [ ] **III Plus model with authentic interlace.** Reuse the existing clock and
      keyboard work. Implement field timing and display-memory behavior rather
      than simply doubling lines.

- [ ] **Apple II Mouse Interface card.** Use host mouse input and validate against
      an existing native mouse-driver configuration.

- [ ] **External memory and optional 512 KiB RAM.** Build on the parameterized
      RAM/MMU support with an external-memory backend and a usable 512 KiB option.
      Preserve paired-byte reads and guest-visible memory timing, and budget for
      future card RAM and disk buffers.

- [ ] **Display Monitor Modes.** Similar to the Apple II core.

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
