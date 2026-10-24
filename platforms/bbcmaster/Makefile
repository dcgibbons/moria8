# Moria8 Acorn BBC Master 128 Platform Makefile

KICKASS_VERSION = 5.25
KICKASS_DIR     ?= ../../tools/kickass
KICKASS_JAR     ?= $(KICKASS_DIR)/KickAss.jar
KICKASS_URL     = https://theweb.dk/KickAssembler/KickAssembler$(KICKASS_VERSION).zip
# kickass_java.sh fails the build on a failed .assert (KickAssembler itself exits 0)
KA              = $(if $(KICKASS),$(KICKASS),../../tools/kickass_java.sh -jar $(KICKASS_JAR))

# Python tools and harnesses must not leave __pycache__ in source directories.
export PYTHONDONTWRITEBYTECODE := 1

ifneq ($(filter clean,$(MAKECMDGOALS)),)
$(filter-out clean,$(MAKECMDGOALS)): | clean
endif

OUT         ?= ../../build
OUTBEEB     = $(OUT)/bbcmaster
OVL_OUTBEEB = $(abspath $(OUTBEEB))

KA_FLAGS    = ":OVL_OUT=$(OVL_OUTBEEB)" -showmem -afo -symbolfile -vicesymbols -symbolfiledir "$(OVL_OUTBEEB)" -libdir ../../core -libdir . -libdir hal -libdir ../commodore/common -libdir ../commodore/c64 -libdir .. -libdir ../.. -define BBCMASTER
PRG2BIN     = python3 ../../tools/prg_to_bin.py

VERSION_FILE     = ../../version.json
VERSION_INC_TOOL = ../../tools/make_version_include.py
VERSION_INC      = $(OUT)/version_strings.inc
MAIN_SRC         = main.s
BOOT_SRC         = boot.s
TITLE_SRC        = title_data.s
TIER_DIR         = creature_data

BEEB_SOURCES := $(shell find . ../commodore/common ../shared ../../core -type f \( -name '*.s' -o -name '*.inc' \) -print)

BEEB_MAIN_PRG   = $(OUTBEEB)/moria8.res.prg
BEEB_PLAY_PRG   = $(OUTBEEB)/beeb.play
BEEB_AUX_PRG    = $(OUTBEEB)/beeb.auxdata
BEEB_HUFF_PRG   = $(OUTBEEB)/beeb.huffdata
BEEB_OVL_PRGS   = $(OUTBEEB)/ovl.start $(OUTBEEB)/ovl.town $(OUTBEEB)/ovl.death $(OUTBEEB)/ovl.modal \
                  $(OUTBEEB)/ovl.gen $(OUTBEEB)/ovl.help $(OUTBEEB)/ovl.ui $(OUTBEEB)/ovl.items \
                  $(OUTBEEB)/ovl.spell $(OUTBEEB)/ovl.chest $(OUTBEEB)/ovl.storage $(OUTBEEB)/ovl.title
BEEB_TIER_PRGS  = $(OUTBEEB)/monster.db.1 $(OUTBEEB)/monster.db.2 $(OUTBEEB)/monster.db.3 $(OUTBEEB)/monster.db.4
BEEB_TITLE_PRG  = $(OUTBEEB)/title.prg
BEEB_BOOT_PRG   = $(OUTBEEB)/boot.prg
BEEB_MAIN_STAMP = $(OUTBEEB)/.main.stamp
BEEB_SSD        = $(OUT)/moria8-bbcmaster.ssd
BEEB_SAVE_SSD   = $(OUTBEEB)/save-disk.ssd

MAME           ?= mame
BEEB_MACHINE   ?= bbcm
BBCMROMS       ?=
MAME_DIR       = $(OVL_OUTBEEB)/mame
MAME_DIR_FLAGS = -cfg_directory "$(MAME_DIR)/cfg" \
                 -nvram_directory "$(MAME_DIR)/nvram" \
                 -input_directory "$(MAME_DIR)/inp" \
                 -state_directory "$(MAME_DIR)/sta" \
                 -snapshot_directory "$(MAME_DIR)/snap" \
                 -diff_directory "$(MAME_DIR)/diff" \
                 -comment_directory "$(MAME_DIR)/comments" \
                 -share_directory "$(MAME_DIR)/share"

.PHONY: all build disk run test test-memory-contract test-memory-contract-selftest test-runtime test-fast-smoke clean kickass

all: build

build: $(BEEB_MAIN_PRG) $(BEEB_PLAY_PRG) $(BEEB_AUX_PRG) $(BEEB_HUFF_PRG) $(BEEB_OVL_PRGS) $(BEEB_TIER_PRGS) $(BEEB_TITLE_PRG) $(BEEB_BOOT_PRG)

