#!/usr/bin/env python3
"""Reference memory map of Apple's 128 and 256 KiB Apple /// boards, from their PROMs.

Nothing here comes from the RTL or from another emulator.  The decode is the
contents of the PROM dumps; the wiring between them is drawing 050-0039-H
sheets 3, 4 and 5 (main logic board), 050-0044-B (5 V memory board) and, for
the 12 V board, the RAM unit table of the service manual (p. 2.10).  See
docs/MEMORY_MAP.md for the sources and for what is not established.

A CPU access is reduced to the DRAM cells it strobes:

    5 V, 256 KiB   (chip row, NAR1, NAR7, 14 multiplexed address bits)
    12 V, 128 KiB  (RAM unit, 14 multiplexed address bits)

Cells are named by walking the documented map once: the banks over
$2000-$9FFF, and the system bank at $0000-$1FFF and $A000-$FFFF.  The name is
the flat byte address the FPGA uses for that byte (bank * 32768 + offset,
system bank = 7 on either board).  Every other access (relocated zero page,
alternate stack, other bank register values, extended addressing) is then
looked up by the cells it reaches.  ROM, VIA, I/O and RAM enables come from
sheet 5's gates with 342-0045 and 342-0046.
"""

import argparse
import hashlib
import os
import sys
from collections import namedtuple

# SHA-256 of the dumps.  bitsavers A3PROMs, archive.org AppleIIIROMs and the
# asimov AppleIII_Logic_PROMs set are byte-identical where they overlap.
COMMON_PROMS = {
    "casb": ("342-0056", "c370630ef41b870e71128acf0fd2d5826aaa990bcc36f13975c4c0ce6408ab82"),
    "status": ("342-0043", "0dc6efe955ac9627e05baef87187c2740055c65f65115360a689a1467abe58ea"),
    "io": ("342-0045", "37bae828a72098713612dd5f6ccb6b0206db23081a4a710e9574bcef3fa7cda0"),
    "timing": ("342-0046", "8ca7d9e76627a1f4cf9f5592b378c4e51bdaa4ea4ad3d4c66ca6c000ae93af1b"),
}
BOARD_PROMS = {
    256: {
        "ras": ("342-0061", "32e3c28b6b81ee81acc6ce7f00ddaa9650f60fc55ca77f607ae2e0b7289c2868"),
        "cas": ("342-0063", "336ee3d21deffd4e728a46fd0fbbe98b166fccaff6da65b1c1f5ce592ca6ca1c"),
    },
    128: {
        "ras": ("341-0044", "3b30fda2ff94500f1224918f14a0c71f10f7f8f2f027386dba4c428d757563eb"),
        "cas": ("341-0042", "afbf4b1bccf88b3f89fa7ebadfc771d9ab699b23a5464d0695bc92af24e232ce"),
    },
}

SYSTEM_BANK = 7
BANK_BYTES = 0x8000


def bit(value, n):
    return (value >> n) & 1


def find_prom(directories, part):
    for directory in directories:
        for name in (f"{part}-A.BIN", f"{part}.bin", f"{part}-A.bin", f"{part}.BIN", f"AppleIII_prom_{part}.bin"):
            path = os.path.join(directory, name)
            if os.path.isfile(path):
                return path
    return None


def load_proms(directories, kib):
    images = {}
    for key, (part, digest) in {**COMMON_PROMS, **BOARD_PROMS[kib]}.items():
        path = find_prom(directories, part)
        if path is None:
            raise FileNotFoundError(f"{part} not found in {', '.join(directories)}")
        with open(path, "rb") as handle:
            data = handle.read()
        actual = hashlib.sha256(data).hexdigest()
        if len(data) != 1024 or actual != digest:
            raise ValueError(f"{path}: SHA-256 {actual}, expected {digest}")
        images[key] = data
    return images


Access = namedtuple(
    "Access",
    "bus_addr zpage cas uselb s399 ind cpu_cells other_cells "
    "ramen ram_to_bus wramen romsel ffdx ffex io_space c0xx",
)

