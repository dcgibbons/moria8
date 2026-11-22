.PHONY: all build build64 build128 buildplus4 cartridge64 cartridge128 cartridgeplus4 disk disk64 disk128 diskplus4 run run64 run128 run128-cart runplus4 runplus4-cart \
	test test64-legal test128-legal testplus4-legal test-disk test-disk-static test-disk-debt test64 test64-cartridge test64-cartridge-persistence test128 test128-guards test128-units test128-boot test128-town test128-cache test128-diag test128-fast test128-fast-smoke test128-soak-long test128-cartridge testplus4 testplus4-build testplus4-runtime testplus4-cartridge testplus4-cartridge-assets testplus4-cartridge-persistence clean \
	check-zp check-6502-lint check-hal-boundaries check-item-docs report-budgets ensure-kickass kickass tools-ready tools-ready-apple2 \
	test-prebuild test-stage-c64 test-stage-c128 test-stage-plus4 test-stage-apple2 test-stage-cx16 test-stage-atari8 test-stage-bbcmaster FORCE \
	buildapple2 diskapple2 runapple2 testapple2 testapple2-smoke testapple2-runtime testapple2-memory-contract testapple2-memory-contract-selftest \
	buildcx16 diskcx16 cartridgecx16 runcx16 runcx16-cart testcx16 testcx16-smoke testcx16-runtime testcx16-cartridge testcx16-memory-contract testcx16-memory-contract-selftest \
	buildatari8 diskatari8 cartridgeatari8 runatari8 runatari8-130xe runatari8-cart runatari8-cart-130xe testatari8 testatari8-smoke testatari8-fast-smoke testatari8-runtime testatari8-cartridge testatari8-memory-contract testatari8-memory-contract-selftest \
	buildbbcmaster diskbbcmaster runbbcmaster testbbcmaster testbbcmaster-smoke testbbcmaster-fast-smoke testbbcmaster-runtime testbbcmaster-memory-contract testbbcmaster-memory-contract-selftest \
	artifact artifact-checksums artifacts \
	playtest-check playtest-queue playtest-queue-status playtest-queue-rebuild playtest-queue-stop-balrog playtest-queue-records-rebuild playtest-subqueue playtest-subqueue-cancel playtest-strategy-evidence playtest-ab playtest-smoke playtest-gate playtest-m0-report playtest-session playtest-qualify playtest-disk \
	playtest-regress playtest-repro playtest-dashboard playtest-publish playtest-selftest

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
REQUIRE_ALL_ROMS ?= 0
export REQUIRE_ALL_ROMS
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

build64 build128 buildplus4 cartridge64 cartridge128 cartridgeplus4 disk64 disk128 diskplus4 run run64 run128 run128-cart runplus4 runplus4-cart \
check-zp check-6502-lint check-hal-boundaries ensure-kickass kickass:
	$(MAKE) -C platforms/commodore $@

test64-legal test128-legal testplus4-legal test-disk test-disk-static test-disk-debt test64 test128 test128-guards test128-units test128-boot test128-town test128-cache test128-diag test128-fast test128-fast-smoke test128-soak-long testplus4 testplus4-build testplus4-runtime testplus4-cartridge testplus4-cartridge-assets testplus4-cartridge-persistence: tools-ready
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
# order. The C64 and Plus/4 stages run test64 and testplus4; the C128 stage
# runs the full test128 suite, not the test128-fast subsets.
TEST_STAGES = test-stage-c64 test-stage-c128 test-stage-plus4 test-stage-apple2 test-stage-cx16 \
	test-stage-atari8 test-stage-bbcmaster

test: $(TEST_STAGES)

# docs/WIZARD.md and docs/FEATURE_MAP.md section 8.3.1 against the item
# catalog: an item added without its doc rows fails here (static, no emulator).
check-item-docs:
	python3 tools/check_wizard_doc.py --selftest
	python3 tools/check_wizard_doc.py
	python3 -B tools/huff_encoder.py --check

report-budgets:
	python3 tools/report_memory_budgets.py

