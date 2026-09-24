#!/usr/bin/env python3
"""Make an empty SOS/ProDOS hard-disk image for the block card, bootable or not.

Without options the image is a formatted, empty volume for Hard Disk 2 or for
use from a floppy. The Utilities' Format cannot make one: the Problock3 driver
has no formatter.

--boot-from takes soshdboot's two-block loader, SOS.KERNEL and SOS.DRIVER from
one of Rob Justice's images (https://github.com/robjustice/soshdboot), with
the program it boots: SOS.INTERP and, for the Selector, SOS.MENU. The menu is
that image's, so its entries find nothing until their folders are copied over.

  tools/blank_hd.py data.po
  tools/blank_hd.py selector.po --boot-from sos_selector_hd.po
"""

import argparse
import datetime
import struct
import sys

BLOCK = 512
ENTRY = 0x27
PER_BLOCK = 0x0D
BITMAP = 6  # after the loader (0-1) and the four volume-directory blocks (2-5)
BOOT_FILES = ("SOS.KERNEL", "SOS.DRIVER")
PROGRAM_FILES = ("SOS.INTERP", "SOS.MENU")  # SOS.MENU is the Selector's
# DOS 3.3 sector holding each half of a ProDOS block within a track.
DOS_SECTOR = (0, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 15)


def is_volume(block):
    return block[4] >> 4 == 0xF and block[0x23] == ENTRY and block[0x24] == PER_BLOCK


class Volume:
    """A ProDOS-order image read into memory. 2MG headers and DOS-order 140K
    images are converted on load."""

    def __init__(self, path):
        with open(path, "rb") as image:
            data = image.read()
        if data[:4] == b"2IMG":
            offset, length = struct.unpack_from("<II", data, 24)
            data = data[offset:offset + length]
        if len(data) == 143360 and not is_volume(data[2 * BLOCK:3 * BLOCK]):
            prodos = bytearray(len(data))
            for block in range(280):
                track, index = divmod(block, 8)
                for half in (0, 1):
                    sector = DOS_SECTOR[2 * index + half]
                    source = (track * 16 + sector) * 256
                    target = block * BLOCK + half * 256
                    prodos[target:target + 256] = data[source:source + 256]
            data = bytes(prodos)
        if not is_volume(data[2 * BLOCK:3 * BLOCK]):
            sys.exit(f"{path}: no SOS/ProDOS volume directory")
        self.data = data

    def block(self, number):
        return self.data[number * BLOCK:(number + 1) * BLOCK]

    def root(self):
        """Yield the volume directory's file entries as (name, 39-byte entry)."""
        number, first = 2, True
        while number:
            block = self.block(number)
            for index in range(PER_BLOCK):
                entry = block[4 + index * ENTRY:4 + (index + 1) * ENTRY]
                if first and index == 0:
                    continue
                if entry[0] >> 4 in (1, 2, 3):
                    yield entry[1:1 + (entry[0] & 0x0F)].decode("ascii"), entry
            first = False
            number = struct.unpack_from("<H", block, 2)[0]

    def contents(self, entry):
        """The data blocks of a seedling, sapling or tree file, in order."""
        storage, key = entry[0] >> 4, struct.unpack_from("<H", entry, 0x11)[0]
        eof = entry[0x15] | entry[0x16] << 8 | entry[0x17] << 16
        count = (eof + BLOCK - 1) // BLOCK
        if storage == 1:
            pointers = [key]
        else:
            indexes = [key] if storage == 2 else self.pointers(key)
            pointers = [p for index in indexes for p in (self.pointers(index) if index else [0] * 256)]
        return [self.block(p) if p else bytes(BLOCK) for p in pointers[:count]] or [bytes(BLOCK)]

    def pointers(self, index):
        block = self.block(index)
        return [block[i] | block[256 + i] << 8 for i in range(256)]


def prodos_date(when):
    date = (when.year % 100) << 9 | when.month << 5 | when.day
    return struct.pack("<HBB", date, when.minute, when.hour)