# 5 V board: U34 ANDs -CAS0 with -CAS2 and -CAS1 with -CAS3, so six CAS lines
# strobe four rows of eight 64K chips.
ROW_256 = {"cas0": "A", "cas2": "A", "cas1": "B", "cas3": "B", "cas46": "C", "cas57": "D"}
# 12 V board: a 16 KiB unit answers when its RAS and its CAS are both strobed
# (service manual p. 2.10).
UNIT_128 = {
    ("ras03", "cas0"): 0,
    ("ras12", "cas1"): 1,
    ("ras12", "cas2"): 2,
    ("ras03", "cas3"): 3,
    ("ras45", "cas46"): 4,
    ("ras45", "cas57"): 5,
    ("ras67", "cas46"): 6,
    ("ras67", "cas57"): 7,
}


class Board:
    """The main logic board's CPU-cycle decode with one of Apple's memory boards."""

    def __init__(self, images, kib):
        self.kib = kib
        self.top_bank = 6 if kib == 256 else 2
        self.ras = images["ras"]
        self.cas = images["cas"]
        self.casb = images["casb"]
        self.status = images["status"]
        self.io = images["io"]
        self.timing = images["timing"]
        self._check_unused_inputs()
        self.bus_of = self._data_buses()

    def _check_unused_inputs(self):
        # RDHIRES and RFSH belong to the video half; a CPU access must not see them.
        for a in range(1024):
            if bit(a, 4) == 0 and self.ras[a] != self.ras[a & ~0x180]:
                raise ValueError("RAS PROM depends on RDHIRES/RFSH in the CPU phase")
            if bit(a, 9) == 0 and self.cas[a] != self.cas[a & ~0x010]:
                raise ValueError("CAS PROM depends on RDHIRES in the CPU phase")
            if bit(a, 6) == 0 and self.casb[a] != self.casb[a & ~0x020]:
                raise ValueError("342-0056 depends on RDHIRES in the CPU phase")
            # RAMEN ignores PH2M, -DMAI and R/-W; WRAMEN in the CPU's own slot
            # (C1M high) ignores the speed, stop, display and clock inputs.
            if bit(self.io[a], 3) != bit(self.io[a | 0x0A2], 3):
                raise ValueError("342-0045 RAMEN depends on PH2M, -DMAI or R/-W")
            if bit(a, 0) and bit(self.timing[a], 2) != bit(self.timing[a & ~0x21A], 2):
                raise ValueError("342-0046 WRAMEN depends on timing inputs with C1M high")

    def _data_buses(self):
        """Which data bus each row or unit drives, from USELB on single-strobe reads."""
        buses = {}
        for abk in range(8):
            for abk4 in (0, 1):
                for page in range(1, 256):
                    strobed, uselb = self._strobes(page << 8, True, abk, abk4, bit(page, 7), bit(page, 0), 1)[:2]
                    if len(strobed) == 1:
                        (where,) = strobed
                        if buses.setdefault(where[0], uselb) != uselb:
                            raise ValueError(f"USELB disagrees about the data bus of {where[0]}")
        if self.kib == 256 and buses != {"A": 0, "B": 1, "C": 0, "D": 1}:
            raise ValueError(f"USELB gives {buses}, 050-0044-B has rows A and C on bus A")
        return buses

    def _strobes(self, bus, read, abk, abk4, pa15, pa8, nzpage):
        a10, a11, a12, a13, a14, a15 = (bit(bus, n) for n in (10, 11, 12, 13, 14, 15))
        abk1, abk2, abk3 = bit(abk, 0), bit(abk, 1), bit(abk, 2)
        rw = 1 if read else 0
        # C11: A9 ABK4, A8 RFSH, A7 RDHIRES, A6 -ZPAGE, A5 PA8, A4 -AY, A3 PA15, A2-A0 ABK3-1.
        r = self.ras[(abk4 << 9) | (nzpage << 6) | (pa8 << 5) | (pa15 << 3) | (abk3 << 2) | (abk2 << 1) | abk1]
        pras = {"ras03": bit(r, 0), "ras12": bit(r, 1), "ras45": bit(r, 2), "ras67": bit(r, 3)}
        # C13: A9 -AY, A8 A14, A7-A5 ABK3-1, A4 RDHIRES, A3 PRAS0,3, A2 A15, A1 A11, A0 A13.
        c = self.cas[(a14 << 8) | (abk3 << 7) | (abk2 << 6) | (abk1 << 5) | (pras["ras03"] << 3) | (a15 << 2) | (a11 << 1) | a13]
        # C12 342-0056: A9 PRAS0,3, A8 PRAS1,2, A7 ABK2, A6 -AY, A5 RDHIRES, A4 R/-W, A3-A0 A15 A14 A13 A11.
        d = self.casb[
            (pras["ras03"] << 9) | (pras["ras12"] << 8) | (abk2 << 7) | (rw << 4) | (a15 << 3) | (a14 << 2) | (a13 << 1) | a11
        ]
        level = {"cas0": bit(d, 0), "cas3": bit(d, 3), "cas1": bit(c, 2), "cas2": bit(c, 3), "cas46": bit(c, 0), "cas57": bit(c, 1)}
        uselb = bit(d, 1)
        pcas03 = 1 - bit(d, 2)
        # Sheet 3, E12/E13/F12/F13 with E10: AR0-AR7 carry A0-A5, A7, A8 for
        # the row and A6, A8, A9, A10 xor -CAS3, A11 xor -CAS3, A12, A13 xor
        # PRAS0,3 xor -CAS1, A8 for the column (E13's pin numbers, and the net
        # list, put the A13 term on AR6 and A8 on AR7).  Fourteen distinct bits.
        chip = (
            (bus & 0x03FF)
            | ((a10 ^ level["cas3"]) << 10)
            | ((a11 ^ level["cas3"]) << 11)
            | (a12 << 12)
            | ((a13 ^ pras["ras03"] ^ level["cas1"]) << 13)
        )
        active = [name for name, low in level.items() if low == 0]
        if self.kib == 256:
            # 050-0044-B.  -RAS1,2 reaches every chip and the PROM holds it
            # active.  U33 replaces AR1's and AR7's column halves, both A8,
            # with RAS4,5 or J17-12 and RAS6,7 or J17-12, and the main board's
            # option bridge puts -PCAS0,3 on J17-12.
            if not pras["ras12"]:
                raise AssertionError("342-0061 released RAS1,2")
            nar1 = pras["ras45"] | pcas03
            nar7 = pras["ras67"] | pcas03
            strobed = {(ROW_256[name], nar1, nar7, chip) for name in active}
        else:
            strobed = {(unit, chip) for (ras, cas), unit in UNIT_128.items() if pras[ras] and level[cas] == 0}
        return strobed, uselb, tuple(active)

    def access(self, addr, read, zero_page=0, env=0x77, native=True, abk=0, abk4=0):
        """One CPU cycle.  abk/abk4 are the outputs of the A9 bank latch."""
        pa8 = bit(addr, 8)
        pa15 = bit(addr, 15)
        alt_stack = not bit(env, 2)
        # Sheet 4: C9 (A15-A11 low), D9 (A10-A9 low), E7 = NAND(PA8, -ALTSTK high or ABK4).
        zpage = (addr >> 9) == 0 and (pa8 == 0 or (alt_stack and not abk4))
        # D7/D8 swap in Z7-Z1; D4 makes bus A8 = Z0 xor PA8.
        high = (zero_page ^ pa8) if zpage else (addr >> 8)
        bus = (high << 8) | (addr & 0xFF)
        nzpage = 0 if zpage else 1
        a = [bit(bus, n) for n in range(16)]
        rw = 1 if read else 0

        # C10 342-0043: A9 -ZPAGE, A8 A15, A7 PA8, A6 ABK4, A5 -SEL2M, A4 IOSYNC, A3-A0 A14 A13 A12 A11.
        st = self.status[(nzpage << 9) | (a[15] << 8) | (pa8 << 7) | (abk4 << 6) | (1 << 5) | (a[14] << 3) | (a[13] << 2) | (a[12] << 1) | a[11]]
        s399 = bit(st, 0)
        ind = 1 - bit(st, 2)

        strobed, uselb, active = self._strobes(bus, read, abk, abk4, pa15, pa8, nzpage)
        cpu_cells = frozenset(cell for cell in strobed if self.bus_of[cell[0]] == uselb)
        other_cells = frozenset(strobed) - cpu_cells

        # Sheet 5.  K8: C-FXXX = A15*A14*-IND.
        c_fxxx = a[15] & a[14] & (1 - ind)
        # G7 (A13-A6 high, -AIISW high) enables G8, which splits A5 A4.
        ff = c_fxxx and all(a[6:14]) and native
        ffcx = ff and (a[5], a[4]) == (0, 0)
        ffdx = ff and (a[5], a[4]) == (0, 1)
        ffex = ff and (a[5], a[4]) == (1, 0)
        # K8/D9: CXXX = C-FXXX * IOEN * /A13 * /A12.  J6 splits A10-A8 while A11 is low.
        cxxx = bool(c_fxxx and bit(env, 6) and not a[13] and not a[12])
        page_c = (a[10] << 2) | (a[9] << 1) | a[8] if cxxx and not a[11] else None
        c0xx = page_c == 0
        # K4 (A7 high) and K7 (A7 low) split A6-A4: $C0Fx is the 6551, $C07x the clock.
        sel6551 = c0xx and a[7] and (a[6], a[5], a[4]) == (1, 1, 1)
        c07x = c0xx and not a[7] and (a[6], a[5], a[4]) == (1, 1, 1)
        fspace = bool(ffdx or ffex or sel6551 or c07x)
        # J7: C-FXXX, S5A, -AIISW, -FFCX, ROMSEL1, R/-W, -FSPACE, -INH, A12, A13.
        romsel = bool(c_fxxx and a[13] and a[12] and native and not ffcx and bit(env, 0) and read and not fspace)
        # F5 342-0045: A9 CXXX, A8 -C7XX, A7 PH2M, A6 -FSPACE, A5 -DMAI, A4 -ROMSEL, A3 -INH, A2 -C6XX, A1 R/-W, A0 -C5XX.
        f5 = self.io[
            (int(cxxx) << 9)
            | (int(page_c != 7) << 8)
            | (1 << 7)
            | (int(not fspace) << 6)
            | (1 << 5)
            | (int(not romsel) << 4)
            | (1 << 3)
            | (int(page_c != 6) << 2)
            | (rw << 1)
            | int(page_c != 5)
        ]
        ramen = bit(f5, 3)
        ram_to_bus = 1 - bit(f5, 0)
        # F7 342-0046: A9 -SEL2M, A8 RWPROT, A7 R/-W, A6 -FSPACE, A5 C-FXXX, A4 -IOSTOPD, A3 DSPLY, A2 RAMEN, A1 -C07X, A0 C1M.
        f7 = self.timing[(1 << 9) | (bit(env, 3) << 8) | (rw << 7) | (int(not fspace) << 6) | (c_fxxx << 5) | (1 << 4) | (ramen << 2) | (int(not c07x) << 1) | 1]
        wramen = bit(f7, 2)
        io_space = cxxx and page_c not in (5, 6, 7)
        return Access(bus, zpage, active, uselb, s399, ind, cpu_cells, other_cells, ramen, ram_to_bus, wramen, romsel, bool(ffdx), bool(ffex), io_space, c0xx)


