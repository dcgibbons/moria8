.PHONY: all build build64 build128 buildplus4 disk disk64 zip64 c64-dist disk128 diskplus4 run run64 run128 runplus4 \
	test test-disk test-disk-static test-disk-debt test64 test128 test128-guards test128-units test128-boot test128-town test128-cache test128-diag test128-fast test128-fast-smoke testplus4 testplus4-build testplus4-runtime clean \
	check-zp check-6502-lint check-hal-boundaries ensure-kickass kickass tools-ready tools-ready-apple2 \
	test-prebuild test-stage-c64 test-stage-c128 test-stage-plus4 test-stage-apple2 test-stage-cx16 \
	buildapple2 diskapple2 runapple2 testapple2 testapple2-smoke testapple2-runtime testapple2-memory-contract testapple2-memory-contract-selftest \
	buildcx16 diskcx16 runcx16 testcx16 testcx16-smoke testcx16-runtime testcx16-memory-contract testcx16-memory-contract-selftest \
	buildatari8 diskatari8 runatari8 runatari8-130xe testatari8 testatari8-smoke testatari8-fast-smoke testatari8-runtime testatari8-memory-contract testatari8-memory-contract-selftest \
	buildbbcmaster diskbbcmaster runbbcmaster testbbcmaster testbbcmaster-smoke testbbcmaster-fast-smoke testbbcmaster-runtime testbbcmaster-memory-contract testbbcmaster-memory-contract-selftest \
	artifact artifact-checksums artifacts \
	playtest-check playtest-smoke playtest-m0-report playtest-session playtest-qualify \
	playtest-regress playtest-repro playtest-dashboard playtest-selftest

# Python tools and harnesses must not leave __pycache__ in source directories.
export PYTHONDONTWRITEBYTECODE := 1

ifneq ($(filter clean,$(MAKECMDGOALS)),)
$(filter-out clean,$(MAKECMDGOALS)): | clean
endif

# Emulator test runs get a private network namespace (tools/isolated.sh), so
# fixed monitor ports never collide with other runs on the same machine.
# ISOLATE=auto (default) isolates when the kernel allows it, ISOLATE=1 requires
# it, ISOLATE=0 disables it. Downloads happen first, outside the namespace.
ISOLATE ?= auto
export ISOLATE
ISOLATED = tools/isolated.sh

all:
	$(MAKE) -C platforms/commodore all
	$(MAKE) -C platforms/apple2 build
	$(MAKE) -C platforms/cx16 build
	$(MAKE) -C platforms/atari8 build
	$(MAKE) -C platforms/bbcmaster build

build:
	$(MAKE) -C platforms/commodore build
	$(MAKE) -C platforms/apple2 build
	$(MAKE) -C platforms/cx16 build
	$(MAKE) -C platforms/atari8 build
	$(MAKE) -C platforms/bbcmaster build

disk:
	$(MAKE) -C platforms/commodore disk
	$(MAKE) -C platforms/apple2 disk
	$(MAKE) -C platforms/cx16 disk
	$(MAKE) -C platforms/atari8 disk
	$(MAKE) -C platforms/bbcmaster disk

build64 build128 buildplus4 disk64 zip64 c64-dist disk128 diskplus4 run run64 run128 runplus4 \
check-zp check-6502-lint check-hal-boundaries ensure-kickass kickass:
	$(MAKE) -C platforms/commodore $@

test-disk test-disk-static test-disk-debt test64 test128 test128-guards test128-units test128-boot test128-town test128-cache test128-diag test128-fast test128-fast-smoke testplus4 testplus4-build testplus4-runtime: tools-ready
	$(ISOLATED) $(MAKE) -C platforms/commodore $@

# Tool downloads (KickAssembler; AppleCommander and ProDOS for Apple images)
# must happen outside the isolated namespace, which has no network.
tools-ready:
	$(MAKE) -C platforms/commodore ensure-kickass

tools-ready-apple2: tools-ready
	$(MAKE) -C platforms/apple2 ensure-ac ensure-prodos

