# [Apple ///](https://en.wikipedia.org/wiki/Apple_III) for MiSTer

__Warning: This core is vibe coded.__

Experimental Apple /// core with 256 KiB RAM, two floppy drives, joystick,
audio and serial support. Tested with SOS 1.3 System Utilities and Business BASIC.

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
   **Mount Drive 1** to select a boot disk. **Mount Drive 2** is the external drive.

Use matching core and Main builds. The custom Main is selected only for this
core. The supplied `MiSTer_AppleIII` binary comes from
[jakesjews/Main_MiSTer, branch `apple3-disk-storage`](https://github.com/jakesjews/Main_MiSTer/tree/apple3-disk-storage).
[Build instructions and Main patch](docs/MAIN_STORAGE.md).

## Disk images

Supported: **WOZ, DSK, DO, PO, NIB and 2MG**.

- **DSK, DO, PO and 2MG** are writable, and SOS can format them. Saves go
  straight into the image you mounted, so keep a copy of anything you want to
  preserve, or make the file read-only on the SD card to protect it.
- **WOZ2** is writable. Writes require existing track allocations; formatting
  cannot create missing tracks.
- WOZ1, flux-encoded WOZ, NIB, NIB-payload 2MG and images inside a zip are
  **read-only**.
- Raw `.dsk`/`.do` files use DOS sector order; `.po` uses ProDOS order.
  For 2MG files, the header determines the order.
- Sector dumps of copy-protected originals (an encrypted `SOS.INTERP`) get the
  SOS protection key and synchronized tracks automatically. Deprotected disks,
  which is most of what circulates, are left without the key so SOS does not
  try to decrypt them.

Most Apple III software circulates as DSK, and most of the original-disk WOZ
dumps on Asimov are WOZ1, so they mount read-only. To turn a DSK or NIB into a
writable WOZ2, see the [conversion instructions](docs/MAIN_STORAGE.md#tests-and-conversion-utility).
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

- [ ] **All four Disk III drives.** Extend the current internal drive and one
      external drive to expose all four drives, retaining the Disk II-compatible
      option. Preserve shared disk-phase/fine-scroll behavior and independent
      mounting, write protection and media-change state.

- [ ] **Reusable slots 1–4.** Implement slot I/O, ROM selection/deselection and
      per-slot interrupt routing. Add coprocessor bus ownership when the first
      card needs it.

- [ ] **Peripheral wait-state and boundary timing.** Implement and test delayed
      IOSTOP/ready behavior, and complete extended-horizontal-state timing beyond
      the existing scan counters and Q3 hold.

- [ ] **One virtual block-storage interface.** Add a virtual card modeled on the
      Apple II core's hard-disk card, with its own ProDOS block-mode firmware,
      so SOS uses it through the [Problock3](https://github.com/robjustice/Problock3)
      driver and needs no new driver. It needs only one fixed slot's I/O and ROM
      pages, not interrupts, `$C800` ROM or the rest of the slots work. Serve two
      units from Main's block-image assignments with block reads and writes,
      status, capacity from the image size and error handling, and add write
      support to Main. Stock boot is unchanged; the
      [soshdboot](https://github.com/robjustice/soshdboot) ROM and kernel boot
      directly from the card. Both are user-supplied, like the ROMs. Test the
      card in simulation and an SOS boot with Problock3, using MAME's CFFA2 card
      as a reference.

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
