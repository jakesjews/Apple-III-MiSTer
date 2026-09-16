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
  metadata/allocation guards and CRC invalidation. Converted sources and block
  images are read-only for Apple III. Other Apple cores retain their policies.

The imported drive/cache and local fixes are documented in
[the provenance note](../rtl/disk/woz/README.md). Reads use standard MiSTer bursts
up to 16 KiB, splitting larger allocations; track writes remain single-block.
The FPGA reads the WOZ track directory into its cache; Main performs full-file
validation and owns the file format, conversion and persistence policy.

See [Main integration](MAIN_STORAGE.md) for the paired binary, configuration,
slot map and converter utility. Native WOZ bits are never normalized or decoded
back into sectors. Converted Apple III sector disks receive the standard SOS
synchronized-track layout and address-field key.

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
