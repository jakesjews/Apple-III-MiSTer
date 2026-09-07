# Apple /// MiSTer core — hardware model and design notes

This document records the hardware model, its sources, and implementation limits.
The [accuracy audit](ACCURACY_AUDIT_2026-09-04.md) and
[fix report](ACCURACY_FIXES_2026-09-07.md) distinguish verified behavior from
remaining coverage gaps.

Sources (abbreviations used below):

* **[SRM]** Apple /// Level 2 Service Reference Manual (1982), theory of operation
  chapters 2-12 (`research/docs/service_manual`).
* **[PROM]** Decoded logic-PROM equations of the main logic board (Patrick Schaefer,
  bitsavers `A3PROMs`): 342-0046 timing logic, 342-0043 status, 342-0045 I/O logic,
  342-0055 video mux, 342-0032 video mode control, 342-0030 scan decode,
  342-0061/-0063 RAS/CAS decode, 342-0056 CASB65.
* **[SOS]** SOS 1.3 kernel/loader/disk driver source, console driver 1.31 source.
* **[ROM]** Boot ROM source (ca65 transcription of the ROM listing).
* **[EDW]** Stephen A. Edwards, "Reconstructing the Apple II+ on an FPGA"
  (Circuit Cellar 224, 2009), a schematic-derived model of the same Woz clock
  generator and its once-per-line extended cycle.
