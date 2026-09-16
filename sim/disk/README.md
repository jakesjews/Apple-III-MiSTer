# Disk validation

Run `./sim/disk/run.sh` from the repository root. This checks:

- All 256 P6 logic entries and 50,000 state-machine cycles and all 256 serialized write bytes against an original
  341-0028 PROM (`APPLE3_DISK_PROM`, otherwise the local research dump).
- WOZ1/WOZ2 parsing with immediate SD acknowledgement and sparse data strobes,
  exact cached track bytes, quarter-track mapping, empty tracks and reset.
  A 40-block allocation checks splitting across the 16 KiB host-buffer limit.
- Rejection of invalid signatures, out-of-range TMAP indices and oversized tracks.
- WOZ2 writeback: exact changed byte, preserved surrounding disk contents including the unchanged header. Main tests cover CRC invalidation. WOZ1 reports write protection.
- WOZ timing metadata, standard 4 us cells over two complete revolutions, cache validity, protected
  writes, and a writable bit preserving its neighboring bits.

The broader register and drive-selection tests remain in `sim/run_tests.sh` and
`sim/accuracy/run.sh`. For actual software, supply your own ROM and media:

```sh
./sim/run_core_boot.sh 400000000 system.woz --woz
./sim/run_core_boot.sh 800000000 system.woz --woz --sd-delay=71590
./sim/run_core_boot.sh 800000000 system.woz --drive2=blank.woz --sd-delay=71590
```

`--warm-reset` also tests a reset after both mounts while host I/O is active.

The WOZ boot harness uses the same native parser, track RAM and drive used in
the MiSTer build, with shared, drive-specific transfers of up to 16 KiB. Success requires the
SOS interpreter milestone, not just reading the boot sector.

Sector images for these tests must be converted with the companion Main's
`tests/apple3/storage_test --convert` utility. No duplicate image converter
is built into this simulator or the FPGA. See `docs/MAIN_STORAGE.md`.
