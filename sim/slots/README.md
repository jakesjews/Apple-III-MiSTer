# Slot tests

Run `./sim/slots/run.sh` from the repository root. Requires Icarus Verilog,
Verilator with timing support, ca65/ld65 and the GHDL dependencies used by the
other whole-core tests. Generated files stay in ignored `obj_dir/`.

`slots_tb.sv` exhaustively checks MMU-qualified slot address decoding and
exercises independent native/Apple II expansion-ROM latches, writes, absent
cards, contention, reset and I/O/extended-addressing overlays.

`core_slots_tb.sv` boots `diagnostic.s` on the real CPU and VIAs with four
instances of `test_card.sv`. The program fails with its phase number or times
out if slot I/O, RAM overlays, IRQ dispatch, persistent/concurrent requests,
NMI masking or CPU-mode behavior fails. The bench also injects actual PS/2
Reset and Control-Reset events to verify card reset and retained state.

These synthetic cards are test fixtures, not installed peripherals. See
[the card interface](../../docs/SLOTS.md) for the connection contract and
hardware sources. Coprocessor ownership and RDY waits are separate work.
