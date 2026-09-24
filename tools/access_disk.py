#!/usr/bin/env python3
"""Build a bootable Access /// disk for calling BBSes through MiSTer's modem.

Access /// is Apple's terminal program for the Apple ///. The apple3rtr bundle
(https://github.com/datajerk/apple3rtr) keeps it on its hard disk, apple3.hd,
and has a bootable Access 3270 floppy whose SOS.KERNEL and SOS.DRIVER (with
.RS232) it can share. This puts Access ///'s interpreter and configuration on
a copy of that floppy, with no recording file, and adds command files that set
2400 baud, 8 bits, no parity and VT100 at boot and dial two BBSes.

Needs MAME's chdman and AppleCommander's command-line jar (AC_JAR or --ac).

  tools/access_disk.py path/to/apple3rtr Access3_MiSTer.dsk --ac AppleCommander-ac.jar
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile

SETUP = [
    "@!! MiSTer setup: VT100, 8 bits, no parity, 2400 baud, full duplex,",
    "@!! no XON/XOFF, no linefeed after return, wraparound.",
    "@V1", "@C8", "@PR1", "@XR4", "@FD", "@LF", "@QF", "@AT",
    "@DI'028",
    "@DLAccess /// is set to 2400 baud, 8 bits, no parity, VT100.",
    "@DLSet the MiSTer UART to Modem, TCP, 2400 baud, then type a dial command:",
    "@DL",
    "@DL   ATDTBBS.FOZZTEXX.COM:23      Level 29",
    "@DL   ATDTBBS.RETROCAMPUS.COM:23   RetroCampus",
    "@DL",
    "@DLor press Open-Apple-C and enter /ACCESS/LEVEL29.CMD or /ACCESS/RETRO.CMD.",
    "@DL",
    "@!! MidiLink ignores the first command after the core starts, so send an",
    "@!! empty line before the AT whose OK shows that the modem is there.",
    "",
    "@WS1",
    "AT",
]
DIALS = {
    "LEVEL29.CMD": ["@!! Dial Level 29 through the MiSTer modem.", "ATDTBBS.FOZZTEXX.COM:23"],
    "RETRO.CMD": ["@!! Dial RetroCampus BBS through the MiSTer modem.", "ATDTBBS.RETROCAMPUS.COM:23"],
}


def text(lines):
    return "".join(line + "\r" for line in lines).encode("ascii")


def patch_config(config):
    """Record to .CONSOLE. Access /// opens the recording file at boot: a file
    there makes it ask to write over it from the second boot on, and an empty
    name is a pathname error. Also clear the previous owner's answerback."""
    config = bytearray(config)
    if len(config) != 242 or config[0x59] != 11 or config[0x5A:0x65] != b".D1/TERMREC":
        sys.exit("unexpected Access /// CONFIG layout")
    config[0x59:0x65] = bytes([8]) + b".CONSOLE" + bytes(3)
    config[0xE1:] = bytes(len(config) - 0xE1)
    return bytes(config)


def main():
    parser = argparse.ArgumentParser(description="Build a bootable Access /// disk for MiSTer's modem.")
    parser.add_argument("apple3rtr", help="apple3rtr checkout (apple3.hd, access.3270.dsk)")
    parser.add_argument("output", help="disk image to write")
    parser.add_argument("--ac", default=os.environ.get("AC_JAR"), help="AppleCommander ac.jar")
    args = parser.parse_args()
    if not args.ac:
        sys.exit("give AppleCommander's jar with --ac or AC_JAR")

    def ac(*argv, data=None):
        result = subprocess.run(["java", "-jar", args.ac, *argv], input=data, capture_output=True, check=False)
        if result.returncode:
            sys.exit(f"AppleCommander {' '.join(argv)}: {result.stderr.decode().strip()}")
        return result.stdout

    with tempfile.TemporaryDirectory() as tmp:
        raw = os.path.join(tmp, "apple3rtr.img")
        subprocess.run(["chdman", "extracthd", "-i", os.path.join(args.apple3rtr, "apple3.hd"),
                        "-o", raw, "-f"], check=True, capture_output=True)
        # The CHD's first block is the drive's identify data; /BOS starts after it.
        bos = os.path.join(tmp, "bos.po")
        with open(raw, "rb") as source, open(bos, "wb") as target:
            source.seek(512)
            shutil.copyfileobj(source, target)
        interp = ac("-g", bos, "PROGRAMS/ACCESS3/SOS.INTERP")
        config = patch_config(ac("-g", bos, "PROGRAMS/ACCESS3/CONFIG"))

    shutil.copyfile(os.path.join(args.apple3rtr, "access.3270.dsk"), args.output)
    for name in ("SOS.INTERP", "AUTOLOG", "CONFIG", "TERMREC"):
        ac("-d", args.output, name)
    ac("-p", args.output, "SOS.INTERP", "PDA", data=interp)
    ac("-p", args.output, "CONFIG", "TXT", data=config)
    ac("-p", args.output, "ACCESS.CMD", "TXT", data=text(SETUP))
    for name, lines in DIALS.items():
        ac("-p", args.output, name, "TXT", data=text(lines))
    sys.stdout.write(ac("-l", args.output).decode())


if __name__ == "__main__":
    main()
