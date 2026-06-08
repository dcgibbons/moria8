# Root Makefile — just a thin wrapper around the commodore dir stuff
.PHONY: all build build64 build128 buildplus4 disk disk64 zip64 c64-dist disk128 diskplus4 artifact artifact-checksums artifacts run run64 run128 runplus4 \
	test test64 test128 test128-fast test128-fast-smoke testplus4 testplus4-build testplus4-runtime clean \
	check-zp check-6502-lint check-hal-boundaries ensure-kickass kickass

all build build64 build128 buildplus4 disk disk64 zip64 c64-dist disk128 diskplus4 artifact artifact-checksums artifacts run run64 run128 runplus4 \
test test64 test128 test128-fast test128-fast-smoke testplus4 testplus4-build testplus4-runtime clean \
check-zp check-6502-lint check-hal-boundaries ensure-kickass kickass:
	$(MAKE) -C commodore $@