def build(total, name, files, loader):
    image = bytearray(total * BLOCK)
    if loader:
        image[:2 * BLOCK] = loader
    bitmap_blocks = (total + 4095) // 4096
    used = set(range(BITMAP + bitmap_blocks))
    next_free = BITMAP + bitmap_blocks

    def write(number, content):
        image[number * BLOCK:(number + 1) * BLOCK] = content

    for number in range(2, 6):  # the directory's four linked blocks
        write(number, struct.pack("<HH", number - 1 if number > 2 else 0, number + 1 if number < 5 else 0) +
              bytes(BLOCK - 4))
    now = prodos_date(datetime.datetime.now().astimezone())  # local time, as SOS keeps it
    header = bytearray(ENTRY)
    header[0] = 0xF0 | len(name)
    header[1:1 + len(name)] = name.encode("ascii")
    header[0x18:0x1C] = now
    header[0x1E] = 0xC3
    header[0x1F], header[0x20] = ENTRY, PER_BLOCK
    struct.pack_into("<HHH", header, 0x21, len(files), BITMAP, total)
    image[2 * BLOCK + 4:2 * BLOCK + 4 + ENTRY] = header

    for slot, (entry, blocks) in enumerate(files, start=1):
        if len(blocks) > 256:
            sys.exit(f"{entry[1:1 + (entry[0] & 15)].decode()}: files over 128 KiB are not supported")
        entry = bytearray(entry)
        if len(blocks) == 1:
            key, count = next_free, 1
            write(next_free, blocks[0])
            next_free += 1
        else:
            key, index = next_free, bytearray(BLOCK)
            next_free += 1
            for i, content in enumerate(blocks):
                index[i], index[256 + i] = next_free & 0xFF, next_free >> 8
                write(next_free, content)
                next_free += 1
            write(key, index)
            count = len(blocks) + 1
        if next_free > total:
            sys.exit("the files do not fit on a volume that size")
        used.update(range(key, next_free))
        entry[0] = (1 if len(blocks) == 1 else 2) << 4 | (entry[0] & 0x0F)
        struct.pack_into("<HH", entry, 0x11, key, count)
        struct.pack_into("<H", entry, 0x25, 2)  # header pointer: the volume directory
        directory, place = divmod(slot, PER_BLOCK)
        at = (2 + directory) * BLOCK + 4 + place * ENTRY
        image[at:at + ENTRY] = entry

    for number in range(total):  # a set bit is a free block
        if number not in used:
            image[BITMAP * BLOCK + number // 8] |= 0x80 >> (number % 8)
    return bytes(image)


def blocks_from(size):
    size = size.upper()
    if size.endswith("M"):
        return min(int(float(size[:-1]) * 2048), 65535)
    if size.endswith("K"):
        return int(size[:-1]) * 2
    return int(size)


def main():
    parser = argparse.ArgumentParser(description="Make an empty SOS/ProDOS hard-disk image.")
    parser.add_argument("output", help="image to write (.po)")
    parser.add_argument("--size", default="32767",
                        help="blocks, or a size such as 16M or 32M (default 32767 blocks, 16 MiB; "
                        "at most 65535)")
    parser.add_argument("--name", default="HARD1", help="volume name (default HARD1)")
    parser.add_argument("--boot-from", metavar="IMAGE",
                        help="soshdboot image to take the loader, SOS.KERNEL, SOS.DRIVER and program from")
    args = parser.parse_args()

    total = blocks_from(args.size)
    name = args.name.upper()
    if not (1 <= len(name) <= 15 and name[0].isalpha() and all(c.isalnum() or c == "." for c in name)):
        sys.exit("volume names are 1-15 letters, digits and periods, starting with a letter")
    if not 280 <= total <= 65535:
        sys.exit("the size must be 280 to 65535 blocks")

    files, loader = [], None
    if args.boot_from:
        boot = Volume(args.boot_from)
        loader = boot.data[:2 * BLOCK]
        root = dict(boot.root())
        for file in BOOT_FILES + PROGRAM_FILES:
            if file in root:
                files.append((root[file], boot.contents(root[file])))
            elif file != "SOS.MENU":
                sys.exit(f"{args.boot_from}: no {file}")

    with open(args.output, "wb") as out:
        out.write(build(total, name, files, loader))
    names = [entry[1:1 + (entry[0] & 15)].decode() for entry, _ in files]
    print(f"/{name}: {total} blocks, {'bootable, ' if loader else ''}{', '.join(names) or 'empty'}")


if __name__ == "__main__":
    main()
