# Mouse card tests

Run `./sim/mouse/run.sh` from the repository root. It needs Verilator with
timing support. Generated files stay in `obj_dir/`.

`mouse_card_tb.sv` drives the card's bus the way SOS's mouse driver does,
against the 68705's own program. See [the card description](../../docs/MOUSE.md)
for what is checked.

## Whole machine

`sim/run_core_boot.sh` takes `--mouse-card` and `--mouse-trace`, and its
`--keys` script takes `mouse:DX:DY[:N]` and `button:1`/`button:0`. Its clock
count is in half-cycles: 1,700,000,000 is about 59 seconds of machine time.

The program to run is ON THREE's Draw ON ///, which opens the `.MOUSE` driver
by name. It is on Rob Justice's [Selector /// images](https://github.com/robjustice/soshdboot),
but the image with the mouse driver also carries the Desktop Manager, which
takes a memory bank Draw ON needs on a 256 KiB machine. So make an image
with the driver and without the manager: copy `.MOUSE` from the mouse image's
`SOS.DRIVER` into the plain image's, and put that file back with AppleCommander:

```sh
java -jar ac.jar -g sos_selector_tdm_hd_mouse.po SOS.DRIVER > mouse.driver
java -jar ac.jar -g sos_selector_hd.po SOS.DRIVER > plain.driver
python3 sim/blockdev/sos_driver.py copy .MOUSE mouse.driver plain.driver
cp sos_selector_hd.po sos_selector_hd_mouse.po
java -jar ac.jar -d sos_selector_hd_mouse.po SOS.DRIVER
java -jar ac.jar -p sos_selector_hd_mouse.po SOS.DRIVER SOS '$0000' < plain.driver
```

Then boot it from the block card, type the menu names at the Selector, and
turn the mouse on in Draw ON with M:

```sh
APPLE3_ROM=apple3hdboot.rom ./sim/run_core_boot.sh 1700000000 - \
    --hd1=sos_selector_hd_mouse.po --block-boot --mouse-card --mouse-trace \
    --keys-after=Selector \
    --keys=text:graphics,enter,wait3,text:draw,enter,wait25,text:m,wait3,mouse:30:-20:20,wait3,dump \
    --frame-out=frame.ppm
```

Draw ON's status panel then shows `Ms 1`, the trace shows it reading the
driver every sixtieth of a second, and the highlight in its option menus
follows the mouse: with the movement it ends on the bottom-right panel, and
without it (`wait7` in place of the reports) on the top-left one.

The mouse image with the Desktop Manager, `sos_selector_tdm_hd_mouse.po`, is
the card-present check: without `--mouse-card` it stops during its boot, as
its author says a machine without the card does.
