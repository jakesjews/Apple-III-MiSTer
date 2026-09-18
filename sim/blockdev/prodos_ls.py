#!/usr/bin/env python3
"""List a directory of a ProDOS/SOS block image on the host.

Usage: prodos_ls.py IMAGE [PATH]

IMAGE is raw ProDOS-order blocks (PO/HDV; a 2MG header is skipped). PATH is a
directory such as /VOLUME/SUBDIR; the volume directory is listed by default.
Each entry prints its storage type, name, file type, block count and EOF, so
a test can confirm that SOS created or changed a file.
"""
import struct
import sys

TYPES = {0x0F: "DIR", 0x04: "TXT", 0x06: "BIN", 0xFF: "SYS", 0x0C: "SOS", 0x0B: "PCD", 0x0A: "PDA"}


def load(path):
    data = open(path, "rb").read()
    if data[:4] == b"2IMG":
        offset, length = struct.unpack_from("<II", data, 24)
        data = data[offset:offset + length]
    return data


def block(data, number):
    return data[number * 512:(number + 1) * 512]


def entries(data, first):
    """Yield (name, storage, file type, key block, blocks, eof) of a directory."""
    number = first
    header = True
    # Only the directory's first block carries the entry geometry.
    entry_length, entries_per_block = block(data, first)[0x23], block(data, first)[0x24]
    while number:
        b = block(data, number)
        at = 4
        for _ in range(entries_per_block):
            e = b[at:at + entry_length]
            at += entry_length
            if header:
                header = False
                continue
            storage = e[0] >> 4
            if storage == 0:
                continue
            name = e[1:1 + (e[0] & 0x0F)].decode("ascii", "replace")
            key, blocks = struct.unpack_from("<HH", e, 0x11)
            eof = e[0x15] | e[0x16] << 8 | e[0x17] << 16
            yield name, storage, e[0x10], key, blocks, eof
        number = struct.unpack_from("<H", b, 2)[0]


def main():
    if len(sys.argv) not in (2, 3):
        raise SystemExit(__doc__)
    data = load(sys.argv[1])
    number = 2
    volume = block(data, 2)
    volume_name = volume[5:5 + (volume[4] & 0x0F)].decode("ascii", "replace")
    parts = [p for p in (sys.argv[2] if len(sys.argv) == 3 else "").upper().split("/") if p]
    if parts and parts[0] == volume_name:
        parts = parts[1:]
    for part in parts:
        for name, storage, _, key, _, _ in entries(data, number):
            if name == part and storage == 0xD:
                number = key
                break
        else:
            raise SystemExit(f"{part}: no such subdirectory")
    print(f"/{volume_name}/{'/'.join(parts)}")
    for name, storage, kind, key, blocks, eof in entries(data, number):
        label = TYPES.get(kind, f"${kind:02X}")
        print(f"{'DIR' if storage == 0xD else label:4} {name:16} key {key:5} blocks {blocks:5} eof {eof:8}")


if __name__ == "__main__":
    main()
