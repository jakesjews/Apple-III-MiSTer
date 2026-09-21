# Video Standard: the 50 Hz Euro system

**Video Standard** in the OSD selects **NTSC**, the machine as sold in North
America, or **PAL**, the one Apple's drawings call a Euro system. PAL is a
frame of 310 lines instead of 262, 50 of them a second instead of 60, with
the same 560 × 192 picture in the middle of it. Nothing else about the machine
changes, and the option takes effect at once.

| | NTSC | PAL |
|---|---|---|
| Scan PROM at G9 | 341-0030 | 341-0060 |
| Lines | 256..511, 250..255 = 262 | 256..511, 202..255 = 310 |
| Vertical sync (six broad pulses) | H = 16 of line 483 to H = 8 of 486 | H = 16 of line 499 to H = 8 of 502 |
| Vertical blanking the program sees | 70 lines | 118 lines |
| Line and field rate in the core | 15.70 kHz, 59.92 Hz | 15.70 kHz, 50.64 Hz |

A program sees the difference through VBL alone: the blanking bit of the E-VIA
and the VBL interrupt come round 50 times a second, and there is more time
between pictures. **Text Interlace** is offered with NTSC only, because the
/// Plus interlace PROM is a 60 Hz part (its S50-60 is high) and no Euro
version of it is known.

## The hardware

Sheet 1 of the main logic schematic (050-0039-H) has two notes for it: "for
standard systems G9 is 341-0030, for Euro systems G9 is 341-0060", and "for
standard systems Y1 is 14.318630 MHz, for Euro systems Y1 is 14.250450 MHz".
A PROM and a crystal, then, and sheet 10 shows why a PROM is enough.

**The reload.** The vertical counter is F11's last stage (VA) and G11 and G12
(VB, VC, V0..V5). It counts to 511 and reloads, and what it reloads is wired
as follows: V5 ground, V4 and V3 high, V0 high, VC ground, VB the PROM's COMP
output, and V2 and V1 the PROM's **S50/60** output, D5, which goes nowhere
else. S50/60 high makes 250 and a 262-line frame; low makes 202 and 310 lines.
The Service Reference Manual's signal list calls it "select 50 Hz/60 Hz".

**The 341-0060.** A dump is on asimov (SHA-1 `d15c1d30…531f`). It differs from
the 341-0030 in 92 bytes, and all of them are one edit: V1 is inverted in the
RSYNCH and RCOLRGT terms that carry V2·V5 and VBL, which are lines 480..511.
The whole vertical sync interval, equalising pulses, broad pulses and the
lines without colour burst, moves 16 lines later and is otherwise the same.
Refresh, the character-generator write window, blanking, RFIELD and COMP are
the 341-0030's bit for bit. COMP is still VA, so the reload's VB is 1: 202,
not the 200 that a 312-line frame like the PAL Apple IIe's would need.

Sixteen lines keep the picture near the middle of the longer frame. The
341-0030 leaves 35 lines from the picture to sync and 35 from sync to the next
picture; the 341-0060 in a 310-line frame leaves 51 and 67, of which a 625-line
monitor blanks about 23.

## What is inferred

**S50/60 low.** In the asimov dump D5 reads high at every address, as it does
in the 341-0030. Taken literally that is a 262-line machine whose sync has
moved to 19 lines before the picture, inside any monitor's vertical blanking,
and a new PROM that does nothing for 50 Hz. Apple's notes change only G9 and
Y1, and the net list gives the S50/60 net three pins: the PROM's and the two
reload inputs. So the select has to come from this pin, and the core takes it
as low; a single output that is low everywhere and reads high is what a bad
contact on one pin of the reader gives. `euro_prom_tb` prints a note when the
dump it is given reads that way, and holds the core to the rest of the dump.

**The crystal.** The core keeps its 14.318 MHz clock in both standards, as
MiSTer's Apple II core does. A Euro system's 14.25045 MHz would make every
clock in the machine 0.47% slower: 15,625 Hz lines and 50.40 fields a second
where the core has 15,700 and 50.64.

**Colour.** The colour output of a Euro system is the same NTSC encoder on a
subcarrier of a quarter of its crystal, 3.56 MHz, which a PAL television shows
in black and white; its colour picture is the RGB one. The core's decoder
follows the machine's own subcarrier, so **Color Composite** shows colour in
both standards.

## On MiSTer

The picture is 560 × 192 in both standards, so scaling and aspect are the
same. The core tells Main when the option changes, and with `vsync_adjust` the
HDMI output follows it to 50 Hz. Analog output is 15.7 kHz and 50.6 Hz.

## Tests

`sim/timing_tb.sv` counts a 310-line frame, its reload to 202 and its
blanking. `sim/accuracy/euro_prom_tb.sv` runs with the two PROM images
([test inputs](DEVELOPMENT.md#testing)): it shows that the 341-0060 is the
341-0030 with that one edit, then holds a whole frame of the core to it:
refresh, character window, blanking, field, the line sequence that COMP and
the reload give, and vertical sync against the PROM's broad pulses. The boot
harness takes `--pal`.

On a MiSTer, Main measures 560 × 192 at 15.7 kHz and 50.6 Hz in PAL, a frame
of 19.7455 ms, which is 310 × 912 clocks, and 59.9 Hz again in NTSC. It follows
the option both ways while SOS runs, and SOS 1.3 boots and loads from disk in
either. `debug=2` in the core's section of `MiSTer.ini` puts those measurements
in `/tmp/debug.txt`. To start a core in PAL without the menu, set bit 3 of
byte 2 of `config/Apple-III.CFG` (0x08; bit 19 of the status word).
