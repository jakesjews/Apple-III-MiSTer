# Mouse card

Slot 4 holds Apple's **Apple II Mouse Interface** card (670-0030), driven by
MiSTer's mouse. It is the card an Apple /// used: Apple never made a /// one,
and its SOS mouse driver, "Apple /// RAT Driver, for Apple ][-//e Mouse Card"
(rls 11/85), and ON THREE's Desktop Manager both run that card in a slot.

The card's two ROMs are built in, as they are in the Apple II MiSTer core,
from whose tables these images come; they match MAME's `a2mouse` set.

| Image | Part | Size | CRC32 | SHA-1 |
|---|---|---|---|---|
| `rtl/cards/apple3_mouse_eprom.hex` | firmware EPROM, 341-0270-C | 2048 | `0bcd1e8e` | `3a9d881a8a8d30f55b9719aceebbcf717f829d6f` |
| `rtl/cards/apple3_mouse_mcu.hex` | 68705P3 program, 341-0269 | 2048 | `94067f16` | `3a2baa6648efe4456d3ec3721216e57c64f7acfc` |

**Mouse Card** in the OSD is On by default; Off leaves the slot empty. Like a
board change, it takes effect at the next reset. The left button is the mouse's
one button.

**Mouse Speed** is how much of the MiSTer mouse's movement the card's mouse
makes: **Normal** an eighth, **Fast** a quarter, **Faster** a half, **Fastest**
all of it. Apple's mouse gave about 90 counts to the inch and a present-day one
gives ten times that, so Normal is near the original in the hand. Programs of
the time count on it: ON THREE's driver keeps only three bits of each
sixtieth of a second's movement, and a mouse that sends forty counts in one
reads there as two.

## The card

| Part | In the core |
|---|---|
| 6821 PIA at $C0C0–$C0C3 | John Kent's `pia6821` |
| 68705P3 microcontroller, 2.0436 MHz | Jose Tejada's jt6805, enabled every seventh 14.318 MHz clock (2.0455 MHz) |
| 2 KiB EPROM, one 256-byte page at $C400 | block RAM; PIA PB1–PB3 choose the page |
| PIA port A ↔ 68705 port A | the byte path |
| PIA PB4, PB5 → 68705 PC0, PC1; PC2, PC3 → PB6, PB7 | handshake |
| 68705 PB0–PB3 | mouse X1, X0, Y0, Y1 |
| 68705 PB7, PB6 | button in (low = down), slot IRQ out (low = request) |
| PIA PB0, the "sync latch" | reads low, as in MAME |

The wiring is the Apple II MiSTer core's `applemouse.v` and MAME's
`a2bus/mouse.cpp`. [Imported parts and local changes](../rtl/cards/mouse/README.md).

SOS's driver does not call the EPROM. At boot it checks two bytes of it,
$Cn0C = $20 and $CnFB = $D6, and from then on it runs the 68705's command
protocol through the PIA itself, at the 1 MHz CPU speed: set mode ($0x), read
($10), serve an interrupt ($20), clear ($30), set position ($40), init ($50),
clamps ($60, $61), home ($70), interrupt period ($A0). The 68705 requests
interrupts on its own sixtieth-of-a-second timer, not the machine's VBL, and
they reach the CPU like any slot interrupt, through the D-VIA's CA1
([slots](SLOTS.md)). The EPROM's 6502 code is there for Apple II programs in
emulation mode.

## Movement

The mouse sends each axis as a gate line and a direction line, and the 68705's
main loop polls them: every gate edge is one count, up or down by the direction
line. A report's movement, scaled by Mouse Speed with the remainder carried
to the next report, waits in a backlog of ±255 counts and leaves an edge at a
time; more than that at once is dropped, as when a real mouse outruns the
program.