class Reference:
    def __init__(self, board):
        self.board = board
        self.names = {}
        bytes_expected = (board.top_bank + 2) * BANK_BYTES
        for bank in range(board.top_bank + 1):
            for addr in range(0x2000, 0xA000):
                self._name(addr, bank, bank * BANK_BYTES + addr - 0x2000)
        for addr in list(range(0x0000, 0x2000)) + list(range(0xA000, 0x10000)):
            self._name(addr, 0, SYSTEM_BANK * BANK_BYTES + (addr & 0x7FFF))
        if len(self.names) != bytes_expected:
            raise AssertionError(f"documented map reaches {len(self.names)} cells, expected {bytes_expected}")

    def _name(self, addr, bank, flat):
        # ROM and I/O off, so every address is RAM.
        write = self.board.access(addr, False, env=0x34, abk=bank)
        read = self.board.access(addr, True, env=0x34, abk=bank)
        if len(write.cpu_cells) != 1 or write.other_cells:
            raise AssertionError(f"write to {addr:04x} bank {bank} strobes {write.cas}")
        if read.cpu_cells != write.cpu_cells:
            raise AssertionError(f"{addr:04x} bank {bank} reads and writes different cells")
        (cell,) = write.cpu_cells
        if cell in self.names:
            raise AssertionError(f"{addr:04x} bank {bank} collides with {self.names[cell]:05x}")
        self.names[cell] = flat

    def resolve(self, addr, read, **state):
        """Flat byte address reached, None when no chip is strobed onto the CPU's bus."""
        access = self.board.access(addr, read, **state)
        if not access.cpu_cells:
            return None, access
        if len(access.cpu_cells) != 1:
            raise AssertionError(f"{addr:04x} {state} strobes {access.cas}")
        (cell,) = access.cpu_cells
        if cell not in self.names:
            raise AssertionError(f"{addr:04x} {state} reaches a cell outside the documented map")
        return self.names[cell], access

    def sister(self, access):
        if not access.other_cells:
            return None
        (cell,) = access.other_cells
        return self.names[cell]


