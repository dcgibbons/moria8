# Commodore Makefile
#
# Primary targets:
#   make build              Build both platform payloads into out/c64 and out/c128
#   make disk               Build both shipping disk images
#   make disk64             Build the C64 shipping disk at out/moria8-c64.d64
#   make disk128            Build the C128 shipping disk at out/moria8-c128.d71
#   make run                Launch the C64 shipping disk in C64 VICE
#   make run128             Launch the C128 shipping disk in C128 VICE
#   make test               Run the default regression mix (C64 + fast C128 coverage)
#   make test64             Run the C64 suite
#   make test128            Run the full C128 suite
#   make test128-fast       Run the fast C128 compare harness
#   make test128-fast-smoke Run the high-value C128 smoke subset
#   make clean              Remove unified outputs plus transitional legacy test outputs
#
# Debug targets:
#   make build64 build128

# ── Tool paths ────────────────────────────────────────────
KICKASS_DIR ?= ../tools/kickass
KICKASS     ?= $(KICKASS_DIR)/KickAss.jar
KICKASS_URL  = https://theweb.dk/KickAssembler/KickAssembler.zip
ifeq ($(filter /%,$(KICKASS)),)
KICKASS_RESOLVED = $(CURDIR)/$(KICKASS)
else
KICKASS_RESOLVED = $(KICKASS)
endif
ifeq ($(filter /%,$(KICKASS_DIR)),)
KICKASS_DIR_RESOLVED = $(CURDIR)/$(KICKASS_DIR)
else
KICKASS_DIR_RESOLVED = $(KICKASS_DIR)
endif
JAVA        ?= java
C1541       ?= c1541
VICE64      ?= x64sc
VICE128     ?= x128
VICEPLUS4   ?= xplus4

# ── Output layout ─────────────────────────────────────────
OUT         ?= out
OUT64        = $(OUT)/c64
OUT128       = $(OUT)/c128
OUTPLUS4     = $(OUT)/plus4

# ── Shared tooling ────────────────────────────────────────
DISKART      = ../tools/diskart.py
PATCH_D64    = ../tools/patch_d64_sector.py
RESERVE_SECTOR = ../tools/reserve_cbm_sector.py
VERSION_FILE = ../version.json
LICENSE_FILE = ../data/LICENSE
SOURCE_OFFER = ../data/SOURCE-OFFER
LICENSE_DISK_FILE = $(OUT)/license.seq
SOURCE_OFFER_DISK_FILE = $(OUT)/source-offer.seq
RUN_FLAGS64  = -autostartprgmode 1 -sound -sounddev coreaudio
RUN_FLAGS128 = -80col -sound -sounddev coreaudio
RUN_FLAGSPLUS4 = -autostartprgmode 1 -sound -sounddev coreaudio
KA_FLAGS     = -showmem -vicesymbols
KA_FLAGS64   = $(KA_FLAGS) -libdir c64
KA_FLAGSPLUS4 = $(KA_FLAGS) -libdir c64 -define PLUS4
DEBUG_FEAT_DISK_TRACE ?= 0
ifeq ($(DEBUG_FEAT_DISK_TRACE),1)
KA_FLAGS64   += -define DEBUG_FEAT_DISK_TRACE
else
KA_FLAGS64   += -define DEBUG_FEAT_DISK_TRACE=0
endif
KA_FLAGS128  = $(KA_FLAGS) -libdir c64 -define C128
ifeq ($(PERF_P1),1)
KA_FLAGS128  += -define PERF_P1
endif

# ── Source roots ──────────────────────────────────────────
C64_MAIN_SRC       = c64/main.s
C64_BOOT_SRC       = c64/boot.s
C64_BOOTART_PNG    = ../artwork/moria8_loading_art_c64.png
C64_BOOTART_PPM    = $(OUT64)/bootart64.ppm
C64_BOOTART_SRC_TOOL = ../tools/png_to_ppm.py
C64_BOOTART_TOOL   = ../tools/ppm_to_c64_bootart.py
LOGO_TOOL = ../tools/make_logo.py
VERSION_INC_TOOL = ../tools/make_version_include.py
VERSION_INC = $(OUT)/version_strings.inc
C128_BOOTART_PNG   = ../artwork/moria8_C128loadingart_tile_native.png
C128_BOOTART_PPM   = $(OUT128)/bootart128.ppm
C128_BOOTART_TOOL  = ../tools/ppm_to_c128_bootart.py
C128_BOOTART_SRC_TOOL = ../tools/png_to_ppm.py
C128_MAIN_SRC      = c128/main.s
C128_BOOT_SRC      = c128/boot128.s
C128_BOOTSECT_SRC  = c128/bootsect128.s
C128_CHARSET_DEMO_SRC = c128/vdc_charset_poster_demo.s
C128_BOOTART_SRC   = c128/bootart128.s
TITLE_SRC          = common/title_data.s
C64_TIER_DIR       = c64/creature_data
PLUS4_MAIN_SRC     = plus4/main.s
PLUS4_BOOT_SRC     = plus4/boot.s

C64_SOURCES        := $(shell find c64 common -type f -name '*.s')
C128_SOURCES       := $(shell find c128 common c64 -type f -name '*.s')
PLUS4_SOURCES      := $(shell find plus4 common -type f -name '*.s')

