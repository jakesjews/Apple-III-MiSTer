# Virtual block-storage card

Slot 1 holds a virtual ProDOS block-mode card. It serves two hard-disk images
from Main's block-device assignments, S4 and S5, as drives 1 and 2. SOS uses
it through Rob Justice's [Problock3](https://github.com/robjustice/Problock3)
driver, and the [soshdboot](https://github.com/robjustice/soshdboot) ROM and
kernel boot from it with no floppy. The card is modeled on the AppleWin
hard-disk controller that the Apple II MiSTer core uses, with its own
firmware. It occupies only slot 1's device and ROM pages: no interrupts, no
$C800 expansion ROM.

## Using it

1. Put a ProDOS-order image in `games/Apple-III/` and choose it with **Mount
   Hard Disk 1** or **Mount Hard Disk 2**. PO, HDV and ProDOS-order 2MG are
   accepted; the length must be a multiple of 512 bytes. Images are written
   in place, so keep a copy. A file that is read-only on the SD card, a
   write-protected 2MG, a DC42 container or a zip member is read-only.
   SOS and ProDOS address 65,535 blocks, so an image beyond 32 MiB shows only
   its first 65,535 blocks.
2. Stock SOS needs the Problock3 driver in `SOS.DRIVER`. Its default slot
   setting, $FF, scans slots 4 to 1 for the card's signature, so the card is
   found with no configuration. Drive 1 is `.PROFILE` and drive 2 is `.PB2`.
   Build the driver with cc65 and install it with
   [`sim/blockdev/sos_driver.py`](../sim/blockdev/sos_driver.py) and
   AppleCommander, as in the [test notes](../sim/blockdev/README.md), or
   through the System Configuration Program from a driver file. The SOS 1.3
   utilities disk ships a `.PROFILE` driver for Apple's ProFile card; the
   Problock3 driver replaces it.
3. To boot from the card, set **Boot ROM** to **soshdboot**, mount an image
   that carries its two-block loader and modified `SOS.KERNEL`, such as the
   [ready-made images](https://github.com/robjustice/soshdboot/tree/master/disks)
   in that repository, and reset. The built-in ROM is Rob Justice's
   ([provenance](../rtl/soshdboot/README.md)). It scans slots 4 to 1 and loads
   block 0 of drive 1 to $A000, or boots the floppy when drive 1 is empty;
   Alpha Lock down at reset boots the floppy instead, and a key held during
   the scan boots drive 2. The images are user-supplied.

   Any other image on drive 1 stops the boot, because the ROM runs its block 0
   whatever it holds: an AppleCommander volume hangs, a blank block 0 crashes,
   and Apple's ProDOS/SOS boot block stops at `KERNEL NOT FOUND` or a black
   screen. Choose **Apple** for such images, or turn on Alpha Lock
   (Caps Lock) and press Ctrl + F2 to boot the floppy; OSD **Reset** turns
   Alpha Lock off again.

With **Boot ROM** at **Apple**, the default, boot is unchanged: Apple's ROM
boots the internal floppy, with or without images on the card.

### Making an image

`tools/blank_hd.py` writes a formatted, empty volume, 16 MiB unless `--size`
says otherwise (up to 65,535 blocks). With `--boot-from` and one of Rob Justice's
images it also takes soshdboot's loader, `SOS.KERNEL`, `SOS.DRIVER` and the
program that image boots:

```sh
tools/blank_hd.py data.po                                       # empty, for Hard Disk 2
tools/blank_hd.py selector.po --boot-from sos_selector_hd.po    # boots the Selector
```

The Selector keeps that image's menu, whose entries find nothing until their
folders are copied over. The Utilities floppy's programs cannot boot from the
card this way: its Pascal system asks for the built-in drive.

The Utilities' **Format a volume** cannot do this on the card: Problock3 has no
formatter (control code $FE), and SOS reports error 103.

## Card interface

Slot 1 decodes $C090–$C09F for the registers and $C100–$C1FF for the
firmware ([slot rules](SLOTS.md)). Register offsets:

| Offset | Access | Function |
|---|---|---|
| 0 | read | Execute the command. The card holds RDY until the result is in the buffer, then returns the error code, 0 for success. |
| 1 | read | Last error code |
| 2 | read/write | Command: 0 status, 1 read, 2 write, 3 format |
| 3 | read/write | Unit; bit 7 selects drive 2 |
| 4, 5 | read/write | Block number, low and high byte |
| 6, 7 | read | Block count of the selected drive, low and high byte |
| 8 | read | Next buffer byte; the read advances the pointer |
| 9 | write | Next buffer byte; the write advances the pointer |

Writing the command register rewinds the buffer pointer, and completing a
command rewinds it again. Offsets 8 and 9 are separate so that the 6502's
dummy read during an indexed store cannot move the pointer, the problem MAME
works around in its CFFA2 card for the Apple /// driver's `sta $c080,x`.
Undriven offsets read $FF.

Errors follow ProDOS 8: $27 I/O error for a block beyond the image or an
unknown command, $28 no device connected for an empty drive, $2B write
protected. Status and format complete immediately; format changes nothing.
A read or write of a mounted, in-range block raises the drive's MiSTer SD
request and holds the CPU on the execute read until Main has moved the
512 bytes. Reset drops a pending request, clears the registers and releases
RDY; the next command waits for an abandoned host transfer to finish before
starting its own. Mounts survive reset.

### Firmware

[`rtl/cards/apple3_block_firmware.s`](../rtl/cards/apple3_block_firmware.s)
assembles to the 256-byte $C1xx page. It carries the ProDOS block-device
signature ($C101 = $20, $C103 = $00, $C105 = $03, $C107 = $3C), the status
byte at $C1FE ($D7: removable, interruptible, two volumes, read, write and
status), and the entry offset at $C1FF. The entry takes the standard
parameters: command at $42, unit at $43 with the slot in bits 6–4 and the
drive in bit 7, buffer pointer at $44, block number at $46. It returns carry
clear and A = 0 on success, or carry set and the error code; STATUS also
returns the block count in X and Y. The slot comes from the unit byte, which
Problock3, the soshdboot ROM and ProDOS all supply, so the image does not
depend on the slot. A read copies the buffer to `($44),Y` and a write copies
from it, restoring $45 afterwards. Problock3 sets the bank register before the
call so that pointer reaches the caller's buffer.

$C108 holds Apple II `PR#1` boot code: it reads block 0 of drive 1 to $0800
and jumps to $0801 with X = $10, calling the entry through the stack because
the ROM cannot patch itself. It uses the monitor's RTS at $FF58, which every
Apple II ROM provides.

### Host side

`apple3_block_card` shares one block number and one 512-byte buffer between
both drives, because only one request is outstanding at a time; the top level
copies them to S4 and S5. Main's Apple /// profile treats S4 and S5 as block
images: 2MG data offsets are honoured and writes go in place behind the
header. [Main storage](MAIN_STORAGE.md) describes the formats.

### Why slot 1

Problock3 and the soshdboot ROM find the card in any slot. Slot 4 is the
Apple II mouse card's usual place and what Rob Justice's mouse-enabled image
expects, so the block card leaves it free. The slot is only a matter of which
slot's selects and ready input `Apple-III.sv` wires to the card; the firmware
and the card itself do not depend on it.

## Validation

`./sim/blockdev/run.sh` (in `sim/run_tests.sh`) runs three checks:

- The firmware hex the RTL loads must match its assembled source.
- `block_card_tb.sv` drives the card's bus and host ports directly: the
  firmware image and signature, every register, RDY held through host
  latency, a read, a write that reaches the host image and reads back, the
  pointer rewinds, each error code, a reset during a transfer and the wait for
  the abandoned acknowledgement, the 65,535-block cap on a 64 MiB image,
  unmounting, and read-only offsets. 2,366 checks.
- `core_block_tb.sv` boots `diagnostic.s` on the real T65, MMU and card bus
  with the card in slot 1 and a host model with 5,000 clocks of latency. The
  program scans the slots for the signature like Problock3, then calls the
  $C1FF entry for STATUS of both drives, a read into $2000, a write of block
  5 and its readback, reads and refused writes on the protected drive 2, a
  block beyond the end, an unmounted drive and a read into a buffer in
  another RAM bank. The bench checks the host image after the write and that
  no CPU cycle completes while RDY is held.

SOS boot runs use `sim/run_core_boot.sh` with `--hd1=IMAGE`:

- Stock ROM, SOS 1.3 utilities floppy with Problock3 replacing `.PROFILE`, a
  16 MiB image on drive 1. The utilities list `.PROFILE`.
- `--block-boot` with the soshdboot ROM (`APPLE3_ROM`, now `--soshdboot`), no
  floppy, the same image on drive 1. SOS boots from the card to the
  Selector /// menu.

Results are in the [results sections](#results-2026-09-18) below.

## Sources

- Apple II MiSTer core `hdd.vhd` and AppleWin `Harddisk.cpp`: register model.
- [Problock3](https://github.com/robjustice/Problock3) `Problock3.s`: signature
  scan, unit numbering, buffer and bank handling, error mapping.
- [soshdboot](https://github.com/robjustice/soshdboot) `saratests.s` and
  `bootloader_prodos_sos.s`: the ROM's card search and block-0 load, the
  two-block loader, `problock3kernel.s`.
- MAME `a2cffa.cpp`: the Apple /// indexed-store dummy-read note.
- Apple's *ProDOS 8 Technical Reference Manual*, chapter 6: block device
  firmware signature, entry parameters, status byte and error codes.
- [Slot interface](SLOTS.md) and [peripheral timing](PERIPHERAL_TIMING.md):
  RDY rules the card follows.

## Results, 2026-09-18

- `sim/blockdev/run.sh`: the register bench passes 2,366 checks; the real-CPU
  diagnostic completes in 1,524,022 master clocks with 5 host transfers and a
  longest RDY hold of 7,058 clocks. `sim/run_tests.sh`, `sim/accuracy/run.sh`
  (zero failing groups), `sim/joystick/run.sh` and `sim/serial/run.sh` pass
  with the card installed, as do `make lint` and `make format-check`.
- Main's sanitizer suite passes with the block-image write tests, and the
  regenerated patch applies to its upstream base.
- Stock ROM, SOS 1.3 utilities floppy with Problock3 in place of `.PROFILE`,
  the 16 MiB `sos_selector_hd.po` on drive 1 and drive 2 empty: SOS initialises
  both units (the empty one reports no device) and shows the menu at 36.5 s
  of machine time. **List files** of `.profile` prints the `/SOS` directory,
  105 block transfers. **Make a new subdirectory** `.profile/blocktest`
  reports `/SOS/BLOCKTEST made` after 71 transfers; the saved image differs
  from the original only in blocks 2, 4, 8 and 10846, the volume directory,
  its bitmap and the new key block, and lists the directory on the host.
- soshdboot ROM with no floppy: block 0 loads to $A000 and SOS boots from the
  card to the Selector /// title in 5.67 million CPU cycles, about 4 s, with
  172 transfers.
- Quartus 17.0.2: 0 errors, 42 warnings; worst setup slack 0.772 ns, hold
  0.206 ns; 19,735 ALMs (47%) and 489 M10K blocks (88%).
- MiSTer with the paired Main: the same utilities floppy boots with the image
  on **Mount Hard Disk 1** and [lists `/SOS`](blockdev/2026-09-18-utilities-list-profile.png);
  [creating `/SOS/HWTEST`](blockdev/2026-09-18-utilities-mkdir.png) changed
  blocks 2, 4, 8 and 10846 of the image on the SD card, the same four blocks as
  in simulation, and the copy pulled from the card lists the new directory.
  The soshdboot ROM loaded through **Load Boot ROM** boots the image with no
  floppy to the [Selector /// menu](blockdev/2026-09-18-soshdboot-selector.png)
  within 45 s of the MGL start, and the one-block `soshdboot.dsk` loader floppy
  boots the same image with the stock ROM.

## Results, 2026-09-22 and 23: built-in soshdboot ROM

- `sim/rom_tb.sv`: every address of both banks reads Apple's ROM, then the
  soshdboot ROM when selected; a 4 KiB upload replaces Apple's ROM and leaves
  the soshdboot choice alone. An upload first won over the option, but a
  MiSTer set up before Apple's ROM was built in still holds it as
  `games/Apple-III/boot.rom`, which MiSTer sends at every start, so the option
  did nothing there.
- `sim/blockdev/run_soshdboot.sh`: with `--soshdboot` and no floppy, one card
  transfer and a jump to $A000 in 1.6 million CPU cycles. Without the option
  the same run never reads the card.
- `--soshdboot`, `sos_selector_hd.po`, no floppy: the Selector /// menu in
  5.67 million CPU cycles with 172 transfers, as with the ROM file on 2026-09-18.
- `--soshdboot`, drive 1 empty, SOS 1.3 utilities floppy: the Utilities menu,
  the card reporting no device.
- `--soshdboot`, the same floppy, and an 800 KiB ProDOS data volume on drive 1:
  AppleCommander's block 0 hangs; a blank block 0 crashes into a memory dump;
  Apple's ProDOS/SOS boot block stops at `KERNEL NOT FOUND`, or at a black
  screen with the MGL's timing (`--mount-delay=8 --reset-delay=3`), as on the
  MiSTer. With `--alpha-lock` the ROM skips the card and the utilities boot.
- MiSTer, 2026-09-23, with Apple's ROM still in `games/Apple-III/boot.rom`:
  **Boot ROM** soshdboot and `sos_selector_hd.po` on **Hard Disk 1** with no
  floppy boots to the Selector /// menu; the utilities floppy with **Hard
  Disk 1** empty boots to the Utilities menu; the floppy with the data volume
  and Apple's boot block stops at a black screen, and Caps Lock then
  Ctrl + F2 boots the utilities. **Boot ROM** Apple with the floppy and the
  Selector image boots the utilities.
