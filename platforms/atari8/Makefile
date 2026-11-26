# Moria8 Atari 8-Bit Platform Makefile

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

OUT        ?= ../../build
OUTATARI8  = $(OUT)/atari8
OUTATARI8_CART = $(OUT)/atari8-cart
OVL_OUTATARI8 = $(abspath $(OUTATARI8))
OVL_OUTATARI8_CART = $(abspath $(OUTATARI8_CART))

KA_FLAGS   = ":OVL_OUT=$(OVL_OUTATARI8)" -afo -symbolfile -vicesymbols -symbolfiledir "$(OVL_OUTATARI8)" -libdir ../../core/6502 -libdir . -libdir hal -libdir ../commodore/common -libdir ../commodore/c64 -libdir .. -libdir ../.. -define ATARI8
KA_CART_FLAGS = ":OVL_OUT=$(OVL_OUTATARI8_CART)" -afo -symbolfile -vicesymbols -symbolfiledir "$(OVL_OUTATARI8_CART)" -libdir ../../core/6502 -libdir . -libdir hal -libdir ../commodore/common -libdir ../commodore/c64 -libdir .. -libdir ../.. -define ATARI8 -define ATARI8_CARTRIDGE

VERSION_FILE         = ../../version.json
VERSION_INC_TOOL     = ../../tools/make_version_include.py
VERSION_INFO_TOOL    = ../../tools/version_info.py
VERSION_STAMP        = $(OUT)/.version.stamp
VERSION_INC          = $(OUT)/version_strings.inc
ifeq ($(filter clean,$(MAKECMDGOALS)),)
_VERSION_STAMP_ERR := $(shell mkdir -p "$(OUT)" && python3 -B "$(VERSION_INFO_TOOL)" --version-file "$(VERSION_FILE)" --write-stamp "$(VERSION_STAMP)" 2>&1)
ifneq ($(strip $(_VERSION_STAMP_ERR)),)
$(error $(_VERSION_STAMP_ERR))
endif
endif
TRAMPOLINES_INC_TOOL = ../../tools/gen_trampolines.py
TRAMPOLINE_MANIFEST  = ../../tools/trampoline_manifest.py
TRAMPOLINES_INC      = $(OUT)/trampolines/atari8_trampolines.inc
MAIN_SRC             = main.s
BOOT_SRC         = boot.s
TITLE_SRC        = title_data.s

ATARI8_SOURCES := $(shell find . ../commodore/common ../shared ../../core/6502 -type f \( -name '*.s' -o -name '*.inc' \) -print)

ATARI8_MAIN_PRG   = $(OUTATARI8)/MORIA8.RES
ATARI8_MAIN_PKB   = $(OUTATARI8)/MORIA8.PKB
ATARI8_BOOT_PRG   = $(OUTATARI8)/boot.prg
ATARI8_TITLE_PRG  = $(OUTATARI8)/TITLE.DAT
ATARI8_CATALOG    = $(OUTATARI8)/MONSTER.CAT
ATARI8_ITEM_CAT   = $(OUTATARI8)/ITEM.CAT
ATARI8_BANK_PRG   = $(OUTATARI8)/ATARI.BNK
ATARI8_OVL_PRGS   = $(OUTATARI8)/OVL.STA $(OUTATARI8)/OVL.TWN $(OUTATARI8)/OVL.DTH $(OUTATARI8)/OVL.MDL $(OUTATARI8)/OVL.HLP $(OUTATARI8)/OVL.UI $(OUTATARI8)/OVL.ITM $(OUTATARI8)/OVL.SPL $(OUTATARI8)/OVL.CHS $(OUTATARI8)/OVL.GEN $(OUTATARI8)/OVL.HOM $(OUTATARI8)/OVL.STO $(OUTATARI8)/OVL.TTL
ATARI8_MAIN_STAMP = $(OUTATARI8)/.main.stamp
ATARI8_ATR        = $(OUT)/moria8-atari8.atr
ATARI8_SAVE_ATR   = $(OUTATARI8)/save-disk.atr

