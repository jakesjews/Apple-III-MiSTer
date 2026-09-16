# Documentation-based accuracy tests

These benches check the RTL against Apple's documentation and the original
motherboard PROMs rather than against the behaviour of another emulator. They
are separate from the unit benches run by `sim/run_tests.sh`.

Run from the repository root:

```sh
bash sim/accuracy/run.sh
```

Requires Icarus Verilog, `vvp` and `xxd`. Outputs are written to
`sim/obj_dir/accuracy/`. The runner continues after a failing group and exits
nonzero if any group failed.

| Test | What it checks |
|---|---|
| `video_accuracy_tb.sv` | Equal 140-mode pixel widths; 49,152 graphics address and byte-lane checks across rows, scroll offsets, planes and pages; the Apple II TEXT, lores and mixed-region boundaries. |
| `keyboard_accuracy_tb.sv` | Strobed NUL; independent left and right modifiers; held-key tracking, release ordering, host typematic suppression and repeat fallback. |
| `disk_protection_tb.sv` | Each drive writes its track cache when writable and emits no writes when protected; the other drive is untouched. |
| `rtc_accuracy_tb.sv` | GO rounds seconds correctly; the 10 Hz interrupt includes whole-second boundaries; rollover status behaves as the data sheet describes; machine reset preserves the clock. |
| `timing_prom_tb.sv` | 134,144 A-slot PHASEN comparisons across RAM selection, screen enable and CPU speed, and 16,768 refresh reservations, compared with the original timing and scan PROM contents. |

The video test seeds the internal line and character memories so it can check
pixel decoding independently of font loading and RAM fetch timing. The RTC test
accelerates milliseconds with the module's existing parameter. The disk test
does not mount or modify disk files.

## PROM comparison

The PROM dumps are not redistributed. Unpack
[A3PROMs.zip](https://bitsavers.org/pdf/apple/apple_III/firmware/A3PROMs.zip)
from bitsavers and set `APPLE3_PROM_DIR` to that directory; without it the
runner skips the group. Expected SHA-256 hashes:

```text
341-0030.BIN   9e04e16903f33b38cd8d7c17dc6ef4c2eab7f5bfb926158194448d8dfbadeace
342-0046-A.BIN 8ca7d9e76627a1f4cf9f5592b378c4e51bdaa4ea4ad3d4c66ca6c000ae93af1b
```

The scan comparison covers all 64 ordinary horizontal states across 262 lines.
It excludes the extended HPE state, where direct counter-pin interpretation is
insufficient. The PHASEN sweep covers ordinary non-peripheral A-slots; it does
not establish the delayed IOSTOP/ready waveform.

## 6502 functional test

`cpu_functional_tb.sv` runs the same T65 wrapper as the core in a flat 64 KiB
memory. It starts at `$0400` and recognises the success trap at `$3469`. Use the
binary from [Klaus Dormann's suite](https://github.com/Klaus2m5/6502_65C02_functional_tests)
at commit `7954e2dbb49c469ea286070bf46cdd71aeb29e4b` (SHA-256
`fa12bfc761e6f9057e4cc01a665a7b800ff01ae91f598af1e39a1201d01953fd`). Another
build of the suite may use a different success address.

After `sim/run_core_boot.sh` has generated `sim/gen/t65.v`:

```sh
xxd -p -c 1 /path/to/6502_functional_test.bin > /tmp/apple3-6502-functional.hex
verilator --binary --timing -j 4 -Wno-fatal -Wno-WIDTH \
  --top-module cpu_functional_tb --Mdir sim/obj_dir/cpu_accuracy \
  sim/gen/t65.v sim/accuracy/cpu_functional_tb.sv
sim/obj_dir/cpu_accuracy/Vcpu_functional_tb +ROM=/tmp/apple3-6502-functional.hex
```

The core passes after about 96 million cycles. This exercises documented NMOS
6502 behaviour including decimal arithmetic; it does not cover interrupt edge
timing, undocumented opcodes or Apple /// memory arbitration.

## 140-mode capture check

`check_140_capture.py` checks a MiSTer screenshot of the Confidence Program's
Video Test 7 (140x192 colour, page 1). Capture at the native 560x192 size with
`direct_video` off. The script requires Pillow:

```sh
python3 sim/accuracy/check_140_capture.py capture.png
```

Every four adjacent master dots must have the same colour. Blank or incorrectly
sized captures are rejected. The check validates pixel widths only; confirm the
screen's identity visually.
