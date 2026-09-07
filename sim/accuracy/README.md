# Documentation-based accuracy tests

These tests were added during the 2026-09-04 audit of commit
`f0069f46d107cae31e8af7bc53108b062e5a1455`. **Five groups fail at that baseline
commit; all five must pass with the 2026-09-07 fixes.** They are separate from
the existing regression suite. See the [fix report](../../docs/ACCURACY_FIXES_2026-09-07.md).

Run from the repository root:

```sh
bash sim/accuracy/run.sh
```

Requires Icarus Verilog, `vvp`, and `xxd`. Outputs are written to
`sim/obj_dir/accuracy/`. The runner continues after a failing group, then exits
nonzero if any group failed.

| Test | Independent expectation |
|---|---|
| `video_accuracy_tb.sv` | Equal 140-mode pixel widths; 49,152 exact graphics address/lane checks across rows, offsets, planes and pages; Apple II TEXT, lores and mixed-region boundaries. |
| `keyboard_accuracy_tb.sv` | Strobed NUL; independent modifier keys; correct held-key tracking, releases, host typematic suppression and repeat fallback. |
| `disk_protection_tb.sv` | Each drive writes when writable and emits no writes when protected; protected cache contents and the other drive remain unchanged. |
| `rtc_accuracy_tb.sv` | GO rounds seconds correctly; 10 Hz includes whole-second boundaries; rollover status is meaningful; machine reset preserves clock time. |
| `timing_prom_tb.sv` | 134,144 A-slot PHASEN comparisons across RAM selection, screen enable and CPU speed; 16,768 refresh reservations compared with original motherboard PROM bytes. |

The video test seeds the internal line and character memories so it can test
pixel decoding independently of font loading and RAM fetch timing. The RTC test
accelerates milliseconds with the module's existing parameter and otherwise
uses register transactions. The disk test does not mount or modify disk files.

For the PROM comparison, unpack [A3PROMs.zip](https://bitsavers.org/pdf/apple/apple_III/firmware/A3PROMs.zip)
and set `APPLE3_PROM_DIR` to that directory. It defaults to the existing local
`research/docs/bitsavers/A3PROMs` directory. Without these files, the runner
explicitly skips the PROM group. Required SHA-256 hashes:

```text
341-0030.BIN   9e04e16903f33b38cd8d7c17dc6ef4c2eab7f5bfb926158194448d8dfbadeace
342-0046-A.BIN 8ca7d9e76627a1f4cf9f5592b378c4e51bdaa4ea4ad3d4c66ca6c000ae93af1b
```

The scan comparison covers all 64 ordinary horizontal states across 262 lines.
It excludes the extended HPE state, where direct counter-pin interpretation is
insufficient. At the audited commit it finds 216 differences out of 16,768:
168 missing refresh reservations and 48 extra ones, all in vertical blanking.
The corrected implementation has zero differences. The PHASEN sweep tests
ordinary non-peripheral A-slots; it does not establish delayed IOSTOP/ready
waveform accuracy.

## Independent 6502 functional test

`cpu_functional_tb.sv` uses the same T65 wrapper as the core, in a flat 64 KiB
memory. It starts execution at `$0400` and recognizes the published success
trap at `$3469`. Use the binary from [Klaus Dormann's suite](https://github.com/Klaus2m5/6502_65C02_functional_tests),
commit `7954e2dbb49c469ea286070bf46cdd71aeb29e4b`, with SHA-256
`fa12bfc761e6f9057e4cc01a665a7b800ff01ae91f598af1e39a1201d01953fd`.
Do not substitute another binary without checking its success address.

After `sim/run_core_boot.sh` has generated `sim/gen/t65.v`:

```sh
xxd -p -c 1 /path/to/6502_functional_test.bin > /tmp/apple3-6502-functional.hex
verilator --binary --timing -j 4 -Wno-fatal -Wno-WIDTH \
  --top-module cpu_functional_tb --Mdir sim/obj_dir/cpu_accuracy \
  sim/gen/t65.v sim/accuracy/cpu_functional_tb.sv
sim/obj_dir/cpu_accuracy/Vcpu_functional_tb +ROM=/tmp/apple3-6502-functional.hex
```

The audited core passes after 96,241,372 cycles. This exercises documented
NMOS 6502 instruction behavior, including decimal arithmetic, but does not
certify external interrupt edge timing, undocumented opcodes, or Apple III
memory arbitration.

Source references and interpretation limits are in
[the audit](../../docs/ACCURACY_AUDIT_2026-09-04.md); captured results are in
[the result transcript](../../docs/accuracy/2026-09-04-results.txt).

## MiSTer 140-mode capture check

`check_140_capture.py` checks the saved Confidence Program Video Test 7 image
(140x192 color, page 1). Capture at the native 560x192 size with direct video
disabled. The script requires Pillow (validated with 12.3.0):

```sh
python3 sim/accuracy/check_140_capture.py docs/accuracy/2026-09-07-after-140.png
```

Every four adjacent master dots must have the same color. The saved baseline
`2026-09-07-before-140.png` fails with 2,642 inconsistent groups; the corrected
capture passes with zero out of 26,880. Blank or incorrectly sized captures are
rejected. The diagnostic screen's identity must also be verified visually;
this width check alone does not certify its contents or palette.
