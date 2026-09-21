# Memory map from the decoder PROMs

The MMU is checked against Apple's boards themselves: a reference built from
the address-decode PROM dumps and the schematic wiring between them, which
shares nothing with the RTL. It covers the 5 V / 256 KiB board and the 12 V /
128 KiB board, which the **Memory** option selects (256K by default; the change
takes effect at the next reset, as a board swap would).
[`sim/memmap`](../sim/memmap/README.md) holds the reference and its tests.

The reference reproduces the documented map exactly on both boards, confirms
the `$87` alias, and found six places where the MMU differed from the machine.
Those are fixed.

## Sources

| Part | Location | Function | SHA-256 |
|---|---|---|---|
| 342-0061 | C11 | RAS256: row selects from the bank latch, PA15, PA8 and -ZPAGE | `32e3c28b6b81ee81acc6ce7f00ddaa9650f60fc55ca77f607ae2e0b7289c2868` |
| 342-0063 | C13 | CAS256: CAS1, CAS2, CAS4,6 and CAS5,7 | `336ee3d21deffd4e728a46fd0fbbe98b166fccaff6da65b1c1f5ce592ca6ca1c` |
| 341-0044 | C11 | the 12 V board's RAS PROM | `3b30fda2ff94500f1224918f14a0c71f10f7f8f2f027386dba4c428d757563eb` |
| 341-0042 | C13 | the 12 V board's CAS PROM | `afbf4b1bccf88b3f89fa7ebadfc771d9ab699b23a5464d0695bc92af24e232ce` |
| 342-0056 | C12 | CASB65: CAS0, CAS3, PCAS0,3 and USELB, the byte selection | `c370630ef41b870e71128acf0fd2d5826aaa990bcc36f13975c4c0ce6408ab82` |
| 342-0043 | C10 | Status: S399 and -IND | `0dc6efe955ac9627e05baef87187c2740055c65f65115360a689a1467abe58ea` |
| 342-0045 | F5 | I/O logic: RAMEN and the RAM bus enable | `37bae828a72098713612dd5f6ccb6b0206db23081a4a710e9574bcef3fa7cda0` |
| 342-0046 | F7 | Timing: WRAMEN, the RAM write enable | `8ca7d9e76627a1f4cf9f5592b378c4e51bdaa4ea4ad3d4c66ca6c000ae93af1b` |

Each is 1,024 nibbles. The bitsavers `A3PROMs`, archive.org `AppleIIIROMs` and
asimov `AppleIII_Logic_PROMs` copies are byte-identical; the two 12 V parts are
only in the archive.org set. The dumps are not in the repository, and the
reference refuses any file whose hash differs.

The reference reads the binaries, not the equations published with them. The
bitsavers text for 342-0056 gives the video term of CAS0, CAS3 and PCAS0,3 as
`/-AY * PRAS0,3 * RDHIRES`. The dump has `-AY * PRAS0,3 * /RDHIRES`, which is
also what the machine needs to read text, and the published equation
disagrees with the dump at 220 of its 1,024 addresses.

The wiring is drawing 050-0039-H sheets 3, 4 and 5 (main logic board) and
050-0044-B (5 V memory board), with the service manual's net list (chapter 15)
as a second reading of the main board:

* **Zero page (sheet 4).** C9 and D9 detect A15..A9 low. E7 is
  `NAND(PA8, -ALTSTK high or ABK4)`, so -ZPAGE is asserted for page `$00`, and
  for page `$01` only with the alternate stack selected and no X byte latched.
  D7 and D8 then put the zero-page register on A15..A9, and D4 makes A8 =
  Z0 xor PA8. Everything else on the board, the slots included, sees this
  substituted address; only 342-0061 and 342-0043 also take the processor's own
  PA8 and PA15.
* **Bank latch (sheet 3, A9, LS399).** Word 0 is BCKSW1..3 from the E VIA's
  PA0..PA2 and ground. Word 1 is DA0..DA2 from RAM data bus A and the S5D
  strap, +5 V. E8 selects word 1 when S399 and DA7 are both high. The outputs
  are ABK1..3, and ABK4, which is therefore high exactly while an X byte is
  latched. PA3 of the VIA is not connected, and neither are DA3..DA6.
* **Latch clock (sheet 3, H4, LS51).** `R/-W * -IND * PH0 + /Q3 * PH0 * SYNC`:
  the latch is a register, clocked at the end of every read that IND is not
  redirecting. Its second term reloads it early in an opcode fetch that IND
  would hold off, which is what ends extended addressing at SYNC.
