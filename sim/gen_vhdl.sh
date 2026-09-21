#!/usr/bin/env bash
# Convert the VHDL components (T65 6502, Gideon via6522) into Verilog netlists
# with GHDL synthesis so the whole core can be simulated with Verilator.
set -e
cd "$(dirname "$0")"
mkdir -p gen work
cd work
ghdl -a --std=08 -fsynopsys ../../rtl/t65/T65_Pack.vhd ../../rtl/t65/T65_MCode.vhd ../../rtl/t65/T65_ALU.vhd ../../rtl/t65/T65.vhd ../../rtl/t65_wrapper.vhd 2>/dev/null
ghdl --synth --std=08 -fsynopsys --out=verilog t65_wrapper > ../gen/t65.v 2>../gen/t65.log
ghdl -a --std=08 -fsynopsys ../../rtl/via/via6522.vhd 2>/dev/null
ghdl --synth --std=08 -fsynopsys --out=verilog via6522 > ../gen/via6522.v 2>../gen/via6522.log
# T65 has signals named break and do, which are SystemVerilog keywords.  GHDL 6
# escapes do; GHDL 4 does not, so rename both.
perl -pi -e "s/\\bbreak\\b/t65_brk/g; s/\\bdo\\b/t65_do/g" ../gen/t65.v
# GHDL 4 declares some wires twice and assigns them to themselves.
perl -ni -e '%seen = () if /^module /; next if /^\s*assign\s+(\S+)\s*=\s*\1\s*;/; next if /^\s*wire\s.*;\s*$/ && $seen{$_}++; print' ../gen/t65.v ../gen/via6522.v
wc -l ../gen/*.v