test-prebuild: tools-ready-apple2
	$(MAKE) check-item-docs
	$(MAKE) check-hal-boundaries
	$(MAKE) check-zp
	$(MAKE) check-6502-lint
	$(MAKE) build
	python3 -B tools/check_overlay_calls.py --check-sym
	$(MAKE) -C platforms/commodore disk
	$(MAKE) -C platforms/commodore test-disk-static
	$(MAKE) -C platforms/apple2 test-memory-contract
	$(MAKE) -C platforms/apple2 disk
	$(MAKE) -C platforms/cx16 disk
	$(MAKE) -C platforms/cx16 test-memory-contract
	$(MAKE) -C platforms/atari8 test-memory-contract
	$(MAKE) -C platforms/atari8 disk
	$(MAKE) -C platforms/bbcmaster test-memory-contract
	$(MAKE) -C platforms/bbcmaster disk
	python3 -B tools/check_item_catalog_ports.py --selftest
	python3 -B tools/check_item_catalog_ports.py
	$(MAKE) playtest-check

test-stage-c64: test-prebuild
	$(ISOLATED) $(MAKE) -C platforms/commodore test64
	$(ISOLATED) $(MAKE) -C platforms/commodore test64-cartridge

test-stage-c128: test-prebuild
	$(ISOLATED) $(MAKE) -C platforms/commodore test128

test-stage-plus4: test-prebuild
	$(ISOLATED) $(MAKE) -C platforms/commodore testplus4
	$(ISOLATED) $(MAKE) -C platforms/commodore testplus4-cartridge

test-stage-apple2: test-prebuild
	$(ISOLATED) $(MAKE) -C platforms/apple2 test-runtime

test-stage-cx16: test-prebuild
	$(ISOLATED) $(MAKE) -C platforms/cx16 test-runtime
	$(ISOLATED) $(MAKE) -C platforms/cx16 test-cartridge

test-stage-atari8: test-prebuild
	$(ISOLATED) $(MAKE) -C platforms/atari8 test-runtime
	$(ISOLATED) $(MAKE) -C platforms/atari8 test-cartridge

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
# CHARACTER=human-warrior etc. (playtest/moria_playtest/goals.py CHARACTERS)
PLAYTEST_CHARACTER = $(if $(CHARACTER),--character $(CHARACTER))
# PORT=plus4, c128, apple2, atari8, bbcmaster or cx16 plays another port
# (playtest/moria_playtest/ports.py, §21); the Plus/4 takes
# PLAYTEST_PLUS4_KERNAL with PLAYTEST_DOS1541 (an optional JiffyDOS pair), the C128 takes
# PLAYTEST_C128_KERNAL with PLAYTEST_DOS1571 (an optional pair), the MAME ports
# A2ROMS, ATARI8ROMS or BBCMROMS, the X16 X16EMU and X16ROM; PLAYTEST_X16_BLOCK=1
# reads the X16 a block at a time, with an x16emu patched for it (docs/BACKLOG.md).
PORT ?= c64
PLAYTEST_DISK = $(or $(PLAYTEST_DISK_$(PORT)),disk64)
PLAYTEST_DISK_c64-cart = disk64 cartridge64
PLAYTEST_DISK_plus4 = diskplus4
PLAYTEST_DISK_plus4-cart = diskplus4 cartridgeplus4
PLAYTEST_DISK_c128 = disk128
PLAYTEST_DISK_c128-cart = disk128 cartridge128
PLAYTEST_DISK_apple2 = diskapple2
PLAYTEST_DISK_atari8 = diskatari8
PLAYTEST_DISK_atari8-cart = diskatari8 cartridgeatari8
PLAYTEST_DISK_bbcmaster = diskbbcmaster
PLAYTEST_DISK_cx16 = buildcx16
PLAYTEST_DISK_cx16-cart = cartridgecx16
PLAYTEST_PORT = --port $(PORT)

playtest-check: build64 cartridge64 buildplus4 cartridgeplus4 build128 cartridge128 buildapple2 buildatari8 cartridgeatari8 buildbbcmaster buildcx16 cartridgecx16
	$(PLAYTEST_PY) -m moria_playtest.check

playtest-smoke: disk64
	$(PLAYTEST_RUN) -m moria_playtest.smoke

# The bot on every port and cartridge from fixed seeds, before a product
# commit: a game finding or a run error fails it (moria_playtest/gate.py).
# Each run isolates itself, as the queue's do. Minutes, not seconds.
playtest-gate: disk64 cartridge64 diskplus4 cartridgeplus4 disk128 cartridge128 diskapple2 diskatari8 \
		cartridgeatari8 diskbbcmaster buildcx16 cartridgecx16
	$(PLAYTEST_PY) -m moria_playtest.gate $(if $(GATE_WORKERS),--workers $(GATE_WORKERS)) \
		$(if $(TARGETS),--targets $(TARGETS)) $(if $(GATE_ALLOW_SKIP),--allow-skip)

