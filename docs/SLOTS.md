# Reusable slots 1–4

`apple3_core` exposes a synchronous card bus for all four expansion slots.
The MiSTer top currently leaves all four sockets empty. A card can be attached
without changing the CPU, MMU, motherboard I/O or interrupt wiring. Main needs
no change for this interface.

## Card interface

All card logic uses `clk_14m`. Vector index 0 is physical slot 1, through index
3 for slot 4. Select signals are active high, unlike the physical connector.

| Core port | Meaning to a card |
|---|---|
| `slot_addr[15:0]` | CPU logical address |
| `slot_data_out[7:0]` | CPU write data |
| `slot_cpu_read` | 1 for a read, 0 for a write |
| `slot_cycle` | Commit the current transaction on this rising `clk_14m` edge |
| `slot_reset` | Synchronous card reset; bus responses must also be disabled immediately |
| `slot_device_select[n]` | Slot's 16-byte device aperture |
| `slot_io_select[n]` | Slot's 256-byte I/O/ROM aperture |
| `slot_io_strobe` | Shared $C800–$CFFF aperture, broadcast to every card |
| `slot_rom_deselect` | Shared $C020–$C02F decode, broadcast to every card |
| `slot_data_in[n][7:0]` | Card's read data returned to the core |
| `slot_data_oe[n]` | Card is driving read data for this address |
| `slot_irq_n[n]`, `slot_nmi_n[n]` | Card's active-low interrupt requests; tie unused inputs high |
| `slot_ready[n]` | 0 holds CPU reads through the shared RDY line; tie unused inputs high |
| `slot_bus_conflict` | More than one card is driving the shared read bus |

Selects and read data remain valid between CPU enables. Qualify register
writes, read acknowledgements and ROM-latch changes with `slot_cycle`; do not
repeat them on every master clock. A combinational ROM works directly; a
registered ROM must provide its byte before the completion edge. A 6502
read/modify/write instruction has two separate write cycles, both delivered.

A card needing more time must drive `slot_ready[n]` low from its address/select
or registered request state before the CPU completion edge. Keep it low until
the read data is valid, then release it. Do not derive RDY from `slot_cycle`:
that signal is suppressed during a read wait. The 6502 ignores RDY on writes,
so a card must accept writes when `slot_cycle` is asserted. Video, VIA timers
and interrupt detection continue while the CPU waits. A card must release RDY
on reset. [Timing details and tests](PERIPHERAL_TIMING.md).

| Slot | Device select | I/O/ROM select | IRQ status, low = pending |
|---|---|---|---|
| 1 | $C090–$C09F | $C100–$C1FF | $C065/$C06D bit 7 |
| 2 | $C0A0–$C0AF | $C200–$C2FF | $C064/$C06C bit 7 |
| 3 | $C0B0–$C0BF | $C300–$C3FF | E-VIA PA5 ($FFE1/$FFEF, configured as input) |
| 4 | $C0C0–$C0CF | $C400–$C4FF | E-VIA PA4 ($FFE1/$FFEF, configured as input) |

The MMU qualifies these apertures with environment bit 6. Hiding I/O exposes
the underlying RAM and does not clear card state. Both extended-addressing
modes bypass cards, including their select/deselect side effects. $C500–$C7FF
remains RAM. These rules also apply in Apple II emulation mode.

Empty slots and undriven card registers read $FF. Read enables are restricted
to the responding card's private aperture or the shared expansion aperture;
they cannot override motherboard I/O or RAM. Multiple responders produce a
deterministic bitwise AND and assert `slot_bus_conflict`. That result is a
diagnostic convention, not a model of electrical bus contention; correct
software/cards must avoid it.

## Expansion ROM selection

`apple3_slot_rom` supplies an optional per-card latch. An access to the card's
Cnxx page selects its expansion ROM. The selected card then sees `rom_select`
for accesses to $C800–$CFFF. Both reads and writes perform selection and release.

The default helper uses the native Apple III C02x release signal. For an Apple
II card, set `DESELECT_C02X=0` and `DESELECT_CFFF=1`; a card supporting both can
enable both. Release behavior belongs to the card, independent of CPU mode.
A CFFF read returns the last selected ROM byte and releases the latch at the
completion edge. Reset clears the latch.

There is no global "last card selected" latch on the motherboard. Selecting
another Cnxx page does not automatically release previous cards. SOS's
`SELC800` accesses C020 and CFFF to deselect both kinds of card before
accessing the desired Cnxx page. Its interrupt dispatcher saves and restores
the selected slot using the same convention. A card with no expansion ROM
simply omits the helper and never drives the shared aperture.

The synthetic [test card](../sim/slots/test_card.sv) demonstrates the interface,
including writable device registers and both ROM-release conventions.

