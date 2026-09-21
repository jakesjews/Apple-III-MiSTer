# Mouse card tests

Run `./sim/mouse/run.sh` from the repository root. It needs Verilator with
timing support. Generated files stay in `obj_dir/`.

`mouse_card_tb.sv` drives the card's bus the way SOS's mouse driver does,
against the 68705's own program. See [the card description](../../docs/MOUSE.md)
for what is checked.

## Whole machine

`sim/run_core_boot.sh` takes `--mouse-card` and `--mouse-trace`, and its
`--keys` script takes `mouse:DX:DY[:N]` and `button:1`/`button:0`. Rob
Justice's mouse-enabled [Selector /// image](https://github.com/robjustice/soshdboot),
whose SOS configuration has ON THREE's `.MOUSE` driver in slot 4 and its
Desktop Manager, boots from the block card:

```sh
APPLE3_ROM=apple3hdboot.rom ./sim/run_core_boot.sh 460000000 - \
    --hd1=sos_selector_tdm_hd_mouse.po --block-boot --mouse-card --mouse-trace \
    --keys-after=Selector --keys=wait1,mouse:0:-4:12,wait3,dump
```

Without `--mouse-card` that image stops during its boot, as its author says a
machine without the card does.
