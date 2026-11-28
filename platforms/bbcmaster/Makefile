# Moria8 Acorn BBC Master 128 Platform Makefile

KICKASS_DIR     ?= ../../tools/kickass
# KICKASS names the jar, as on every port (README: KICKASS=/path/to/KickAss.jar)
KICKASS         ?= $(KICKASS_DIR)/KickAss.jar
KICKASS_JAR     = $(KICKASS)
# kickass_java.sh fails the build on a failed .assert (KickAssembler itself exits 0)
KA              = ../../tools/kickass_java.sh -jar $(KICKASS_JAR)

# Python tools and harnesses must not leave __pycache__ in source directories.
export PYTHONDONTWRITEBYTECODE := 1

ifneq ($(filter clean,$(MAKECMDGOALS)),)
$(filter-out clean,$(MAKECMDGOALS)): | clean
endif

OUT         ?= ../../build
OUTBEEB     = $(OUT)/bbcmaster
OVL_OUTBEEB = $(abspath $(OUTBEEB))

KA_FLAGS    = ":OVL_OUT=$(OVL_OUTBEEB)" -showmem -afo -symbolfile -vicesymbols -symbolfiledir "$(OVL_OUTBEEB)" -libdir ../../core/6502 -libdir . -libdir hal -libdir ../commodore/common -libdir ../commodore/c64 -libdir .. -libdir ../.. -define BBCMASTER
PRG2BIN     = python3 -B ../../tools/prg_to_bin.py

VERSION_FILE     = ../../version.json
VERSION_INC_TOOL = ../../tools/make_version_include.py
VERSION_INFO_TOOL = ../../tools/version_info.py
VERSION_STAMP    = $(OUT)/.version.stamp
VERSION_INC      = $(OUT)/version_strings.inc
ifeq ($(filter clean,$(MAKECMDGOALS)),)
_VERSION_STAMP_ERR := $(shell mkdir -p "$(OUT)" && python3 -B "$(VERSION_INFO_TOOL)" --version-file "$(VERSION_FILE)" --write-stamp "$(VERSION_STAMP)" 2>&1)
ifneq ($(strip $(_VERSION_STAMP_ERR)),)
$(error $(_VERSION_STAMP_ERR))
endif
endif
TRAMPOLINES_INC  = $(OUT)/trampolines/bbcmaster_trampolines.inc
MAIN_SRC         = main.s
BOOT_SRC         = boot.s
TITLE_SRC        = title_data.s

BEEB_SOURCES := $(shell find . ../commodore/common ../shared ../../core/6502 -type f \( -name '*.s' -o -name '*.inc' \) -print) \
                ../commodore/c128/ui_help_data_80.s

BEEB_MAIN_PRG   = $(OUTBEEB)/moria8.res.prg
BEEB_PLAY_PRG   = $(OUTBEEB)/beeb.play
BEEB_AUX_PRG    = $(OUTBEEB)/beeb.auxdata
BEEB_HUFF_PRG   = $(OUTBEEB)/beeb.huffdata
BEEB_CAT_PRG    = $(OUTBEEB)/beeb.catalog
BEEB_OVL_PRGS   = $(OUTBEEB)/ovl.start $(OUTBEEB)/ovl.town $(OUTBEEB)/ovl.death $(OUTBEEB)/ovl.modal \
                  $(OUTBEEB)/ovl.gen $(OUTBEEB)/ovl.help $(OUTBEEB)/ovl.ui $(OUTBEEB)/ovl.items \
                  $(OUTBEEB)/ovl.spell $(OUTBEEB)/ovl.chest $(OUTBEEB)/ovl.home $(OUTBEEB)/ovl.storage $(OUTBEEB)/ovl.title
BEEB_TITLE_PRG  = $(OUTBEEB)/title.prg
BEEB_BOOT_PRG   = $(OUTBEEB)/boot.prg
BEEB_MAIN_STAMP = $(OUTBEEB)/.main.stamp
BEEB_SSD        = $(OUT)/moria8-bbcmaster.ssd
BEEB_SAVE_SSD   = $(OUTBEEB)/save-disk.ssd

