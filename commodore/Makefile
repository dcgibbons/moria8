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
JAVA        ?= java
C1541       ?= c1541
VICE64      ?= x64sc
VICE128     ?= x128

# ── Output layout ─────────────────────────────────────────
OUT         ?= out
OUT64        = $(OUT)/c64
OUT128       = $(OUT)/c128

# ── Shared tooling ────────────────────────────────────────
DISKART      = ../tools/diskart.py
PATCH_D64    = ../tools/patch_d64_sector.py
RESERVE_SECTOR = ../tools/reserve_cbm_sector.py
VERSION_FILE = ../version.json
RUN_FLAGS64  = -autostartprgmode 1 -sound -sounddev coreaudio
RUN_FLAGS128 = -80col -sound -sounddev coreaudio
KA_FLAGS     = -showmem -vicesymbols
KA_FLAGS64   = $(KA_FLAGS) -libdir c64
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

C64_SOURCES        := $(shell find c64 common -type f -name '*.s')
C128_SOURCES       := $(shell find c128 common c64 -type f -name '*.s')

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
C128_RUNTIME_LOW   = $(OUT128)/128.runtime.prg
C128_RUNTIME_COMMON = $(OUT128)/128.fdisk.prg
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
EMPTY_PRG          = $(OUT)/empty.prg
DISK64_LABEL       = "moria8 c64,m8"
DISK128_LABEL      = "moria8 c128,m8"

# ── Aggregate groups ──────────────────────────────────────
C64_BUILD_ARTIFACTS  = $(C64_MAIN_PRG) $(C64_BOOT_PRG) $(C64_BOOTART_PRG) $(C64_TITLE_PRG) $(C64_TIER_PRGS) \
	$(C64_OVL_START) $(C64_OVL_TOWN) $(C64_OVL_DEATH) $(C64_OVL_GEN) $(C64_OVL_HELP) $(C64_OVL_UI)
C128_BUILD_ARTIFACTS = $(C128_MAIN_PRG) $(C128_BOOT_PRG) $(C128_BOOT_CHAIN_PRG) $(C128_BOOTSECT_PRG) \
	$(C128_BOOTART_DIAG_PRG) \
	$(C128_TITLE_PRG) $(C128_TIER_PRGS) $(C128_OVL_START) $(C128_OVL_TOWN) $(C128_OVL_DEATH) \
	$(C128_OVL_GEN) $(C128_OVL_HELP) $(C128_OVL_UI) $(C128_RUNTIME_LOW) $(C128_RUNTIME_COMMON)

.PHONY: all build build64 build128 disk disk64 disk128 run run64 run128 \
	bootart128-charset-demo \
	test test64 test128 test128-fast test128-fast-smoke clean \
	check-zp check-6502-lint

all: build

build: build64 build128

