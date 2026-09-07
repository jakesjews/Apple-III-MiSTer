# Apple III core accuracy audit — 2026-09-04

**Update:** the 13 reproduced defects below are addressed by the
[2026-09-07 fixes](ACCURACY_FIXES_2026-09-07.md). This audit retains the original
findings and evidence for the baseline commit.

**The core runs SOS, but it is not yet an accurate reproduction of the Apple
III motherboard.** Independent checks reproduce discrepancies in five
subsystems that the existing regression tests do not detect. Write protection
is the highest-priority finding because its signal does not inhibit writes.

Audited RTL: `f0069f46d107cae31e8af7bc53108b062e5a1455`, branch `main`.
The checkout was clean before this audit. Only verification tests and this
report were added; the production RTL was not changed. This report describes
that commit, not a corrected implementation.

## Evidence and scope

The audit combined the repository's substantial research archive with fresh
source searches, original Apple documentation, motherboard PROM binaries,
manufacturer documentation, original software, focused simulation, a fresh
Quartus build, and a physical MiSTer check. It is a broad audit of the available
documentation, not a claim that every surviving document or hardware revision
has been found, or that every behavior has been exhaustively tested.

Primary source material consulted:

| Source | Sections used and purpose |
|---|---|
| [Apple III Level 2 Service Reference Manual, 1982](https://mirrors.apple2.org.za/ftp.apple.asimov.net/documentation/apple3/service_reference_manual/Apple%20III%20Service%20Reference%20Manual-OCR-1982.pdf) | Chapters 2–12: addressing, VIA/ACIA, clocks, video, RTC, keyboard, analog input, emulation, and disks. Original page images checked where OCR was ambiguous; an alternate scan helped resolve transcription errors. |
| [Apple III motherboard schematics](https://www.apple3.org/iiischematics.html) and [original PROM dumps](https://bitsavers.org/pdf/apple/apple_III/firmware/A3PROMs.zip) | Timing, scan, video-mode, scroll, status and memory decode. Tests compare against binary scan/timing PROM contents, not merely an emulator's interpretation. |
| [National Semiconductor AN-353, MM58167B Real Time Clock Design Guide](https://bitsavers.org/components/national/_appNotes/AN-0353.pdf) | Register behavior, periodic interrupts, GO, and counter-read rollover status; particularly printed pp. 8, 16–17. The guide references the April 1982 device data sheet. |
| [Apple SOS 1.3 source](https://www.apple3.org/Documents/SourceCode/SOS13Src.txt) | Boot, extended addressing, disk routines and clock access. `SET.TIME`/`GET.TIME` check rollover status and store the year in clock compare RAM. Console/boot listings in the local archive provided additional cross-checks. |
| [Apple's July 1981 Funny Mode memo](https://mirrors.apple2.org.za/ftp.apple.asimov.net/documentation/apple3/Apple%20III%20Funny%20Mode%20Memo.zip) | Native-mode limitations and the distinction between native DOS operation and true Apple II emulation. |
| [Apple technical-note collection](https://www.apple3.org/iiitechnotes.html) | TA29932/TA29941 RAM diagnostics; TA46708 keyboard encoding; TA40749 sync; TA48103 RGB in emulation; TA33950 drive mapping; TA35669 slot/reset limitations. Individual archived HTML copies are under `research/sources/technotes/`. |
| [Apple patent US4383296A](https://patents.google.com/patent/US4383296A/en) | Independent architectural confirmation of relocated zero page/stack, dual memory output buses and video addressing. The patent describes an earlier memory configuration; it is not a substitute for the later 256 KiB board's decode. |
| [On Three, July 1986](https://mirrors.apple2.org.za/ftp.apple.asimov.net/documentation/apple3/on_three/OnThree_v3n7.pdf) | Contemporary explanation of 140-column graphics packing. |

Additional cross-checks: [Jeppson's extended-addressing article](https://www.apple3.org/Documents/Magazines/AppleIIIExtendedAddressing.html),
the source of [diskhero](https://github.com/paulhagstrom/diskhero) (`buildfont.s`,
`reg-medres.s`, `interrupts.s`), and the local MAME Apple III driver. MAME is
secondary evidence; its comments and partially modeled behavior were not
treated as hardware specifications. Diskhero's author explicitly records
cases where real hardware and MAME differ.

## Reproduced discrepancies

### 1. Write protection does not inhibit the write path — high priority

With a mounted, ready, write-protected drive, selecting write mode still emits
track write strobes. The new test observes **14 strobes** in its observation
window. The SRM's printed p. 12.7 describes protection blocking the drive's
write/erase current; software merely reading a protected status is insufficient.

`rtl/apple3_disk.sv:83` uses `write_protect` only for the status read.
`rtl/disk/drive_ii.v:204` asserts `TRACK_WE` without a protection input.
`Apple-III.sv:254` passes it directly to the cache, whose RAM accepts the write.
`rtl/disk/floppy_track.sv:88` also marks a NIB cache dirty, allowing the normal
writeback path to submit it to the HPS.

**Impact:** software that attempts a write despite protection can alter the
cached track. OSD protection on a writable NIB is not enforced in this path.
Persistent image corruption was not deliberately attempted on the MiSTer;
the cache/writeback consequence follows from tracing the connected RTL.
Sector images avoid persistence through their separate read-only backend,
but their cached data can still be changed.

Reproducer: `sim/accuracy/disk_protection_tb.sv`.

### 2. 140×192 graphics has incorrect pixel widths

In `rtl/apple3_video.sv:248`, `{h_state[0], state_dot}` advances the second
14-dot state to index 16 instead of 14. A complete seven-pixel, 28-dot group
therefore has **six incorrectly colored dots** in the test pattern. The
second state selects colors too early, producing uneven pixel widths.

The test uses seven distinct colors across four seven-bit memory fragments,
covering the join between the two states. A spot check at the first pixel
would miss this defect. See SRM chapter 6, video mode PROM 342-0032, and the
contemporary On Three graphics description.

Reproducer: first check in `sim/accuracy/video_accuracy_tb.sv`.

### 3. Graphics smooth scrolling does not change memory fetches

`rtl/apple3_video.sv:249` applies the scroll offset to text glyph rows, but
graphics addressing at lines 168–169 uses `next_y[2:0]` unchanged. Enabling
scroll with offset one leaves the fetched address unchanged in **all four
graphics modes** tested. The video-address scroll hardware described by SRM
chapter 2 and PROM 342-0055 operates on the row address; MAME and diskhero
provide independent software cross-checks.

**Impact:** programs using graphics scrolling receive the unshifted image.
`docs/DESIGN.md:112` currently claims that both graphics and character rows
are handled, which overstates the implementation.

Reproducer: four address checks in `sim/accuracy/video_accuracy_tb.sv`.

### 4. Apple II emulation does not select Apple II video modes

The pixel-mode case at `rtl/apple3_video.sv:255` always interprets the switches
as native Apple III modes. `native_mode` only suppresses native text color;
it does not implement the separate Apple II mode decode in PROM 342-0032.

The focused test clears native mode, selects TEXT and HIRES, and provides a
known lit character pixel. It gets black instead of the expected text pixel.
TEXT must override HIRES in Apple II emulation. The same structural omission
leaves Apple II lores and the mixed text region unimplemented.

This finding concerns **mode selection**, not NTSC artifact colors. Apple
TA48103 explicitly says emulated Apple II hires does not produce color on the
Apple III RGB outputs. Monochrome RGB hires is not, by itself, a defect.

Reproducer: final check in `sim/accuracy/video_accuracy_tb.sv`.

### 5. CPU arbitration differs from the timing PROM

`rtl/apple3_timing.sv:50` disallows every fast A-slot during display or refresh.
The hardware timing PROM also considers `RAMEN`, permitting non-RAM accesses
to proceed in cases where RAM is occupied. The timing module has no RAM-access
input, so it cannot implement that distinction.

The test selects a fast non-RAM display cycle and compares with original
342-0046-A PROM address `$0DA`: **PHASEN is 1; RTL CPU enable is 0**.
ROM execution and suitable non-RAM I/O therefore do not have the hardware's
cycle schedule. Peripheral accesses are also reduced to a fixed 1 MHz slot;
the documented delayed IOSTOP/ready behavior needs a separate pin-level timing
test before it can be claimed accurate.

Reproducer: first comparison in `sim/accuracy/timing_prom_tb.sv`.

### 6. Vertical-blank refresh reservations differ from the scan PROM

The simple `H[4:2] == V[2:0]` comparison at
`rtl/apple3_timing.sv:41` agrees during visible lines but does not reproduce
the scan PROM's special vertical-blank terms. Comparing 341-0030's RRFSH output
over all 64 ordinary horizontal states and 262 lines finds:

| Comparison | Result |
|---|---:|
| States checked | 16,768 |
| Visible-line differences | 0 |
| Vertical-blank differences | 216 |
| Missing refresh reservations | 168 |
| Extra refresh reservations | 48 |

The extended HPE state is deliberately excluded from this comparison.
FPGA block RAM does not require DRAM refresh, but the reserved slots affect
software-visible CPU timing. `docs/DESIGN.md:49` claims the extra VBL states
are implemented; the test shows that they are not.

Reproducer: frame comparison in `sim/accuracy/timing_prom_tb.sv`.

### 7–9. Keyboard NUL, dual Shift, and held-key tracking

Three input sequences fail independently:

* **Control-Shift-2:** the translator returns `$00`, then
  `rtl/apple3_keyboard.sv:124` rejects zero as an unrecognized key. The documented
  NUL code never receives a strobe. SRM p. 8.7 and Apple TA46708 corroborate it.
* **Both Shift keys held, then one released:** both PS/2 keys overwrite a single
  state bit at line 149. Releasing either incorrectly clears SHIFT.
* **A held, B pressed and released:** the module tracks only the latest key;
  lines 165–168 clear any-key-down even though A remains held. This does not
  reproduce the encoder's ANY-key signal described in SRM chapter 8.

Reproducer: `sim/accuracy/keyboard_accuracy_tb.sv`.

### 10–13. RTC register and reset behavior

`sim/accuracy/rtc_accuracy_tb.sv` reproduces four distinct RTC problems:

* **GO:** writing register `$15` clears only fractions, leaving seconds and
  minutes unchanged. `12:34:45` should become `12:35:00`; both seconds and minute
  assertions fail. See `rtl/apple3_rtc.sv:189` and AN-353 p. 16.
* **10 Hz interrupt:** the hundredths `99→00` branch omits IRQ bit 1, so the
  periodic event coincident with each whole second is missing. See lines
  126–133 and AN-353 p. 8.
* **Rollover status:** register `$14` always returns zero at line 76. It cannot
  warn a multi-register reader about a counter update. AN-353 p. 17 specifies
  this mechanism; SOS actually checks it in `GET.TIME` and `SET.TIME`.
* **Machine reset:** the core connects `machine_reset` to the clock, clearing
  the time and compare RAM. An Apple III reset does not remove the clock's
  battery supply. A later host-clock update may reseed counters, but it does
  not preserve the clock's software-written state or battery RAM. See
  `rtl/apple3_core.sv:274`, RTC reset block, and SRM p. 7.11.

These findings are narrower than a complete MM58167 validation. Alarm edge
cases, calendar quirks, standby behavior, and electrical bus timing still
need dedicated coverage.

## What passed

Captured output is in [the result transcript](accuracy/2026-09-04-results.txt).

| Check | Observed result | Limit |
|---|---|---|
| Existing `sim/run_tests.sh` | All nine groups pass; MMU reports 31 checks. | Their expectations miss the defects above. The focused MMU bench uses the 512 KiB parameter, whereas the board build is 256 KiB. |
| Independent [Klaus Dormann 6502 test](https://github.com/Klaus2m5/6502_65C02_functional_tests) | Success trap `$3469` after **96,241,372 cycles**. | Documented NMOS instruction behavior including decimal arithmetic; not exhaustive bus/interrupt timing or illegal opcodes. |
| Integrated stock-ROM run | Reset/vector, bank reconfiguration and disk-boot milestones pass. | This run has no mounted system disk. |
| SOS through buffered NIB data | Reaches interpreter; 1,508 block reads; no loader or disk errors reported. | Ordinary sector content, not flux/copy-protection fidelity. |
| SOS through direct DSK backend | Reaches interpreter; keyboard scenario completes; 2,768 block reads; no loader/disk errors reported. | Inspected screen text confirms menu navigation; this is not a full software compatibility suite. |
| Nibblizer | 6,656/6,656 bytes match for DOS tracks 0 and 12 and ProDOS track 3. | No proof of physical disk-controller write timing. |
| Fresh Quartus 17.0 compilation through CrossOver | Full flow succeeds, 0 errors, 25 warnings, 11m36s reported elapsed time. | Compilation success is separate from hardware fidelity. |
| TimeQuest | Worst setup **+0.803 ns**, hold **+0.166 ns**; recovery/removal/pulse-width slack positive. | 4 input and 50 output ports remain wholly or partly unconstrained, mostly MiSTer shell interfaces. No unconstrained clocks. This is not complete board I/O timing sign-off. |

## Physical MiSTer validation

The freshly compiled bitstream was copied to a temporary core directory over
SSH. Its SHA-256 was checked on both machines. A scratch copy of the SOS system
disk mounted successfully, confirmed through MiSTer's open file descriptor.
SOS reached System Utilities and changed to Device Handling after a Zaparoo
keyboard command. Apple's Confidence disk also reached its menu.

The initial direct-video configuration produced 256×192 scaler captures with
lost text detail. A temporary alternate configuration with direct video disabled
produced clean **560×192** images from the same bitstream. This resolved the
capture issue without changing the RTL; it was not evidence of broken text
rendering. See [the Confidence menu capture](accuracy/2026-09-04-confidence-menu.png).

The Confidence memory diagnostic exercised the displayed 256 KiB configuration,
zero-page/alternate-stack and indirect-addressing tests. It advanced to pass 4
without reporting an error, establishing completion of at least three passes.
See [the memory-test capture](accuracy/2026-09-04-memory-test.png).
This adds hardware evidence for the current RAM map, while leaving the
exhaustive equivalence and bus-timing questions below open.

The MiSTer was returned to the main configuration and MENU. Temporary RBF,
disk copies, MGLs and the alternate INI were removed. Zaparoo was stopped again,
matching its initial service state. Existing core files, disks and the main
MiSTer INI were not overwritten.

## Known limitations and remaining coverage

The README already acknowledges several substantial omissions: external slot
cards/ROMs, full serial connectivity, Silentype, drives 3/4, flux formats and
sector-image writeback. Those should remain explicit compatibility limits.
`apple3_core.sv:282` ties ACIA receive inactive and the wrapper drives UART TX
idle. A passing ACIA register smoke test cannot validate RS-232 operation.

Further work needed before an accuracy claim:

* Exhaustive 256 KiB memory-PROM equivalence, including extended-address latch
  transitions, relocated stack interactions and overlays. Existing tests and
  SOS are good evidence, not exhaustive proof. The `$8F` extended-map/alternate
  stack corner needs direct schematic resolution; no definite defect is
  asserted here from MAME alone.
* Cycle-level VIA timer, shift-register, handshake and interrupt tests. The
  integrated SOS boot exercises the VIAs, but is not a complete VIA test.
* Active-display writes, raster mode/page changes, and character-download
  timing. The video implementation prefetches each line in HBL and batches font
  loading at line 261, unlike the motherboard's time-distributed fetches.
  Static images cannot establish equivalence for programs that modify those
  inputs during a frame.
* Analog color/sync, DAC/speaker amplitude and mixing, joystick RC timing, disk
  rotation/bitstream/half-track behavior, and protected-media software.
  Pixel palettes and nibble streams alone do not establish electrical fidelity.
* Broader original software: Apple II emulation disk, graphics/raster programs,
  BASIC/Pascal applications, and sustained read/write tests on disposable media
  after write protection is corrected.

Two interpretation traps were explicitly avoided: the SRM's VIA IER description
on p. 3.20 specifies a zero high bit on read, so a modern W65C22 rule must not be
substituted automatically; and the 1981 memo's native “funny mode” is not a
synonym for true Apple II emulation. Some current code/document comments
conflate the latter terms.

## Reproduction and artifact identities

Run the existing regression suite and the added checks separately:

```sh
./sim/run_tests.sh
bash sim/accuracy/run.sh
./sim/run_core_boot.sh 30000000
sim/coretest/obj_dir/Vcore_tb 1400000000 research/disks/apple3.org/Apple3SOS1.3SysUtils.dsk --buffered
sim/coretest/obj_dir/Vcore_tb 1400000000 research/disks/apple3.org/Apple3SOS1.3SysUtils.dsk --rawdsk --keytest
./build.sh compile
```

The simulation limit is in **half cycles**. The keyboard mode extends its run
to complete the scripted interaction. ROMs and disk images are not included
with these tests. [The accuracy test README](../sim/accuracy/README.md) records
PROM hashes, the pinned CPU-suite revision, and its separate invocation.

```text
RTL commit      f0069f46d107cae31e8af7bc53108b062e5a1455
RBF SHA-256     c7ac011970332e2b5b84446df2a69bf84b70122525144ec5436a00ef39d42a7b
RBF bytes       3549924
Boot ROM SHA256 370be5f0c1b57b606d6c7312f99e5f6064bf405b22430ab53d9bec9bcc0f7520
SOS DSK SHA256  ca38eab537738cdc2b7b27328957134f945d1dd06cbb6474a0b37bee073c89b3
Confidence DSK  9237844d083015e88c277cd7aea514256484b72ac57aff5e72dc34a29bd72cbf
```

Full local logs, downloaded sources and hardware captures are retained in the
ignored `research/accuracy-audit-2026-09-04/` directory. The concise result
transcript and test sources are retained alongside this report.