* **Address multiplexer (sheet 3, E12, E13, F12, F13, E10).** AR0..AR7 carry
  A0..A5, A7, A8 for the row and A6, A8, A9, A10 xor -CAS3, A11 xor -CAS3, A12,
  A13 xor PRAS0,3 xor -CAS1, A8 for the column: fourteen distinct bits, with
  A8 three times. The PROM outputs are taken before the D13 latch. The drawing
  prints E13's two output pin numbers against the wrong halves of the symbol;
  by pin number, which is how the net list has it (`U13-9` to AR6 and J17-4,
  `U13-7` to AR7 and J17-24), AR6 is A7 and the A13 term, as in the manual's
  address logic truth table (p. 2.18), and AR7 is A8 twice.
* **Option bridge (sheet 3).** It joins -PCAS0,3 to the RAS0,3 pin of the
  memory connector. The 5 V board needs it: without it only 65,536 cells are
  distinct.
* **5 V memory board.** -RAS1,2 goes to every chip, and 342-0061 holds it
  active. U34 ANDs -CAS0 with -CAS2 and -CAS1 with -CAS3, which with -CAS4,6
  and -CAS5,7 gives four rows of eight 64K chips: two on data bus A, two on
  bus B. U33 replaces the column halves of AR1 and AR7, both spare copies of
  A8, with `RAS4,5 or J17-12` and `RAS6,7 or J17-12`. RAS4,5 and RAS6,7 are no
  longer strobes on this board; they name one of four 16 KiB quarters of a row.
* **12 V memory board.** Eight 16 KiB units, each answering when its RAS and its
  CAS are both strobed; the service manual lists the pairs (p. 2.10).
* **ROM, VIAs and I/O (sheet 5).** K8 makes C-FXXX = A15 * A14 * -IND. G7 and
  G8 decode `$FFCx`, `$FFDx` and `$FFEx` from it with -AIISW high. K8, D9 and
  J6 make CXXX (IOEN, `$C000`..`$CFFF`) and -C5XX..-C7XX. J4 makes FSPACE from
  the VIAs, the ACIA and the clock. J7 makes -ROMSEL from C-FXXX, A13, A12,
  -AIISW, -FFCX, ROMSEL1, R/-W, -FSPACE and -INH. 342-0045 then gives RAMEN,
  and 342-0046 gives WRAMEN, with RWPROT applying over C-FXXX.

A CPU access therefore comes down to the cells it strobes, and to those
enables. The reference names every cell by walking the documented map once
(each bank over `$2000`..`$9FFF`, and the system bank), using the flat byte
address the FPGA gives that byte. It finds 262,144 distinct cells on the 5 V
board and 131,072 on the 12 V board, one per byte, with no collisions and
reads agreeing with writes; which data bus each row or unit drives comes from
USELB, and agrees with the drawing. Every other access is then resolved
through the cells it reaches.

## What the boards do

`./sim/memmap/prom_reference.py --report` prints this; `--board 128` for the
12 V board.

| Access | 256 KiB | 128 KiB | Standing |
|---|---|---|---|
| Bank register 0..2 | that bank at `$2000`..`$9FFF` | the same | documented, PROM |
| Bank register 3..6 | that bank | **no RAM** | PROM |
| Bank register 7 | bank 2 | **bank 0** | PROM; MAME has bank 2 for both |
| Bank register bit 3 | ignored | ignored | schematic: PA3 not connected |
| X byte `$80`, `$81` | bank n below `$8000`, bank n+1 above | the same | documented, PROM |
| X byte `$82`..`$85` | the same | bank 2 below for `$82`; otherwise **no RAM** | PROM. "Bank Switch Razzle-Dazzle" (Softalk, August 1982): "bank 3 nonexistent in 128K machine" |
| X byte `$86` | bank 6 below; **no RAM** above | no RAM | PROM: no CAS is strobed. The same article: "bank 7 nonexistent in 256K machine" |
| X byte `$8F` | system map, bank 0 in the window, all RAM | the same | documented, PROM |
| X byte `$87` | **the same as `$8F`** | the same | schematic and PROM. ON THREE: "either an $8F OR $87 X-Byte on a 256K Apple ///" |
| X byte `$88`..`$8E`, bits 6..4 | bit 3 and bits 6..4 ignored | the same | schematic: DA3..DA6 not connected |
| Zero page register, any value | the page it names, through the whole decode: RAM by the ordinary map and bank register, but also a slot, the ROM or a VIA, and write protected when `$C0`..`$FF` | the same | schematic, PROM |
| Alternate stack | zero page xor 1 | the same | schematic (D4), PROM |
| Page `$01` while an X byte is latched | never the alternate stack: `$8n:01xx` is bank n, `$8F:01xx` the true stack page | the same | schematic (E7, J8) |
| Sister byte | reads of `$0800`..`$0FFF` and `$1800`..`$1FFF` strobe CAS0 with CAS3: the CPU takes bus B, and bus A carries address xor `$0C00` | the same | PROM |
| S399 | zero page register `$18`..`$1F`, zero-page accesses only, never the stack | the same | PROM |
| A latched X byte | ROM, VIAs, I/O and write protection all off | the same | schematic (K8) |
| Apple II mode | the VIAs and the ROM both give way to RAM | the same | schematic (G7, J7). The "Funny Mode" memo: the ROM "cannot be accessed in emulation mode" |
| Store to the bank register | reaches the map after the next read: the opcode fetch that follows still sees the old bank | the same | schematic (H4) |
| Opcode fetched from a zero page of `$18`..`$1F` | latches its X byte like any zero-page read | the same | schematic (H4) |

