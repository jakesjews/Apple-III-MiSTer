# Companion Main storage integration

This core requires the companion Main changes in
[`support/main/apple3-storage.patch`](../support/main/apple3-storage.patch).
The patch applies to MiSTer-devel/Main_MiSTer commit
`f80abdc79e76bfc63799d028f2337c4d762b5e50`.

The changes extend `support/a2/iigs_disk.{cpp,h}`, `iigs_fmt.{cpp,h}` and the
existing `SD_TYPE_IIGS` dispatch in `user_io.cpp`. There is one shared codec;
Apple III supplies a format profile for its synchronized tracks and, where a
disk needs it, the SOS protection key. The hardware retains its own P6
controller and Disk III drive logic.

| Main mount | Apple III assignment | Policy |
|---|---|---|
| S0 | Internal Disk III (.D1) | Native WOZ2 and sector-image writes; NIB read-only |
| S1 | First external Disk III (.D2) | Native WOZ2 and sector-image writes; NIB read-only |
| S2, S3 | Block-device assignments | Raw ProDOS-order payload, read-only |

The present FPGA exposes **S0 and S1 only**. S2/S3 are tested Main assignments
for a future block-device interface; this change does not add a ProFile or
expansion-card controller to the Apple III hardware.

Main recognizes Apple III only when its S0 format list advertises WOZ, preserving
older cores' raw/NIB interface. The //e and IIgs retain their existing, different
mount assignments and write policies.

## Formats and transport

- Raw DSK/DO uses DOS order; PO uses ProDOS order. 2MG's format, data offset,
  payload length and volume flags take precedence. Invalid headers are rejected.
- 140K ProDOS-order images use the standard sector map: block 2, the volume
  directory, is DOS sectors 11 and 10. The map inherited from upstream Main
  placed only sectors 0 and 15 correctly, so real `.po` images did not boot.
- SOS copy protection (`BFM.INIT2`) reads one address-field volume byte on each
  of tracks 9 to 16. If those tracks are synchronized and the bytes differ, SOS
  takes them as a key and decrypts `SOS.INTERP` in memory. Main rebuilds that
  key only for a volume whose `SOS.INTERP` is encrypted: it decodes a sample
  with the key and keeps whichever version has the byte statistics of 6502
  code. Of 29 apple3.org images checked, three are protected dumps (Apple
  Writer III, the System Demonstration and VisiCalc's boot disk). Giving the key
  to a plain disk makes SOS decrypt working code and stop with SYSTEM FAILURE
  $06 whenever its synchronization check passes, which on hardware was most
  boots.
- NIB is packed directly into a bitstream without a sector decode/re-encode.
  Standard FF sync gaps acquire ten-bit spacing; data/address bytes stay intact.
- Native WOZ is fully validated (signature, chunks, track bounds, optional CRC)
  and served from RAM without normalization. Both drives keep separate buffers.
- WOZ1, FLUX, NIB, archived and write-protected images are read-only. Writable
  WOZ2 persists only existing track allocations. It cannot allocate an unmapped
  track or resize tracks.
- DSK, DO, PO and sector-order 2MG images are written in place. The drive saves
  a track one 512-byte block at a time, so the track is torn until its last
  block arrives. Main decodes it then with a strict parser: address checksum and
  track number, a data field within the following gap, valid GCR codes, data
  checksum and both epilogs. Verified sectors replace the file's, in the file's
  own sector order and behind any 2MG header, with one 4 KiB write per track.
  The image is opened O_SYNC, and sixteen separate sector writes held the
  drive's cache busy long enough to break SOS's formatter. A damaged sector
  never reaches the file, and Main shows how many were not saved. The
  reconstructed SOS address-field key is not stored, because sector images have
  no address fields.
- Converted Apple III tracks hold 51,424 cells read at 3.875 us (INFO timing
  31), not the bare 50,304 at 4 us. The drive model consumes one cell per bit
  the machine writes, so a track's cell count is what the machine's own
  formatter measures as drive speed. Apple's Disk III formatter shrinks its
  sync gap until sixteen sectors of 10n + 2,988 cells close the track and
  accepts 19 to 24 nibbles, 22 being a correctly adjusted drive. On 50,304
  cells SOS reported "drive is too fast" and the Confidence Program's Align
  check failed; on 51,904 it closed at 25, "too slow". 51,424 closes at 22. The
  inter-track rotation is recomputed so SOS's key sectors still pass the head
  56.5 ms apart.
- Main receives complete transfers of up to 16 KiB and zero-pads partial reads.
  Native writes reject metadata/out-of-file ranges and clear the CRC to the WOZ
  specification's zero/not-calculated value. Unknown chunks are preserved.
- Block payloads use their declared lengths, excluding 2MG comments or DC42 tags.
  Main never silently moves an image to another mount slot.

## Build and install

From the Apple III repository root, clone the matching Main source and apply
its patch:

```sh
git clone https://github.com/MiSTer-devel/Main_MiSTer.git ../Main_MiSTer-AppleIII
git -C ../Main_MiSTer-AppleIII checkout f80abdc79e76bfc63799d028f2337c4d762b5e50
git -C ../Main_MiSTer-AppleIII apply ../Apple-III-MiSTer/support/main/apple3-storage.patch
```

In that checkout, use Main's normal ARM Linux cross toolchain and run
`make -j6 MAKEFLAGS=-j6`. For the FPGA, follow the
[core build instructions](DEVELOPMENT.md#building).
Copy `bin/MiSTer` to `/media/fat/MiSTer_AppleIII`. In `MiSTer.ini`:

```ini
[Apple-III]
main=MiSTer_AppleIII
```

MiSTer selects that binary only for Apple III and returns to the normal Main
when loading Menu or another core. Keep the paired Main and RBF together.
For an MGL, mount files with `type="s"`, indexes 0 and 1. The validation MGL
uses eight-second mount delays and a three-second reset delay (units are seconds).

## Tests and conversion utility

From the Main checkout, run `tests/apple3/run.sh`. It builds the actual shared
backend with file/SPI shims under address and undefined-behavior sanitizers.
Tests cover format/slot matching, DOS/PO/2MG equivalence, bit-packed GCR, NIB
preservation, multi-block transfers, read-only enforcement and native WOZ writes
that survive remount while preserving unrelated bytes. The ProDOS-order map is
pinned to block positions rather than to the codec's own inverse, and the
protection key must appear only for an encrypted `SOS.INTERP`. Sector write-back tests
save tracks block by block into DSK, PO and 2MG sources and check after every
block that each sector holds either its old or its new contents; a bad data
checksum, a lost data prologue and another track's address fields must all leave
the affected sectors untouched. The tests live in the patch and are not part of
the Main branch.

After that build, use the same backend to save an explicit WOZ2 copy of a sector
image or a NIB (a native WOZ is served unchanged, so a WOZ1 stays WOZ1):

```sh
/tmp/mister-apple3-tests/storage_test --convert source.dsk writable-copy.woz
```

This writes a separate output file. Mounting never creates an implicit converted
file; a sector image changes only when the Apple III writes to it. ROMs and
software disks are not distributed.