build64: $(C64_BUILD_ARTIFACTS)
	mkdir -p c64/out
	cp -f $(OUT64)/* c64/out/

build128: $(C128_BUILD_ARTIFACTS)
	mkdir -p c128/out
	cp -f $(OUT128)/* c128/out/

disk: $(DISK64_IMAGE) $(DISK128_IMAGE)

disk64: $(DISK64_IMAGE)

disk128: $(DISK128_IMAGE)

run: $(DISK64_IMAGE)
	$(VICE64) -drive8truedrive -drive8type 1541 +busdevice8 $(RUN_FLAGS64) -autostart $(DISK64_IMAGE)

run64: run

run128: $(DISK128_IMAGE)
	$(VICE128) -drive8truedrive -drive8type 1571 +busdevice8 $(RUN_FLAGS128) $(DISK128_IMAGE)

bootart128-charset-demo: $(C128_CHARSET_DEMO_PRG)

test: test64 test128-fast test128-fast-smoke

test64:
	cd c64 && ./run_tests.sh

test128:
	cd c128 && ./run_tests128.sh

test128-fast:
	cd c128 && python3 -u ./harness128_batch.py --mode compare --snapshot-path out/ready.vsf --vice $(VICE128) --connect-timeout 12

test128-fast-smoke:
	cd c128 && TEST_FILTER='boot_title_idle_smoke|scripted_summary_to_town_smoke|town_overlay_smoke' ./run_tests128.sh

check-zp:
	python3 ../tools/check_zp_usage.py

check-6502-lint:
	python3 ../tools/check_6502_lint.py

# ── C64 build rules ───────────────────────────────────────
$(VERSION_INC): $(VERSION_FILE) $(VERSION_INC_TOOL) | $(OUT)
	python3 $(VERSION_INC_TOOL) $(VERSION_FILE) $(VERSION_INC)

$(C64_MAIN_PRG): $(C64_SOURCES) $(VERSION_INC) $(KICKASS) | $(OUT64)
	$(JAVA) -jar $(KICKASS) $(C64_MAIN_SRC) $(KA_FLAGS64) -o $(C64_MAIN_PRG)
	mv -f c64/out/ovl.start $(C64_OVL_START)
	mv -f c64/out/ovl.town $(C64_OVL_TOWN)
	mv -f c64/out/ovl.death $(C64_OVL_DEATH)
	mv -f c64/out/ovl.gen $(C64_OVL_GEN)
	mv -f c64/out/ovl.help $(C64_OVL_HELP)
	mv -f c64/out/ovl.ui $(C64_OVL_UI)

$(C64_OVL_START): $(C64_MAIN_PRG)
$(C64_OVL_TOWN): $(C64_MAIN_PRG)
$(C64_OVL_DEATH): $(C64_MAIN_PRG)
$(C64_OVL_GEN): $(C64_MAIN_PRG)
$(C64_OVL_HELP): $(C64_MAIN_PRG)
$(C64_OVL_UI): $(C64_MAIN_PRG)

$(C64_BOOT_PRG): $(C64_SOURCES) $(KICKASS) | $(OUT64)
	$(JAVA) -jar $(KICKASS) $(C64_BOOT_SRC) -o $(C64_BOOT_PRG)

$(C64_BOOTART_PNG):
	@echo "Missing source art: $@"
	@false

$(C64_BOOTART_PPM): $(C64_BOOTART_PNG) $(C64_BOOTART_SRC_TOOL) | $(OUT64)
	python3 $(C64_BOOTART_SRC_TOOL) $(C64_BOOTART_PNG) 160 200 $@

$(C64_BOOTART_PRG): $(C64_BOOTART_PPM) $(C64_BOOTART_TOOL) | $(OUT64)
	python3 $(C64_BOOTART_TOOL) $(C64_BOOTART_PPM) $(C64_BOOTART_PRG)

$(C64_TITLE_PRG): $(TITLE_SRC) $(VERSION_INC) $(KICKASS) | $(OUT64)
	$(JAVA) -jar $(KICKASS) $(TITLE_SRC) -o $(C64_TITLE_PRG)

$(OUT64)/monster.db.1: $(C64_TIER_DIR)/tier1_prg.s $(C64_TIER_DIR)/tier1.s $(KICKASS) | $(OUT64)
	$(JAVA) -jar $(KICKASS) $(C64_TIER_DIR)/tier1_prg.s -o $@

$(OUT64)/monster.db.2: $(C64_TIER_DIR)/tier2_prg.s $(C64_TIER_DIR)/tier2.s $(KICKASS) | $(OUT64)
	$(JAVA) -jar $(KICKASS) $(C64_TIER_DIR)/tier2_prg.s -o $@

$(OUT64)/monster.db.3: $(C64_TIER_DIR)/tier3_prg.s $(C64_TIER_DIR)/tier3.s $(KICKASS) | $(OUT64)
	$(JAVA) -jar $(KICKASS) $(C64_TIER_DIR)/tier3_prg.s -o $@

$(OUT64)/monster.db.4: $(C64_TIER_DIR)/tier4_prg.s $(C64_TIER_DIR)/tier4.s $(KICKASS) | $(OUT64)
	$(JAVA) -jar $(KICKASS) $(C64_TIER_DIR)/tier4_prg.s -o $@

# ── C128 build rules ──────────────────────────────────────
$(C128_MAIN_PRG): $(C128_SOURCES) $(VERSION_INC) $(KICKASS) | $(OUT128)
	$(JAVA) -jar $(KICKASS) $(C128_MAIN_SRC) $(KA_FLAGS128) -o $(C128_MAIN_PRG)
	mkdir -p "$(OUT128)" "c128/out"
	mv -f "c128/out/ovl.start" "$(C128_OVL_START)"
	mv -f "c128/out/ovl.town" "$(C128_OVL_TOWN)"
	mv -f "c128/out/ovl.death" "$(C128_OVL_DEATH)"
	mv -f "c128/out/ovl.gen" "$(C128_OVL_GEN)"
	mv -f "c128/out/ovl.help" "$(C128_OVL_HELP)"
	mv -f "c128/out/ovl.ui" "$(C128_OVL_UI)"
	mv -f "c128/out/128.runtime.prg" "$(C128_RUNTIME_LOW)"
	mv -f "c128/out/128.fdisk.prg" "$(C128_RUNTIME_COMMON)"

$(C128_OVL_START): $(C128_MAIN_PRG)
$(C128_OVL_TOWN): $(C128_MAIN_PRG)
$(C128_OVL_DEATH): $(C128_MAIN_PRG)
$(C128_OVL_GEN): $(C128_MAIN_PRG)
$(C128_OVL_HELP): $(C128_MAIN_PRG)
$(C128_OVL_UI): $(C128_MAIN_PRG)
$(C128_RUNTIME_LOW): $(C128_MAIN_PRG)
$(C128_RUNTIME_COMMON): $(C128_MAIN_PRG)

$(C128_BOOT_PRG): $(C128_SOURCES) $(KICKASS) | $(OUT128)
	$(JAVA) -jar $(KICKASS) $(C128_BOOT_SRC) -o $(C128_BOOT_PRG)

$(C128_BOOT_CHAIN_PRG): $(C128_SOURCES) $(KICKASS) | $(OUT128)
	$(JAVA) -jar $(KICKASS) $(C128_BOOT_SRC) -define BOOT128_CHAIN -o $(C128_BOOT_CHAIN_PRG)

$(C128_CHARSET_DEMO_PRG): $(C128_CHARSET_DEMO_SRC) $(KICKASS) | $(OUT128)
	$(JAVA) -jar $(KICKASS) $(C128_CHARSET_DEMO_SRC) $(KA_FLAGS128) -o $(C128_CHARSET_DEMO_PRG)

$(C128_BOOTART_PPM): $(C128_BOOTART_PNG) $(C128_BOOTART_SRC_TOOL) | $(OUT128)
	python3 $(C128_BOOTART_SRC_TOOL) $(C128_BOOTART_PNG) 640 200 $@

$(C128_BOOTART_INC) $(C128_BOOTART_CHARSET_BIN) $(C128_BOOTART_SCREEN_BIN) $(C128_BOOTART_ATTR_BIN) $(C128_BOOTART_PREVIEW_PPM): $(C128_BOOTART_PPM) $(C128_BOOTART_TOOL) | $(OUT128)
	python3 $(C128_BOOTART_TOOL) $(C128_BOOTART_PPM) $(OUT128)/bootart128

$(C128_BOOTART_DIAG_PRG): $(C128_BOOTART_SRC) $(C128_BOOTART_INC) $(C128_BOOTART_CHARSET_BIN) $(C128_BOOTART_SCREEN_BIN) $(C128_BOOTART_ATTR_BIN) $(KICKASS) | $(OUT128)
	$(JAVA) -jar $(KICKASS) $(C128_BOOTART_SRC) $(KA_FLAGS128) -o $(C128_BOOTART_DIAG_PRG)

$(C128_TITLE_PRG): $(TITLE_SRC) $(VERSION_INC) $(KICKASS) | $(OUT128)
	$(JAVA) -jar $(KICKASS) $(TITLE_SRC) -define C128 -o $(C128_TITLE_PRG)

$(OUT128)/monster.db.1: $(C64_TIER_DIR)/tier1_prg.s $(C64_TIER_DIR)/tier1.s $(KICKASS) | $(OUT128)
	$(JAVA) -jar $(KICKASS) $(C64_TIER_DIR)/tier1_prg.s -o $@

$(OUT128)/monster.db.2: $(C64_TIER_DIR)/tier2_prg.s $(C64_TIER_DIR)/tier2.s $(KICKASS) | $(OUT128)
	$(JAVA) -jar $(KICKASS) $(C64_TIER_DIR)/tier2_prg.s -o $@

$(OUT128)/monster.db.3: $(C64_TIER_DIR)/tier3_prg.s $(C64_TIER_DIR)/tier3.s $(KICKASS) | $(OUT128)
	$(JAVA) -jar $(KICKASS) $(C64_TIER_DIR)/tier3_prg.s -o $@

$(OUT128)/monster.db.4: $(C64_TIER_DIR)/tier4_prg.s $(C64_TIER_DIR)/tier4.s $(KICKASS) | $(OUT128)
	$(JAVA) -jar $(KICKASS) $(C64_TIER_DIR)/tier4_prg.s -o $@

$(C128_BOOTSECT_PRG): $(C128_BOOTSECT_SRC) $(KICKASS) | $(OUT128)
	$(JAVA) -jar $(KICKASS) $(C128_BOOTSECT_SRC) -o $(C128_BOOTSECT_PRG)

# ── Disk recipes ──────────────────────────────────────────
$(EMPTY_PRG): | $(OUT)
	printf '\x01\x08' > $(EMPTY_PRG)

$(DISK64_IMAGE): $(C64_BUILD_ARTIFACTS) $(DISKART) $(VERSION_FILE) | $(OUT)
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
		-write $(C64_OVL_UI) "64.ui"
	python3 $(DISKART) $(DISK64_IMAGE) c64
	mkdir -p c64/out
	cp -f $(DISK64_IMAGE) c64/out/moria8-c64.d64
	rm -f $(EMPTY_PRG)

$(DISK128_IMAGE): $(C128_BUILD_ARTIFACTS) $(C128_BOOT_CHAIN_PRG) $(C128_BOOTSECT_PRG) $(DISKART) $(RESERVE_SECTOR) $(VERSION_FILE) | $(OUT)
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
		-write $(C128_RUNTIME_LOW) "128.runtime" \
		-write $(C128_RUNTIME_COMMON) "128.fdisk"
	python3 $(PATCH_D64) $(DISK128_IMAGE) 1 0 $(C128_BOOTSECT_PRG) 0x0b00
	python3 $(DISKART) $(DISK128_IMAGE) c128
	mkdir -p c128/out
	cp -f $(DISK128_IMAGE) c128/out/moria128.d71
	rm -f $(EMPTY_PRG)

# ── Tool bootstrap / directories ──────────────────────────
$(KICKASS):
	@echo "Downloading KickAssembler..."
	@mkdir -p $(KICKASS_DIR)
	@curl -sL $(KICKASS_URL) -o $(KICKASS_DIR)/KickAssembler.zip
	@unzip -qo $(KICKASS_DIR)/KickAssembler.zip -d $(KICKASS_DIR)
	@rm -f $(KICKASS_DIR)/KickAssembler.zip
	@test -f $(KICKASS) || { echo "ERROR: KickAss.jar not found after download"; exit 1; }
	@echo "KickAssembler ready at $(KICKASS)"

$(OUT):
	mkdir -p $(OUT)

$(OUT64):
	mkdir -p $(OUT64)

$(OUT128):
	mkdir -p $(OUT128)

clean:
	rm -rf $(OUT)
	rm -rf c64/out c128/out
	rm -f c64/tests/*.prg c64/tests/*.vs c64/tests/*.sym
	rm -f /tmp/test_*.mon
