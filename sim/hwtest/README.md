# Hardware test disks

Boot-block programs for checking the core on a MiSTer by eye. The Apple ///
ROM reads block 0 of the disk to `$A000` and jumps there, so each program is
one 512-byte block and needs no SOS. The same disks run on a real Apple ///.

```sh
./sim/hwtest/build.sh        # needs ca65/ld65 (cc65); writes sim/obj_dir/hwtest/*.po
```

Copy a `.po` to `games/Apple-III/`, mount it as drive 1 and reset. The program
runs about three seconds after the reset and then holds its screen.

## `char_window.po`: character-download windows

The character generator is written only while `$C0DB` is selected, and only in
the scan PROM's `RTCWRT` states: four states on each of 18 blanking lines, each
line reading one screen hole (two font rows). The program loads a reference
glyph over a whole blanking interval, then loads a solid test glyph with
`$C0DB` switched on only from about line 217 to about line 240. That window
reads holes 3, 4 and 5 (font rows 6-7, 0-1 and 2-3) and misses holes 2 and 6
(rows 4-5).

Expected screen: two full-width bars of blocks, the reference and the test.
Each character is solid in rows 0-3 and 6-7 with a two-line gap in rows 4-5,
and the two bars match.

| Test bar | Meaning |
|---|---|
| Matches the reference | Downloads follow the per-line windows. Pass. |
| Blank | The whole set loads at one moment outside the window (the core before the display-fetch rework loaded it on line 261). |
| Solid, no gap | Downloads happen whenever `$C0DB` is selected. |

The program runs the CPU at 1 MHz, one 14-dot state per cycle, and times the
window from the vertical-blanking edge on the E VIA's CB2. Each end of the
window has about nine lines of slack. `./sim/run_core_boot.sh 130000000
char_window.woz --font-dump=01,02` shows the same glyphs in simulation after
converting the disk with Main's `storage_test --convert`.

## `joystick.po`: joystick readings

Reads both joystick ports continuously with SOS 1.3's GET_ANALOG timing,
through the ROM's own ANALOG routine, and shows the readings in hex with the
buttons and switches (1 = closed). With the sticks at rest X reads 80 and Y 7F;
the full travel reads 00 to FF, with Y increasing upward. Button 1 of a
controller shows as its port's BUTTON while it is held; each press of button 2
flips SWITCH. GROUND reads 00 and REFERENCE FF: the 2.26 V reference lies above
the joystick window.

## `wpsense.po`: write-protect sense

Reads the internal drive's write-protect sense (Q6H, then Q7L) in eight drive
states and shows each byte in hex; bit 7 set means protected. Mount it
writable. The expected line is `00 00 FF FF 00 00 00 00`:

| Column | Drive state | Reads |
|---|---|---|
| A | Motor on, drive selected, after 1.3 s | 00 |
| B | 0.3 s after motor off, inside the enable timeout | 00 |
| C | 1.6 s after motor off | FF: no drive is enabled |
| D | Motor on, internal drive deselected | FF |
| E, F | Reselected, at once and 0.3 s later | 00 |
| G, H | Straight after a ROM block read, and 0.3 s later | 00 |

With the disk write-protected every column reads FF. The character at the
right of the third line changes on each pass. The same readings come from
`./sim/run_core_boot.sh 700000000 wpsense.woz --writable --keys=wait16,dump
--keys-after="WP SENSE"`.

## diskhero: mode changes between display fetches

Paul Hagstrom's [diskhero](https://github.com/paulhagstrom/diskhero) (2022,
tested by its author on real hardware) splits the screen into six regions in
four video modes. A timer interrupt counting blanking pulses switches the mode
every eight scan lines, part-way through a line. The motherboard reads each
byte in its own state, so every region starts cleanly. A core that fetches
each line early, during the previous line's blanking, reads the first line of
a region with the previous region's address map.

Boot `diskhero.po` and look at the first line of the upper 140-colour map
(line 32, under the Level/Score bar), the grey playfield border (line 64), the
lower map (line 144) and the compass strip (line 176). Each should begin
cleanly. A one-line stripe of coloured dashes across the width at those
boundaries is the early-fetch fault.

## `memmap.po`: memory-map boundaries

Writes through one view of memory and reads through another, as the decoder
PROMs of Apple's boards lay the map out ([memory map](../../docs/MEMORY_MAP.md)).
It finds the memory size from bank 3, shows it, and shows `P` or `F` under each
group's number. The expected screen is `MAP 256K 123456789A` or `MAP 128K ...`
with `PPPPPPPPPP.` below; the full stop marks the end of the run. It is three
blocks long: the ROM loads block 0, which reads the other two through the ROM's
BLOCKIO.

| Group | Checks |
|---|---|
| 1 | Bank pairs: `$81:0100`, the bytes either side of `$81:8000`, and the top byte of the last pair, against the banks in the window |
| 2 | `$8F`: bank 0 in the window, RAM under the zero page register and under the ROM, registers untouched |
| 3 | `$87` is `$8F` |
| 4 | Nothing behind `$86:8000` (256K), or behind `$82:8000`, `$85` and bank register 3 (128K): reads `$FF`, and no other byte changes |
| 5 | Bank register 7, and bit 3: bank 2 with 256K, bank 0 with 128K |
| 6 | X byte bits 6-4 and bit 3 are ignored |
| 7 | The alternate stack sits at zero page xor 1, and a latched X byte switches it off |
| 8 | The bank latch is a register: the opcode after a store to the bank register comes from the old bank, its operand from the new one |
| 9 | An opcode fetched from zero page `$1A` latches its X byte: a PLA at `$00FF` pulls through `$81` |
| A | A zero page register of `$F0` or `$FF` reads the ROM and the VIA |

Cores before the PROM-backed map show `PPFFPPFFFF.`. A 512 KiB machine lays
some of these banks out differently and fails those groups.
`./sim/run_core_boot.sh 200000000 memmap.woz --dump-mem=0580,10` shows the
result row in simulation (`D0` is P, `C6` is F); add `--ram128k` for the other
board.

## `audio.po`: the three sound sources

Plays the speaker toggle, the hardware bell and the six-bit DAC in turn,
forever, with the step that is playing shown as an inverse bar. There is
nothing to press. Turn the volume down first: the DAC steps are full scale.
It is two blocks long, like `memmap.po`.

| Step | Source | What to hear |
|---|---|---|
| 1 | Speaker toggle, `$C030` | Three rising notes, C5 E5 G5 (523, 658 and 784 Hz), a third of a second each, at the speaker's level |
| 2 | Bell, `$C040` | Three 1 kHz beeps of 0.1 s, 0.3 s apart |
| 3 | DAC square, `$FFE0` bits 5-0 | The same three notes as a full-scale square wave, eight times the speaker's amplitude |
| 4 | DAC triangle | A soft tone of about 260 Hz for three quarters of a second |
| 5 | DAC bits 0 to 5 | Six bursts of one pitch (517 Hz), 0.2 s each, every one twice as loud as the one before; the first is faint |

Half a second of silence separates the steps and the character after `PASS`
changes on each pass, about every eight seconds. The speaker toggle and the
bell drive the same one-bit speaker, so a silent step 2 after an audible step
1 is the bell's timer; steps 3 to 5 come from the E VIA's port B, and a step 5
that starts loud, skips a level or does not grow evenly is a DAC bit stuck or
crossed. The CPU runs at 1 MHz, so the pitches are counted in even cycles.
`./sim/run_core_boot.sh 360000000 audio.woz --audio-out=audio.wav` records
what the core plays through the first pass as a WAV file.
