# Companion Main storage integration

This core requires the companion Main changes in
[`support/main/apple3-storage.patch`](../support/main/apple3-storage.patch).
The patch applies to MiSTer-devel/Main_MiSTer commit
`f80abdc79e76bfc63799d028f2337c4d762b5e50`.

The changes extend `support/a2/iigs_disk.{cpp,h}`, `iigs_fmt.{cpp,h}` and the
existing `SD_TYPE_IIGS` dispatch in `user_io.cpp`. There is one shared codec;
Apple III supplies a format profile for its synchronized tracks and SOS address
volume key. The hardware retains its own P6 controller and Disk III drive logic.

| Main mount | Apple III assignment | Policy |
|---|---|---|
| S0 | Internal Disk III (.D1) | Native WOZ2 writes; conversions read-only |
| S1 | First external Disk III (.D2) | Native WOZ2 writes; conversions read-only |
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
- NIB is packed directly into a bitstream without a sector decode/re-encode.
  Standard FF sync gaps acquire ten-bit spacing; data/address bytes stay intact.
- Native WOZ is fully validated (signature, chunks, track bounds, optional CRC)
  and served from RAM without normalization. Both drives keep separate buffers.
- WOZ1, FLUX, archived/write-protected images and every converted image are
  read-only. Writable WOZ2 persists only existing track allocations. It cannot
  allocate an unmapped track or resize tracks.
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
that survive remount while preserving unrelated bytes.

After that build, use the same backend to save an explicit WOZ copy:

```sh
/tmp/mister-apple3-tests/storage_test --convert source.dsk writable-copy.woz
```

This writes a separate output file. Mounting a DSK never modifies its source or
creates an implicit converted file. ROMs and software disks are not distributed.
