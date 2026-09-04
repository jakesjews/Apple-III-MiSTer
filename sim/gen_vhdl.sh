#!/bin/zsh
# Convert the VHDL components (T65 6502, Gideon via6522) into Verilog netlists
# with GHDL synthesis so the whole core can be simulated with Verilator.
set -e
cd "$(dirname "$0")"
mkdir -p gen work
cd work
ghdl -a --std=08 -fsynopsys ../../rtl/t65/T65_Pack.vhd ../../rtl/t65/T65_MCode.vhd ../../rtl/t65/T65_ALU.vhd ../../rtl/t65/T65.vhd 2>/dev/null
ghdl --synth --std=08 -fsynopsys --out=verilog T65 > ../gen/t65.v 2>../gen/t65.log
ghdl -a --std=08 -fsynopsys ../../rtl/via/via6522.vhd 2>/dev/null
ghdl --synth --std=08 -fsynopsys --out=verilog via6522 > ../gen/via6522.v 2>../gen/via6522.log
perl -pi -e "s/\\bbreak\\b/t65_brk/g" ../gen/t65.v
wc -l ../gen/*.v