* **[MAME]** MAME `apple3` driver (Nathan Woods / R. Belmont).
* **[JEP]** John Jeppson, Softalk 1982/1983 articles.
* **[DH]** diskhero (2022 game, verified on real hardware).
* **[MEMO]** Apple internal memo "Funny Mode and SOS", July 1981, appendix 2.
* **[RTC]** National Semiconductor [AN-353, MM58167B Real Time Clock Design Guide](https://bitsavers.org/components/national/_appNotes/AN-0353.pdf), especially pp. 8, 16–17 and figure 23.

## Clocks and CPU speed

* Master clock 14.318 MHz. One video "state" = 14 clocks (65 states per line,
  912 clocks per line: the 65th state is stretched to 16 clocks). 262 lines per
  frame. [SRM ch.5, EDW]
* Q3, the disk-state-machine clock, repeats every seven master clocks and is
  high for four. HPE holds the Q shift register for the final two clocks of the
  extended horizontal state. This preserves 130 Q3 cycles for 65 CPU cycles
  while reproducing the physical once-per-line stretch. [SRM ch.5, schematics]
* Each state has two 2 MHz slots. Slot B (second half) is always available to the
  CPU (`C1M` high). Slot A is the video/refresh slot; the CPU may use it in 2 MHz
  mode when nothing else needs RAM, or when the CPU access does not select RAM.
  RAM selection remains asserted for write-protected RAM writes. From the timing
  PROM [PROM 342-0046]:

  ```
  PHASEN = C1M·IOSTOPD
         + !DSPLY·!FSPACE·SEL2M
         + !RAMEN·!FSPACE·SEL2M
         + C1M·!FSPACE
         + C1M·!C07X·!SEL2M
  ```
  `SEL2M` = env bit 7 clear (2 MHz selected), `FSPACE` = access to the VIAs, the
  ACIA or the clock chip ($C07x), `RAMEN` = the access goes to RAM, `DSPLY` = the
  video or the DRAM refresh needs this slot, `IOSTOPD` = FSPACE sampled at the C1M
  rising edge (a wait state for VIA/ACIA/RTC accesses).
  The current RTL uses one B-slot for peripheral accesses; the motherboard's
  delayed IOSTOP/ready waveform still needs separate implementation/verification.
* `DSPLY` = (screen enabled AND active display window) OR refresh. Refresh states
  come from the scan-decode ROM [PROM 342-0030], `RRFSH`: 4 consecutive states per
  half-line where `H[4:2] == V[2:0]` during display, with additions and exclusions
  during VBL. The hardware vertical counter runs 256..511 then 250..255.
  All 16,768 ordinary states per frame match the binary scan PROM; the extended
  HPE state's refresh decode is outside that comparison.
* SOS switches to 1 MHz (env bit 7) around disk transfers. [SOS]

## Memory

* RAM is N×32 KB banks (N = 4/8/16 for 128/256/512 KB). The MiSTer shell models
  the stock 256 KB 5 V memory board (N=8), the largest configuration Apple
  shipped; 512 KB requires a third-party expansion board. The parameterized MMU
  also covers 128/512 KB for simulation and future backends. The system bank
  ("S") is the highest bank. CPU $0000-$1FFF = S-bank offset $0000-$1FFF, CPU
  $A000-$FFFF = S-bank offset $2000-$7FFF, CPU $2000-$9FFF = window into bank
  register bank. [SRM ch.1-2, JEP, On Three 512K guide, MAME]
* Bank register = E-VIA port A bits 3..0 ($FFEF). Selecting the S-bank's own number
  (N-1) selects bank 2 instead (verified from the RAS/CAS PROM decode for the 256 KB
  board: bank 7 decodes identically to bank 2; MAME implements the same rule).
  Higher values wrap modulo N.
* Zero page register = D-VIA port B ($FFD0). Any CPU access with A[15:8]=$00 is
  redirected to page ZP; with env bit 2 clear, page $01 is redirected to ZP^1
  (alternate stack). [SRM ch.2, JEP, MAME]
* Environment register = D-VIA port A ($FFDF): bit0 ROM enable, bit1 ROM bank
  (1 = stock ROM), bit2 primary stack, bit3 write-protect $C000-$FFFF RAM, bit4
  reset/NMI enable, bit5 screen enable, bit6 I/O enable ($C000-$CFFF), bit7 1 MHz.
* $C500-$C7FF is always RAM; $FFC0-$FFCF is always RAM; $FFD0-$FFEF are the VIAs
  only while E-VIA PA6 is not driven low (native mode) [MEMO, MAME]; ROM is 4 KB at
  $F000-$FFFF when enabled. Writes to $F000-$FFFF always go to the underlying RAM
  (subject to write-protect).
* Every RAM read returns two bytes: the byte at A and its "sister" at A^$0C00 (text
  area) — the video uses both in 80-column/560/140 modes; for the CPU the sister
  byte of a zero-page pointer fetch is the X byte. [SRM ch.2, JEP]
* Extended addressing: when ZP is in $18-$1F (status PROM `S399`: translated zero
  page in $1800-$1FFF) and the CPU reads a zero-page location (not an opcode fetch),
  the X byte at (ZP^$0C):offset is latched. If bit 7 is set, every following access
  ≥ $0100 of the same instruction (until SYNC) is redirected: X=$80+n → linear
  address n·32K + A (bank n at $0000-$7FFF, bank n+1 at $8000-$FFFF); X=$8F → the
  normal map with bank 0 in the window and RAM under the VIAs. The redirected
  accesses bypass I/O, ROM and write protection. [JEP, MAME, PROM 342-0043]

## Video

* Modes selected by VM0..VM3, set/cleared through $C050-$C057 (same addresses as
  the Apple II soft switches but different meaning). {VM3,VM1,VM0}: 000/001 =
  40-column text (VM0 = colour: fg nibble = bits 7-4, bg = bits 3-0 of the sister
  byte), 010/011 = 80-column text, 100 = 280×192 mono, 101 = 280×192 fg/bg colour,
  110 = 560×192 mono, 111 = 140×192 16 colours. VM2 = page 2. [SRM ch.6, PROM
  342-0032, MAME, DH]
* With native mode disabled, VM0/VM1/VM3 mean TEXT/MIXED/HIRES. TEXT overrides
  HIRES; otherwise HIRES selects 280-pixel monochrome and its absence selects
  40×48 lores from text-page nibbles. MIXED replaces scan lines 160–191 with
  40-column text. RGB hires remains monochrome, as documented by Apple TA48103.
* 140-mode packs four seven-bit memory fragments into seven four-bit pixels,
  each four master dots wide. The second state starts at dot 14 of the group.
* Text pages are in the S-bank at $0400/$0800; graphics pages are in physical bank 0
  (CPU $2000-$3FFF/$4000-$5FFF for page 1, $6000-$7FFF/$8000-$9FFF for page 2).
  Page 2 swaps the roles of the two halves in text modes. [SRM ch.6]
* Exception: the Apple ][-compatible 280x192 monochrome mode ({VM3,VM1,VM0}=100)
  keeps the Apple II page-2 address. Its page 2 is CPU $4000, i.e. physical
  $2000, not the $4000 used by the native graphics modes. Verified with the
  Confidence Program's "Apple ][ Hires (280 x 192), Page 2" test, which renders
  a fragmented image when page 2 is taken from $4000; MAME's `apple3_v.cpp`
  makes the same distinction. [MAME, Confidence Program]
* Character generator = 1 KB RAM (128 chars × 8 rows), bit 7 of a font row = flash
  attribute. Screen byte bit 7 clear = inverse (or flashing when the font row's bit 7
  is set). Loaded by hardware from the text-page screen holes ($x78-$x7F of text rows
  0-7) while $C0DB is enabled: font row = {V[4:3], H[2]}, code from the $08xx hole
  byte, bitmap from the $04xx hole byte. [MAME, DH buildfont.s, SOS console driver]
  The RTL prefetches display lines during HBL and batches character downloads at
  line 261. Mid-frame writes and character-download timing are not yet equivalent
  to the motherboard's distributed fetches.
* Smooth scroll: $C0D8/$C0D9 disable/enable; offset = disk stepper phase latch bits
  0-2 ($C0E0-$C0E5). The offset is added modulo 8 to the row-within-cell used for
  fetching graphics rows and character rows. [SRM ch.2, PROM 342-0055, MAME]
* Screen enable (env bit 5) blanks the output and frees the video RAM slot.
* Blanking: HBL for the 25 non-display states, VBL for 70 lines. E-VIA PB6 = composite
  blanking (1 = blanking), CB1/CB2 = VBL (1 = in vertical blanking). [SOS kernel VIDEO
  routine counts BL pulses with T2; SOS interrupt table "E.CB2 VBL+, E.CB1 VBL-"]

## I/O ($C000-$C0FF, only with env bit 6)

| Address | Function |
|---|---|
| $C000-7 | keyboard ASCII (bit 7 = strobe) |
| $C008-F | keyboard flags: b0 any-key-down, b1 shift, b2 /control, b3 /alpha-lock, b4 /open-apple, b5 /solid-apple, b6 1, b7 key code bit 7 (keypad/special) |
| $C010-1F | clear strobe |
| $C020-2F | deselect $C800 expansion ROM |
| $C030-3F | speaker toggle |
| $C040-4D | bell: 1 kHz for 0.1 s |
| $C04E/F | character RAM disable/enable (unused here) |
| $C050-57 | VM0..VM3 clear/set |
| $C058/9 | A/D select 0 |
| $C05A/B | A/D select 2 |
| $C05C/D | A/D ramp charge / start timeout |
| $C05E/F | A/D select 1 |
| $C060-3 / $C068-B | joystick switches 0-3 (bit 7) |
| $C064/5, $C06C/D | slot IRQ status (bit 7, negative logic) |
| $C066/E | A/D timeout (bit 7 = 1 while ramping) |
| $C070-7F | MM58167 RTC, register selected by the zero page register |
| $C090-CF | slots 1-4 device select (unpopulated) |
| $C0D0-7 | drive select A0/A1, internal enable, side 2 |
| $C0D8/9 | smooth scroll off/on |
| $C0DA/B | character download off/on |
| $C0DC-F | ENSEL/ENSIO (Silentype serial port, not implemented) |
| $C0E0-EF | Disk II style controller (phases, motor, int/ext, Q6, Q7) |
| $C0F0-3 | 6551 ACIA |

Drive selection [SOS disk3 driver]: .D1 = $C0EA (internal I/O select) + $C0D4;
.D2 = $C0EB + A1=0,A0=1; .D3 = $C0EB + A1=1,A0=0; .D4 = $C0EB + A1=1,A0=1.

The MiSTer drive backend stores one pre-nibblized 6-and-2 byte every 64 Q3
cycles. Q6L data is cleared on the completed CPU read strobe, after the CPU has
sampled it. Using the strobe is important at the HPE boundary: inferring the
read from an address level at a later Q3 edge can clear a newly arrived byte.
While the HPS fills the 13-block track cache, its old contents belong to the
previous track; the read head pauses and exposes an empty latch until `busy`
clears. The buffered boot integration test models the same 512-byte HPS
handshake and cache RAM latency. It exercises the stock ROM's 32-cycle nibble
loops and the SOS disk driver's longer loader path. [ROM, SOS, PROM 341-0028]
Write protection gates each drive's track-cache write strobe, independently of
the readable protection status. Protected media cannot change the cached track.

A/D channel codes (A/D2,A/D1,A/D0) from Service Reference Manual table 9 and
the SOS 1.3 joystick driver: 001 = port B X, 010 = port B Y, 011 = port A X,
100 = port A Y, 101 = clock battery, 110 = not connected, 111 = reference.

## VIAs

D-VIA ($FFD0): PA = environment register, PB = zero page register (also RTC
register select), CA1 = slot IRQ (OR of slots, active low), CA2 = joystick switch 1
(margin switch), CB1/CB2 = Silentype serial port.

E-VIA ($FFE0): PA3..0 = bank register (outputs), PA4/PA5 = slot 1/2 IRQ inputs, PA6 =
solid Apple key input / native-mode output (when configured as an output and driven
low the VIAs disappear from $FFD0-$FFEF — Apple II emulation mode), PA7 = IRQ line
status (0 = interrupt pending). PB5..0 = 6-bit sound DAC, PB6 = composite blanking
input, PB7 = slot NMI input. CA1 = RTC interrupt, CA2 = keyboard data-ready strobe,
CB1 = CB2 = VBL.

## Keyboard

10×8 matrix scanned by an AY-3600-style encoder with Apple's mask ROM; shift and
control are direct inputs to the encoder; alpha lock and the two Apple keys are direct
switch inputs to $C008. Codes per [SRM ch.8] table (upper case letters, control codes,
keypad/arrows with bit 7 set). Any key held for 0.5 s repeats at 10 cps; with the
solid Apple key held, 30 cps. Ctrl+Reset = hardware reset, Reset alone = NMI, both
gated by env bit 4. [SRM ch.8, MAME]

The PS/2 adapter tracks the two instances of each modifier independently and
keeps an ordinary-key bitmap for ANY-key-down. Validity is separate from the
encoded byte, so Control-Shift-2 emits a strobed NUL. Duplicate host make events
do not restart repeat; after releasing the newest key, another held key can repeat.

## Real-time clock

The MM58167 model has separate counter, comparison, interrupt and rollover-status
registers. GO clears fractions and seconds, rounding up at 40 seconds and carrying
through the calendar. The 10 Hz interrupt includes whole-second rollover. A
counter read arms a sticky rollover detector with a 150 us update window each
millisecond; reading status returns and clears that result. [RTC]

FPGA configuration initializes clock state. Machine reset suppresses bus access
but preserves time, comparison RAM and interrupt settings while the clock runs.
MiSTer host-clock toggle updates seed the counters. The explicit counter/RAM
reset commands remain available. This models battery retention across machine
reset, not across FPGA reconfiguration or loss of MiSTer power.
