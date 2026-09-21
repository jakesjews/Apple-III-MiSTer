# Imported mouse card parts

Imported from [MiSTer-devel/Apple-II_MiSTer](https://github.com/MiSTer-devel/Apple-II_MiSTer/tree/a9498bb079993323966d98286b0e5dbe0e7d01d8/rtl/mouse),
commit `a9498bb079993323966d98286b0e5dbe0e7d01d8` (2026-09-16), where Gyorgy
Szombathelyi's `applemouse.v` builds the Apple II Mouse Interface card from them.

- `pia6821.v`: John E. Kent's OpenCores 6821 PIA, GPL, in the Verilog port that
  core uses.
- `jt6805/`: Jose Tejada's jt6805 CPU and `jtframe_6805mcu` 68705 wrapper from
  [jtcores](https://github.com/jotego/jtcores/tree/master/modules/jt680x),
  GPL-3.0-or-later, with its microcode (`6805.uc`, generated from `6805.yaml`).

Original notices are retained; see [COPYING](COPYING).

`applemouse.v` itself is **not** imported: [`../apple3_mouse_card.sv`](../apple3_mouse_card.sv)
puts the card on the Apple /// slot bus and makes the mouse's pulses its own
way. That core's two ROM tables, Apple's firmware EPROM (341-0270-C) and 68705
program (341-0269), are here as `../apple3_mouse_eprom.hex` and
`../apple3_mouse_mcu.hex`, byte for byte.
[Mouse card notes](../../../docs/MOUSE.md) describe the card.

Local changes:

- `6805.vh`: the microcode path is relative to the repository root, like the
  project's other memory images, so simulation finds it from there.
- `jtframe_6805mcu.v`: reset clears the port C direction register. Upstream
  clears port A's twice and port C's never, so after a Control-Reset the
  handshake lines stayed outputs until the program set them again.
- `jtframe_6805mcu.v`: the internal RAM is declared `[0:127]`, which is plain
  Verilog 2005, the language `.v` files are linted as.