clean:
	$(MAKE) -C platforms/commodore clean
	$(MAKE) -C platforms/apple2 clean
	$(MAKE) -C platforms/cx16 clean
	$(MAKE) -C platforms/atari8 clean
	$(MAKE) -C platforms/bbcmaster clean

# `make test` runs one up-front build, then seven isolated stages. They are
# independent (each writes only its own build/test/<platform> scratch), so
# `make -j7 -O test` runs them in parallel; plain `make test` runs them in
# order. The C64/C128/Plus4 stages mirror platforms/commodore's `test`
# (test64 test128-fast test128-fast-smoke testplus4); the two C128 steps
# share build/test/c128 and stay sequential within their stage.
TEST_STAGES = test-stage-c64 test-stage-c128 test-stage-plus4 test-stage-apple2 test-stage-cx16 \
	test-stage-atari8 test-stage-bbcmaster

test: $(TEST_STAGES)

test-prebuild: tools-ready-apple2
	$(MAKE) build
	$(MAKE) -C platforms/apple2 disk
	$(MAKE) -C platforms/cx16 test-memory-contract
	$(MAKE) -C platforms/atari8 test-memory-contract
	$(MAKE) -C platforms/atari8 disk
	$(MAKE) -C platforms/bbcmaster test-memory-contract
	$(MAKE) -C platforms/bbcmaster disk

test-stage-c64: test-prebuild
	$(ISOLATED) $(MAKE) -C platforms/commodore test64

test-stage-c128: test-prebuild
	$(ISOLATED) $(MAKE) -C platforms/commodore test128-fast
	$(ISOLATED) $(MAKE) -C platforms/commodore test128-fast-smoke

test-stage-plus4: test-prebuild
	$(ISOLATED) $(MAKE) -C platforms/commodore testplus4

test-stage-apple2: test-prebuild
	$(ISOLATED) $(MAKE) -C platforms/apple2 test-runtime

test-stage-cx16: test-prebuild
	$(ISOLATED) $(MAKE) -C platforms/cx16 test-runtime

test-stage-atari8: test-prebuild
	$(ISOLATED) $(MAKE) -C platforms/atari8 test-runtime

test-stage-bbcmaster: test-prebuild
	$(ISOLATED) $(MAKE) -C platforms/bbcmaster test-runtime

# AI playtester (docs/AI_PLAYTEST_DESIGN.md). playtest-check and
# playtest-dashboard do not launch an emulator; every other playtest-* target
# launches VICE (see AGENTS.md).
PLAYTEST_PY = PYTHONPATH=playtest PYTHONDONTWRITEBYTECODE=1 python3
# Emulator-launching playtest runs are isolated; the dashboard serves HTTP on
# localhost and must stay outside the namespace.
PLAYTEST_RUN = $(ISOLATED) env PYTHONPATH=playtest PYTHONDONTWRITEBYTECODE=1 python3
GOAL ?= enter_dungeon
WORKERS ?= 4
PLAYTEST_SEEDS = $(if $(SEEDS),--seeds $(SEEDS))

playtest-check: build64
	$(PLAYTEST_PY) -m moria_playtest.check

playtest-smoke: disk64
	$(PLAYTEST_RUN) -m moria_playtest.smoke

playtest-m0-report: disk64
	$(PLAYTEST_RUN) -m moria_playtest.m0

playtest-session: disk64
	$(PLAYTEST_RUN) -m moria_playtest.session --goal $(GOAL) --workers $(WORKERS) $(PLAYTEST_SEEDS) $(PLAYTEST_ARGS)

playtest-qualify: disk64
	$(PLAYTEST_RUN) -m moria_playtest.session --qualify --goal $(GOAL) --workers $(WORKERS) $(PLAYTEST_SEEDS) $(PLAYTEST_ARGS)

playtest-regress: disk64
	$(PLAYTEST_RUN) -m moria_playtest.session --regress --workers $(WORKERS)

playtest-repro: disk64
	$(PLAYTEST_RUN) -m moria_playtest.repro $(FINDING)

playtest-dashboard:
	$(PLAYTEST_PY) -m moria_playtest.dashboard

