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
