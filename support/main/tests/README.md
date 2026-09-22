# Companion Main storage tests

`run.sh` compiles Main's `support/apple3` and `support/a2` sources against
file and SPI shims, with address and undefined-behaviour sanitizers, and runs
the Apple III storage checks: format conversion and equivalence, the DOS 3.3
volume number, NIB and sector write-back, SOS protection-key rules, native WOZ
writes and guards, four simultaneous drives, block images, invalid containers,
and that the //e and IIgs paths are untouched. Fixtures are generated; no ROMs
or disk images are needed. `MAIN_DIR` points at the Main checkout (default
`../Main_MiSTer-AppleIII`). These tests are not part of the upstream Main PR.

The same binary converts an image the way Main mounts it, for the simulator:

```
/tmp/mister-apple3-tests/storage_test --convert source.dsk copy.woz
```
