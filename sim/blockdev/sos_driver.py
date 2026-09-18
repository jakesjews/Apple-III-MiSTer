#!/usr/bin/env python3
"""Add a ca65-built SOS driver to a SOS.DRIVER file.

A SOS.DRIVER file is "SOS DRVR", a 16-bit header length, the header (drive
count, character set and keyboard layout), then one record per driver:
a 16-bit comment length and comment, a 16-bit code length and the driver's
DIBs and code, and a 16-bit relocation-table length followed by 16-bit code
offsets whose words the loader relocates. An $FFFF word ends the list.

The driver comes from cc65's o65 output: the TEXT segment holds the comment
record and the DATA segment the code; the o65 relocation table lists the
data-segment words to relocate. This is the same conversion Rob Justice's
A3Driverutil performs (https://github.com/robjustice/A3Driverutil).

Usage:
    sos_driver.py add DRIVER.o65 SOS.DRIVER     add or replace the driver
    sos_driver.py list SOS.DRIVER               show the drivers and DIBs
"""
import struct
import sys


def word(data, at):
    return data[at] | data[at + 1] << 8


def convert_o65(path):
    data = open(path, "rb").read()
    if data[2:5] != b"o65":
        raise SystemExit(f"{path}: not an o65 file")
    mode, _, tlen, dbase, dlen = struct.unpack_from("<HHHHH", data, 6)
    if mode & 0x2000:
        raise SystemExit(f"{path}: 32-bit o65 layout is not supported")
    at = 26
    while data[at] != 0:  # header options
        at += data[at]
    at += 1
    comment = data[at:at + tlen]
    at += tlen
    code = data[at:at + dlen]
    at += dlen
    at += 2  # undefined references count (16-bit, must be 0)
    if word(data, at - 2):
        raise SystemExit(f"{path}: driver has undefined references")
    if data[at] != 0:
        raise SystemExit(f"{path}: comment segment must not need relocation")
    at += 1
    relocations = []
    address = dbase - 1
    while data[at] != 0:
        offset = data[at]
        at += 1
        if offset == 255:
            address += 254
            continue
        address += offset
        kind = data[at]
        at += 1
        if kind == 0x83:  # 16-bit word in the data segment
            relocations.append(address)
        else:
            raise SystemExit(f"{path}: unsupported relocation type {kind:02x}")
    if comment[:2] == b"\xff\xff":  # the driver's own comment marker
        comment = comment[2:]
    record = comment + struct.pack("<H", dlen) + code
    record += struct.pack("<H", 2 * len(relocations))
    record += b"".join(struct.pack("<H", r) for r in relocations)
    return record


def driver_records(image):
    if image[:8] != b"SOS DRVR":
        raise SystemExit("not a SOS.DRIVER file")
    at = 10 + word(image, 8)
    records = []
    while word(image, at) != 0xFFFF:
        start = at
        at += 2 + word(image, at)  # comment
        code = at
        at += 2 + word(image, at)  # code
        at += 2 + word(image, at)  # relocations
        records.append((start, code, at))
    return records, at


def dib_name(image, dib):
    """Name of the DIB at offset dib: a length byte at +4 and 15 characters."""
    return image[dib + 5:dib + 5 + image[dib + 4]].decode("ascii", "replace")


def record_name(record):
    return dib_name(record, 2 + word(record, 0) + 2)


def add(o65, path):
    record = convert_o65(o65)
    image = bytearray(open(path, "rb").read())
    records, end = driver_records(image)
    name = record_name(record)
    for start, code, stop in records:
        if dib_name(image, code + 2).upper() == name.upper():
            image[start:stop] = record
            print(f"{name}: replaced in {path}")
            break
    else:
        image[end:end] = record
        print(f"{name}: added to {path}")
    open(path, "wb").write(image)


def list_drivers(path):
    image = open(path, "rb").read()
    records, _ = driver_records(image)
    print("driver            active slot unit type sub   code bytes")
    for _, code, _ in records:
        dib = code + 2
        while True:
            print(f"{dib_name(image, dib):16}  {'yes' if image[dib + 20] & 0x80 else 'no':6} {image[dib + 21]:4} "
                  f"{image[dib + 22]:4} {image[dib + 23]:4x} {image[dib + 24]:3x}  {word(image, code):5}")
            link = word(image, dib)
            if not link:
                break
            dib = code + 2 + link


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "add":
        add(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 3 and sys.argv[1] == "list":
        list_drivers(sys.argv[2])
    else:
        raise SystemExit(__doc__)
