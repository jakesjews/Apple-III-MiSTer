# Serial verification

The ordinary regression runner (`./sim/run_tests.sh`) includes:

- `sim/acia_tb.sv`: bus and serial-pin checks for 40 word/parity/stop formats,
  queued transmission, error flags, reset behavior, handshakes and IRQs.
- `sim/acia_baud_tb.sv`: 105 transmitted bit periods across all 15 internal baud
  settings using the motherboard's nominal 14.318182 MHz clock. It also checks
  that a missing external RxC clock is not replaced by the reference clock.

Run `./sim/serial/compare_candidates.sh` for the nine-check comparison of the
pinned upstream cores. It downloads source into ignored `research/acia-candidates`
and deliberately reports upstream failures. It is a comparison tool, not a
passing regression gate. Our regular pin-level tests cover the corrected core.

## CPU integration

Run `./sim/serial/run.sh`. It needs ca65/ld65, GHDL, Verilator and a C++ compiler.
The script builds `echo.s` into a diagnostic ROM, then runs the actual T65,
MMU, RAM, VIAs and 6551. The external serial sender transmits all 256 byte
values; the T65 handles receive interrupts and echoes the bytes from a RAM
queue. It then receives 64 back-to-back bytes while CTS stalls transmission
and checks that TX interrupts drain the queue when CTS is asserted again.
The bench checks frame/data integrity, IRQ entries, and the ROM's stored
receive-error flags. It does not require Apple's boot ROM or disk images.

Only the IRQ handler reads ACIA status. Polling status in the main loop can
acknowledge a receive interrupt before the CPU takes it; the CTS regression
reproduced this race in the first diagnostic ROM and covers its correction.

The generated `obj_dir/echo.bin` contains two identical 4 KiB banks and can be
loaded through the core's **Load Boot ROM** option for the same test on MiSTer.
This temporarily replaces the normal boot ROM until the FPGA is reloaded.
It displays no UI; it echoes incoming 19200 8N1 data via receive interrupts.

## MiSTer hardware

Load the production core and `obj_dir/echo.bin`, select **Serial CTS: Host RTS**,
and ensure no other program uses `/dev/ttyS1`.
Copy `mister_echo.py` to MiSTer and run it with Python 3. It sends
4,096 binary bytes, compares every echo, and then verifies CTS pauses/resumes
64 queued bytes. It restores termios and modem-control settings on exit.

The host test directly opens the HPS UART; PPP, MIDI and login-console services
must not own that port during the test. The test starts no services itself.
Restore **Serial CTS: Always ready** and reload the normal RBF afterward to
restore the stock ROM. Alternatively keep Host RTS selected with a host that
asserts RTS before the stock ROM's ACIA self-test.