kickass: $(KICKASS_JAR)
$(KICKASS_JAR):
	@echo "Downloading KickAssembler $(KICKASS_VERSION)..."
	@mkdir -p $(KICKASS_DIR)
	@curl -sL "$(KICKASS_URL)" -o $(KICKASS_DIR)/kickass.zip
	@unzip -qo $(KICKASS_DIR)/kickass.zip -d $(KICKASS_DIR)
	@rm -f $(KICKASS_DIR)/kickass.zip

$(VERSION_INC): $(VERSION_FILE) $(VERSION_INC_TOOL)
	@mkdir -p $(OUT)
	python3 "$(VERSION_INC_TOOL)" "$(VERSION_FILE)" "$(VERSION_INC)"

$(BEEB_MAIN_STAMP): $(BEEB_SOURCES) $(VERSION_INC) $(KICKASS_JAR)
	@mkdir -p $(OUTBEEB)
	$(KA) $(KA_FLAGS) $(MAIN_SRC) -o $(BEEB_MAIN_PRG)
	@touch $(BEEB_MAIN_STAMP)

$(BEEB_MAIN_PRG) $(BEEB_PLAY_PRG) $(BEEB_AUX_PRG) $(BEEB_HUFF_PRG) $(BEEB_OVL_PRGS) $(OUTBEEB)/main.sym: $(BEEB_MAIN_STAMP)
	@test -f "$@" || { rm -f "$(BEEB_MAIN_STAMP)"; $(MAKE) "$(BEEB_MAIN_STAMP)"; }
	@test -f "$@"

$(OUTBEEB)/monster.db.%: $(TIER_DIR)/tier%_prg.s ../commodore/c64/creature_data/tier%.s $(KICKASS_JAR)
	@mkdir -p $(OUTBEEB)
	$(KA) $(KA_FLAGS) $< -o $@

$(BEEB_TITLE_PRG): $(TITLE_SRC) $(VERSION_INC) $(KICKASS_JAR)
	@mkdir -p $(OUTBEEB)
	$(KA) $(KA_FLAGS) $(TITLE_SRC) -o $(BEEB_TITLE_PRG)

$(BEEB_BOOT_PRG): $(BOOT_SRC) cache_layout.s $(KICKASS_JAR)
	@mkdir -p $(OUTBEEB)
	$(KA) $(KA_FLAGS) $(BOOT_SRC) -o $(BEEB_BOOT_PRG)

$(OUTBEEB)/boot.sym: $(BEEB_BOOT_PRG)

disk: $(BEEB_SSD)

