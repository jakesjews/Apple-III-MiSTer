# WOZ media implementation

Imported from [MiSTer-devel/Apple-II_MiSTer](https://github.com/MiSTer-devel/Apple-II_MiSTer/tree/a9498bb079993323966d98286b0e5dbe0e7d01d8/rtl/woz),
commit `a9498bb079993323966d98286b0e5dbe0e7d01d8` (2026-09-16).
`flux_drive.v` and `woz_floppy_controller.sv` are copyright 2026 Alan Steremberg,
GPL-3.0-or-later; the accompanying `woz_bram.sv` and `woz_cell525.sv` are from the
same implementation. Original notices are retained; see [COPYING](COPYING).

The Apple II controller and its slot ROM are **not** imported. The Apple III
uses its own drive-selection logic and a 341-0028-equivalent P6 sequencer.

Local changes:

- Read complete tracks in standard MiSTer bursts of up to 16 KiB, splitting
  larger allocations. Avoid per-block host scheduling delays during the SOS
  synchronized-track protection check.

- Accept an SD acknowledgement on the first request cycle, including its first
  byte, without requiring an extra unacknowledged request cycle.
- Replace the upstream track-length normalization with WOZ INFO timing in
  125 ns units, defaulting WOZ1 to 4 us. Nine-bit counters cover the full
  nonzero timing-byte range; reserved WOZ1 INFO bytes are ignored.
- Widen the fractional bit-cell addition to 11 bits. Two fractions below 1000
  can sum to 1998; the upstream 10-bit intermediate discarded carries.
- Use fixed asynchronous reset values for the rotation counters so Quartus
  infers flip-flops rather than variable-reset latches.
- Validate the WOZ signature, disk type, TMAP indices, image bounds and track-buffer bounds.
- Respect host and INFO write protection. WOZ1 and FLUX representations report
  read-only; writeback currently supports allocated WOZ2 bitstream tracks.
- Track writeback emits only track blocks. Main owns file writes, metadata
  protection and CRC invalidation; no header-write buffer is needed in the FPGA.

The interface remains ordinary MiSTer block I/O. The companion Main extends
its existing Apple-family storage backend for Apple III; see
[the integration notes](../../../docs/MAIN_STORAGE.md). All floppy formats use
this single WOZ cache and the Apple III P6 sequencer.

Run `./sim/disk/run.sh`. Fixtures are generated locally from original patterns;
no ROMs or software disks are distributed. The original PROM comparison is
optional when its separately supplied dump is unavailable.