# ── C64 artifacts ─────────────────────────────────────────
C64_MAIN_PRG       = $(OUT64)/moria8.prg
C64_BOOT_PRG       = $(OUT64)/boot.prg
C64_BOOTART_PRG    = $(OUT64)/bootart64.prg
C64_TITLE_PRG      = $(OUT64)/title
C64_TIER_PRGS      = $(OUT64)/monster.db.1 $(OUT64)/monster.db.2 $(OUT64)/monster.db.3 $(OUT64)/monster.db.4
C64_OVL_START      = $(OUT64)/ovl.start
C64_OVL_TOWN       = $(OUT64)/ovl.town
C64_OVL_DEATH      = $(OUT64)/ovl.death
C64_OVL_GEN        = $(OUT64)/ovl.gen
C64_OVL_HELP       = $(OUT64)/ovl.help
C64_OVL_UI         = $(OUT64)/ovl.ui
C64_OVL_ITEMS      = $(OUT64)/ovl.items
C64_OVL_SPELL      = $(OUT64)/ovl.spell
C64_RUNTIME_BANKED = $(OUT64)/64.bank

# ── Plus/4 artifacts ──────────────────────────────────────
PLUS4_MAIN_PRG       = $(OUTPLUS4)/moria4.prg
PLUS4_BOOT_PRG       = $(OUTPLUS4)/boot4.prg
PLUS4_TITLE_PRG      = $(OUTPLUS4)/title
PLUS4_TIER_PRGS      = $(OUTPLUS4)/monster.db.1 $(OUTPLUS4)/monster.db.2 $(OUTPLUS4)/monster.db.3 $(OUTPLUS4)/monster.db.4
PLUS4_OVL_START      = $(OUTPLUS4)/ovl.start
PLUS4_OVL_TOWN       = $(OUTPLUS4)/ovl.town
PLUS4_OVL_DEATH      = $(OUTPLUS4)/ovl.death
PLUS4_OVL_GEN        = $(OUTPLUS4)/ovl.gen
PLUS4_OVL_HELP       = $(OUTPLUS4)/ovl.help
PLUS4_OVL_UI         = $(OUTPLUS4)/ovl.ui
PLUS4_OVL_ITEMS      = $(OUTPLUS4)/ovl.items
PLUS4_OVL_SPELL      = $(OUTPLUS4)/ovl.spell
PLUS4_RUNTIME_BANKED = $(OUTPLUS4)/4.bank

# ── C128 artifacts ────────────────────────────────────────
C128_MAIN_PRG      = $(OUT128)/moria128.prg
C128_BOOT_PRG      = $(OUT128)/boot128.prg
C128_BOOT_CHAIN_PRG = $(OUT128)/boot128.chain.prg
C128_TITLE_PRG     = $(OUT128)/title
C128_TIER_PRGS     = $(OUT128)/monster.db.1 $(OUT128)/monster.db.2 $(OUT128)/monster.db.3 $(OUT128)/monster.db.4
C128_OVL_START     = $(OUT128)/ovl.start
C128_OVL_TOWN      = $(OUT128)/ovl.town
C128_OVL_DEATH     = $(OUT128)/ovl.death
C128_OVL_GEN       = $(OUT128)/ovl.gen
C128_OVL_HELP      = $(OUT128)/ovl.help
C128_OVL_UI        = $(OUT128)/ovl.ui
C128_OVL_ITEMS     = $(OUT128)/ovl.items
C128_RUNTIME_INPUT = $(OUT128)/128.input.prg
C128_RUNTIME_PROJECTILE = $(OUT128)/128.proj.prg
C128_RUNTIME_LOW   = $(OUT128)/128.runtime.prg
C128_RUNTIME_COMMON = $(OUT128)/128.fdisk.prg
C128_RUNTIME_DISKIO = $(OUT128)/128.diskio.prg
C128_RESIDENT_WORLD = $(OUT128)/128.world.prg
C128_RESIDENT_ITEMS = $(OUT128)/128.item.prg
C128_RESIDENT_SELECT = $(OUT128)/128.select.prg
C128_RESIDENT_PERSIST = $(OUT128)/128.persist.prg
C128_RESIDENT_PLAY = $(OUT128)/128.play.prg
C128_RUNTIME_BANKED = $(OUT128)/128.bank.prg
C128_MAIN_STAMP   = $(OUT128)/.main.stamp
C128_BOOTSECT_PRG  = $(OUT128)/bootsect128.prg
C128_CHARSET_DEMO_PRG = $(OUT128)/vdc_charset_poster_demo.prg
C128_BOOTART_DIAG_PRG = $(OUT128)/bootart128.prg
C128_BOOTART_INC   = $(OUT128)/bootart128.inc
C128_BOOTART_CHARSET_BIN = $(OUT128)/bootart128_charset.bin
C128_BOOTART_SCREEN_BIN  = $(OUT128)/bootart128_screen.bin
C128_BOOTART_ATTR_BIN    = $(OUT128)/bootart128_attr.bin
C128_BOOTART_PREVIEW_PPM = $(OUT128)/bootart128_preview.ppm