$(BEEB_SSD): build ../../data/LICENSE ../../data/SOURCE-OFFER ../../tools/make_pak.py ../../tools/make_ssd.py
	@mkdir -p "$(OUTBEEB)/bin"
	$(PRG2BIN) "$(BEEB_BOOT_PRG)" "$(OUTBEEB)/bin/MORIA8" --expect-addr 0x1900
	$(PRG2BIN) "$(BEEB_MAIN_PRG)" "$(OUTBEEB)/bin/MORIA8.RES" --expect-addr 0x0E00
	$(PRG2BIN) "$(BEEB_PLAY_PRG)" "$(OUTBEEB)/bin/BEEB.PLAY" --expect-addr 0x8000
	$(PRG2BIN) "$(BEEB_HUFF_PRG)" "$(OUTBEEB)/bin/BEEB.HUFFDATA" --expect-addr 0x8000
	$(PRG2BIN) "$(BEEB_AUX_PRG)" "$(OUTBEEB)/bin/BEEB.AUXDATA" --expect-addr 0x6000
	@for f in START TOWN DEATH MODAL GEN HELP UI ITEMS SPELL CHEST STORAGE TITLE; do \
	  lower=$$(echo $$f | tr 'A-Z' 'a-z'); \
	  $(PRG2BIN) "$(OUTBEEB)/ovl.$$lower" "$(OUTBEEB)/bin/OVL.$$f" --expect-addr 0xA800 || exit 1; \
	done
	@for n in 1 2 3 4; do \
	  $(PRG2BIN) "$(OUTBEEB)/monster.db.$$n" "$(OUTBEEB)/bin/MONSTER.DB.$$n" --expect-addr 0xA800 || exit 1; \
	done
	$(PRG2BIN) "$(BEEB_TITLE_PRG)" "$(OUTBEEB)/bin/TITLE" --expect-addr 0x8000
	python3 ../../tools/make_pak.py "$(OUTBEEB)/bin/MORIA8.PAK" \
	  "$(OUTBEEB)/bin/MORIA8.RES" "$(OUTBEEB)/bin/BEEB.PLAY" \
	  "$(OUTBEEB)/bin/BEEB.HUFFDATA" "$(OUTBEEB)/bin/BEEB.AUXDATA" \
	  "$(OUTBEEB)/bin/OVL.UI" "$(OUTBEEB)/bin/OVL.TOWN" \
	  "$(OUTBEEB)/bin/OVL.MODAL" "$(OUTBEEB)/bin/MONSTER.DB.1" \
	  "$(OUTBEEB)/bin/OVL.SPELL" "$(OUTBEEB)/bin/OVL.ITEMS" \
	  "$(OUTBEEB)/bin/OVL.GEN"
	printf '*RUN MORIA8\r' > "$(OUTBEEB)/bin/!BOOT"
	LC_ALL=C tr '\012' '\015' < ../../data/LICENSE > "$(OUTBEEB)/bin/LICENSE"
	LC_ALL=C tr '\012' '\015' < ../../data/SOURCE-OFFER > "$(OUTBEEB)/bin/SRCOFFR"
	python3 ../../tools/make_ssd.py --title MORIA8 --opt 3 "$(BEEB_SSD)" \
	  "!BOOT=$(OUTBEEB)/bin/!BOOT:FFFF0000:FFFFFFFF" \
	  "MORIA8=$(OUTBEEB)/bin/MORIA8:FFFF1900:FFFF1900" \
	  "MORIA8P=$(OUTBEEB)/bin/MORIA8.PAK:00000000:00000000" \
	  "OVLSTA=$(OUTBEEB)/bin/OVL.START:FFFFA800:FFFFA800" \
	  "OVLDTH=$(OUTBEEB)/bin/OVL.DEATH:FFFFA800:FFFFA800" \
	  "OVLHLP=$(OUTBEEB)/bin/OVL.HELP:FFFFA800:FFFFA800" \
	  "OVLCHS=$(OUTBEEB)/bin/OVL.CHEST:FFFFA800:FFFFA800" \
	  "OVLSTO=$(OUTBEEB)/bin/OVL.STORAGE:FFFFA800:FFFFA800" \
	  "OVLTTL=$(OUTBEEB)/bin/OVL.TITLE:FFFFA800:FFFFA800" \
	  "MONDB2=$(OUTBEEB)/bin/MONSTER.DB.2:FFFFA800:FFFFA800" \
	  "MONDB3=$(OUTBEEB)/bin/MONSTER.DB.3:FFFFA800:FFFFA800" \
	  "MONDB4=$(OUTBEEB)/bin/MONSTER.DB.4:FFFFA800:FFFFA800" \
	  "TITLE=$(OUTBEEB)/bin/TITLE:FFFF8000:FFFF8000" \
	  "LICENSE=$(OUTBEEB)/bin/LICENSE:FFFF0000:FFFFFFFF" \
	  "SRCOFFR=$(OUTBEEB)/bin/SRCOFFR:FFFF0000:FFFFFFFF"

test-memory-contract-selftest:
	python3 ../../tools/make_ssd.py --selftest
	python3 check_memory_contract.py --selftest
	python3 harness_smoke.py --selftest

test-memory-contract: build test-memory-contract-selftest
	python3 check_memory_contract.py --build-dir $(OUTBEEB)

test-runtime: disk
	@if [ -n "$(BBCMROMS)" ]; then \
		python3 harness_smoke.py --rompath "$(BBCMROMS)" --disk "$(BEEB_SSD)" --sym "$(OUTBEEB)/main.sym" --all; \
	else \
		echo "WARNING: BBCMROMS not set; skipping BBC Master 128 MAME runtime smoke suite"; \
	fi

test-fast-smoke: disk
	@if [ -n "$(BBCMROMS)" ]; then \
		python3 harness_smoke.py --rompath "$(BBCMROMS)" --disk "$(BEEB_SSD)" --sym "$(OUTBEEB)/main.sym" --fast-smoke; \
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
	@test -f "$(BEEB_SAVE_SSD)" || python3 ../../tools/make_ssd.py --blank-disk "$(BEEB_SAVE_SSD)"
	$(MAME) $(BEEB_MACHINE) -rompath "$(BBCMROMS)" \
		-flop1 "$(abspath $(BEEB_SSD))" \
		-flop2 "$(abspath $(BEEB_SAVE_SSD))" \
		$(MAME_DIR_FLAGS) \
		-autoboot_delay 2 -autoboot_command "*EXEC !BOOT\n" \
		-window -nomaximize -skip_gameinfo

clean:
	rm -rf $(OUTBEEB) $(BEEB_SSD)
	rm -rf cfg nvram inp sta snap diff comments share
