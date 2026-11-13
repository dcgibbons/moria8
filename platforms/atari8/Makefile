# Moria8 Atari 8-Bit Platform Makefile

KICKASS_DIR     ?= ../../tools/kickass
# KICKASS names the jar, as on every port (README: KICKASS=/path/to/KickAss.jar)
KICKASS         ?= $(KICKASS_DIR)/KickAss.jar
KICKASS_JAR     = $(KICKASS)
KICKASS_URL     = https://theweb.dk/KickAssembler/KickAssembler.zip
# kickass_java.sh fails the build on a failed .assert (KickAssembler itself exits 0)
KA              = ../../tools/kickass_java.sh -jar $(KICKASS_JAR)

# Python tools and harnesses must not leave __pycache__ in source directories.
export PYTHONDONTWRITEBYTECODE := 1

ifneq ($(filter clean,$(MAKECMDGOALS)),)
$(filter-out clean,$(MAKECMDGOALS)): | clean
endif

OUT        = ../../build
OUTATARI8  = $(OUT)/atari8
OVL_OUTATARI8 = $(abspath $(OUTATARI8))

KA_FLAGS   = ":OVL_OUT=$(OVL_OUTATARI8)" -afo -symbolfile -vicesymbols -symbolfiledir "$(OVL_OUTATARI8)" -libdir ../../core -libdir . -libdir hal -libdir ../commodore/common -libdir ../commodore/c64 -libdir .. -libdir ../.. -define ATARI8

VERSION_FILE     = ../../version.json
VERSION_INC_TOOL = ../../tools/make_version_include.py
VERSION_INC      = $(OUT)/version_strings.inc
MAIN_SRC         = main.s
BOOT_SRC         = boot.s
TITLE_SRC        = title_data.s

ATARI8_SOURCES := $(shell find . ../commodore/common ../shared ../../core -type f \( -name '*.s' -o -name '*.inc' \) -print)

ATARI8_MAIN_PRG   = $(OUTATARI8)/MORIA8.RES
ATARI8_BOOT_PRG   = $(OUTATARI8)/boot.prg
ATARI8_TITLE_PRG  = $(OUTATARI8)/TITLE.DAT
ATARI8_CATALOG    = $(OUTATARI8)/MONSTER.CAT
ATARI8_BANK_PRG   = $(OUTATARI8)/ATARI.BNK
ATARI8_OVL_PRGS   = $(OUTATARI8)/OVL.STA $(OUTATARI8)/OVL.TWN $(OUTATARI8)/OVL.DTH $(OUTATARI8)/OVL.MDL $(OUTATARI8)/OVL.HLP $(OUTATARI8)/OVL.UI $(OUTATARI8)/OVL.ITM $(OUTATARI8)/OVL.SPL $(OUTATARI8)/OVL.CHS $(OUTATARI8)/OVL.GEN
ATARI8_MAIN_STAMP = $(OUTATARI8)/.main.stamp
ATARI8_ATR        = $(OUT)/moria8-atari8.atr
ATARI8_SAVE_ATR   = $(OUTATARI8)/save-disk.atr

MAME           ?= mame
ATARI8_MACHINE ?= a800xl
ATARI8ROMS     ?=
MAME_DIR   = $(OVL_OUTATARI8)/mame
MAME_DIR_FLAGS = -cfg_directory "$(MAME_DIR)/cfg" \
                 -nvram_directory "$(MAME_DIR)/nvram" \
                 -input_directory "$(MAME_DIR)/inp" \
                 -state_directory "$(MAME_DIR)/sta" \
                 -snapshot_directory "$(MAME_DIR)/snap" \
                 -diff_directory "$(MAME_DIR)/diff" \
                 -comment_directory "$(MAME_DIR)/comments" \
                 -share_directory "$(MAME_DIR)/share"

ATARI8_OVL_PRGS += $(OUTATARI8)/legalui
.PHONY: all build disk run run-130xe test test-memory-contract test-memory-contract-selftest test-runtime test-fast-smoke clean kickass

all: build

build: $(ATARI8_MAIN_PRG) $(ATARI8_BANK_PRG) $(ATARI8_OVL_PRGS) $(ATARI8_BOOT_PRG) $(ATARI8_TITLE_PRG) $(ATARI8_CATALOG)

kickass: $(KICKASS_JAR)
$(KICKASS_JAR):
	@echo "Downloading KickAssembler..."
	@mkdir -p $(KICKASS_DIR)
	@curl -sL "$(KICKASS_URL)" -o $(KICKASS_DIR)/kickass.zip
	@unzip -qo $(KICKASS_DIR)/kickass.zip -d $(KICKASS_DIR)
	@rm -f $(KICKASS_DIR)/kickass.zip

