.PHONY: all build build64 build128 buildplus4 disk disk64 zip64 c64-dist disk128 diskplus4 artifact artifact-checksums artifacts run run64 run128 runplus4 \
	test test-disk test-disk-static test-disk-debt test64 test128 test128-fast test128-fast-smoke testplus4 testplus4-build testplus4-runtime clean \
	check-zp check-6502-lint check-hal-boundaries ensure-kickass kickass \
	buildapple2 diskapple2 runapple2 testapple2 testapple2-smoke testapple2-runtime testapple2-memory-contract testapple2-memory-contract-selftest

all:
	$(MAKE) -C platforms/commodore all
	$(MAKE) -C platforms/apple2 build

build:
	$(MAKE) -C platforms/commodore build
	$(MAKE) -C platforms/apple2 build

disk:
	$(MAKE) -C platforms/commodore disk
	$(MAKE) -C platforms/apple2 disk

build64 build128 buildplus4 disk64 zip64 c64-dist disk128 diskplus4 artifact artifact-checksums artifacts run run64 run128 runplus4 \
test test-disk test-disk-static test-disk-debt test64 test128 test128-fast test128-fast-smoke testplus4 testplus4-build testplus4-runtime clean \
check-zp check-6502-lint check-hal-boundaries ensure-kickass kickass:
	$(MAKE) -C platforms/commodore $@

buildapple2:
	$(MAKE) -C platforms/apple2 build

diskapple2:
	$(MAKE) -C platforms/apple2 disk

runapple2:
	$(MAKE) -C platforms/apple2 run

testapple2: testapple2-memory-contract

testapple2-smoke: testapple2-memory-contract

testapple2-runtime: testapple2-memory-contract

testapple2-memory-contract:
	$(MAKE) -C platforms/apple2 test-memory-contract

testapple2-memory-contract-selftest:
	$(MAKE) -C platforms/apple2 test-memory-contract-selftest
