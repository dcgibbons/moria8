.PHONY: all build build64 build128 buildplus4 buildcx16 disk disk64 zip64 c64-dist disk128 diskplus4 artifact artifact-checksums artifacts run run64 run128 runplus4 runcx16 cx16 run-cx16 \
	test test-disk test-disk-static test-disk-debt test64 test128 test128-fast test128-fast-smoke testplus4 testplus4-build testplus4-runtime testcx16 testcx16-smoke testcx16-runtime testcx16-shared-link clean \
	check-zp check-6502-lint check-hal-boundaries ensure-kickass kickass

all build build64 build128 buildplus4 disk disk64 zip64 c64-dist disk128 diskplus4 artifact artifact-checksums artifacts run64 run128 runplus4 \
test test-disk test-disk-static test-disk-debt test64 test128 test128-fast test128-fast-smoke testplus4 testplus4-build testplus4-runtime clean \
check-zp check-6502-lint check-hal-boundaries ensure-kickass kickass:
	$(MAKE) -C platforms/commodore $@

run:
ifneq ($(filter cx16,$(MAKECMDGOALS)),)
	$(MAKE) -C platforms/cx16 runcx16
else
	$(MAKE) -C platforms/commodore run
endif

ifneq ($(filter run,$(MAKECMDGOALS)),)
cx16:
	@:
else
cx16: runcx16
endif

run-cx16: runcx16

buildcx16 runcx16 testcx16 testcx16-smoke testcx16-runtime testcx16-shared-link:
	$(MAKE) -C platforms/cx16 $@
