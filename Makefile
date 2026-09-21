PYTHON ?= python3
VERILATOR ?= verilator

.PHONY: help format format-check lint lint-prepare check-tools test test-quick boot

help:
	@echo "make format        Format project RTL and testbenches in place"
	@echo "make format-check  Check formatting without changing files"
	@echo "make lint          Prepare dependencies and lint the emu top with Verilator"
	@echo "make lint-prepare  Prepare dependencies for a direct Verilator invocation"
	@echo "make check-tools   Report which simulation tools are installed"
	@echo "make test-quick    Unit, disk, memory map, slot, block card, mouse card and timing benches (about a minute)"
	@echo "make test          Every simulation that needs no disk image (about ten minutes)"
	@echo "make boot [DISK=system.woz ARGS='--to-menu'] [ROM=other.rom]"
	@echo "                   Boot the whole machine, from the stock ROM unless ROM= names another"
	@echo "Append FILES='rtl/apple3_acia.sv sim/acia_tb.sv' to select formatter files"

format format-check:
	$(PYTHON) tools/verible.py $@ $(FILES)

lint: lint-prepare
	$(VERILATOR) --lint-only -Wall --top-module emu -f lint/rtl.f

lint-prepare:
	./sim/gen_vhdl.sh
	@mkdir -p lint/gen
	@printf '`define BUILD_DATE "lint"\n' > lint/gen/build_id.v

check-tools:
	@./sim/check_tools.sh

test-quick: check-tools
	./sim/run_tests.sh

test: test-quick
	bash sim/accuracy/run.sh
	./sim/joystick/run.sh
	./sim/serial/run.sh
	./sim/run_core_boot.sh 30000000

# 30 M clocks reach the disk bootstrap; SOS needs far more with a disk mounted.
# The harness treats any argument after the clock count as a disk test.
CLOCKS ?= $(if $(DISK),2000000000,30000000)
boot: check-tools
	APPLE3_ROM="$(ROM)" ./sim/run_core_boot.sh $(CLOCKS) $(if $(DISK),"$(DISK)" $(ARGS))