## Interrupts and reset

Each card retains its own interrupt state. Following Apple's interface rules,
cards must latch IRQ until software acknowledges it, provide a software mask,
and reset with interrupts masked. The bus does not acknowledge requests itself.

The schematic's J4/D9 circuit drives D-VIA CA1 with
`!((&slot_irq_n) || H1)`: idle is low; while any request is held, CA1 follows
the complement of scanner H1. This supplies repeated edges every four normal
horizontal states. Clearing the VIA flag does not lose a still-pending request
from another card. SOS uses falling-edge CA1 mode and enables D-VIA IER bit 1.
The VIA's interrupt then reaches the CPU; slot IRQs have no direct CPU bypass.
The individual status inputs remain independent of the VIA interrupt mask.
Entering Apple II mode does not rewire the pins; software disables the VIA
interrupts before hiding the VIAs.

All four slot NMIs combine onto IONMI. E-VIA PB7 reports the raw active-low
line; environment bit 4 masks its connection to CPU NMI, just as it masks the
keyboard NMI. Power-on/core reset and native Control-Reset reset every card.
Reset alone in native mode leaves the cards intact and requests NMI. In Apple
II mode Reset alone also asserts the card reset line, per sheet 9.

Coprocessor/DMA ownership and memory inhibit are not part of this interface
yet. Ownership will be added with the first card that needs it.

## Sources

- Apple's [050-0039-H I/O schematic](https://apple3.org/Documents/Schematics/IO%20Logic.jpg),
  sheet 5: slot decode, shared C02x/C800 signals and J4/D9 interrupt retriggering.
- [Sound and serial schematic](https://apple3.org/Documents/Schematics/Sound-Serial%20Logic.jpg),
  sheet 8: individual IRQ status and E-VIA PB7.
- [Keyboard schematic](https://apple3.org/Documents/Schematics/Keyboard%20Logic.jpg),
  sheet 9: NMI gating and slot reset.
- Apple's [SOS 1.3 source](https://apple3.org/Documents/SourceCode/SOS13Src.txt),
  `INT.INIT`, `POLL.IO`, `SELC800` and the interrupt receivers: PCR=$76,
  individual IRQ polling and expansion-ROM save/deselect/restore.
- Apple's [Level 2 Service Reference Manual](https://vintagecomputer.ca/files/Apple/Apple%20III/Apple3ServiceRefManual1982.pdf),
  pp. 3.13, 7.1–7.2 and 7.7–7.10. The schematic and SOS agree on the slot
  numbering; some manual text swaps the pairs of IRQ status inputs.

## Validation

Run `sim/slots/run.sh` (also included in `sim/run_tests.sh`). It checks every
16-bit address in both access directions, both CPU modes, I/O enabled/hidden
and extended-system-bank addressing. Focused tests cover independent ROM
latches, both release conventions, final-byte reads, writable apertures,
contention detection, unmapped reads, reset and side effects only on a CPU
completion edge. Both linear and system-bank extended accesses are checked.

The second test boots a self-checking diagnostic on the real T65, MMU and
6522s with four synthetic cards. It exercises slow/fast reads, read/modify/write,
RAM overlays, simultaneous interrupts and SOS-style dispatch, held-request
retriggering, each slot's NMI, NMI masking and the PS/2 Reset/Control-Reset
paths in native and Apple II modes. No Apple ROM is required for these tests.

Results on 2026-09-18:

- Slot decode/ROM tests: 10,498,121 checks pass; the CPU diagnostic completes
  both native passes and the Apple II pass in 22,786 master clocks.
- The full regression and accuracy suites pass, including all timing PROM
  comparisons. Lint and formatting checks pass.
- Stock-ROM SOS simulation with all four drives and 71,590-clock host delays
  reaches the System Utilities menu without disk, loader or retry errors. All
  1,024 character-generator bytes match SOS's downloaded font.
- Quartus 17.0.2 full compilation: 0 errors, 39 warnings; all 38 timing groups
  pass, minimum hold slack +0.200 ns and minimum setup slack +0.568 ns. The
  empty-slot configuration uses 19,929 ALMs and 487 M10K blocks. A separate
  synthesis fixture with four synthetic cards also passes (414 logic cells),
  checking the populated bus and both ROM-latch variants.
- With all sockets empty the new card paths optimize away: the release RBF
  is byte-for-byte identical to the four-drive build, SHA-256
  `8e89ed823b8e3e51709e156202086a40e5c128bd98a20db3f8b2cbb1d895e3b5`.
  On MiSTer it boots to the SOS System Utilities menu with four disposable
  images mounted and leaves every image unchanged. Card behavior is verified
  by the populated simulations and synthesis fixture; this hardware boot has
  no expansion cards installed.
