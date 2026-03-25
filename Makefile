# Root Makefile — delegates to commodore/c64/ and commodore/c128/
.PHONY: all build rundisk rundual debug test test128 test128-fast test128-fast-smoke disk savedisk clean run128demo
.PHONY: build128 run128 clean128
.PHONY: check-zp check-6502-lint

all build rundisk rundual debug test disk savedisk clean run128demo:
	$(MAKE) -C commodore/c64 $@

build128 run128 rundisk128 disk128 clean128 test128 test128-fast test128-fast-smoke:
	$(MAKE) -C commodore/c128 $@

check-zp:
	python3 tools/check_zp_usage.py

check-6502-lint:
	python3 tools/check_6502_lint.py