MAME           ?= mame
BEEB_MACHINE   ?= bbcm
BBCMROMS       ?=
REQUIRE_ALL_ROMS ?= 0
MAME_DIR       = $(OVL_OUTBEEB)/mame
MAME_DIR_FLAGS = -cfg_directory "$(MAME_DIR)/cfg" \
                 -nvram_directory "$(MAME_DIR)/nvram" \
                 -input_directory "$(MAME_DIR)/inp" \
                 -state_directory "$(MAME_DIR)/sta" \
                 -snapshot_directory "$(MAME_DIR)/snap" \
                 -diff_directory "$(MAME_DIR)/diff" \
                 -comment_directory "$(MAME_DIR)/comments" \
                 -share_directory "$(MAME_DIR)/share"

BEEB_OVL_PRGS += $(OUTBEEB)/legalui
.PHONY: all build disk run test test-memory-contract test-memory-contract-selftest test-runtime test-fast-smoke clean ensure-kickass kickass

all: build

build: $(BEEB_MAIN_PRG) $(BEEB_PLAY_PRG) $(BEEB_AUX_PRG) $(BEEB_HUFF_PRG) $(BEEB_CAT_PRG) $(BEEB_OVL_PRGS) $(BEEB_TITLE_PRG) $(BEEB_BOOT_PRG)

kickass: ensure-kickass
ensure-kickass $(KICKASS_JAR):
ifeq ($(origin KICKASS),file)
	@../../tools/ensure_kickass.sh "$(KICKASS_DIR)" "$(KICKASS_JAR)"
else
	@../../tools/ensure_kickass.sh --custom "$(KICKASS_DIR)" "$(KICKASS_JAR)"
endif

$(VERSION_STAMP): $(VERSION_FILE) $(VERSION_INFO_TOOL)
	@mkdir -p $(OUT)
	python3 -B "$(VERSION_INFO_TOOL)" --version-file "$(VERSION_FILE)" --write-stamp "$@"

$(VERSION_INC): $(VERSION_FILE) $(VERSION_STAMP) $(VERSION_INC_TOOL) $(VERSION_INFO_TOOL)
	@mkdir -p $(OUT)
	python3 -B "$(VERSION_INC_TOOL)" "$(VERSION_FILE)" "$(VERSION_INC)"

$(TRAMPOLINES_INC): ../../tools/gen_trampolines.py ../../tools/trampoline_manifest.py
	@mkdir -p $(dir $@)
	python3 -B ../../tools/gen_trampolines.py --port bbcmaster --output "$@"

$(BEEB_MAIN_STAMP): $(BEEB_SOURCES) $(VERSION_INC) $(TRAMPOLINES_INC) $(KICKASS_JAR)
	@mkdir -p $(OUTBEEB)
	$(KA) $(KA_FLAGS) $(MAIN_SRC) -o $(BEEB_MAIN_PRG)
	@touch $(BEEB_MAIN_STAMP)

$(BEEB_MAIN_PRG) $(BEEB_PLAY_PRG) $(BEEB_AUX_PRG) $(BEEB_HUFF_PRG) $(BEEB_CAT_PRG) $(BEEB_OVL_PRGS) $(OUTBEEB)/main.sym: $(BEEB_MAIN_STAMP)
	@test -f "$@" || { rm -f "$(BEEB_MAIN_STAMP)"; $(MAKE) "$(BEEB_MAIN_STAMP)"; }
	@test -f "$@"

$(BEEB_TITLE_PRG): $(TITLE_SRC) $(VERSION_INC) $(KICKASS_JAR)
	@mkdir -p $(OUTBEEB)
	$(KA) $(KA_FLAGS) $(TITLE_SRC) -o $(BEEB_TITLE_PRG)

$(BEEB_BOOT_PRG): $(BOOT_SRC) cache_layout.s $(KICKASS_JAR)
	@mkdir -p $(OUTBEEB)
	$(KA) $(KA_FLAGS) $(BOOT_SRC) -o $(BEEB_BOOT_PRG)

$(OUTBEEB)/boot.sym: $(BEEB_BOOT_PRG)

disk: $(BEEB_SSD)