$(VERSION_INC): $(VERSION_FILE) $(VERSION_INC_TOOL)
	@mkdir -p $(OUT)
	python3 "$(VERSION_INC_TOOL)" "$(VERSION_FILE)" "$(VERSION_INC)"

$(ATARI8_MAIN_STAMP): $(ATARI8_SOURCES) $(VERSION_INC) $(KICKASS_JAR)
	@mkdir -p $(OUTATARI8)
	$(KA) $(KA_FLAGS) $(MAIN_SRC) -o $(ATARI8_MAIN_PRG)
	@touch $(ATARI8_MAIN_STAMP)

$(ATARI8_MAIN_PRG) $(ATARI8_BANK_PRG) $(ATARI8_OVL_PRGS) $(OUTATARI8)/main.sym: $(ATARI8_MAIN_STAMP)
	@test -f "$@" || { rm -f "$(ATARI8_MAIN_STAMP)"; $(MAKE) "$(ATARI8_MAIN_STAMP)"; }
	@test -f "$@"

$(ATARI8_BOOT_PRG): $(BOOT_SRC) memory.s $(KICKASS_JAR)
	@mkdir -p $(OUTATARI8)
	$(KA) $(KA_FLAGS) $(BOOT_SRC) -o $(ATARI8_BOOT_PRG)

$(ATARI8_TITLE_PRG): $(TITLE_SRC) $(VERSION_INC) $(KICKASS_JAR)
	@mkdir -p $(OUTATARI8)
	$(KA) $(KA_FLAGS) $(TITLE_SRC) -o $(ATARI8_TITLE_PRG)

# The monster catalog's records (monster_catalog_a8.s), from the committed
# catalog sources.
$(ATARI8_CATALOG): ../../tools/catalog_disk.py monster_catalog_a8.s ../commodore/common/catalog_records.s $(wildcard ../shared/catalog/*.s)
	@mkdir -p $(OUTATARI8)
	python3 ../../tools/catalog_disk.py atari "$@"

disk: $(ATARI8_ATR)

$(ATARI8_ATR): build ../../data/LICENSE ../../data/SOURCE-OFFER ../../tools/make_atr.py
	python3 ../../tools/make_atr.py --build-dir $(OUTATARI8) --root-dir ../.. -o $(ATARI8_ATR)

test-memory-contract-selftest:
	python3 ../../tools/make_atr.py --selftest
	python3 check_memory_contract.py --selftest
	python3 harness_smoke.py --selftest

test-memory-contract: build test-memory-contract-selftest
	python3 check_memory_contract.py --build-dir $(OUTATARI8)

test-runtime: disk
	@if [ -n "$(ATARI8ROMS)" ]; then \
		python3 harness_smoke.py --rompath "$(ATARI8ROMS)" --disk "$(ATARI8_ATR)" --sym "$(OUTATARI8)/main.sym" --all; \
	else \
		echo "WARNING: ATARI8ROMS not set; skipping Atari 8-bit MAME runtime smoke suite"; \
	fi

test-fast-smoke: disk
	@if [ -n "$(ATARI8ROMS)" ]; then \
		python3 harness_smoke.py --rompath "$(ATARI8ROMS)" --disk "$(ATARI8_ATR)" --sym "$(OUTATARI8)/main.sym" --fast-smoke; \
	else \
		echo "WARNING: ATARI8ROMS not set; skipping Atari 8-bit MAME fast smoke suite"; \
	fi

test: test-memory-contract test-runtime

run: disk
	@if [ -z "$(ATARI8ROMS)" ]; then \
		echo "ERROR: set ATARI8ROMS=/path/to/atari8/roms to launch MAME $(ATARI8_MACHINE)"; \
		exit 1; \
	fi
	@mkdir -p "$(MAME_DIR)/cfg" "$(MAME_DIR)/nvram" "$(MAME_DIR)/inp" "$(MAME_DIR)/sta" "$(MAME_DIR)/snap" "$(MAME_DIR)/diff" "$(MAME_DIR)/comments" "$(MAME_DIR)/share"
	@test -f "$(ATARI8_SAVE_ATR)" || python3 ../../tools/make_atr.py --blank-disk -o "$(ATARI8_SAVE_ATR)"
	$(MAME) $(ATARI8_MACHINE) -rompath "$(ATARI8ROMS)" \
		-flop1 "$(abspath $(ATARI8_ATR))" \
		-flop2 "$(abspath $(ATARI8_SAVE_ATR))" \
		$(MAME_DIR_FLAGS) \
		-window -nomaximize -skip_gameinfo

run-130xe:
	$(MAKE) run ATARI8_MACHINE=a130xe

clean:
	rm -rf $(OUTATARI8) $(ATARI8_ATR)
	rm -rf cfg nvram inp sta snap diff comments share