playtest-selftest:
	$(PLAYTEST_RUN) -m moria_playtest.selftest

buildapple2:
	$(MAKE) -C platforms/apple2 build

diskapple2:
	$(MAKE) -C platforms/apple2 disk

runapple2:
	$(MAKE) -C platforms/apple2 run

testapple2: testapple2-memory-contract

testapple2-smoke: testapple2-runtime

testapple2-runtime: testapple2-memory-contract tools-ready-apple2
	$(ISOLATED) $(MAKE) -C platforms/apple2 test-runtime

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

testcx16: testcx16-memory-contract tools-ready
	$(ISOLATED) $(MAKE) -C platforms/cx16 test-runtime

testcx16-smoke: testcx16-runtime

testcx16-runtime: tools-ready
	$(ISOLATED) $(MAKE) -C platforms/cx16 test-runtime

testcx16-memory-contract:
	$(MAKE) -C platforms/cx16 test-memory-contract

testcx16-memory-contract-selftest:
	$(MAKE) -C platforms/cx16 test-memory-contract-selftest

buildatari8:
	$(MAKE) -C platforms/atari8 build

diskatari8:
	$(MAKE) -C platforms/atari8 disk

runatari8:
	$(MAKE) -C platforms/atari8 run

runatari8-130xe:
	$(MAKE) -C platforms/atari8 run-130xe

testatari8: testatari8-memory-contract
	$(MAKE) -C platforms/atari8 test-runtime

testatari8-smoke: testatari8-runtime

testatari8-fast-smoke: testatari8-memory-contract
	$(MAKE) -C platforms/atari8 test-fast-smoke

testatari8-runtime:
	$(MAKE) -C platforms/atari8 test-runtime

testatari8-memory-contract:
	$(MAKE) -C platforms/atari8 test-memory-contract

testatari8-memory-contract-selftest:
	$(MAKE) -C platforms/atari8 test-memory-contract-selftest

buildbbcmaster:
	$(MAKE) -C platforms/bbcmaster build

diskbbcmaster:
	$(MAKE) -C platforms/bbcmaster disk

runbbcmaster:
	$(MAKE) -C platforms/bbcmaster run

testbbcmaster: testbbcmaster-memory-contract
	$(MAKE) -C platforms/bbcmaster test-runtime

testbbcmaster-smoke: testbbcmaster-runtime

testbbcmaster-fast-smoke: testbbcmaster-memory-contract
	$(MAKE) -C platforms/bbcmaster test-fast-smoke

testbbcmaster-runtime:
	$(MAKE) -C platforms/bbcmaster test-runtime

testbbcmaster-memory-contract:
	$(MAKE) -C platforms/bbcmaster test-memory-contract

testbbcmaster-memory-contract-selftest:
	$(MAKE) -C platforms/bbcmaster test-memory-contract-selftest

# ── Release artifacts (all seven ports) ────────────────────
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
DISKATARI8_IMAGE   = $(BUILD)/moria8-atari8.atr
DISKBBCMASTER_IMAGE = $(BUILD)/moria8-bbcmaster.ssd
RELEASE_ARTIFACTS  = $(DISK64_IMAGE) $(C64_ZIP_IMAGE) $(DISK128_D64_IMAGE) $(DISK128_D71_IMAGE) $(DISK128_D81_IMAGE) $(DISKPLUS4_IMAGE) $(DISKAPPLE2_IMAGE) $(DISKCX16_IMAGE) $(DISKATARI8_IMAGE) $(DISKBBCMASTER_IMAGE)
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

$(DISKATARI8_IMAGE): FORCE
	$(MAKE) -C platforms/atari8 disk

$(DISKBBCMASTER_IMAGE): FORCE
	$(MAKE) -C platforms/bbcmaster disk

$(ARTIFACT_MANIFEST): $(RELEASE_ARTIFACTS)
	cd "$(BUILD)" && $(SHASUM) -a 256 $(notdir $(RELEASE_ARTIFACTS)) > "$(notdir $@)"

%.asc: %
	$(GPG) --yes $(GPG_SIGN_FLAGS) --output "$@" "$<"

FORCE:
