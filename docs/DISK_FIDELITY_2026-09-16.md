# Disk III fidelity and Main-backed WOZ storage

The Apple III disk path now executes the original 341-0028 P6 logic instead of
supplying whole bytes and clearing them on CPU reads. It keeps Disk III's
native drive selection and disk-change behavior. Image handling lives in the
companion Main's shared Apple-family storage backend.

## Implementation

- `apple3_p6.sv`: Boolean equations equivalent to all 256 original PROM entries.
- `apple3_disk_sequencer.sv`: Q3*-clocked state register and 74LS323 behavior,
  including protection sensing and serialized bit writes.
- `apple3_disk.sv`: independent native spindle and I/O selection, unpopulated
  D3/D4 selection, approximately 2/3-second motor holdover, and phase-1
  acknowledgement of a disk change. Apple II mode uses its own enable behavior.
- `apple3_woz_drive.sv`: per-drive mount state, physical head/rotation model and
  WOZ cache. There is no FPGA sector converter or byte-based NIB write path.
- Main: Apple III S0/S1 floppy assignments, S2/S3 block assignments, image
  detection, container validation, ordering and shared WOZ conversion. The
  present FPGA exposes only the two floppies; no block controller is added.
- Main: complete multi-block transfers, native WOZ caching and file writes,
  metadata/allocation guards and CRC invalidation. Sector-image sources take
  verified per-sector write-back (added after the hardware run below); NIB
  sources and block images are read-only. Other Apple cores retain their policies.

The imported drive/cache and local fixes are documented in
[the provenance note](../rtl/disk/woz/README.md). Reads use standard MiSTer bursts
up to 16 KiB, splitting larger allocations; track writes remain single-block.
The FPGA reads the WOZ track directory into its cache; Main performs full-file
validation and owns the file format, conversion and persistence policy.

