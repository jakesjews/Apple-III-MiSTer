# Peripheral waits and horizontal boundaries

The timing unit models the motherboard's delayed IOSTOP, the timing PROM's
PHASEN and CS6522 decisions, and the once-per-line extension of the Q chain.
The card bus supplies four ready inputs connected to the NMOS 6502 RDY path.
The shipped MiSTer configuration ties the empty slots' ready inputs high.

## Onboard peripheral accesses

FSPACE includes the two VIAs, ACIA ($C0F0–$C0F3) and RTC ($C07x), qualified by
their actual MMU selects. Hidden I/O and extended RAM accesses do not trigger
peripheral waits. D11 samples FSPACE at C1M rising. The address of a new cycle
following an A-slot completion has not settled at that sampling edge; its
first B completion must wait. The RTL samples before T65 changes that address,
representing this ordering on the single master clock.

| New peripheral cycle follows | Clocks to completion | When crossing state 63 into HPE |
|---|---|---|
| Fast A completion | 21 | 23 |
| B completion | 14 | 16 |

The next full PRE1M cycle services the VIA. CS6522 prevents the preceding,
incomplete cycle from writing or acknowledging the register. Slow VIA/ACIA
accesses have the timing PROM's bypass; RTC accesses still depend on IOSTOP.
Each actual 6502 RMW write remains a distinct transaction.

RDY is separate from this clock stretching. `t65_wrapper` exposes T65's ready
input, and `apple3_core` keeps sending scheduled clock enables during a wait.
This preserves T65's NMI detection. CPU bus completion and card side effects
are suppressed on held reads; writes proceed even with RDY low. See the
[card interface](SLOTS.md) for assertion and release rules.

## Extended horizontal state

The line remains 912 master clocks: 64 states of 14 clocks and one of 16.
HPE holds the parallel-loaded Q register for two extra clocks in the A slot.
It does not append two idle clocks after a completed CPU cycle.

| Event, zero-based state dot | Ordinary state | Extended state |
|---|---|---|
| VIA rising enable | 0 | 0 |
| Optional CPU A completion | 6 | 8 |
| VIA falling enable | 7 | 9 |
| CPU B completion, subject to waits | 13 | 15 |
| Q3 high intervals | 0–3, 7–10 | 0–5, 9–12 |

The scan-decode latch G10 retains H=63's refresh decode on entry to HPE.
Refresh therefore still reserves an A slot when needed. The retained character
write decode is low and HPE forces blanking. Normal display fetches and the
72 character-download states per frame retain their existing timing. Machine
reset and RDY leave the scanner and VIA timebase running.

## Sources and verification

