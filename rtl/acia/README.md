# Imported 6551 serial core

`gen_uart.v` derives from Gyorgy Szombathelyi's GPL-2.0-or-later
[gen_uart.v](https://github.com/gyurco/apple2efpga/blob/518f05fba289fa7effe9d7a46a38a856d01c06e0/gen_uart.v),
pinned at commit `518f05fba289fa7effe9d7a46a38a856d01c06e0`.
The original copyright and license notice are retained; see COPYING.
Only the MOS 6551, baud generator, receiver and transmitter are imported.
The unrelated MC6850 and AY-31015 wrappers are omitted.

## Why this implementation

A nine-check bus/pin comparison (`sim/serial/compare_candidates.sh`) against
the Apple II MiSTer core's older `glb6551` (commit
`96980455374321293dcbbb91ff9d08b116571772`) found five failures there: software
reset destroyed the control/parity configuration, status reads did not
acknowledge receive IRQs, DSR transitions did not generate IRQs, and transmit
break was absent. gyurco's core passed eight of the nine, lacking only break.
It also uses one clock with enables, which fits this machine's scheduler
without introducing baud clocks into the FPGA fabric. Inspection found further
gaps in stop-bit handling and parity over short words; the corrections below
cover all of these and the pin-level bench in `sim/acia_tb.sv` checks them.

## Local corrections

- Preserve control and parity fields on programmed reset; clear overrun without
  discarding unread receive data. Preserve Apple-compatible command reset `$00`.
- Latch receive IRQs at arrival with IRQ enabled, acknowledge on status reads,
  and retain IRQ when only the data register is read. Qualify modem IRQs with DTR.
- Implement transmit break, CTS backpressure/TDRE masking, and DTR/carrier receive
  gating. Preserve the latest received word on overrun.
- Fix parity over the selected 5/6/7/8 data bits; implement 1, 1.5 and 2 stop bits
  and the eight-bit-plus-parity exception. Rework TX bit scheduling so queued
  frames have the programmed spacing. Reject false receive start pulses.
- Separate the external RxC enable from the baud-generator reference. The Apple
  III adapter ties RxC low, as on motherboard schematic sheet 8.
- Make read data combinational independently of the side-effect strobe, matching
  the existing motherboard bus contract.

The adapter in `../apple3_acia.sv` supplies a fractional 1.8432 MHz enable from
14.318182 MHz and synchronizes RX/CTS/DSR/DCD inputs. It connects the chip to
MiSTer's HPS UART; MiSTer has no separate DCD input, so carrier is asserted.
The OSD's `Serial CTS` option defaults to `Always ready`, matching the unplugged
motherboard port's receiver pull-up and allowing the stock ROM's self-test to
pass with no host UART open. `Host RTS` connects the real HPS flow-control line.

## Reset variant evidence

The SY6551 table in the Apple III Service Reference Manual (printed p. 4.11)
shows command bit 1 set after reset. However, the original Apple III ROM's
`ACIA` self-test sums masked status, command and control and requires `$10`.
With idle status `$10`, that requires command/control `$00`. The `$02` variant
reproduces the ROM's ACIA failure. The existing Apple II implementations and
MAME likewise use `$00`. This core targets the Apple-compatible variant rather
than imposing the incompatible SY table value.

## Sources and validation

- [Apple III Service Reference Manual](https://mirrors.apple2.org.za/ftp.apple.asimov.net/documentation/apple3/service_reference_manual/Apple%20III%20Service%20Reference%20Manual-OCR-1982.pdf), chapter 4 and motherboard sheet 8.
- [Rockwell R6551 datasheet](https://www.bitsavers.org/components/rockwell/R6551_Asynchronous_Communication_Interface_Adapter_DataSheet_Jan1981.pdf).
- [Gideon Zweijtzer's measured 6551 IRQ behavior](https://github.com/GideonZ/1541ultimate/blob/master/fpga/io/acia/vhdl_source/acia6551.vhd), comments at end of file.
- [MAME MOS6551](https://github.com/mamedev/mame/blob/master/src/devices/machine/mos6551.cpp), used as a secondary implementation cross-check.

`./sim/run_tests.sh` runs the bus/pin suite and all 15 baud-divider checks.
`./sim/serial/run.sh` runs a separate diagnostic ROM on the real T65 and checks
256 byte values through IRQ-driven receive and queued serial transmit.

Remaining limits: sub-bit interrupt edge timing, modem changes during an active
frame, and echo/break transitions in the middle of a frame are not certified
against a physical 6551. The motherboard baud source is modeled at its nominal
1.8432 MHz rate rather than reconstructing the original divider's jitter.