playtest-m0-report: disk64
	$(PLAYTEST_RUN) -m moria_playtest.m0

# Disk save/load edge cases through the real UI, on the VICE ports
# (playtest/moria_playtest/disk.py); SCENARIOS=save_resume,full_disk picks some.
playtest-disk: $(PLAYTEST_DISK)
	$(PLAYTEST_RUN) -m moria_playtest.disk $(PLAYTEST_PORT) $(if $(SCENARIOS),--scenarios $(SCENARIOS)) $(PLAYTEST_ARGS)

playtest-session: $(PLAYTEST_DISK)
	$(PLAYTEST_RUN) -m moria_playtest.session $(PLAYTEST_PORT) --goal $(GOAL) --workers $(WORKERS) $(PLAYTEST_SEEDS) $(PLAYTEST_CHARACTER) $(PLAYTEST_ARGS)

playtest-qualify: $(PLAYTEST_DISK)
	$(PLAYTEST_RUN) -m moria_playtest.session $(PLAYTEST_PORT) --qualify --goal $(GOAL) --workers $(WORKERS) $(PLAYTEST_SEEDS) $(PLAYTEST_CHARACTER) $(PLAYTEST_ARGS)

playtest-regress: $(PLAYTEST_DISK)
	$(PLAYTEST_RUN) -m moria_playtest.session $(PLAYTEST_PORT) --regress --workers $(WORKERS) $(PLAYTEST_CHARACTER) $(PLAYTEST_ARGS)

playtest-repro: disk64
	$(PLAYTEST_RUN) -m moria_playtest.repro $(FINDING)

playtest-dashboard:
	$(PLAYTEST_PY) -m moria_playtest.dashboard

# Publishes the dashboard as static files with rsync over SSH, every 30 s:
# PLAYTEST_PUBLISH_TARGET (user@host:/path/) and PLAYTEST_PUBLISH_KEY come from
# the caller's environment. PLAYTEST_PUBLISH_ARGS: --once, --no-push, --every N.
playtest-publish:
	$(PLAYTEST_PY) -m moria_playtest.publish $(PLAYTEST_PUBLISH_ARGS)

# The continuous queue (§23.4): the service (a systemd user unit runs
# `make -s playtest-queue`; it fetches, so it runs outside the network
# namespace and starts each run inside one), its status, and subqueues
# (§23.5): NAME=..., GOAL=... or REGRESS=1, CHARACTERS=all|a,b, SEEDS=...,
# RANDOM_SEEDS=N, QUEUE_BUILD=tree|commit|main; PLAYTEST_QUEUE_ARGS passes more.
playtest-queue:
	$(PLAYTEST_PY) -m moria_playtest.queue serve

playtest-queue-status:
	$(PLAYTEST_PY) -m moria_playtest.queue status

playtest-queue-rebuild:
	$(PLAYTEST_PY) -m moria_playtest.queue rebuild$(if $(RESTART_BALROG), --restart-balrog)

# End the named characters' live Balrog runs (CHARACTERS=half-troll-priest,...).
playtest-queue-stop-balrog:
	$(PLAYTEST_PY) -m moria_playtest.queue stop-balrog --characters "$(CHARACTERS)"

# Re-creates var/moria8/queue.db from runs.jsonl (§23.10).
playtest-queue-records-rebuild:
	$(PLAYTEST_PY) -m moria_playtest.records rebuild

playtest-subqueue:
	$(PLAYTEST_PY) -m moria_playtest.queue submit --name $(NAME) $(if $(filter-out file,$(origin GOAL)),--goal $(GOAL)) \
		$(if $(REGRESS),--regress) $(if $(CHARACTERS),--characters $(CHARACTERS)) \
		$(if $(SEEDS),--seeds $(SEEDS)) $(if $(RANDOM_SEEDS),--random-seeds $(RANDOM_SEEDS)) \
		$(if $(QUEUE_BUILD),--build $(QUEUE_BUILD)) --platforms $(PORT) $(PLAYTEST_QUEUE_ARGS)