The 68705 takes about 0.3 ms over a count, and it also reads the same port for
the button, in its read command and in its timer interrupt. An edge that came
and went between two polls of the main loop would be lost, and its partner
with it. So the lines hold each state until the port has been read three
times, which is more than can fall between two polls, and reads that belong to
a set or clear of the interrupt-request bit are not counted.

The Apple II core's card steps on every enable that shows port B's address,
and jt6805 holds a read's address for two, so its gate moves twice for each
look; it also multiplies each report by eight. Measured in this bench against
the same 68705 program, a report of 1, 5, 20 or 100 units all come out as one
or two counts there: its pointer follows how often reports arrive, not how
large they are.

## Tests

`./sim/mouse/run.sh` (in `sim/run_tests.sh`) drives the card's bus with the RAT
driver's own `InitB`, `SndRDat` and `GetRDat` sequences at 1 MHz against the
68705's program: the reset state, the signature bytes, the EPROM paging,
`InitRat`, exact counts right, left, up and down and through a reversal, Mouse
Speed's eighths and their remainder, the clamps, both button bits, set
position, home, a timer interrupt every 16.7 ms and its serve code, movement
and button interrupts, 540 × 360 counts kept exactly with every interrupt on
and read commands back to back, and IRQ released by reset.

The whole-machine harness takes `--mouse-card`, `--mouse-trace` and, in its
`--keys` script, `mouse:DX:DY[:N]` and `button:1`/`button:0`
([development](DEVELOPMENT.md#testing), [an example](../sim/mouse/README.md)).

## Results, 2026-09-21

The native configuration is Rob Justice's `sos_selector_tdm_hd_mouse.po`,
booted from the [block card](BLOCK_STORAGE.md) with his soshdboot ROM. Its
`SOS.DRIVER` has ON THREE's "Desktop Mouse Driver" (`.MOUSE`, slot 4) and
Desktop Manager.

- **Simulation.** With `--mouse-card` SOS boots to the Selector /// menu; without
  it the boot stops at the SOS banner, as its author says of a machine with no
  card. `--mouse-trace` shows the driver at work on the 68705: mouse on, clear,
  clamps −840..840 and −288..288, `$B2`, `$98 $01`, `$C0`, mode 7, home. A
  60-unit movement then raises the slot interrupt each sixtieth of a second
  while it lasts; each time the driver serves it (`$20` → `$02`), reads the
  position (`$10`), and the deltas it reads add up to 60 exactly.
- **MiSTer.** The same image reaches the Selector with the card
  ([screenshot](mouse/2026-09-21-selector-with-card.png)) and stops at the
  banner with **Mouse Card** Off
  ([screenshot](mouse/2026-09-21-selector-without-card.png)). Moving a real
  mouse there has not been tried from this desk.
- **Draw ON ///, in simulation.** ON THREE's drawing program opens `.MOUSE`
  by name. On an image with the driver and without the Desktop Manager
  ([recipe](../sim/mouse/README.md)) it starts from the Selector, shows `Ms 1`
  in its status panel once M turns the mouse on, reads the driver every
  sixtieth of a second, and its option-menu highlight follows the mouse:
  twenty reports of 30 right and 20 down move it from the top-left panel to
  the bottom-right one, and a control run without them leaves it where it was.
- **Not shown: the Desktop Manager moving a menu.** That image's Desktop Manager turns
  mouse movement into cursor keys from the clock chip's tenth-of-a-second
  interrupt. It enables that interrupt in its `D_INIT`, and SOS 1.3's
  `INIT.KRNL` runs `CLK.INIT` after the drivers' inits, which writes zero to
  the clock's interrupt control register. The driver posts movement at
  $190C/$190D every sixtieth and nothing collects it. MAME's MM58167 treats
  that write the same way, so this looks like the software's doing and not the
  card's. Draw ON, above, is the program that opens `.MOUSE` itself.

Quartus 17.0: 21,372 ALMs and 498 RAM blocks for the whole core; setup slack
9.048 ns on the machine clock and 5.220 ns on the video clock.
