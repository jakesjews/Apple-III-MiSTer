#!/usr/bin/env bash
# Report which simulation tools are installed and how to get the missing ones.
missing=0

check() {
	if command -v "$1" >/dev/null 2>&1; then
		printf '  ok       %-10s %s\n' "$1" "$2"
	else
		printf '  MISSING  %-10s %s\n' "$1" "$2"
		missing=1
	fi
}

echo "Simulation tools:"
check iverilog  "Icarus Verilog, unit benches"
check vvp       "Icarus Verilog runtime"
check verilator "whole-machine benches (version 5 or later)"
check ghdl      "converts the VHDL 6502 and VIA to Verilog"
check ca65      "cc65 assembler, test ROMs"
check ld65      "cc65 linker"
check xxd       "ROM hex dumps"
check c++       "C++ compiler for Verilator"
check make      "Verilator builds"
check python3   "disk fixtures"

if command -v verilator >/dev/null 2>&1; then
	major=$(verilator --version | sed -E 's/^Verilator ([0-9]+).*/\1/')
	if [ "${major:-0}" -lt 5 ]; then
		echo "  TOO OLD  verilator  $(verilator --version); --binary and --timing need 5 or later"
		missing=1
	fi
fi
if command -v ghdl >/dev/null 2>&1 && ! ghdl help 2>&1 | grep -q synth; then
	echo "  NO SYNTH ghdl       this GHDL build lacks the synth command"
	missing=1
fi

if [ "$missing" -ne 0 ]; then
	echo
	echo "Install what is missing:"
	echo "  macOS:          brew install icarus-verilog verilator cc65 && brew install --cask ghdl"
	echo "  Debian/Ubuntu:  sudo apt install iverilog verilator ghdl cc65 xxd g++ make python3"
	exit 1
fi
echo "All simulation tools found."
