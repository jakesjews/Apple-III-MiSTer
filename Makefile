PYTHON ?= python3
VERILATOR ?= verilator

.PHONY: help format format-check lint lint-prepare

help:
	@echo "make format        Format project RTL and testbenches in place"
	@echo "make format-check  Check formatting without changing files"
	@echo "make lint          Prepare dependencies and lint the emu top with Verilator"
	@echo "make lint-prepare  Prepare dependencies for a direct Verilator invocation"
	@echo "Append FILES='rtl/apple3_acia.sv sim/acia_tb.sv' to select formatter files"

format format-check:
	$(PYTHON) tools/verible.py $@ $(FILES)

lint: lint-prepare
	$(VERILATOR) --lint-only -Wall --top-module emu -f lint/rtl.f

lint-prepare:
	./sim/gen_vhdl.sh
	@mkdir -p lint/gen
	@printf '`define BUILD_DATE "lint"\n' > lint/gen/build_id.v