ATARI8_CART_MAIN_PRG  = $(OUTATARI8_CART)/MORIA8.RES
ATARI8_CART_STAMP     = $(OUTATARI8_CART)/.cart.stamp
ATARI8_CART_BOOT_BIN  = $(OUTATARI8_CART)/bank0.bin
ATARI8_CART_TITLE_PRG = $(OUTATARI8_CART)/TITLE.DAT
ATARI8_CART_OVL_PRGS  = $(OUTATARI8_CART)/OVL.STA $(OUTATARI8_CART)/OVL.TWN $(OUTATARI8_CART)/OVL.DTH $(OUTATARI8_CART)/OVL.MDL $(OUTATARI8_CART)/OVL.HLP $(OUTATARI8_CART)/OVL.UI $(OUTATARI8_CART)/OVL.ITM $(OUTATARI8_CART)/OVL.SPL $(OUTATARI8_CART)/OVL.CHS $(OUTATARI8_CART)/OVL.GEN $(OUTATARI8_CART)/OVL.HOM $(OUTATARI8_CART)/OVL.STO $(OUTATARI8_CART)/OVL.TTL $(OUTATARI8_CART)/legalui
ATARI8_CART_SYMS_INC  = $(OUTATARI8_CART)/cartridge_product_symbols.inc
ATARI8_CAT_TEST_PRG   = $(OUTATARI8_CART)/catalog-test.prg
ATARI8_CAR            = $(OUT)/moria8-atari8.car

MAME           ?= mame
ATARI8_MACHINE ?= a800xl
ATARI8ROMS     ?=
REQUIRE_ALL_ROMS ?= 0
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
.PHONY: all build disk cartridge run run-130xe run-cart run-cart-130xe test test-memory-contract test-memory-contract-selftest test-runtime test-fast-smoke test-cartridge clean ensure-kickass kickass

all: build

build: $(ATARI8_MAIN_PRG) $(ATARI8_BANK_PRG) $(ATARI8_OVL_PRGS) $(ATARI8_BOOT_PRG) $(ATARI8_TITLE_PRG) $(ATARI8_CATALOG) $(ATARI8_ITEM_CAT) $(ATARI8_CAR) $(ATARI8_CAT_TEST_PRG)

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

$(TRAMPOLINES_INC): $(TRAMPOLINES_INC_TOOL) $(TRAMPOLINE_MANIFEST)
	@mkdir -p $(dir $@)
	python3 -B "$(TRAMPOLINES_INC_TOOL)" --port atari8 --output "$@"

$(ATARI8_MAIN_STAMP): $(ATARI8_SOURCES) $(VERSION_INC) $(TRAMPOLINES_INC) $(KICKASS_JAR)
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

