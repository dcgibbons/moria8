.PHONY: all build build64 build128 buildplus4 disk disk64 zip64 c64-dist disk128 diskplus4 run run64 run128 runplus4 \
	test test-disk test-disk-static test-disk-debt test64 test128 test128-guards test128-units test128-boot test128-town test128-cache test128-diag test128-fast test128-fast-smoke testplus4 testplus4-build testplus4-runtime clean \
	check-zp check-6502-lint check-hal-boundaries ensure-kickass kickass \
	buildapple2 diskapple2 runapple2 testapple2 testapple2-smoke testapple2-runtime testapple2-memory-contract testapple2-memory-contract-selftest \
	buildcx16 diskcx16 runcx16 testcx16 testcx16-smoke testcx16-runtime testcx16-memory-contract testcx16-memory-contract-selftest \
	artifact artifact-checksums artifacts

# Python tools and harnesses must not leave __pycache__ in source directories.
export PYTHONDONTWRITEBYTECODE := 1

all:
	$(MAKE) -C platforms/commodore all
	$(MAKE) -C platforms/apple2 build
	$(MAKE) -C platforms/cx16 build

build:
	$(MAKE) -C platforms/commodore build
	$(MAKE) -C platforms/apple2 build
	$(MAKE) -C platforms/cx16 build

disk:
	$(MAKE) -C platforms/commodore disk
	$(MAKE) -C platforms/apple2 disk
	$(MAKE) -C platforms/cx16 disk

build64 build128 buildplus4 disk64 zip64 c64-dist disk128 diskplus4 run run64 run128 runplus4 \
test-disk test-disk-static test-disk-debt test64 test128 test128-guards test128-units test128-boot test128-town test128-cache test128-diag test128-fast test128-fast-smoke testplus4 testplus4-build testplus4-runtime \
check-zp check-6502-lint check-hal-boundaries ensure-kickass kickass:
	$(MAKE) -C platforms/commodore $@

clean:
	$(MAKE) -C platforms/commodore clean
	$(MAKE) -C platforms/apple2 clean
	$(MAKE) -C platforms/cx16 clean

test:
	$(MAKE) -C platforms/commodore test
	$(MAKE) -C platforms/apple2 test-runtime
	$(MAKE) -C platforms/cx16 test-memory-contract
	$(MAKE) -C platforms/cx16 test-runtime

buildapple2:
	$(MAKE) -C platforms/apple2 build

diskapple2:
	$(MAKE) -C platforms/apple2 disk

runapple2:
	$(MAKE) -C platforms/apple2 run

testapple2: testapple2-memory-contract

testapple2-smoke: testapple2-runtime

testapple2-runtime: testapple2-memory-contract
	$(MAKE) -C platforms/apple2 test-runtime

testapple2-memory-contract:
	$(MAKE) -C platforms/apple2 test-memory-contract

testapple2-memory-contract-selftest:
	$(MAKE) -C platforms/apple2 test-memory-contract-selftest

buildcx16:
	$(MAKE) -C platforms/cx16 build

diskcx16:
	$(MAKE) -C platforms/cx16 disk

runcx16:
	$(MAKE) -C platforms/cx16 run

testcx16: testcx16-memory-contract
	$(MAKE) -C platforms/cx16 test-runtime

testcx16-smoke: testcx16-runtime

testcx16-runtime:
	$(MAKE) -C platforms/cx16 test-runtime

testcx16-memory-contract:
	$(MAKE) -C platforms/cx16 test-memory-contract

testcx16-memory-contract-selftest:
	$(MAKE) -C platforms/cx16 test-memory-contract-selftest

# ── Release artifacts (all five ports) ────────────────────
# Image freshness is owned by the sub-makefiles; these rules always delegate.
GPG         ?= gpg
GPG_SIGN_FLAGS ?= --armor --detach-sign
SHASUM      ?= shasum

BUILD       ?= build

DISK64_IMAGE       = $(BUILD)/moria8-c64.d64
C64_ZIP_IMAGE      = $(BUILD)/moria8-c64.zip
DISK128_D64_IMAGE  = $(BUILD)/moria8-c128.d64
DISK128_D71_IMAGE  = $(BUILD)/moria8-c128.d71
DISK128_D81_IMAGE  = $(BUILD)/moria8-c128.d81
DISKPLUS4_IMAGE    = $(BUILD)/moria8-plus4.d64
DISKAPPLE2_IMAGE   = $(BUILD)/moria8-apple2.po
DISKCX16_IMAGE     = $(BUILD)/moria8-cx16.zip
RELEASE_ARTIFACTS  = $(DISK64_IMAGE) $(C64_ZIP_IMAGE) $(DISK128_D64_IMAGE) $(DISK128_D71_IMAGE) $(DISK128_D81_IMAGE) $(DISKPLUS4_IMAGE) $(DISKAPPLE2_IMAGE) $(DISKCX16_IMAGE)
ARTIFACT_MANIFEST  = $(BUILD)/SHA256SUMS
ARTIFACT_SIGNATURES = $(addsuffix .asc,$(RELEASE_ARTIFACTS) $(ARTIFACT_MANIFEST))

artifact-checksums: $(ARTIFACT_MANIFEST)

artifact artifacts: $(ARTIFACT_MANIFEST) $(ARTIFACT_SIGNATURES)

$(DISK64_IMAGE): FORCE
	$(MAKE) -C platforms/commodore disk64

$(C64_ZIP_IMAGE): FORCE
	$(MAKE) -C platforms/commodore zip64

$(DISK128_D64_IMAGE): FORCE
	$(MAKE) -C platforms/commodore disk128

$(DISK128_D71_IMAGE): FORCE
	$(MAKE) -C platforms/commodore disk128

$(DISK128_D81_IMAGE): FORCE
	$(MAKE) -C platforms/commodore disk128

$(DISKPLUS4_IMAGE): FORCE
	$(MAKE) -C platforms/commodore diskplus4

$(DISKAPPLE2_IMAGE): FORCE
	$(MAKE) -C platforms/apple2 disk

$(DISKCX16_IMAGE): FORCE
	$(MAKE) -C platforms/cx16 disk

$(ARTIFACT_MANIFEST): $(RELEASE_ARTIFACTS)
	cd "$(BUILD)" && $(SHASUM) -a 256 $(notdir $(RELEASE_ARTIFACTS)) > "$(notdir $@)"

%.asc: %
	$(GPG) --yes $(GPG_SIGN_FLAGS) --output "$@" "$<"

FORCE:
