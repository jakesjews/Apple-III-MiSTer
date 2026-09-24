# Calling a BBS

The Apple ///'s serial port is wired to MiSTer's UART. In MiSTer's **Modem**
mode, MidiLink answers Hayes `AT` commands and dials telnet addresses, so the
Apple /// can call today's BBSes with Access ///, Apple's terminal program for
it. Checked on a MiSTer with Level 29 and RetroCampus BBS at 2400 baud.

## 1. Make the Access /// disk

Access /// is on the hard disk of datajerk's
[Apple /// Ready-to-Run](https://github.com/datajerk/apple3rtr) bundle, next to
a bootable Access 3270 floppy. `tools/access_disk.py` puts Access /// on a copy
of that floppy. It needs MAME's `chdman` and AppleCommander's command-line jar:

```sh
git clone https://github.com/datajerk/apple3rtr
tools/access_disk.py apple3rtr Access3_MiSTer.dsk --ac AppleCommander-ac.jar
```

Copy `Access3_MiSTer.dsk` to `games/Apple-III`. At boot its `ACCESS.CMD` sets
2400 baud, 8 bits, no parity and VT100 emulation, lists the dial commands and
sends `AT`. MidiLink ignores the first command after the core starts, so the
disk sends an empty line first; the `OK` that follows shows the modem is there.

## 2. Set up the MiSTer

With the Apple /// core loaded, open MiSTer's system menu (Win+F12) and set
**UART Connection** to **Modem**, **Link** to **TCP** and **Baud** to **2400**.
MiSTer keeps these for the core.

Leave the core's **Hardware** page at its defaults: **Serial CTS** and
**Serial DSR** at **Always ready** and **Serial DCD** at **Always on**. MiSTer's
modem never raises the line behind DSR, and Apple's serial driver sends nothing
while DSR is false.

## 3. Call

Mount `Access3_MiSTer.dsk` as Drive 1 and reset. Once `OK` appears below the
list, type

```
ATDTBBS.FOZZTEXX.COM:23
```

and press Return. MidiLink answers `DIALING` and `CONNECT 2400`, and Level 29
shows its banner. Log in as `VISITOR`, accept `80x24` with Return, and give
`vt100` as the terminal type. **O** logs off.

RetroCampus BBS is `ATDTBBS.RETROCAMPUS.COM:23`. Choose **4**, plain ASCII at
80 × 24, for its news, games, chat and text web browser.

Open Apple (the Windows or Command key) + **C** runs a command file instead:
`/ACCESS/LEVEL29.CMD` or `/ACCESS/RETRO.CMD`.

## 4. Hang up

Type `+++`, wait a second, then `ATH` and Return. MidiLink answers
`NO CARRIER` and `OK`.

## Notes

* Level 29's first line can show a few stray characters from its telnet
  negotiation.
* Access /// also runs at 4800 and 9600 baud (`@XR5` and `@XR6` in
  `ACCESS.CMD`); set MiSTer's modem to the same speed. Only 2400 has been tried.
* If there is no `OK` at startup, or `ATDT` shows nothing, check **Serial DSR**
  and that the UART is in Modem mode at Access ///'s speed. With **Serial DSR**
  at **Host DTR** the Apple /// sends nothing.
* Rob Justice's `sos_selector_hd.po` also has Access /// in
  `/SOS/PROGRAMS/ACCESS3`, with its original settings rather than these.
* MidiLink's other commands, such as `ATIP` and its dialing directory, are in
  [its README](https://github.com/MiSTer-devel/MidiLink_MiSTer).