- Apple [Level 2 Service Reference Manual](https://vintagecomputer.ca/files/Apple/Apple%20III/Apple3ServiceRefManual1982.pdf),
  pp. 5.4–5.12 (clock chain, HPE and FSPACE waveforms), 7.8 (RDY) and
  7.11 (RTC access).
- Apple [timing schematic](https://apple3.org/Documents/Schematics/Timing%20Logic.jpg),
  sheet 10 of 050-0039-H: D10/D11, F7, the scan counters and G10 latch.
- Apple [I/O schematic](https://apple3.org/Documents/Schematics/IO%20Logic.jpg),
  sheet 5: FSPACE sources, RTC strobe qualification and VIA CS6522/PRE1M.
- Original 341-0030 and 342-0046-A PROM dumps and Patrick Schaefer's decoded
  equations; hashes and local-file configuration are in the
  [accuracy-test instructions](../sim/accuracy/README.md).

Run `bash sim/accuracy/run.sh` and `./sim/timing/run.sh`. The latter needs cc65,
GHDL and Verilator, and uses its own diagnostic ROM; it needs no Apple ROM.
It runs register readbacks and timer reads at both CPU speeds with the screen
off/on, checking exactly one VIA select for each access. Each card ready input
holds a read for 4,500 master clocks, while the bench checks stable CPU state,
continued VIA ticks and no completed bus strobes. A short NMI wholly inside
the first wait must reach the handler. Finally it verifies an ordinary store
and both RMW writes while ready is low.
It also resets the CPU while all four ready inputs remain low and verifies
that the scanner advances uninterrupted and the reset vector is fetched.

The new arrival test fails the preceding RTL at its first fast peripheral
access (7 clocks instead of 21). The boundary-only test also fails that RTL
at the first extended Q3 pulse (dot 900 of the line). These are regressions
that boot-only testing did not detect.

## Validation on 2026-09-18

- The full regression and accuracy suites pass. The arrival/boundary bench
  makes 10,574 checks; the original PROM comparison covers all 17,030 scan
  states, 136,240 A-slot decisions and 96 delayed PHASEN/CS6522 combinations.
- The T65 diagnostic passes 6,155 VIA accesses, four independent RDY waits
  totaling 18,000 master clocks, an NMI during a wait, three writes with RDY
  low (including both RMW writes), and reset with all ready inputs low.
- Serial echo passes all 256 byte values and a 64-byte CTS pause/resume.
  Joystick read-method checks pass at every one of the 256 positions.
- SOS 1.3 boots to the Utilities menu in the integrated four-drive simulation,
  with a 5 ms image-service delay, no disk retries/errors and all 1,024 downloaded
  font bytes matching. The run allows 1.4 billion half cycles.
- `make lint`, formatting checks for the changed Verilog and
  `git diff --check` pass.
- Quartus Prime 17.0.2 completes with zero errors and 39 warnings. All 38
  reported timing groups pass with zero total negative slack: minimum setup
  +0.614 ns and hold +0.244 ns. The fit uses 19,800 ALMs, 487 M10Ks and 33 DSPs.
  The existing WOZ and framework warnings remain; no timing constraints were
  changed.
- The same RBF boots SOS 1.3 on the DE10-Nano from a copy of the raw system
  disk, with all four image slots mounted. Keyboard commands open Device
  Handling and complete its device listing; the system and blank volumes
  appear and the clock advances. Screenshots: [Utilities menu](timing/2026-09-18-mister-sos.png)
  and [device list](timing/2026-09-18-mister-devices.png). Card RDY is exercised
  by simulated cards; the MiSTer build has empty expansion slots.
- After the hardware test, MiSTer returns to MENU, its INI is restored
  byte-for-byte, and hashes confirm the original disks, installed release RBF
  and Main binary are unchanged. Temporary core/disk/screenshot files are
  removed and the test's Zaparoo service is stopped.

Built RBF: `output_files/Apple-III.rbf` (3,988,968 bytes), SHA-256
`a4ab00707050c23b4222971e9a290044b98bdda29c0dc09b42c73000b04c8bdb`.

## Confidence Program 1.1 on 2026-09-18

The same RBF is packaged as `releases/Apple-III_20260918.rbf` and installed on
MiSTer, paired with Main SHA-256
`ac0688117c185bc5d7d67cc5c6cddd781997ac8f12f1f75c987329a8ffd696f2`.
Physical testing used copies of the user's Confidence Program and blank disk.
Confidence's **Make Ext. Drive Test Diskette** command prepared the external
test media; three separate image copies were mounted on .D2, .D3 and .D4.

- The repeating RAM test reached pass 3 without displaying an error, establishing
  at least two completed passes before Escape stopped it.
- **Seek/Read/Write/Align** showed successful checks in every row on all four
  drives, including recognition of the prepared test disks.
- **Disk Switch Detection** recognized removal and reinsertion on .D1, .D2
  and .D3 and advanced to .D4. Testing stopped at the user's request before
  exercising .D4's disk switch. Machine Configuration, Video Tests and
  Continuous Test were not validated in this session.
- Cleanup returned MiSTer to MENU, restored its original INI byte-for-byte,
  stopped the test's Zaparoo service and removed the scratch disks and remote
  screenshots. The original Confidence and blank images remained unchanged;
  the installed core and Main retained the hashes above.

[RAM test, pass 3](timing/2026-09-18-confidence-memory.png) ·
[All four disk drives](timing/2026-09-18-confidence-four-drives.png)