# ── Disk artifacts ────────────────────────────────────────
DISK64_IMAGE       = $(OUT)/moria8-c64.d64
DISK128_IMAGE      = $(OUT)/moria8-c128.d71
DISKPLUS4_IMAGE    = $(OUT)/moria8-plus4.d64
EMPTY_PRG          = $(OUT)/empty.prg
DISK64_LABEL       = "moria8 c64,m8"
DISK128_LABEL      = "moria8 c128,m8"
DISKPLUS4_LABEL    = "moria8 plus4,m8"

# ── Aggregate groups ──────────────────────────────────────
C64_BUILD_ARTIFACTS  = $(C64_MAIN_PRG) $(C64_BOOT_PRG) $(C64_BOOTART_PRG) $(C64_TITLE_PRG) $(C64_TIER_PRGS) \
	$(C64_OVL_START) $(C64_OVL_TOWN) $(C64_OVL_DEATH) $(C64_OVL_GEN) $(C64_OVL_HELP) $(C64_OVL_UI) $(C64_OVL_ITEMS) $(C64_OVL_SPELL) \
	$(C64_RUNTIME_BANKED)
PLUS4_BUILD_ARTIFACTS  = $(PLUS4_MAIN_PRG) $(PLUS4_BOOT_PRG) $(PLUS4_TITLE_PRG) $(PLUS4_TIER_PRGS) \
	$(PLUS4_OVL_START) $(PLUS4_OVL_TOWN) $(PLUS4_OVL_DEATH) $(PLUS4_OVL_GEN) $(PLUS4_OVL_HELP) $(PLUS4_OVL_UI) $(PLUS4_OVL_ITEMS) $(PLUS4_OVL_SPELL) \
	$(PLUS4_RUNTIME_BANKED)
C128_BUILD_ARTIFACTS = $(C128_MAIN_PRG) $(C128_BOOT_PRG) $(C128_BOOT_CHAIN_PRG) $(C128_BOOTSECT_PRG) \
	$(C128_BOOTART_DIAG_PRG) \
	$(C128_TITLE_PRG) $(C128_TIER_PRGS) $(C128_OVL_START) $(C128_OVL_TOWN) $(C128_OVL_DEATH) \
		$(C128_OVL_GEN) $(C128_OVL_HELP) $(C128_OVL_UI) $(C128_OVL_ITEMS) $(C128_RUNTIME_INPUT) $(C128_RUNTIME_PROJECTILE) $(C128_RUNTIME_LOW) $(C128_RUNTIME_COMMON) $(C128_RUNTIME_DISKIO) \
	$(C128_RESIDENT_WORLD) $(C128_RESIDENT_ITEMS) $(C128_RESIDENT_SELECT) $(C128_RESIDENT_PERSIST) $(C128_RESIDENT_PLAY) $(C128_RUNTIME_BANKED)
C128_MAIN_OUTPUTS = $(C128_MAIN_PRG) $(C128_OVL_START) $(C128_OVL_TOWN) $(C128_OVL_DEATH) \
	$(C128_OVL_GEN) $(C128_OVL_HELP) $(C128_OVL_UI) $(C128_OVL_ITEMS) \
		$(C128_RUNTIME_INPUT) $(C128_RUNTIME_PROJECTILE) $(C128_RUNTIME_LOW) $(C128_RUNTIME_COMMON) $(C128_RUNTIME_DISKIO) \
	$(C128_RESIDENT_WORLD) $(C128_RESIDENT_ITEMS) $(C128_RESIDENT_SELECT) \
	$(C128_RESIDENT_PERSIST) $(C128_RESIDENT_PLAY) $(C128_RUNTIME_BANKED)

.PHONY: all build build64 build128 buildplus4 disk disk64 disk128 diskplus4 run run64 run128 runplus4 \
	bootart128-charset-demo \
	test test64 test128 test128-fast test128-fast-smoke testplus4 testplus4-build testplus4-runtime clean \
	check-zp check-6502-lint check-hal-boundaries ensure-kickass kickass

all: build

build: build64 build128 buildplus4