$(BEEB_SSD): build ../../data/LICENSE ../../data/SOURCE-OFFER ../../platforms/shared/item_catalog/item_cat_data.s ../../platforms/shared/catalog/monster_catalog_spec.json ../../tools/catalog_disk.py ../../tools/build_catalog.py ../../tools/make_pak.py ../../tools/make_ssd.py
	@mkdir -p "$(OUTBEEB)/bin"
	$(PRG2BIN) "$(BEEB_BOOT_PRG)" "$(OUTBEEB)/bin/MORIA8" --expect-addr 0x1900
	$(PRG2BIN) "$(BEEB_MAIN_PRG)" "$(OUTBEEB)/bin/MORIA8.RES" --expect-addr 0x0E00
	$(PRG2BIN) "$(BEEB_PLAY_PRG)" "$(OUTBEEB)/bin/BEEB.PLAY" --expect-addr 0x8000
	$(PRG2BIN) "$(BEEB_HUFF_PRG)" "$(OUTBEEB)/bin/BEEB.HUFFDATA" --expect-addr 0x8000
	$(PRG2BIN) "$(BEEB_AUX_PRG)" "$(OUTBEEB)/bin/BEEB.AUXDATA" --expect-addr 0x6000
	@for f in START TOWN DEATH MODAL GEN HELP UI ITEMS SPELL CHEST HOME STORAGE TITLE; do \
	  lower=$$(echo $$f | tr 'A-Z' 'a-z'); \
	  $(PRG2BIN) "$(OUTBEEB)/ovl.$$lower" "$(OUTBEEB)/bin/OVL.$$f" --expect-addr 0xA800 || exit 1; \
	done
	$(PRG2BIN) "$(BEEB_CAT_PRG)" "$(OUTBEEB)/bin/BEEB.CATALOG" --expect-addr 0x9500
	$(PRG2BIN) "$(OUTBEEB)/legalui" "$(OUTBEEB)/bin/LEGALUI" --expect-addr 0xA800
	$(PRG2BIN) "$(BEEB_TITLE_PRG)" "$(OUTBEEB)/bin/TITLE" --expect-addr 0x8000
	python3 -B ../../tools/catalog_disk.py item-raw "$(OUTBEEB)/bin"
	python3 -B ../../tools/build_catalog.py ext-rows --out "$(OUTBEEB)/bin/MON.EXT"
	python3 -B ../../tools/make_pak.py "$(OUTBEEB)/bin/MORIA8.PAK" \
	  "$(OUTBEEB)/bin/MORIA8.RES" "$(OUTBEEB)/bin/BEEB.PLAY" \
	  "$(OUTBEEB)/bin/BEEB.HUFFDATA" "$(OUTBEEB)/bin/BEEB.AUXDATA" \
	  "$(OUTBEEB)/bin/BEEB.CATALOG" \
	  "$(OUTBEEB)/bin/OVL.TITLE" "$(OUTBEEB)/bin/OVL.UI" \
	  "$(OUTBEEB)/bin/OVL.MODAL" \
	  "$(OUTBEEB)/bin/OVL.SPELL" "$(OUTBEEB)/bin/OVL.ITEMS" \
	  "$(OUTBEEB)/bin/OVL.GEN"
	printf '*RUN MORIA8\r' > "$(OUTBEEB)/bin/!BOOT"
	LC_ALL=C tr '\012' '\015' < ../../data/LICENSE > "$(OUTBEEB)/bin/LICENSE"
	LC_ALL=C tr '\012' '\015' < ../../data/SOURCE-OFFER > "$(OUTBEEB)/bin/SRCOFFR"
	python3 -B ../../tools/make_ssd.py --title MORIA8 --opt 3 "$(BEEB_SSD)" \
	  "!BOOT=$(OUTBEEB)/bin/!BOOT:FFFF0000:FFFFFFFF" \
	  "MORIA8=$(OUTBEEB)/bin/MORIA8:FFFF1900:FFFF1900" \
	  "ITEMCAT=$(OUTBEEB)/bin/ITEM.CAT:FFFF0000:FFFFFFFF" \
	  "MONEXT=$(OUTBEEB)/bin/MON.EXT:FFFF0000:FFFFFFFF" \
	  "TITLE=$(OUTBEEB)/bin/TITLE:FFFF8000:FFFF8000" \
	  "OVLSTA=$(OUTBEEB)/bin/OVL.START:FFFFA800:FFFFA800" \
	  "OVLTWN=$(OUTBEEB)/bin/OVL.TOWN:FFFFA800:FFFFA800" \
	  "OVLDTH=$(OUTBEEB)/bin/OVL.DEATH:FFFFA800:FFFFA800" \
	  "OVLCHS=$(OUTBEEB)/bin/OVL.CHEST:FFFFA800:FFFFA800" \
	  "OVLHLP=$(OUTBEEB)/bin/OVL.HELP:FFFFA800:FFFFA800" \
	  "OVLSTO=$(OUTBEEB)/bin/OVL.STORAGE:FFFFA800:FFFFA800" \
	  "OVLHOM=$(OUTBEEB)/bin/OVL.HOME:FFFFA800:FFFFA800" \
	  "LEGALUI=$(OUTBEEB)/bin/LEGALUI:FFFFA800:FFFFA800" \
	  "MORIA8P=$(OUTBEEB)/bin/MORIA8.PAK:00000000:00000000" \
	  "LICENSE=$(OUTBEEB)/bin/LICENSE:FFFF0000:FFFFFFFF" \
	  "SRCOFFR=$(OUTBEEB)/bin/SRCOFFR:FFFF0000:FFFFFFFF"
	python3 -B check_memory_contract.py --disk "$(BEEB_SSD)" || { rm -f "$(BEEB_SSD)"; exit 1; }

