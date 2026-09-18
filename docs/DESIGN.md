# Apple /// MiSTer core — hardware model and design notes

This document records the hardware model, its sources, and implementation limits.

Sources (abbreviations used below):

* **[SRM]** [Apple /// Level 2 Service Reference Manual](https://mirrors.apple2.org.za/ftp.apple.asimov.net/documentation/apple3/service_reference_manual/Apple%20III%20Service%20Reference%20Manual-OCR-1982.pdf)
  (1982), theory of operation chapters 2-12.
* **[PROM]** Decoded logic-PROM equations of the main logic board (Patrick Schaefer,
  bitsavers `A3PROMs`): 342-0046 timing logic, 342-0043 status, 342-0045 I/O logic,
  342-0055 video mux, 342-0032 video mode control, 342-0030 scan decode,
  342-0061/-0063 RAS/CAS decode, 342-0056 CASB65.
* **[SOS]** SOS 1.3 kernel/loader/disk driver source, console driver 1.31 source.
* **[ROM]** Boot ROM source (Rob Justice's ca65 transcription of the ROM listing).
* **[EDW]** Stephen A. Edwards, "Reconstructing the Apple II+ on an FPGA"
  (Circuit Cellar 224, 2009), a schematic-derived model of the same Woz clock
  generator and its once-per-line extended cycle.
* **[MAME]** MAME `apple3` driver (Nathan Woods / R. Belmont).
* **[JEP]** John Jeppson, Softalk 1982/1983 articles.
* **[DH]** diskhero (2022 game, verified on real hardware).
* **[MEMO]** Apple internal memo "Funny Mode and SOS", July 1981, appendix 2.
* **[RTC]** National Semiconductor [AN-353, MM58167B Real Time Clock Design Guide](https://bitsavers.org/components/national/_appNotes/AN-0353.pdf), especially pp. 8, 16–17 and figure 23.
* **[PLUS]** Apple /// Plus addendum to the Standard Device Drivers manual (1983),
  appendix A keyboard codes.
* **[MB4053]** Fujitsu MB4053 data sheet (DS04-13103), the second source for the
  9708 A/D converter ("compatible with MC14443 and µA9708").
* **[OG]** Apple /// Owner's Guide appendix C, port specifications, and Tech Info
  Library article 13, "Apple III: Game Paddles".

## Clocks and CPU speed

* Master clock 14.318 MHz. One video "state" = 14 clocks (65 states per line,
  912 clocks per line: the 65th state is stretched to 16 clocks). 262 lines per
  frame. [SRM ch.5, EDW]
* Q3, the disk-state-machine clock, repeats every seven master clocks and is
  high for four. HPE holds the parallel-loaded Q register for two extra clocks
  at the start of the extended state's A slot. Its CPU completions move from
  dots 6/13 to 8/15 and the VIA falling edge from 7 to 9; Q3 has a six-clock
  high pulse followed by its normal three-clock low pulse. There are still
  130 Q3 cycles and 65 VIA cycles per line. [SRM ch.5, schematic sheet 10]
* Each state has two 2 MHz slots. Slot B (second half) is available to the
  CPU (`C1M` high), subject to peripheral waits. Slot A is the video/refresh slot; the CPU may use it in 2 MHz
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
  rising edge. An FSPACE address following an A completion misses that sampling
  boundary, suppressing the first B completion. `CS6522` from the same PROM
  prevents an early VIA access. The slow-mode bypass excludes the RTC.
  Card RDY reaches T65 independently of its clock enables: reads wait, writes
  finish and NMI detection continues. See [peripheral timing](PERIPHERAL_TIMING.md).
* `DSPLY` = (screen enabled AND active display window) OR refresh. Refresh states
  come from the scan-decode ROM [PROM 342-0030], `RRFSH`: 4 consecutive states per
  half-line where `H[4:2] == V[2:0]` during display, with additions and exclusions
  during VBL. The hardware vertical counter runs 256..511 then 250..255.
  All 17,030 states per frame match the binary scan PROM for `RRFSH`,
  the character-write window `RTCWRT` and the display window `-RBL`
  (`/H5·/VBL + /H3·/H4·/VBL`, H = 0-39). On entry to HPE, G10 retains the
  preceding H=63 decode: refresh can remain asserted, while RTCWRT is low
  and the HPE blanking gate prevents display.
* SOS switches to 1 MHz (env bit 7) around disk transfers. [SOS]
* Machine reset does not stop the timing chain, so video sync continues through
  a reset. The counters start from zero when the FPGA is configured.

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
* Display fetch: the scanner reads memory in the video half of every state, all
  65 states of all 262 lines. The text address is A9..A0 = V5..V3,
  (H5..H3 + 5·V7..V6) mod 16, H2..H0, so each line reads 64 consecutive bytes of
  its 128-byte block, starting with its 40-byte segment. In blanking (V7..V6 = 3)
  that segment is the screen hole. The SRM describes the addressing as "much the
  same as in the Apple ][. There is a minor difference in the Summing Circuit":
  the Apple II's adder offsets H because its display starts at H = 24, and the
  Apple /// counter's display starts at H = 0. The extended state repeats H = 0.
  Graphics add the row within the cell, with any smooth-scroll offset, as
  A12..A10. Vertical blanking forces the text map in every mode, because every
  DHIRES term of 342-0032 has /VBL. [SRM p.2.6, PROM 342-0030/0032]
* A pair read in state S is shifted out in state S + 2. A processor store in the
  B slot of the state before a column's video slot shows on the line being drawn.
  A store in the column's own state shows a frame later, or on the next scan line
  for text, which is read again on every scan line of its row. The RGB blanking
  and sync outputs trail the counter by the same 28 dots; E-VIA PB6 and VBL do
  not. The FPGA RAM pairs A with A xor $0C00, which covers the text sister byte,
  so a graphics state reads the other plane ($2000 away) with a second access in
  the same video half.
* Character generator = 1 KB RAM (128 chars × 8 rows), bit 7 of a font row = flash
  attribute. Screen byte bit 7 clear = inverse (or flashing when the font row's bit 7
  is set). Loaded by hardware from the text-page screen holes ($x78-$x7F of text rows
  0-7) while $C0DB is enabled: code from the $08xx hole byte, bitmap from the $04xx
  hole byte. [MAME, DH buildfont.s, SOS console driver] The scan PROM's `RTCWRT`
  selects the reads: VBL, H5..H3 = 0, H2 = VA and V1..V0 = VC..VB. That gives four
  states on each of 18 blanking lines. Counter values 448-511 supply 16 of those
  lines, and 254-255, after the counter wraps, read hole 7 again. The font row is
  VC..VA, which the window makes {V[4:3], H[2]}. Every window is also a refresh
  state, so the processor cannot take the slot. The 2114s are written in the video
  half of the next state, `WE2114* = NAND(ENCWRT, TCWRT, C1M*, Q0)`, with $C0DB as
  it stands at that point. One blanking interval loads all eight cells.
* Smooth scroll: $C0D8/$C0D9 disable/enable; offset = disk stepper phase latch bits
  0-2 ($C0E0-$C0E5). The offset is added modulo 8 to the row-within-cell used for
  fetching graphics rows and character rows. [SRM ch.2, PROM 342-0055, MAME]
* Screen enable (env bit 5) blanks the output and frees the video RAM slot.
  Character downloads continue, since their windows are refresh states.
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
| $C05C/D | A/D RAMP START (PDLEN): low charges, high starts the ramp |
| $C05E/F | A/D select 1 |
| $C060-3 / $C068-B | bit 7: port B switch, port A button, port B button, port A switch |
| $C064/5, $C06C/D | slot IRQ status (bit 7, negative logic) |
| $C066/E | A/D RAMP STOP (bit 7 = 1 while the capacitor is above the threshold) |
| $C070-7F | MM58167 RTC, register selected by the zero page register |
| $C090-CF | slots 1-4 device select (reusable card bus); $C090-9F is the [block-storage card](BLOCK_STORAGE.md) |
| $C0D0-7 | drive select A0/A1, internal enable, side 2 |
| $C0D8/9 | smooth scroll off/on |
| $C0DA/B | character download off/on |
| $C0DC-F | ENSEL/ENSIO: Silentype outputs on port A (only their effect on the joystick inputs) |
| $C0E0-EF | Disk II style controller (phases, motor, int/ext, Q6, Q7) |
| $C0F0-3 | 6551 ACIA |

Drive selection [SOS disk3 driver]: .D1 = $C0EA (internal I/O select) + $C0D4;
.D2 = $C0EB + A1=0,A0=1; .D3 = $C0EB + A1=1,A0=0; .D4 = $C0EB + A1=1,A0=1.
All four have independent media, track caches, write protection and disk-change
latches. External address 00 selects no drive. Apple II mode uses D1/D2 and
disables D3/D4, ignoring the native motor-select latches. The four shared phase
bits still feed the video fine-scroll offset, even with all drives deselected.

The disk conditioner executes logic equivalent to all 256 entries of the
341-0028 P6 PROM on Q3*. Its 74LS323 model clears, holds, shifts or loads as
directed by P6; a CPU read has no independent clearing action. A flux event is
held until the next sequencer clock. [SRM 12.3, schematic sheet 7, PROM 341-0028]

WOZ uses a native block-backed track cache and physical drive model imported
from Apple-II_MiSTer (see `rtl/disk/woz/README.md`). Quarter tracks select TMAP
entries, WOZ INFO controls the bit-cell period in 125 ns units, and
unavailable cached data does not produce stale flux. WOZ1 uses the standard 4 us bit cell. The native drive model
continues rotating while data loads. Its weak-bit and analog behavior remains
an approximation; variable-length/flux-track seeks do not establish exact
cross-track angular equivalence.

The controller models the documented roughly two-thirds-second motor-off
grace period. The native disk-change latch suppresses read pulses after a
media change until a selected phase-1 edge; Apple II mode bypasses it.
[SRM 12.4, analog schematic 050-0031-C, 1980 disk-switch rework notice]

Disk III spindle enables are independent of I/O selection: SOS may leave both
internal and external motors running while the phase/read/write bus selects one.
Apple II emulation restores the conventional mutually exclusive drive enables.
[Disk analog schematic 050-0031-C; SOS DISK3 UNITSEL, SPINNING and SELECT]

Main's shared Apple-family backend detects containers and sector order, validates
WOZ CRC/chunk/track bounds, and converts sector/NIB images into in-memory WOZ.
A converted sector image gets the SOS protection key in its track 9 to 16
address fields only when its `SOS.INTERP` is encrypted; SOS's BFM.INIT2 would
otherwise decrypt a plain interpreter and die with SYSTEM FAILURE $06.
The FPGA reads the WOZ track directory into its cache using the existing MiSTer
block protocol. It contains no sector-to-GCR converter. Main preserves native
WOZ bits and metadata, bounds writes to allocated track blocks, and clears the
CRC before the first write. Writes to a converted DSK, DO, PO or 2MG are decoded
from the saved track by Main, and only sectors whose address and data fields
fully verify are stored back into the source file. A NIB source is stored a
whole track at a time, only when all sixteen sectors verify, keeping its
address-field volume bytes; block images are written in place. WOZ1, FLUX and
unmapped tracks are protected in the drive as well.
See `docs/MAIN_STORAGE.md` for the mount assignments and companion Main build.
`sim/disk` tests P6, cache transfers and physical timing; the Main repository's
`tests/apple3` tests formats, transport, write policy and file persistence.

## Joysticks and A/D converter

Channels (A/D2,A/D1,A/D0): 000 ground, 001 port B X, 010 port B Y, 011 port A X,
100 port A Y, 101 clock battery, 110 not connected, 111 reference. [SRM table 9,
SOS GET_ANALOG]

The converter is a 9708 (M9), second-sourced by Fujitsu as the MB4053. PDLEN is
its RAMP START input. $C05C takes it low and the selected input charges the
ramp capacitor C15, 0.01 uF, to the input voltage plus a diode drop; the input
is sampled only while PDLEN is low. $C05D takes it high and a constant current
discharges C15. R39 sets that current: 1.2 Mohm from +12 V to RREF, which the
chip holds at VREF, gives 8.11 uA and a ramp of 0.811 V/ms. VREF is +12 V
divided by R37 and R38 (4.3K and 1K), 2.264 V: channel 7 and the top of the
0 to 2.2 V joystick input range. RAMP STOP, open collector at $C066 bit 7, is
high whenever C15 is above the comparator threshold, through the charge as
well as the ramp. [schematic 050-0039-H sheet 8, MB4053, OG]

The acquisition current, at least 150 uA, charges C15 about twenty times as
fast as the ramp: a full-scale input settles in about 150 us, inside the
500 us the manual asks software to allow. Only the discharge current lowers
C15, so a move to a lower input during the charge settles at the ramp rate.
Reset clears PDLEN and the channel bits in the 9334 at H6 but leaves C15 alone.
Two values are nominal: a ground conversion lasts about 30 us (the boot ROM's
self-test needs it under 32 passes of an 11-cycle loop), and a finished ramp
leaves C15 about 0.45 V below the threshold, 28 us of charge away. An
unconnected input floats to the top of the input range, VCC - 2 V, and so does
the clock's battery of three AA cells; both ramp for about 3.7 ms, the
reference for 2.8 ms. [MB4053, SRM 10.5, ROM, SRM 7.11]

SOS 1.3's GET_ANALOG ($64) charges for 500 ticks of the D VIA's timer 2, then
times the ramp with the boot ROM's ANALOG routine: 360 ticks to step 0 and
8 ticks, 112.25 master clocks, per step. The emulation disk's PREAD charges
for 800 us, waits 370 us and counts 16 cycles per two steps at 1 MHz; Atomic
Defense has its own 1 MHz loop of 17 cycles per step. The modeled joystick
spans GET_ANALOG's window: position p ramps for 354 + 8p ticks, 0.26 V to
1.88 V. ANALOG's 2 MHz loop sees the end of the ramp up to six ticks late, so
GET_ANALOG reads every position exactly, with under a tick of margin either
way, and PREAD, which samples later, reads one or two steps low. GET_ANALOG
rounds half up and turns 256 into 0: a joystick that overshot the window by
half a step would read 0 at full deflection. [SOS, SRM 10.19-10.20, ROM]

Each joystick has a momentary pushbutton and a toggle switch, both closing to
+5 V. The 74LS251 at L7 reads SW0 (port B switch), SW1 (port A button), SW2
(port B button) and SW3 (port A switch) into bit 7 of $C060-$C063. SW1/MGNSW,
pulled up by R85, is also the D VIA's CA2, and SW3/SCO its CB1. [SRM 7.5, OG,
schematic sheets 5 and 8]

Port A is also the Silentype port. ENSEL ($C0DD) drives AXCO onto Y1/XCO and
connects SW3/SCO to the printer instead of the switch, so that line follows the
VIA's shift clock. ENSIO ($C0DF) drives the VIA's serial data, CB2, onto
X1/SER. The converter then measures those levels instead of the joystick, which
is why GET_ANALOG turns both off first. [schematic sheet 8, SOS]

MiSTer controller 1 plugs into port B, which SOS and Business BASIC call
joystick 0; the "Joystick 1 on" option moves it to port A, where Apple II
emulation's PDL(0) is. Controller 2 takes the other port. An axis spans the
whole travel, with Y increasing upward like the graphics driver's Y axis, as
MAME also has it; digital directions reach the ends. Button 1 is the
pushbutton. Each press of button 2 flips the switch, which keeps its position
through a reset.

## VIAs

D-VIA ($FFD0): PA = environment register, PB = zero page register (also RTC
register select), CA1 = `!(IRQ1_n & IRQ2_n & IRQ3_n & IRQ4_n) & !H1`
(repeated edges while any card requests service), CA2 = port A's
button (SW1/MGNSW, the Silentype margin switch), CB1 = port A's switch (SW3/SCO,
the Silentype clock), CB2 = Silentype serial data (SER).

E-VIA ($FFE0): PA3..0 = bank register (outputs), PA4/PA5 = slot 4/3 IRQ inputs, PA6 =
solid Apple key input / native-mode output (when configured as an output and driven
low the VIAs disappear from $FFD0-$FFEF — Apple II emulation mode), PA7 = IRQ line
status (0 = interrupt pending). PB5..0 = 6-bit sound DAC, PB6 = composite blanking
input, PB7 = slot NMI input. CA1 = RTC interrupt, CA2 = keyboard data-ready strobe,
CB1 = CB2 = VBL.

The [slot interface](SLOTS.md) connects all four private I/O and ROM apertures,
the shared expansion-ROM bus, IRQs and reset-masked NMIs. Cards own their ROM
selection latches; native cards release on C02x, Apple II cards on CFFF.

## Keyboard

10×8 matrix scanned by an AY-3600-style encoder with Apple's mask ROM; shift and
control are direct inputs to the encoder; alpha lock and the two Apple keys are direct
switch inputs to $C008. Codes per [SRM ch.8] table (upper case letters, control codes,
keypad/arrows with bit 7 set). Ctrl+Reset = hardware reset, Reset alone = NMI, both
gated by env bit 4. [SRM ch.8, MAME]

Repeat: a key held for 0.5 s repeats at 10 cps. The solid Apple switch line
(Apple's Apple2, keyboard connector KB-5; Open Apple is Apple1 on KB-7) clocks
the high-speed flip-flop and changes the 556 timing, so it has to close after
the key it speeds up. Pressed while a key is already held it raises that key to
30 cps; held before the key it never clocks the flip-flop, and the key sends a
single character instead of repeating. Releasing it returns the held key to 10
cps. [SRM 8.7-8.8]

The four cursor keys are two-contact switches. The first contact sends the code,
and a firmer press closes a second contact OR-wired into that same solid Apple
line on KB-5. That both starts the high-speed repeat and is what the guest sees
as solid Apple, at $C008 bit 5 and on the E VIA's port A bit 6. A PS/2 keyboard
reports one contact per key, so a cursor key held to its repeat threshold stands
in for the firmer press: a tap leaves the solid Apple line alone, and a hold
gives one 10 cps repeat and then 30 cps, as pressing harder does on the real
keyboard. The host Backspace key shares the left-arrow code but is an ordinary
key. [SRM 8.7-8.8]

The PS/2 adapter tracks the two instances of each modifier independently and
keeps an ordinary-key bitmap for ANY-key-down. Validity is separate from the
encoded byte, so Control-Shift-2 emits a strobed NUL. Duplicate host make events
do not restart repeat; after releasing the newest key, another held key can repeat.

OSD status bit 8 selects the Apple /// Plus keyboard, which is the original's 61
main keys plus a DELETE key; both machines share the same encoder codes and the
same SOS keyboard layouts. DELETE arrives on the host Delete key, which otherwise
duplicates keypad period. Its encoder code is $FF: DEL with the special-code flag,
because the console driver only rewrites codes without that flag, and the layout
table is documented as never defining DELETE. [PLUS, SOS]

## Real-time clock

The MM58167 model has separate counter, comparison, interrupt and rollover-status
registers. GO clears fractions and seconds, rounding up at 40 seconds and carrying
through the calendar. The 10 Hz interrupt includes whole-second rollover. A
counter read arms a sticky rollover detector with a 150 us update window each
millisecond; reading status returns and clears that result. [RTC]

FPGA configuration initializes clock state. Machine reset suppresses bus access
but preserves time, comparison RAM and interrupt settings while the clock runs.
MiSTer host-clock toggle updates seed the counters, mapping MiSTer's
Sunday = 0 weekday to the chip's 1 to 7. The chip has no year counter: SOS
SET.TIME keeps the two-digit year in the day and month compare latches with
their other bits in the don't-care state, and GET.TIME reads it back as
((month << 2) | 3) & day. The host seed writes those latches too. Left at
power-on don't-care they read as year 00, and Apple Pascal then treats the
clock as never set and overwrites it with the date saved on the boot disk. The explicit counter/RAM
reset commands remain available. This models battery retention across machine
reset, not across FPGA reconfiguration or loss of MiSTer power.

## 6551 serial integration

The serial ACIA uses the pinned gyurco UART implementation described in
[`rtl/acia/README.md`](../rtl/acia/README.md), with documented local accuracy
corrections. `apple3_acia.sv` adapts bus side-effect strobes, generates a nominal
1.8432 MHz clock enable, and synchronizes external inputs. TX/RX, RTS/CTS and
DTR/DSR connect to MiSTer's HPS UART. DCD is asserted because the HPS connection
has no separate carrier signal. The original motherboard's grounded RxC input
is represented by an inactive external receive-clock enable.

OSD status bit 9 selects CTS: the default holds it ready, while `Host RTS`
uses the HPS handshake input. An unopened HPS UART deasserts RTS; directly
using that idle state fails the stock ROM's ACIA self-test. The default models
the ready CTS level of an unplugged Apple III port with its receiver pull-up.
Host-controlled flow requires the UART to be open with RTS asserted at boot.

The `$00` command reset is intentional: the original Apple III ROM requires it
and fails its ACIA test with the SY6551 table's `$02` reset variant. Programmed
reset preserves control/parity fields and unread receive data. Tests operate at
the CPU bus and serial pins, including a T65 IRQ-driven diagnostic ROM.