# The evidence behind the strategy guide (§23.7): var/moria8/strategy-evidence.md
# from the queue's run records. Reads files only.
playtest-strategy-evidence:
	$(PLAYTEST_PY) -m moria_playtest.strategy

playtest-subqueue-cancel:
	$(PLAYTEST_PY) -m moria_playtest.queue cancel --name $(NAME) $(if $(CHARACTERS),--characters $(CHARACTERS))

# An A/B subqueue (§23.10): NAME=..., GOAL=... (default deep), CHARACTERS=a,b,
# SEEDS=... or RANDOM_SEEDS=N (drawn once, both arms play them), VARIANT_A=...
# and VARIANT_B=... (e.g. tactics=-dangerous; empty: the goal as defined).
# `python3 -m moria_playtest.queue report --name NAME` prints the comparison.
playtest-ab:
	$(PLAYTEST_PY) -m moria_playtest.queue ab --name $(NAME) --goal $(if $(filter-out file,$(origin GOAL)),$(GOAL),deep) \
		$(if $(CHARACTERS),--characters $(CHARACTERS)) \
		$(if $(SEEDS),--seeds $(SEEDS)) $(if $(RANDOM_SEEDS),--random-seeds $(RANDOM_SEEDS)) \
		--variant-a '$(VARIANT_A)' --variant-b '$(VARIANT_B)' \
		$(if $(QUEUE_BUILD),--build $(QUEUE_BUILD)) --platforms $(PORT) $(PLAYTEST_QUEUE_ARGS)

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

cartridgecx16:
	$(MAKE) -C platforms/cx16 cartridge

runcx16:
	$(MAKE) -C platforms/cx16 run

runcx16-cart:
	$(MAKE) -C platforms/cx16 run-cart

testcx16: testcx16-memory-contract tools-ready
	$(ISOLATED) $(MAKE) -C platforms/cx16 test-runtime
	$(ISOLATED) $(MAKE) -C platforms/cx16 test-cartridge

testcx16-smoke: testcx16-runtime

testcx16-runtime: tools-ready
	$(ISOLATED) $(MAKE) -C platforms/cx16 test-runtime

testcx16-cartridge: tools-ready
	$(ISOLATED) $(MAKE) -C platforms/cx16 test-cartridge

testcx16-memory-contract:
	$(MAKE) -C platforms/cx16 test-memory-contract

testcx16-memory-contract-selftest:
	$(MAKE) -C platforms/cx16 test-memory-contract-selftest

buildatari8:
	$(MAKE) -C platforms/atari8 build

diskatari8:
	$(MAKE) -C platforms/atari8 disk

cartridgeatari8:
	$(MAKE) -C platforms/atari8 cartridge

runatari8:
	$(MAKE) -C platforms/atari8 run

runatari8-130xe:
	$(MAKE) -C platforms/atari8 run-130xe

runatari8-cart:
	$(MAKE) -C platforms/atari8 run-cart

runatari8-cart-130xe:
	$(MAKE) -C platforms/atari8 run-cart-130xe

testatari8: testatari8-memory-contract tools-ready
	$(ISOLATED) $(MAKE) -C platforms/atari8 test-runtime
	$(ISOLATED) $(MAKE) -C platforms/atari8 test-cartridge

testatari8-smoke: testatari8-runtime

testatari8-fast-smoke: testatari8-memory-contract tools-ready
	$(ISOLATED) $(MAKE) -C platforms/atari8 test-fast-smoke

testatari8-runtime: tools-ready
	$(ISOLATED) $(MAKE) -C platforms/atari8 test-runtime

testatari8-cartridge: tools-ready
	$(ISOLATED) $(MAKE) -C platforms/atari8 test-cartridge

testatari8-memory-contract: tools-ready
	$(MAKE) -C platforms/atari8 test-memory-contract

testatari8-memory-contract-selftest:
	$(MAKE) -C platforms/atari8 test-memory-contract-selftest

buildbbcmaster:
	$(MAKE) -C platforms/bbcmaster build

diskbbcmaster:
	$(MAKE) -C platforms/bbcmaster disk

runbbcmaster:
	$(MAKE) -C platforms/bbcmaster run

testbbcmaster: testbbcmaster-memory-contract tools-ready
	$(ISOLATED) $(MAKE) -C platforms/bbcmaster test-runtime