build64: $(C64_BUILD_ARTIFACTS)
	mkdir -p c64/out
	cp -f $(OUT64)/* c64/out/

build128: $(C128_BUILD_ARTIFACTS)
	mkdir -p c128/out
	cp -f $(OUT128)/* c128/out/

buildplus4: $(PLUS4_BUILD_ARTIFACTS)
	mkdir -p plus4/out
	cp -f $(OUTPLUS4)/* plus4/out/

disk: $(DISK64_IMAGE) $(DISK128_IMAGE) $(DISKPLUS4_IMAGE)

disk64: $(DISK64_IMAGE)

disk128: $(DISK128_IMAGE)

diskplus4: $(DISKPLUS4_IMAGE)

run: $(DISK64_IMAGE)
	$(VICE64) -drive8truedrive -drive8type 1541 +busdevice8 $(RUN_FLAGS64) -autostart $(DISK64_IMAGE)

run64: run

run128: $(DISK128_IMAGE)
	$(VICE128) -drive8truedrive -drive8type 1571 +busdevice8 $(RUN_FLAGS128) $(DISK128_IMAGE)

runplus4: $(DISKPLUS4_IMAGE)
	$(VICEPLUS4) -drive8truedrive -drive8type 1541 $(RUN_FLAGSPLUS4) -autostart $(DISKPLUS4_IMAGE)

bootart128-charset-demo: $(C128_CHARSET_DEMO_PRG)

test: test64 test128-fast test128-fast-smoke testplus4

test64: ensure-kickass
	cd c64 && KICKASS="$(KICKASS_RESOLVED)" ./run_tests.sh

test128: ensure-kickass
	cd c128 && KICKASS="$(KICKASS_RESOLVED)" ./run_tests128.sh

test128-fast: ensure-kickass
	cd c128 && KICKASS="$(KICKASS_RESOLVED)" python3 -u ./harness128_batch.py --mode compare --snapshot-path out/ready.vsf --vice $(VICE128) --connect-timeout 12

test128-fast-smoke: ensure-kickass
	cd c128 && KICKASS="$(KICKASS_RESOLVED)" TEST_FILTER='boot_title_idle_smoke|marker_init_d64_smoke|boot_title_save_write_product_smoke|scripted_summary_to_town_smoke|scripted_spell_cast_smoke|scripted_book_overlay_smoke|scripted_spell_list_overlay_smoke|scripted_spell_list_cancel_smoke|scripted_prayer_cast_smoke|town_overlay_smoke' ./run_tests128.sh

testplus4-build: ensure-kickass $(PLUS4_BUILD_ARTIFACTS)
	@echo "Plus/4 build artifacts assembled; runtime smoke is make testplus4-runtime."

testplus4: testplus4-runtime

testplus4-runtime: ensure-kickass
	cd plus4 && KICKASS="$(KICKASS_RESOLVED)" VICEPLUS4="$(VICEPLUS4)" ./run_testsplus4.sh

check-zp:
	python3 ../tools/check_zp_usage.py

check-6502-lint:
	python3 ../tools/check_6502_lint.py

check-hal-boundaries:
	cd .. && python3 tools/check_hal_boundaries_selftest.py
	cd .. && python3 tools/check_hal_boundaries.py
	cd .. && python3 tools/check_hal_storage_exports.py
	cd .. && python3 tools/check_hal_asset_exports.py
	cd .. && python3 tools/check_hal_layout_exports.py
	cd .. && python3 tools/check_hal_entropy_exports.py
	cd .. && python3 tools/check_hal_memory_bank_exports.py
	cd .. && python3 tools/check_hal_cpu_port_exports.py
	cd .. && python3 tools/check_hal_vic_bank_exports.py
	cd .. && python3 tools/check_hal_reu_exports.py
	cd .. && python3 tools/check_hal_c128_mmu_diag_exports.py
	cd .. && python3 tools/check_hal_sound_exports.py
	cd .. && python3 tools/check_hal_lifecycle_exports.py
	cd .. && python3 tools/check_hal_screen_exports.py
	cd .. && python3 tools/check_hal_input_exports.py
	cd .. && python3 tools/check_hal_missing_stubs.py
	cd .. && python3 tools/check_hal_manifests.py
	cd .. && python3 tools/check_hal_contract_docs.py
	cd .. && python3 tools/check_plus4_hal_independence.py

# ── C64 build rules ───────────────────────────────────────
$(VERSION_INC): $(VERSION_FILE) $(VERSION_INC_TOOL) | $(OUT)
	python3 $(VERSION_INC_TOOL) $(VERSION_FILE) $(VERSION_INC)

$(C64_MAIN_PRG): $(C64_SOURCES) $(VERSION_INC) | ensure-kickass $(OUT64)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(C64_MAIN_SRC) $(KA_FLAGS64) -o $(C64_MAIN_PRG)
	mv -f c64/out/ovl.start $(C64_OVL_START)
	mv -f c64/out/ovl.town $(C64_OVL_TOWN)
	mv -f c64/out/ovl.death $(C64_OVL_DEATH)
	mv -f c64/out/ovl.gen $(C64_OVL_GEN)
	mv -f c64/out/ovl.help $(C64_OVL_HELP)
	mv -f c64/out/ovl.ui $(C64_OVL_UI)
	mv -f c64/out/ovl.items $(C64_OVL_ITEMS)
	mv -f c64/out/ovl.spell $(C64_OVL_SPELL)
	mv -f c64/out/64.bank $(C64_RUNTIME_BANKED)

$(C64_OVL_START): $(C64_MAIN_PRG)
$(C64_OVL_TOWN): $(C64_MAIN_PRG)
$(C64_OVL_DEATH): $(C64_MAIN_PRG)
$(C64_OVL_GEN): $(C64_MAIN_PRG)
$(C64_OVL_HELP): $(C64_MAIN_PRG)
$(C64_OVL_UI): $(C64_MAIN_PRG)
$(C64_OVL_ITEMS): $(C64_MAIN_PRG)
$(C64_OVL_SPELL): $(C64_MAIN_PRG)
$(C64_RUNTIME_BANKED): $(C64_MAIN_PRG)

$(C64_BOOT_PRG): $(C64_SOURCES) | ensure-kickass $(OUT64)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(C64_BOOT_SRC) -o $(C64_BOOT_PRG)

$(C64_BOOTART_PPM): $(C64_BOOTART_PNG) $(C64_BOOTART_SRC_TOOL) | $(OUT64)
	@test -f "$(C64_BOOTART_PNG)" || { echo "Missing source art: $(C64_BOOTART_PNG)"; false; }
	python3 $(C64_BOOTART_SRC_TOOL) $(C64_BOOTART_PNG) 160 200 $@

$(C64_BOOTART_PRG): $(C64_BOOTART_PPM) $(C64_BOOTART_TOOL) | $(OUT64)
	python3 $(C64_BOOTART_TOOL) $(C64_BOOTART_PPM) $(C64_BOOTART_PRG)

$(C64_TITLE_PRG): $(TITLE_SRC) $(VERSION_INC) | ensure-kickass $(OUT64)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(TITLE_SRC) -define TITLE_PLATFORM_64 -o $(C64_TITLE_PRG)

$(OUT64)/monster.db.1: $(C64_TIER_DIR)/tier1_prg.s $(C64_TIER_DIR)/tier1.s | ensure-kickass $(OUT64)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(C64_TIER_DIR)/tier1_prg.s -o $@

$(OUT64)/monster.db.2: $(C64_TIER_DIR)/tier2_prg.s $(C64_TIER_DIR)/tier2.s | ensure-kickass $(OUT64)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(C64_TIER_DIR)/tier2_prg.s -o $@

$(OUT64)/monster.db.3: $(C64_TIER_DIR)/tier3_prg.s $(C64_TIER_DIR)/tier3.s | ensure-kickass $(OUT64)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(C64_TIER_DIR)/tier3_prg.s -o $@

$(OUT64)/monster.db.4: $(C64_TIER_DIR)/tier4_prg.s $(C64_TIER_DIR)/tier4.s | ensure-kickass $(OUT64)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(C64_TIER_DIR)/tier4_prg.s -o $@

# ── Plus/4 build rules ────────────────────────────────────
$(PLUS4_MAIN_PRG): $(PLUS4_SOURCES) $(VERSION_INC) | ensure-kickass $(OUTPLUS4)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(PLUS4_MAIN_SRC) $(KA_FLAGSPLUS4) -o $(PLUS4_MAIN_PRG)
	mv -f plus4/out/ovl.start $(PLUS4_OVL_START)
	mv -f plus4/out/ovl.town $(PLUS4_OVL_TOWN)
	mv -f plus4/out/ovl.death $(PLUS4_OVL_DEATH)
	mv -f plus4/out/ovl.gen $(PLUS4_OVL_GEN)
	mv -f plus4/out/ovl.help $(PLUS4_OVL_HELP)
	mv -f plus4/out/ovl.ui $(PLUS4_OVL_UI)
	mv -f plus4/out/ovl.items $(PLUS4_OVL_ITEMS)
	mv -f plus4/out/ovl.spell $(PLUS4_OVL_SPELL)
	mv -f plus4/out/4.bank $(PLUS4_RUNTIME_BANKED)

$(PLUS4_OVL_START): $(PLUS4_MAIN_PRG)
$(PLUS4_OVL_TOWN): $(PLUS4_MAIN_PRG)
$(PLUS4_OVL_DEATH): $(PLUS4_MAIN_PRG)
$(PLUS4_OVL_GEN): $(PLUS4_MAIN_PRG)
$(PLUS4_OVL_HELP): $(PLUS4_MAIN_PRG)
$(PLUS4_OVL_UI): $(PLUS4_MAIN_PRG)
$(PLUS4_OVL_ITEMS): $(PLUS4_MAIN_PRG)
$(PLUS4_OVL_SPELL): $(PLUS4_MAIN_PRG)
$(PLUS4_RUNTIME_BANKED): $(PLUS4_MAIN_PRG)

$(PLUS4_BOOT_PRG): $(PLUS4_SOURCES) | ensure-kickass $(OUTPLUS4)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(PLUS4_BOOT_SRC) $(KA_FLAGSPLUS4) -o $(PLUS4_BOOT_PRG)

$(PLUS4_TITLE_PRG): $(TITLE_SRC) $(VERSION_INC) | ensure-kickass $(OUTPLUS4)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(TITLE_SRC) -define TITLE_PLATFORM_4 -o $(PLUS4_TITLE_PRG)

$(OUTPLUS4)/monster.db.1: $(C64_TIER_DIR)/tier1_prg.s $(C64_TIER_DIR)/tier1.s | ensure-kickass $(OUTPLUS4)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(C64_TIER_DIR)/tier1_prg.s -o $@

$(OUTPLUS4)/monster.db.2: $(C64_TIER_DIR)/tier2_prg.s $(C64_TIER_DIR)/tier2.s | ensure-kickass $(OUTPLUS4)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(C64_TIER_DIR)/tier2_prg.s -o $@

$(OUTPLUS4)/monster.db.3: $(C64_TIER_DIR)/tier3_prg.s $(C64_TIER_DIR)/tier3.s | ensure-kickass $(OUTPLUS4)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(C64_TIER_DIR)/tier3_prg.s -o $@

$(OUTPLUS4)/monster.db.4: $(C64_TIER_DIR)/tier4_prg.s $(C64_TIER_DIR)/tier4.s | ensure-kickass $(OUTPLUS4)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(C64_TIER_DIR)/tier4_prg.s -o $@

# ── C128 build rules ──────────────────────────────────────
$(C128_MAIN_STAMP): $(C128_SOURCES) $(VERSION_INC) | ensure-kickass $(OUT128)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(C128_MAIN_SRC) $(KA_FLAGS128) -o $(C128_MAIN_PRG)
	mkdir -p "$(OUT128)" "c128/out"
	mv -f "c128/out/ovl.start" "$(C128_OVL_START)"
	mv -f "c128/out/ovl.town" "$(C128_OVL_TOWN)"
	mv -f "c128/out/ovl.death" "$(C128_OVL_DEATH)"
	mv -f "c128/out/ovl.gen" "$(C128_OVL_GEN)"
	mv -f "c128/out/ovl.help" "$(C128_OVL_HELP)"
	mv -f "c128/out/ovl.ui" "$(C128_OVL_UI)"
	mv -f "c128/out/ovl.items" "$(C128_OVL_ITEMS)"
	mv -f "c128/out/128.input.prg" "$(C128_RUNTIME_INPUT)"
	mv -f "c128/out/128.proj.prg" "$(C128_RUNTIME_PROJECTILE)"
	mv -f "c128/out/128.runtime.prg" "$(C128_RUNTIME_LOW)"
	mv -f "c128/out/128.fdisk.prg" "$(C128_RUNTIME_COMMON)"
	mv -f "c128/out/128.diskio.prg" "$(C128_RUNTIME_DISKIO)"
	mv -f "c128/out/128.world.prg" "$(C128_RESIDENT_WORLD)"
	mv -f "c128/out/128.item.prg" "$(C128_RESIDENT_ITEMS)"
	mv -f "c128/out/128.select.prg" "$(C128_RESIDENT_SELECT)"
	mv -f "c128/out/128.persist.prg" "$(C128_RESIDENT_PERSIST)"
	mv -f "c128/out/128.play.prg" "$(C128_RESIDENT_PLAY)"
	mv -f "c128/out/128.bank.prg" "$(C128_RUNTIME_BANKED)"
	touch "$(C128_MAIN_STAMP)"

$(C128_MAIN_OUTPUTS): $(C128_MAIN_STAMP)
	@test -f "$@" || { rm -f "$(C128_MAIN_STAMP)"; $(MAKE) "$(C128_MAIN_STAMP)"; }
	@test -f "$@"

$(C128_BOOT_PRG): $(C128_SOURCES) | ensure-kickass $(OUT128)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(C128_BOOT_SRC) -o $(C128_BOOT_PRG)

$(C128_BOOT_CHAIN_PRG): $(C128_SOURCES) | ensure-kickass $(OUT128)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(C128_BOOT_SRC) -define BOOT128_CHAIN -o $(C128_BOOT_CHAIN_PRG)

$(C128_CHARSET_DEMO_PRG): $(C128_CHARSET_DEMO_SRC) | ensure-kickass $(OUT128)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(C128_CHARSET_DEMO_SRC) $(KA_FLAGS128) -o $(C128_CHARSET_DEMO_PRG)

$(C128_BOOTART_PPM): $(C128_BOOTART_PNG) $(C128_BOOTART_SRC_TOOL) | $(OUT128)
	python3 $(C128_BOOTART_SRC_TOOL) $(C128_BOOTART_PNG) 640 200 $@

$(C128_BOOTART_INC) $(C128_BOOTART_CHARSET_BIN) $(C128_BOOTART_SCREEN_BIN) $(C128_BOOTART_ATTR_BIN) $(C128_BOOTART_PREVIEW_PPM): $(C128_BOOTART_PPM) $(C128_BOOTART_TOOL) | $(OUT128)
	python3 $(C128_BOOTART_TOOL) $(C128_BOOTART_PPM) $(OUT128)/bootart128

$(C128_BOOTART_DIAG_PRG): $(C128_BOOTART_SRC) $(C128_BOOTART_INC) $(C128_BOOTART_CHARSET_BIN) $(C128_BOOTART_SCREEN_BIN) $(C128_BOOTART_ATTR_BIN) | ensure-kickass $(OUT128)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(C128_BOOTART_SRC) $(KA_FLAGS128) -o $(C128_BOOTART_DIAG_PRG)

$(C128_TITLE_PRG): $(TITLE_SRC) $(VERSION_INC) | ensure-kickass $(OUT128)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(TITLE_SRC) -define TITLE_PLATFORM_128 -o $(C128_TITLE_PRG)

$(OUT128)/monster.db.1: $(C64_TIER_DIR)/tier1_prg.s $(C64_TIER_DIR)/tier1.s | ensure-kickass $(OUT128)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(C64_TIER_DIR)/tier1_prg.s -o $@

$(OUT128)/monster.db.2: $(C64_TIER_DIR)/tier2_prg.s $(C64_TIER_DIR)/tier2.s | ensure-kickass $(OUT128)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(C64_TIER_DIR)/tier2_prg.s -o $@

$(OUT128)/monster.db.3: $(C64_TIER_DIR)/tier3_prg.s $(C64_TIER_DIR)/tier3.s | ensure-kickass $(OUT128)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(C64_TIER_DIR)/tier3_prg.s -o $@

$(OUT128)/monster.db.4: $(C64_TIER_DIR)/tier4_prg.s $(C64_TIER_DIR)/tier4.s | ensure-kickass $(OUT128)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(C64_TIER_DIR)/tier4_prg.s -o $@

$(C128_BOOTSECT_PRG): $(C128_BOOTSECT_SRC) | ensure-kickass $(OUT128)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" $(C128_BOOTSECT_SRC) -o $(C128_BOOTSECT_PRG)

# ── Disk recipes ──────────────────────────────────────────
$(EMPTY_PRG): | $(OUT)
	printf '\x01\x08' > $(EMPTY_PRG)

$(LICENSE_DISK_FILE): $(LICENSE_FILE) | $(OUT)
	LC_ALL=C tr '\012' '\015' < $< > $@

$(SOURCE_OFFER_DISK_FILE): $(SOURCE_OFFER) | $(OUT)
	LC_ALL=C tr '\012' '\015' < $< > $@

$(DISK64_IMAGE): $(C64_BUILD_ARTIFACTS) $(DISKART) $(VERSION_FILE) $(LICENSE_DISK_FILE) $(SOURCE_OFFER_DISK_FILE) | $(OUT)
	printf '\x01\x08' > $(EMPTY_PRG)
	rm -f $(DISK64_IMAGE)
	$(C1541) -format $(DISK64_LABEL) d64 $(DISK64_IMAGE) \
		-attach $(DISK64_IMAGE) \
		-write $(EMPTY_PRG) "art1" \
		-write $(EMPTY_PRG) "art2" \
		-write $(EMPTY_PRG) "art3" \
		-write $(EMPTY_PRG) "art4" \
		-write $(EMPTY_PRG) "art5" \
		-write $(C64_BOOT_PRG) "moria8" \
		-write $(C64_BOOT_PRG) "boot64" \
		-write $(C64_BOOTART_PRG) "bootart64" \
		-write $(C64_MAIN_PRG) "moria64" \
		-write $(C64_TITLE_PRG) "t64" \
		-write $(OUT64)/monster.db.1 "monster.db.1" \
		-write $(OUT64)/monster.db.2 "monster.db.2" \
		-write $(OUT64)/monster.db.3 "monster.db.3" \
		-write $(OUT64)/monster.db.4 "monster.db.4" \
		-write $(C64_OVL_START) "64.start" \
		-write $(C64_OVL_TOWN) "64.town" \
		-write $(C64_OVL_DEATH) "64.death" \
			-write $(C64_OVL_GEN) "64.gen" \
			-write $(C64_OVL_HELP) "64.help" \
			-write $(C64_OVL_UI) "64.ui" \
			-write $(C64_OVL_ITEMS) "64.items" \
			-write $(C64_OVL_SPELL) "64.spell" \
			-write $(C64_RUNTIME_BANKED) "64.bank" \
			-write $(LICENSE_DISK_FILE) "license,s" \
			-write $(SOURCE_OFFER_DISK_FILE) "source-offer,s"
	python3 $(DISKART) $(DISK64_IMAGE) c64
	mkdir -p c64/out
	cp -f $(DISK64_IMAGE) c64/out/moria8-c64.d64
	rm -f $(EMPTY_PRG)

$(DISKPLUS4_IMAGE): $(PLUS4_BUILD_ARTIFACTS) $(DISKART) $(VERSION_FILE) $(LICENSE_DISK_FILE) $(SOURCE_OFFER_DISK_FILE) | $(OUT)
	printf '\x01\x08' > $(EMPTY_PRG)
	rm -f $(DISKPLUS4_IMAGE)
	$(C1541) -format $(DISKPLUS4_LABEL) d64 $(DISKPLUS4_IMAGE) \
		-attach $(DISKPLUS4_IMAGE) \
		-write $(EMPTY_PRG) "art1" \
		-write $(EMPTY_PRG) "art2" \
		-write $(EMPTY_PRG) "art3" \
		-write $(EMPTY_PRG) "art4" \
		-write $(EMPTY_PRG) "art5" \
		-write $(PLUS4_BOOT_PRG) "moria8" \
		-write $(PLUS4_BOOT_PRG) "boot4" \
		-write $(PLUS4_MAIN_PRG) "moria4" \
		-write $(PLUS4_TITLE_PRG) "t64" \
		-write $(OUTPLUS4)/monster.db.1 "monster.db.1" \
		-write $(OUTPLUS4)/monster.db.2 "monster.db.2" \
		-write $(OUTPLUS4)/monster.db.3 "monster.db.3" \
		-write $(OUTPLUS4)/monster.db.4 "monster.db.4" \
		-write $(PLUS4_OVL_START) "4.start" \
		-write $(PLUS4_OVL_TOWN) "4.town" \
		-write $(PLUS4_OVL_DEATH) "4.death" \
		-write $(PLUS4_OVL_GEN) "4.gen" \
		-write $(PLUS4_OVL_HELP) "4.help" \
		-write $(PLUS4_OVL_UI) "4.ui" \
		-write $(PLUS4_OVL_ITEMS) "4.items" \
		-write $(PLUS4_OVL_SPELL) "4.spell" \
		-write $(PLUS4_RUNTIME_BANKED) "4.bank" \
		-write $(LICENSE_DISK_FILE) "license,s" \
		-write $(SOURCE_OFFER_DISK_FILE) "source-offer,s"
	python3 $(DISKART) $(DISKPLUS4_IMAGE) plus4
	mkdir -p plus4/out
	cp -f $(DISKPLUS4_IMAGE) plus4/out/moria8-plus4.d64
	rm -f $(EMPTY_PRG)

$(DISK128_IMAGE): $(C128_BUILD_ARTIFACTS) $(C128_BOOT_CHAIN_PRG) $(C128_BOOTSECT_PRG) $(DISKART) $(RESERVE_SECTOR) $(VERSION_FILE) $(LICENSE_DISK_FILE) $(SOURCE_OFFER_DISK_FILE) | $(OUT)
	printf '\x01\x08' > $(EMPTY_PRG)
	rm -f $(DISK128_IMAGE)
	$(C1541) -format $(DISK128_LABEL) d71 $(DISK128_IMAGE)
	python3 $(RESERVE_SECTOR) $(DISK128_IMAGE) 1 0
	$(C1541) -attach $(DISK128_IMAGE) \
		-write $(C128_BOOTSECT_PRG) "art1" \
		-write $(C128_BOOTSECT_PRG) "art2" \
		-write $(C128_BOOTSECT_PRG) "art3" \
		-write $(C128_BOOTSECT_PRG) "art4" \
		-write $(C128_BOOTSECT_PRG) "art5" \
		-write $(C128_BOOT_CHAIN_PRG) "boot128" \
		-write $(C128_BOOTART_DIAG_PRG) "bootart128" \
		-write $(C128_MAIN_PRG) "moria128" \
		-write $(C128_TITLE_PRG) "t128" \
		-write $(OUT128)/monster.db.1 "monster.db.1" \
		-write $(OUT128)/monster.db.2 "monster.db.2" \
		-write $(OUT128)/monster.db.3 "monster.db.3" \
		-write $(OUT128)/monster.db.4 "monster.db.4" \
		-write $(C128_OVL_START) "128.start" \
		-write $(C128_OVL_TOWN) "128.town" \
		-write $(C128_OVL_DEATH) "128.death" \
		-write $(C128_OVL_GEN) "128.gen" \
		-write $(C128_OVL_HELP) "128.help" \
		-write $(C128_OVL_UI) "128.ui" \
		-write $(C128_OVL_ITEMS) "128.items" \
		-write $(C128_RUNTIME_INPUT) "128.input" \
			-write $(C128_RUNTIME_PROJECTILE) "128.proj" \
				-write $(C128_RUNTIME_LOW) "128.runtime" \
				-write $(C128_RUNTIME_COMMON) "128.fdisk" \
				-write $(C128_RUNTIME_DISKIO) "128.diskio" \
				-write $(C128_RESIDENT_WORLD) "128.world" \
			-write $(C128_RESIDENT_ITEMS) "128.item" \
			-write $(C128_RESIDENT_SELECT) "128.select" \
			-write $(C128_RESIDENT_PERSIST) "128.persist" \
			-write $(C128_RESIDENT_PLAY) "128.play" \
			-write $(C128_RUNTIME_BANKED) "128.bank" \
			-write $(LICENSE_DISK_FILE) "license,s" \
			-write $(SOURCE_OFFER_DISK_FILE) "source-offer,s"
	python3 $(PATCH_D64) $(DISK128_IMAGE) 1 0 $(C128_BOOTSECT_PRG) 0x0b00
	python3 $(DISKART) $(DISK128_IMAGE) c128
	mkdir -p c128/out
	cp -f $(DISK128_IMAGE) c128/out/moria128.d71
	rm -f $(EMPTY_PRG)

# ── Tool bootstrap / directories ──────────────────────────
kickass: ensure-kickass

ensure-kickass:
ifeq ($(origin KICKASS),file)
	@if [ ! -f "$(KICKASS_RESOLVED)" ]; then \
		echo "Downloading KickAssembler..."; \
		mkdir -p "$(KICKASS_DIR_RESOLVED)"; \
		curl -sL "$(KICKASS_URL)" -o "$(KICKASS_DIR_RESOLVED)/KickAssembler.zip" || { echo "ERROR: failed to download KickAssembler"; exit 1; }; \
		unzip -qo "$(KICKASS_DIR_RESOLVED)/KickAssembler.zip" -d "$(KICKASS_DIR_RESOLVED)" || { echo "ERROR: failed to unpack KickAssembler"; rm -f "$(KICKASS_DIR_RESOLVED)/KickAssembler.zip"; exit 1; }; \
		rm -f "$(KICKASS_DIR_RESOLVED)/KickAssembler.zip"; \
		test -f "$(KICKASS_RESOLVED)" || { echo "ERROR: KickAss.jar not found after download at $(KICKASS_RESOLVED)"; exit 1; }; \
		echo "KickAssembler ready at $(KICKASS_RESOLVED)"; \
	fi
else
	@test -f "$(KICKASS_RESOLVED)" || { echo "ERROR: custom KICKASS path does not exist: $(KICKASS_RESOLVED)"; exit 1; }
endif

$(OUT):
	mkdir -p $(OUT)

$(OUT64):
	mkdir -p $(OUT64)

$(OUT128):
	mkdir -p $(OUT128)

$(OUTPLUS4):
	mkdir -p $(OUTPLUS4)

clean:
	rm -rf $(OUT)
	rm -rf c64/out c128/out plus4/out
	rm -f c64/tests/*.prg c64/tests/*.vs c64/tests/*.sym
	rm -f /tmp/test_*.mon
