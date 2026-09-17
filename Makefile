PYTHON ?= python3

.PHONY: help format format-check

help:
	@echo "make format        Format project RTL and testbenches in place"
	@echo "make format-check  Check formatting without changing files"
	@echo "Append FILES='rtl/apple3_acia.sv sim/acia_tb.sv' to select files"

format format-check:
	$(PYTHON) tools/verible.py $@ $(FILES)