test-memory-contract-selftest:
	python3 -B ../../tools/make_ssd.py --selftest
	python3 -B check_memory_contract.py --selftest
	python3 -B harness_smoke.py --selftest

test-memory-contract: build test-memory-contract-selftest
	python3 -B check_memory_contract.py --build-dir $(OUTBEEB)

test-runtime: disk
	@if [ -n "$(BBCMROMS)" ]; then \
		python3 -B harness_smoke.py --rompath "$(BBCMROMS)" --disk "$(BEEB_SSD)" --sym "$(OUTBEEB)/main.sym" --all; \
	elif [ "$(strip $(REQUIRE_ALL_ROMS))" = "1" ]; then \
		echo "ERROR: BBCMROMS not set and REQUIRE_ALL_ROMS=1" >&2; exit 1; \
	else \
		echo "WARNING: BBCMROMS not set; skipping BBC Master 128 MAME runtime smoke suite"; \
	fi

test-fast-smoke: disk
	@if [ -n "$(BBCMROMS)" ]; then \
		python3 -B harness_smoke.py --rompath "$(BBCMROMS)" --disk "$(BEEB_SSD)" --sym "$(OUTBEEB)/main.sym" --fast-smoke; \
	elif [ "$(strip $(REQUIRE_ALL_ROMS))" = "1" ]; then \
		echo "ERROR: BBCMROMS not set and REQUIRE_ALL_ROMS=1" >&2; exit 1; \
	else \
		echo "WARNING: BBCMROMS not set; skipping BBC Master 128 MAME fast smoke suite"; \
	fi

test: test-memory-contract test-runtime

run: disk
	@if [ -z "$(BBCMROMS)" ]; then \
		echo "ERROR: set BBCMROMS=/path/to/bbcm/roms to launch MAME $(BEEB_MACHINE)"; \
		exit 1; \
	fi
	@mkdir -p "$(MAME_DIR)/cfg" "$(MAME_DIR)/nvram" "$(MAME_DIR)/inp" "$(MAME_DIR)/sta" "$(MAME_DIR)/snap" "$(MAME_DIR)/diff" "$(MAME_DIR)/comments" "$(MAME_DIR)/share"
	@test -f "$(BEEB_SAVE_SSD)" || python3 -B ../../tools/make_ssd.py --blank-disk "$(BEEB_SAVE_SSD)"
	$(MAME) $(BEEB_MACHINE) -rompath "$(BBCMROMS)" \
		-flop1 "$(abspath $(BEEB_SSD))" \
		-flop2 "$(abspath $(BEEB_SAVE_SSD))" \
		$(MAME_DIR_FLAGS) \
		-autoboot_delay 2 -autoboot_command "*EXEC !BOOT\n" \
		-window -nomaximize -skip_gameinfo

clean:
	rm -rf $(OUTBEEB) $(BEEB_SSD)
	rm -rf cfg nvram inp sta snap diff comments share