See [Main integration](MAIN_STORAGE.md) for the paired binary, configuration,
slot map and converter utility. Native WOZ bits are never normalized or decoded
back into sectors. Converted Apple III sector disks receive the standard SOS
synchronized-track layout. At the time of this run they all received the
address-field key as well; see the [2026-09-17 follow-up](#follow-up-2026-09-17).

## Validation

[Recorded results](disk/2026-09-16-simulation.txt) cover:

- All 256 P6 entries, 50,000 sequencer cycles and all 256 serialized write bytes
  against a separately supplied original PROM.
- WOZ1/WOZ2 track contents, quarter tracks, reset/remount, invalid signatures,
  invalid TMAP indices and oversized allocations. A 40-block track exercises
  splitting at the host's 16 KiB transfer limit.
- WOZ2 cache writeback changes exactly the requested track byte and leaves its
  header untouched; Main separately tests CRC invalidation and file persistence.
- WOZ timing in 125 ns units (including fast/slow mastering), standard 4 us cells
  over two revolutions, cache/flux gating, protection and isolated bit writes.
- Main under ASan/UBSan: DOS/PO/2MG equivalence, NIB preservation, multi-block
  transfers, header/payload bounds, native WOZ preservation, rejected writes,
  writable-track persistence and //e/IIgs regressions.
- Stock-ROM SOS 1.3 boot with two drives, using WOZ1 and WOZ2 generated/served
  by Main. WOZ2 also passes with 5 ms of host delay before every request, with
  zero loader I/O, read, retry or hard errors.
- Existing machine tests, zero failing accuracy groups, and interrupt-driven
  T65 serial echo (256 byte values plus 64 queued across a CTS stall).

Every valid bit of all 35 converted SOS tracks matches an independently
converted Apple III image. That reference uses `robjustice/a3dsk2woz`, with its
local descending-XOR loop bounded by `while (location > 1)` to avoid reading
`dest[-1]`. Padding outside the declared bit count is not disk content. ROMs
and software images remain local and are not distributed.

The paired Quartus build completed with zero errors, using six processors.
All 38 timing groups pass; minimum slack is +0.225 ns. Logic uses 17,099 ALMs
(41%) and 417 RAM blocks (75%). [Build record and hashes](disk/2026-09-16-build.txt).

On the physical MiSTer, the paired build reaches
[System Utilities with both drives mounted](disk/dual-drive-boot.png): Main
converts the original SOS DSK in D1 and serves a native, writable WOZ2 in D2.
[SOS renamed the D2 scratch volume](disk/woz-volume-write.png) from BLANK to
WOZVALIDATION01. Downloading and decoding the saved WOZ recovered all 560
sectors; only the name and its length changed (16 logical bytes). The on-disk
WOZ CRC became zero, with all other header/directory bytes preserved. The
source DSK remained byte-identical. After reloading the core and both images,
[SOS read the persisted volume name](disk/woz-volume-after-reload.png) from D2.

## Follow-up 2026-09-17

The hardware run above booted intermittently: seven of its screenshots show
**SYSTEM FAILURE = $06**, and the next evening 9 of 11 boots of the same
System Utilities DSK failed the same way, with either Main build and with one
drive or two. The simulation had never shown it because the boot test stopped
when SOS entered the interpreter.

Running the simulation on to the menu reproduced the failure on every boot.
SOS's `BFM.INIT2` found synchronized tracks and the protection key that the
converter added to every sector image, so it decrypted `SOS.INTERP`. That
image is deprotected and its interpreter is plain code, so the loader's entry
pointer became $4D3E instead of $830E, the stray code returned through an empty
stack, and the interrupt receiver's stack check raised failure $06. On hardware
SD latency made the synchronization check fail about one boot in five, and
only those boots survived.

Main now adds the key only when `SOS.INTERP` is encrypted
([details](MAIN_STORAGE.md#formats-and-transport)). With that change:

- Simulation, run to the menu with an MGL-style late mount and reset: the
  System Utilities DSK reaches its menu. The protected Apple Writer III and
  System Demonstration dumps, which do get the key, reach their title screens.
- Hardware: six of six captured two-drive boots reached the menu, with
  `direct_video` on and off.
- Sector-image write-back on hardware: SOS created a subdirectory on a DSK in
  each drive and on a ProDOS-order PO in drive 2. The host-side check found
  exactly the directory, bitmap and new directory blocks changed (2, 6 and 76)
  and every other byte identical. After reloading the core
  [SOS lists the new directory](disk/sector-image-write-after-reload.png).

`sim/run_core_boot.sh` gained `--to-menu`, `--mount-delay` and `--reset-delay`
so the boot test covers this path.

### Protected disks and the drive model

With the key now reserved for protected dumps, those disks showed the opposite
failure: the Apple Writer III DSK reached its title on 3 of 7 hardware boots
and stopped at SYSTEM FAILURE $06 on the other 4. Main-side timing logs showed
SOS reading all eight key tracks at the normal 56 ms cadence and then skipping
the one-second decrypt, so its synchronization check had failed. Host latency
was not the cause: a track transfer takes 2.7 ms and Main polls about every
0.25 ms.

A latency sweep in simulation reproduced it and `--disk-trace` located it in
the imported WOZ controller. `trk_bit_count` is assembled one byte per lookup
step and was visible to the drive while incomplete. After an unmapped half
track it starts from zero, so the track length read 128 bits for two clocks. A
bit-cell tick in that window made the drive wrap its rotation position to zero,
and every later sector arrived at the wrong angle. The count is now published
only when complete. The same controller reloaded a track on every quarter-track
change, two or three transfers of identical data per one-track step, each
blanking the flux; it now reuses the TRKS entry already in its track RAM. In
simulation that raises the tolerated track-load time from about 11 ms to about
40 ms. SOS's numbers from the trace: a one-track seek reaches its address read
after 48.2 ms, the key header follows about 6 ms later, sectors pass every
12.57 ms, and an address read with no flux gives up after 12 ms.

On hardware with the rebuilt core the Apple Writer III DSK reached its title on
10 of 10 captured boots and the System Demonstration DSK ran on 4 of 4. SOS
created directories on a DSK in each drive, and the host check again found only
the five expected sectors changed per image.

### Formatting and the Confidence disk test

The Confidence Program's Seek/Read/Write/Align test reported `err` on Align,
and SOS's Format a Volume failed on a converted DSK. Align is a format pass:
fill a track with sync, write sixteen sectors, check that the track closes, and
shrink the gaps until it does. The imported drive model consumes one cell per
written bit, so the cell count of a track is the "drive speed" a formatter
sees, and converted tracks had the bare minimum of 50,304 cells. Apple's
formatter source gives the criterion (19 to 24 sync nibbles per gap, 22
nominal), and a simulated SOS format gave the layout: 10n + 2,988 cells per
sector. Main now converts to 51,424 cells, which closes at 22, with a 3.875 us
read cell and the inter-track rotation recomputed for it.

On hardware SOS then formatted three tracks and stopped with an I/O error.
Main's write-back did up to sixteen synchronous sector writes per saved track;
it now stores each track once, with a single write, when its last block
arrives. With that build [SOS formats a DSK](disk/sos-format-dsk.png) (twice of
two tries; all 35 tracks rewritten and the image reads back as an empty 280
block volume, which then took a new directory), the
[Confidence disk test passes](disk/confidence-disk-test.png) every check for
D1, and the protected Apple Writer III DSK reached its title on 6 of 6 boots.
A simulation with 25 ms added to every saved block still formatted, so the
single-write change is supported by the hardware result, not by simulation.

### Clock

SOS keeps the two-digit year in the MM58167's day and month compare latches.
The core seeded the counters from MiSTer's clock but left those latches at
power-on don't-care, which reads as year 00; Apple Pascal then treated the clock
as unset and overwrote it with the date stored on the boot disk, so Utilities
showed 16 Dec 87 counting up from midnight. The host seed now writes the year
latches and maps the weekday (MiSTer Sunday = 0, chip Sunday = 1). Hardware
shows the correct date and time, with the year as SOS's two digits.

The paired build for this follow-up passes all 38 timing groups with
+0.246 ns minimum slack. [Build record and hashes](disk/2026-09-17-build.txt).

## Limits

WOZ1 and FLUX representations are read-only. Writes modify existing allocated
WOZ2 bitstream tracks; allocating an unmapped track is not supported. The track
cache is bounded. Main validates a nonzero source CRC and writes zero after a
modification, as permitted by WOZ's not-calculated convention.

Converted sector/NIB images cannot recover lost mastering timing, weak regions
or write splices. The imported analog/weak-bit and head-motion models remain
approximations. Exact angular equivalence across different-length/FLUX tracks
and broad copy-protection compatibility are unproven. This does not claim full
electrical or mechanical equivalence to every Disk III drive.
