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

- **DSK, DO, PO and 2MG** are writable. Saves go straight into the image you
  mounted, so keep a copy of anything you want to preserve, or make the file
  read-only on the SD card to protect it.
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
- SOS-protected disks rely on a track-to-track timing check that SD card latency
  can upset. If one stops at **SYSTEM FAILURE = $06** during boot, reset and try
  again.

## Planned features and accuracy work

The following items remain open. Existing partial implementations are noted
where they provide a starting point.

1. **Confidence Program regression.** Recheck the **Machine Configuration**
   hang with the completed Disk III controller and add a regression test.
   Remove the known limitation above if the retest confirms it is resolved.

2. **Keyboard accuracy and optional III Plus keymap.** Build on the existing
   encoder, modifier tracking and repeat tests. Complete repeat activation
   ordering, cursor second-stage behavior and the corresponding guest-visible
   modifier state, and add an optional III Plus keymap.

3. **All four Disk III drives.** Extend the current internal drive and one
   external drive to expose all four drives, retaining the Disk II-compatible
   option. Preserve shared disk-phase/fine-scroll behavior and independent
   mounting, write protection and media-change state.

4. **Reusable slots 1–4.** Implement slot I/O, ROM selection/deselection and
   per-slot interrupt routing. Add coprocessor bus ownership when the first
   card needs it.

5. **One virtual block-storage interface.** Use a single interface in place of
   separate historical storage-card projects, with compatible SOS driver and
   firmware support. Main already has read-only block-image assignments, but
   the core has no block controller. Add block reads/writes, status, capacity
   and error handling, and a known working SOS configuration. Keep optional
   direct hard-disk boot separate from stock boot behavior.

6. **Video source modes.** Add monochrome-composite and color-composite modes
   alongside the existing RGB output. Include Apple II artifact color, native
   III composite behavior and the dedicated monochrome signal's grayscale
   behavior.

7. **Native joystick accuracy.** Complete the existing conversion and switch
   model with accurate charge/start/timeout behavior. Test different polling
   and timer methods, and provide a host mapping for the latching switch.

8. **Peripheral wait-state and boundary timing.** Implement and test delayed
   IOSTOP/ready behavior, and complete extended-horizontal-state timing beyond
   the existing scan counters and Q3 hold.

9. **Display-fetch and character-download timing.** Replace the current line
   prefetch and batched character downloads with hardware-equivalent timing.
   Add tests for writes during active display and around character-download
   boundaries, extending the static rendering checks.

10. **Apple II Mouse Interface card.** Use host mouse input and validate against
    an existing native mouse-driver configuration.

11. **External memory and optional 512 KiB RAM.** Build on the parameterized
    RAM/MMU support with an external-memory backend and a usable 512 KiB option.
    Preserve paired-byte reads and guest-visible memory timing, and budget for
    future card RAM and disk buffers.

12. **PCPI Appli-Card.** Add it as the first CP/M option and validate its disk
    services against the chosen storage configuration.

13. **III Plus model with authentic interlace.** Reuse the existing clock and
    keyboard work. Implement field timing and display-memory behavior rather
    than simply doubling lines.

14. **Microsoft SoftCard III.** Add it as a second CP/M option, including the
    required bus integration and storage-driver configuration.

15. **Titan III+II.** Add support for this expansion.

16. **Titan III+IIe.** Add support for this expansion.

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