# The monster catalog's 57-byte records (monster_catalog_a8.s + build_catalog_a8.py),
# combining 49B base records + 8B Phase 5 extended records (2/sector = 140 sectors).
$(ATARI8_CATALOG): build_catalog_a8.py ../../tools/catalog_disk.py monster_catalog_a8.s ../commodore/common/catalog_records.s $(wildcard ../shared/catalog/*.s)
	@mkdir -p $(OUTATARI8)
	python3 -B build_catalog_a8.py "$@"

$(ATARI8_ITEM_CAT): ../../tools/catalog_disk.py item_catalog_a8.s $(wildcard ../shared/item_catalog/*.s)
	@mkdir -p $(OUTATARI8)
	python3 -B ../../tools/catalog_disk.py item-atari "$@"

disk: $(ATARI8_ATR) $(ATARI8_CAR)

$(ATARI8_MAIN_PKB): $(ATARI8_MAIN_PRG) ../../tools/build_catalog.py
	head -c 2 "$(ATARI8_MAIN_PRG)" > "$@"
	python3 -B ../../tools/build_catalog.py packbits --strip-prg --in "$(ATARI8_MAIN_PRG)" --out "$@.body"
	cat "$@.body" >> "$@"
	rm -f "$@.body"

$(ATARI8_ATR): $(ATARI8_MAIN_PRG) $(ATARI8_MAIN_PKB) $(ATARI8_BANK_PRG) $(ATARI8_OVL_PRGS) $(ATARI8_BOOT_PRG) $(ATARI8_TITLE_PRG) $(ATARI8_CATALOG) $(ATARI8_ITEM_CAT) ../../data/LICENSE ../../data/SOURCE-OFFER ../../tools/make_atr.py ../../tools/build_catalog.py
	python3 -B ../../tools/make_atr.py --build-dir $(OUTATARI8) --root-dir ../.. -o $(ATARI8_ATR)

$(ATARI8_CART_STAMP): $(ATARI8_SOURCES) $(VERSION_INC) $(TRAMPOLINES_INC) $(KICKASS_JAR)
	@mkdir -p $(OUTATARI8_CART)
	$(KA) $(KA_CART_FLAGS) $(MAIN_SRC) -o $(ATARI8_CART_MAIN_PRG)
	cp "$(OUTATARI8_CART)/main.sym" "$(ATARI8_CART_SYMS_INC)"
	@touch $(ATARI8_CART_STAMP)

$(ATARI8_CART_MAIN_PRG) $(OUTATARI8_CART)/ATARI.BNK $(ATARI8_CART_OVL_PRGS) $(OUTATARI8_CART)/main.sym $(ATARI8_CART_SYMS_INC): $(ATARI8_CART_STAMP)
	@test -f "$@" || { rm -f "$(ATARI8_CART_STAMP)"; $(MAKE) "$(ATARI8_CART_STAMP)"; }
	@test -f "$@"

$(ATARI8_CART_BOOT_BIN): cartridge_boot.s cartridge_contract.s memory.s $(KICKASS_JAR)
	@mkdir -p $(OUTATARI8_CART)
	$(KA) ":CART_OUT=$(OVL_OUTATARI8_CART)" -afo -symbolfiledir "$(OVL_OUTATARI8_CART)" -libdir . -libdir ../../core/6502 cartridge_boot.s -o "$(OUTATARI8_CART)/cartridge_boot.prg"

$(ATARI8_CART_TITLE_PRG): $(TITLE_SRC) $(VERSION_INC) $(KICKASS_JAR)
	@mkdir -p $(OUTATARI8_CART)
	$(KA) $(KA_CART_FLAGS) $(TITLE_SRC) -o $(ATARI8_CART_TITLE_PRG)

$(ATARI8_CAT_TEST_PRG): $(ATARI8_CART_SYMS_INC) cartridge_test_catalog.s cartridge_contract.s ../commodore/common/catalog_records.s $(KICKASS_JAR)
	@mkdir -p $(OUTATARI8_CART)
	$(KA) -afo -symbolfiledir "$(OVL_OUTATARI8_CART)" -libdir "$(OVL_OUTATARI8_CART)" -libdir . -libdir ../commodore/common -libdir ../../core/6502 cartridge_test_catalog.s -o $(ATARI8_CAT_TEST_PRG)

cartridge: $(ATARI8_CAR)

$(ATARI8_CAR): $(ATARI8_CART_STAMP) $(ATARI8_CART_BOOT_BIN) $(ATARI8_CART_TITLE_PRG) ../../data/LICENSE ../../data/SOURCE-OFFER ../../tools/make_atari8_car.py ../../tools/check_atari8_car.py ../../tools/catalog_disk.py ../../tools/build_catalog.py $(wildcard ../shared/catalog/*.s) $(wildcard ../shared/item_catalog/*.s)
	python3 -B ../../tools/make_atari8_car.py $(OUTATARI8_CART) $(ATARI8_CAR)
	python3 -B ../../tools/check_atari8_car.py $(ATARI8_CAR) $(OUTATARI8_CART)

test-memory-contract-selftest:
	python3 -B build_catalog_a8.py --selftest
	python3 -B ../../tools/make_atr.py --selftest
	python3 -B check_memory_contract.py --selftest
	python3 -B harness_smoke.py --selftest
	python3 -B ../../tools/check_atari8_car.py --selftest
	python3 -B test_cartridge.py --selftest

test-memory-contract: build test-memory-contract-selftest
	python3 -B check_memory_contract.py --build-dir $(OUTATARI8)
	python3 -B ../../tools/check_atari8_car.py $(ATARI8_CAR) $(OUTATARI8_CART)

test-runtime: disk
	@if [ -n "$(ATARI8ROMS)" ]; then \
		python3 -B harness_smoke.py --rompath "$(ATARI8ROMS)" --disk "$(ATARI8_ATR)" --sym "$(OUTATARI8)/main.sym" --all; \
	elif [ "$(strip $(REQUIRE_ALL_ROMS))" = "1" ]; then \
		echo "ERROR: ATARI8ROMS not set and REQUIRE_ALL_ROMS=1" >&2; exit 1; \
	else \
		echo "WARNING: ATARI8ROMS not set; skipping Atari 8-bit MAME runtime smoke suite"; \
	fi

test-fast-smoke: disk
	@if [ -n "$(ATARI8ROMS)" ]; then \
		python3 -B harness_smoke.py --rompath "$(ATARI8ROMS)" --disk "$(ATARI8_ATR)" --sym "$(OUTATARI8)/main.sym" --fast-smoke; \
	elif [ "$(strip $(REQUIRE_ALL_ROMS))" = "1" ]; then \
		echo "ERROR: ATARI8ROMS not set and REQUIRE_ALL_ROMS=1" >&2; exit 1; \
	else \
		echo "WARNING: ATARI8ROMS not set; skipping Atari 8-bit MAME fast smoke suite"; \
	fi

test-cartridge: cartridge disk $(ATARI8_CAT_TEST_PRG)
	@if [ -n "$(ATARI8ROMS)" ]; then \
		python3 -B test_cartridge.py --rompath "$(ATARI8ROMS)" --car "$(ATARI8_CAR)" --sym "$(OUTATARI8_CART)/main.sym" --catalog-test "$(ATARI8_CAT_TEST_PRG)" --disk "$(ATARI8_ATR)" --disk-sym "$(OUTATARI8)/main.sym" --mame "$(MAME)"; \
	elif [ "$(strip $(REQUIRE_ALL_ROMS))" = "1" ]; then \
		echo "ERROR: ATARI8ROMS not set and REQUIRE_ALL_ROMS=1" >&2; exit 1; \
	else \
		echo "WARNING: ATARI8ROMS not set; skipping Atari 8-bit MAME cartridge suite"; \
	fi

test: test-memory-contract test-runtime test-cartridge

run: disk
	@if [ -z "$(ATARI8ROMS)" ]; then \
		echo "ERROR: set ATARI8ROMS=/path/to/atari8/roms to launch MAME $(ATARI8_MACHINE)"; \
		exit 1; \
	fi
	@mkdir -p "$(MAME_DIR)/cfg" "$(MAME_DIR)/nvram" "$(MAME_DIR)/inp" "$(MAME_DIR)/sta" "$(MAME_DIR)/snap" "$(MAME_DIR)/diff" "$(MAME_DIR)/comments" "$(MAME_DIR)/share"
	@test -f "$(ATARI8_SAVE_ATR)" || python3 -B ../../tools/make_atr.py --blank-disk -o "$(ATARI8_SAVE_ATR)"
	$(MAME) $(ATARI8_MACHINE) -rompath "$(ATARI8ROMS)" \
		-flop1 "$(abspath $(ATARI8_ATR))" \
		-flop2 "$(abspath $(ATARI8_SAVE_ATR))" \
		$(MAME_DIR_FLAGS) \
		-window -nomaximize -skip_gameinfo

run-130xe:
	$(MAKE) run ATARI8_MACHINE=a130xe

run-cart: cartridge
	@if [ -z "$(ATARI8ROMS)" ]; then \
		echo "ERROR: set ATARI8ROMS=/path/to/atari8/roms to launch MAME $(ATARI8_MACHINE)"; \
		exit 1; \
	fi
	@mkdir -p "$(MAME_DIR)/cfg" "$(MAME_DIR)/nvram" "$(MAME_DIR)/inp" "$(MAME_DIR)/sta" "$(MAME_DIR)/snap" "$(MAME_DIR)/diff" "$(MAME_DIR)/comments" "$(MAME_DIR)/share"
	@test -f "$(ATARI8_SAVE_ATR)" || python3 -B ../../tools/make_atr.py --blank-disk -o "$(ATARI8_SAVE_ATR)"
	$(MAME) $(ATARI8_MACHINE) -rompath "$(ATARI8ROMS)" \
		-cart1 "$(abspath $(ATARI8_CAR))" \
		-flop1 "$(abspath $(ATARI8_SAVE_ATR))" \
		$(MAME_DIR_FLAGS) \
		-window -nomaximize -skip_gameinfo

run-cart-130xe:
	$(MAKE) run-cart ATARI8_MACHINE=a130xe

clean:
	rm -rf $(OUTATARI8) $(OUTATARI8_CART) $(ATARI8_ATR) $(ATARI8_CAR) $(OUT)/test/atari8-cartridge
	rm -rf cfg nvram inp sta snap diff comments share
