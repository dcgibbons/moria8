# Root Makefile — just a thin wrapper around the commodore dir stuff
.PHONY: all build build64 build128 disk disk64 disk128 run run64 run128 \
	test test64 test128 test128-fast test128-fast-smoke clean \
	check-zp check-6502-lint

all build build64 build128 disk disk64 disk128 run run64 run128 \
test test64 test128 test128-fast test128-fast-smoke clean \
check-zp check-6502-lint:
	$(MAKE) -C commodore $@