Absent RAM reads `$FF`: both memory boards pull their data buses up.

The sister byte is how the X byte reaches the latch: for a zero page in
`$18`..`$1F` it is the byte on bus A, which is where the latch's word 1 is
wired. Other CPU reads strobe one CAS, so only these pages return a pair.

## What changed in the MMU

1. **`$87` is `$8F`.** With eight banks the MMU treated `$87` as a linear pair
   starting at bank 7, which put `$87:2000` on the system bank. The 512 KiB
   configuration keeps four bits, where ON THREE documents `$87` as bank 7.
2. **Nothing behind `$86:8000`.** The MMU wrapped the upper half of the last
   pair onto the system bank, so a stray extended write could land in SOS.
   RAMEN is unaffected, so timing is unchanged.
3. **The latch turns the alternate stack off.** `$8F:0100`..`$01FF` went to the
   alternate stack page when it was selected.
4. **The zero-page register goes through the whole decode.** Zero page and
   stack were always RAM, and never write protected. The slots now see the
   substituted address too.
5. **The bank latch is a register** (`apple3_extaddr`). The map used the bank
   register directly, and a SYNC always cleared the X byte. Code that switches
   its own bank from inside `$2000`..`$9FFF` now fetches the next opcode from
   the old bank, and an opcode fetch from a zero page of `$18`..`$1F` can latch
   an X byte.
6. **No ROM in Apple II mode.** The ROM stayed selectable with ROMSEL1 set. The
   emulation disk runs with ROMSEL1 clear, so nothing depended on it, but a
   test that entered Apple II mode from ROM had to move into RAM.

SOS rewrites `$8n:01xx` pointers to the pair below and, as far as its source
shows, uses `$8F` only for the window and the clock bytes under the VIA, which
is how these went unnoticed. Everything else matched.

## Not established

* **The 5 V board with 128 KiB.** It uses 342-0062 for its CAS PROM, and no
  dump of that part was found. The 128 KiB setting is the 12 V board; bank
  register 7 in particular may land elsewhere on the other one.
* **512 KiB.** The third-party upgrade replaces C11..C13 with its own PROMs
  and adds the fourth bank bit. Apple's PROMs say nothing about it, and the
  16-bank configuration is unchanged and unvalidated. Its dumps, for whoever
  takes that on: `C11_512K.bin` (512 nibbles)
  `abf9b5ebffc63c8ef05da637946cccf992c80b845c794cd8685c6a0af6f04c54`,
  `C12_512K.bin` `f31c834f1c6aefd61fe77e1d6fcc9dd14db097ed20d6e347b70cf71d83ac431e`,
  `C13_512K.bin` `745985d5ca9df76fad7ab193f56ca3cd335578f8f72ff609eb4ffe1c7b22b6de`.
* **-INH and DMA.** Both reach 342-0045 and J7; no card in the core drives
  them, and the reference holds them inactive.
* **Latch timing within a cycle.** The latch is modelled per CPU cycle. H4's
  early reload relies on Q3 and PH0 edges inside the opcode fetch; that it
  lands before the RAM access is taken from the design's evident purpose.
* Video and refresh cycles. Only the CPU half of the PROMs is used here.

## Tests

[`sim/memmap`](../sim/memmap/README.md): 342,320 vectors from the reference
against `apple3_mmu`, for both boards, covering the RAM address, RAMEN, the RAM
read and write enables, ROM, VIA and I/O selects and the bus address; and a
real-CPU diagnostic that reads and writes across each boundary, runs the latch
cases on the real 6502, and then swaps to the 128 KiB board. It needs no
dumps. `sim/mmu_tb.sv` and `sim/storage_tb.sv` carry a few of the cases for a
clone without them.

On a MiSTer, [`memmap.po`](../sim/hwtest/README.md) runs the same checks from a
boot disk and finds the memory size itself: `PPPPPPPPPP.` on this core at
either setting, `PPFFPPFFFF.` on the build before the PROM-backed map. SOS 1.3
boots to System Utilities at both sizes, the Apple II emulation disk reaches
its monitor, and the Confidence Program reports "Memory Map good for: 256K" or
"128K" and runs its memory test (zero page and alternate stack, RAM, indirect
addressing, every bank present and the `$8F` extension) without errors.