testbbcmaster-smoke: testbbcmaster-runtime

testbbcmaster-fast-smoke: testbbcmaster-memory-contract tools-ready
	$(ISOLATED) $(MAKE) -C platforms/bbcmaster test-fast-smoke

testbbcmaster-runtime: tools-ready
	$(ISOLATED) $(MAKE) -C platforms/bbcmaster test-runtime

testbbcmaster-memory-contract: tools-ready
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
CART64_IMAGE       = $(BUILD)/moria8-c64.crt
DISK128_D64_IMAGE  = $(BUILD)/moria8-c128.d64
DISK128_D71_IMAGE  = $(BUILD)/moria8-c128.d71
DISK128_D81_IMAGE  = $(BUILD)/moria8-c128.d81
CART128_IMAGE      = $(BUILD)/moria8-c128.crt
DISKPLUS4_IMAGE    = $(BUILD)/moria8-plus4.d64
CARTPLUS4_IMAGE    = $(BUILD)/moria8-plus4.crt
DISKAPPLE2_IMAGE   = $(BUILD)/moria8-apple2.po
DISKCX16_IMAGE     = $(BUILD)/moria8-cx16.zip
CARTCX16_IMAGE     = $(BUILD)/moria8-cx16.crt
DISKATARI8_IMAGE   = $(BUILD)/moria8-atari8.atr
CARTATARI8_IMAGE   = $(BUILD)/moria8-atari8.car
DISKBBCMASTER_IMAGE = $(BUILD)/moria8-bbcmaster.ssd
RELEASE_ARTIFACTS  = $(DISK64_IMAGE) $(CART64_IMAGE) $(DISK128_D64_IMAGE) $(DISK128_D71_IMAGE) $(DISK128_D81_IMAGE) $(CART128_IMAGE) $(DISKPLUS4_IMAGE) $(CARTPLUS4_IMAGE) $(DISKAPPLE2_IMAGE) $(DISKCX16_IMAGE) $(CARTCX16_IMAGE) $(DISKATARI8_IMAGE) $(CARTATARI8_IMAGE) $(DISKBBCMASTER_IMAGE)
ARTIFACT_MANIFEST  = $(BUILD)/SHA256SUMS
ARTIFACT_SIGNATURES = $(addsuffix .asc,$(RELEASE_ARTIFACTS) $(ARTIFACT_MANIFEST))

artifact-checksums: $(ARTIFACT_MANIFEST)

artifact artifacts: $(ARTIFACT_MANIFEST) $(ARTIFACT_SIGNATURES)

$(DISK64_IMAGE): FORCE
	$(MAKE) -C platforms/commodore disk64

$(CART64_IMAGE): FORCE
	$(MAKE) -C platforms/commodore cartridge64

$(DISK128_D64_IMAGE) $(DISK128_D71_IMAGE) $(DISK128_D81_IMAGE) &: FORCE
	$(MAKE) -C platforms/commodore disk128

$(CART128_IMAGE): FORCE
	$(MAKE) -C platforms/commodore cartridge128

$(DISKPLUS4_IMAGE): FORCE
	$(MAKE) -C platforms/commodore diskplus4

$(CARTPLUS4_IMAGE): FORCE
	$(MAKE) -C platforms/commodore cartridgeplus4

$(DISKAPPLE2_IMAGE): FORCE
	$(MAKE) -C platforms/apple2 disk

$(DISKCX16_IMAGE) $(CARTCX16_IMAGE) &: FORCE
	$(MAKE) -C platforms/cx16 disk

$(DISKATARI8_IMAGE) $(CARTATARI8_IMAGE) &: FORCE
	$(MAKE) -C platforms/atari8 disk

$(DISKBBCMASTER_IMAGE): FORCE
	$(MAKE) -C platforms/bbcmaster disk

$(ARTIFACT_MANIFEST): $(RELEASE_ARTIFACTS)
	cd "$(BUILD)" && $(SHASUM) -a 256 $(notdir $(RELEASE_ARTIFACTS)) > "$(notdir $@)"

%.asc: %
	$(GPG) --yes $(GPG_SIGN_FLAGS) --output "$@" "$<"

FORCE:

test64-cartridge test64-cartridge-persistence test128-cartridge: tools-ready
	$(ISOLATED) $(MAKE) -C platforms/commodore $@
