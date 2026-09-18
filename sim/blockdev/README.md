# Block-storage card tests

Run `./sim/blockdev/run.sh` from the repository root. It needs Icarus
Verilog, Verilator with timing support, cc65's ca65/ld65 and the GHDL
dependencies of the other whole-core tests. Generated files stay in
`obj_dir/`.

- The committed firmware image `rtl/cards/apple3_block_firmware.hex` is
  reassembled and compared; rerun `rtl/cards/build_firmware.sh` after editing
  the firmware source.
- `block_card_tb.sv` drives the card's slot and host ports directly with a
  modelled host.
- `core_block_tb.sv` boots `diagnostic.s` on the real CPU with the card in
  slot 1, the way SOS's Problock3 driver and the soshdboot ROM use it.

See [the card description](../../docs/BLOCK_STORAGE.md) for the interface.

## SOS boot with Problock3

The whole-machine harness mounts hard-disk images with `--hd1=IMAGE` and
`--hd2=IMAGE` (raw ProDOS blocks; strip a 2MG header first). `--hd1-out=PATH`
saves drive 1 after the run, and `--block-boot` relaxes the stock ROM's
floppy milestones for a boot ROM that loads from the card.

To make a stock SOS 1.3 utilities floppy that uses the card, assemble
[Problock3](https://github.com/robjustice/Problock3) as a relocatable driver,
install it in `SOS.DRIVER` and convert the disk with Main's converter:

```sh
ca65 Problock3.s -o problock3.o
ld65 -C sim/blockdev/driver_o65.cfg problock3.o -o problock3.o65
java -jar ac.jar -g sysutils.dsk SOS.DRIVER > SOS.DRIVER.bin   # AppleCommander
python3 sim/blockdev/sos_driver.py add problock3.o65 SOS.DRIVER.bin
java -jar ac.jar -d sysutils.dsk SOS.DRIVER
java -jar ac.jar -p sysutils.dsk SOS.DRIVER SOS '$0000' < SOS.DRIVER.bin
storage_test --convert sysutils.dsk sysutils.woz
APPLE3_ROM=apple3.rom ./sim/run_core_boot.sh 2400000000 sysutils.woz --hd1=hard.po \
    --keys=text:f,wait3,text:l,wait3,text:.profile,enter,enter,enter,wait20,dump \
    --keys-after="Device handling"
```

The utilities act on a menu letter at once, so `text:f` opens the file menu
and `text:l` the list form; the three Returns accept the pathname, the level
count and the `.CONSOLE` destination. `text:m` opens the make-subdirectory
form, whose default is the boot volume: type the new path before pressing
Return. With `--writable --hd1-out=after.po`, `prodos_ls.py after.po` then
shows the directory SOS created.

`sos_driver.py` converts the o65 file to a `SOS.DRIVER` record and adds it,
or replaces a driver with the same name; the utilities disk ships a
`.PROFILE` driver for Apple's ProFile card, which Problock3 replaces.
`sos_driver.py list` shows the drivers in a file.

For a direct boot, point `APPLE3_ROM` at the soshdboot ROM, use `-` in place
of the floppy and pass an image that carries the soshdboot loader and kernel:

```sh
APPLE3_ROM=apple3hdboot.rom ./sim/run_core_boot.sh 1400000000 - \
    --hd1=sos_selector_hd.po --block-boot --to-menu --expect=Selector
```

`prodos_ls.py IMAGE [PATH]` lists a ProDOS-order image's directory on the
host, which verifies a save made by SOS without trusting the screen.