def latch_state(bank_register, xbyte):
    """A9 (LS399) outputs.  Word 0 = BCKSW1-3 and ground, word 1 = DA0-DA2 and S5D (+5 V)."""
    if xbyte is not None and xbyte & 0x80:
        return {"abk": xbyte & 7, "abk4": 1}
    return {"abk": bank_register & 7, "abk4": 0}


def describe(flat):
    if flat is None:
        return "no RAM"
    bank, offset = divmod(flat, BANK_BYTES)
    return f"S:{offset:04x}" if bank == SYSTEM_BANK else f"{bank}:{offset:04x}"


def page_runs(ref, pages, **state):
    """Summarise a mapping as runs of pages whose (bank, offset - address) is constant."""
    runs = []
    previous = object()
    for page in pages:
        addr = page << 8
        flat, _ = ref.resolve(addr, True, env=0x34, **state)
        key = None if flat is None else (flat // BANK_BYTES, (flat % BANK_BYTES) - addr)
        if key != previous:
            runs.append((addr, flat))
            previous = key
    return " ".join(f"{addr:04x}>{describe(flat)}" for addr, flat in runs)


def check_page_granularity(ref):
    """The low eight address bits reach the chips unmodified, so RAM vectors can be per page."""
    for state in ({"abk": 1}, {"abk": 5}, {"abk": 1, "abk4": 1}, {"abk": 7, "abk4": 1}, {"zero_page": 0x1A, "env": 0x30}):
        state = {"env": 0x34, **state}
        for page in range(256):
            base, _ = ref.resolve(page << 8, False, **state)
            for low in (0x01, 0x7F, 0x80, 0xFF):
                flat, _ = ref.resolve((page << 8) | low, False, **state)
                if (base is None) != (flat is None) or (base is not None and flat != base + low):
                    raise AssertionError(f"page {page:02x} is not mapped as a unit in {state}")


def report(ref, out):
    board = ref.board
    name = "5 V / 256 KiB" if board.kib == 256 else "12 V / 128 KiB"
    out.write(f"{name} board, CPU accesses, from the PROM dumps\n\n")
    out.write(f"documented map: {len(ref.names)} distinct cells, one per byte, no collisions\n\n")

    out.write("bank register (VIA PA0-PA2 only; PA3 is not connected)\n")
    for bank in range(8):
        out.write(f"  {bank}: {page_runs(ref, range(0x02, 0x100), abk=bank)}\n")

    out.write("\nextended addressing (latch word 1: DA0-DA2 and +5 V; DA3-DA6 are not connected)\n")
    for low in range(8):
        out.write(f"  $8{low:X}/$8{low + 8:X}: {page_runs(ref, range(0x01, 0x100), abk=low, abk4=1)}\n")

    out.write("\nsister byte on bus A while the CPU reads bus B (both CAS0 and CAS3 strobed)\n")
    paired = []
    for page in range(256):
        flat, access = ref.resolve(page << 8, True, env=0x34, abk=0)
        sister = ref.sister(access)
        if sister is not None:
            if sister != flat ^ 0x0C00 or access.uselb != 1:
                raise AssertionError(f"page {page:02x} sister is {sister:05x}")
            paired.append(page)
    out.write("  pages " + " ".join(f"{p:02x}" for p in paired) + " pair with address xor $0C00\n")

    out.write("\nstatus PROM\n")
    s399_pages = sorted({zp for zp in range(256) if board.access(0x0010, True, zero_page=zp).s399})
    out.write("  S399 for zero page register " + " ".join(f"{p:02x}" for p in s399_pages) + "\n")
    for zp in range(256):
        if board.access(0x0110, True, zero_page=zp, env=0x73).s399:
            raise AssertionError("S399 on a stack access")

    out.write("\nROM, VIA and I/O decode for a zero page register naming them (I/O and ROM enabled)\n")
    for zp, low in ((0xC0, 0x90), (0xC5, 0x00), (0xF0, 0x00), (0xFF, 0xD0), (0xFF, 0xC0)):
        a = board.access(low, True, zero_page=zp, env=0x77)
        what = "VIA D" if a.ffdx else "VIA E" if a.ffex else "ROM" if a.romsel else "I/O" if a.io_space else "RAM"
        out.write(f"  register {zp:02x}, zero page ${low:02x}: bus {a.bus_addr:04x}, {what}\n")


VECTOR_FLAGS = ("ramen", "ram_read", "ram_write", "rom", "io_space", "c0xx", "via_d", "via_e", "populated")


def vector_lines(ref):
    """Text vectors for memmap_prom_tb.sv.

    addr zero_page environment bank_register ext_active xbyte read native ram_128k
    bus_addr flat flags
    """
    lines = []
    kib128 = 1 if ref.board.kib == 128 else 0

    def emit(addr, read, zero_page, env, bank_register, xbyte, native=True):
        state = latch_state(bank_register, xbyte)
        flat, a = ref.resolve(addr, read, zero_page=zero_page, env=env, native=native, **state)
        populated = flat is not None
        values = {
            "ramen": a.ramen,
            "ram_read": a.ram_to_bus and populated,
            "ram_write": a.wramen and populated,
            "rom": a.romsel,
            "io_space": a.io_space,
            "c0xx": a.c0xx,
            "via_d": a.ffdx,
            "via_e": a.ffex,
            "populated": populated,
        }
        flags = sum(1 << n for n, name in enumerate(VECTOR_FLAGS) if values[name])
        lines.append(
            f"{addr:04x} {zero_page:02x} {env:02x} {bank_register:02x} {1 if xbyte is not None else 0} {(xbyte or 0):02x} "
            f"{1 if read else 0} {1 if native else 0} {kib128} {a.bus_addr:04x} {(flat or 0):05x} {flags:03x}"
        )

    def offsets(page):
        lows = [0x00, 0xA5, 0xFF]
        if page == 0xFF:
            lows += [0xBF, 0xC0, 0xCF, 0xD0, 0xDF, 0xE0, 0xEF, 0xF0]
        if page == 0xC0:
            lows += [0x6F, 0x70, 0x7F, 0x80, 0xEF, 0xF0]
        return lows

    def emit_page(page, *args, **kwargs):
        for low in (0x00, 0xA5, 0xFF):
            emit((page << 8) | low, *args, **kwargs)

    for read in (True, False):
        # Every page under every bank register value.  Bits 3-7 of the register are
        # interrupt inputs and the Apple II switch; only PA0-PA2 reach the latch.
        for bank_register in list(range(16)) + [0x42, 0xF5]:
            for page in range(0x02, 0x100):
                emit_page(page, read, 0x00, 0x34, bank_register, None)
        # Zero page and both stacks for every zero-page register value.
        for bank_register in range(8):
            for zero_page in range(256):
                emit_page(0x00, read, zero_page, 0x34, bank_register, None)
                emit_page(0x01, read, zero_page, 0x34, bank_register, None)
                emit_page(0x01, read, zero_page, 0x30, bank_register, None)
        # Extended addressing.  The latch can only hold an X byte while the zero
        # page register is $18-$1F, and then it ignores the bank register.
        for xbyte in list(range(0x80, 0x90)) + [0x00, 0x07, 0x7F, 0x93, 0xF6, 0xFF]:
            for page in range(0x100):
                emit_page(page, read, 0x1A, 0x77, 5, xbyte)
            for env in (0x73, 0x7F):
                for page in (0x00, 0x01, 0x02, 0xC0, 0xF0, 0xFF):
                    emit_page(page, read, 0x1A, env, 0, xbyte)
        for zero_page in range(0x18, 0x20):
            for xbyte in (0x81, 0x86, 0x87, 0x8F):
                for page in (0x00, 0x01, 0x02, 0x7F, 0x80, 0xFF):
                    emit_page(page, read, zero_page, 0x73, 2, xbyte)
        # ROM, VIA, I/O and write protection: every combination of ROMSEL1,
        # alternate stack, RWPROT and IOEN, in native and Apple II mode, with and
        # without an X byte, and through a zero page register that names them.
        for env in [0x30 | rom | (stack << 2) | (protect << 3) | (ioen << 6) for rom in (0, 1) for stack in (0, 1) for protect in (0, 1) for ioen in (0, 1)]:
            for native in (True, False):
                for xbyte in (None, 0x81, 0x8F):
                    for page in list(range(0xA0, 0x100)) + [0x00, 0x01, 0x02, 0x20, 0x9F]:
                        for low in offsets(page):
                            emit((page << 8) | low, read, 0x1A if xbyte else 0x00, env, 1, xbyte, native)
                for zero_page in (0xC0, 0xC4, 0xC5, 0xC7, 0xC8, 0xCF, 0xD0, 0xEF, 0xF0, 0xFF):
                    for page in (0x00, 0x01):
                        for low in offsets(zero_page) + offsets(zero_page ^ 1):
                            emit((page << 8) | low, read, zero_page, env, 1, None, native)
    return lines


def main():
    parser = argparse.ArgumentParser(description="PROM-derived Apple /// memory map reference")
    parser.add_argument(
        "--prom-dir",
        action="append",
        help="directory holding PROM dumps; may be given more than once",
    )
    parser.add_argument("--board", type=int, choices=(128, 256), default=256)
    parser.add_argument("--vectors", help="write bench vectors to this file")
    parser.add_argument("--report", action="store_true", help="print the derived map")
    args = parser.parse_args()
    directories = args.prom_dir or [
        os.environ.get("APPLE3_PROM_DIR", "research/docs/bitsavers/A3PROMs"),
        os.environ.get("APPLE3_PROM_12V_DIR", "research/roms/archive.org_AppleIIIROMs"),
    ]

    ref = Reference(Board(load_proms(directories, args.board), args.board))
    check_page_granularity(ref)
    if args.report:
        report(ref, sys.stdout)
    if args.vectors:
        lines = vector_lines(ref)
        with open(args.vectors, "w") as handle:
            handle.write("\n".join(lines) + "\n")
        print(f"PROM reference, {args.board} KiB: {len(ref.names)} cells named, {len(lines)} vectors")


if __name__ == "__main__":
    main()
