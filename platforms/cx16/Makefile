# Commander X16 Makefile — moria8 (65C02 / VERA / x16emu)
#
# Primary targets:
#   make build        Assemble all payloads into ../../build/cx16
#   make disk         Build the shipping bundle ../../build/moria8-cx16.zip
#   make run          Launch MORIA8.PRG in x16emu
#   make test-memory-contract[-selftest]  Static placement gate
#   make test-runtime Headless x16emu -testbench smoke suite

KICKASS_DIR ?= ../../tools/kickass
KICKASS     ?= $(KICKASS_DIR)/KickAss.jar
KICKASS_URL  = https://theweb.dk/KickAssembler/KickAssembler.zip
ifeq ($(filter /%,$(KICKASS)),)
KICKASS_RESOLVED = $(CURDIR)/$(KICKASS)
else
KICKASS_RESOLVED = $(KICKASS)
endif
JAVA        ?= ../../tools/kickass_java.sh

# Python tools and harnesses must not leave __pycache__ in source directories.
export PYTHONDONTWRITEBYTECODE := 1

ifneq ($(filter clean,$(MAKECMDGOALS)),)
$(filter-out clean,$(MAKECMDGOALS)): | clean
endif

X16EMU      ?= x16emu
X16ROM      ?=
ifneq ($(strip $(X16ROM)),)
X16ROM_FLAG  = -rom "$(X16ROM)"
endif

LICENSE_FILE  = ../../data/LICENSE
SOURCE_OFFER  = ../../data/SOURCE-OFFER

BUILD       ?= ../../build
OUTCX16      = $(BUILD)/cx16
OVL_OUTCX16  = $(abspath $(OUTCX16))
CARTCX16_OUT = $(abspath $(BUILD)/cx16-cart)

KA_COMMON_FLAGS = -showmem -libdir ../../core -libdir . -libdir hal -libdir ../commodore/common -define CX16 -afo
KA_FLAGS        = $(KA_COMMON_FLAGS) -symbolfiledir "$(OVL_OUTCX16)"
KA_CART_FLAGS   = $(KA_COMMON_FLAGS) -define CX16_CARTRIDGE -symbolfiledir "$(CARTCX16_OUT)"
VERSION_FILE = ../../version.json
VERSION_INC_TOOL = ../../tools/make_version_include.py
VERSION_INC  = $(BUILD)/version_strings.inc
GEN_TRAMPOLINES_TOOL = ../../tools/gen_trampolines.py
TRAMPOLINE_MANIFEST  = ../../tools/trampoline_manifest.py
TRAMPOLINES_INC      = $(BUILD)/trampolines/cx16_trampolines.inc

CX16_MAIN_SRC  = main.s
CX16_TITLE_SRC = title_data_cx16.s
CX16_TIER_DIR  = creature_data
CX16_SOURCES   = $(wildcard *.s hal/*.s creature_data/*.s ../../core/*.s ../../platforms/shared/*.s ../../platforms/shared/catalog/*.s ../../platforms/shared/item_catalog/*.s ../../platforms/commodore/common/*.s) \
                 ../commodore/c128/ui_help_data_80.s

CX16_MAIN_PRG  = $(OUTCX16)/MORIA8.PRG
CX16_AUX_PRG   = $(OUTCX16)/CX16.AUXDATA
CX16_HUFF_PRG  = $(OUTCX16)/CX16.HUFFDATA
CX16_OVL_PRGS  = $(OUTCX16)/OVL.START $(OUTCX16)/OVL.TOWN $(OUTCX16)/OVL.DEATH $(OUTCX16)/OVL.MODAL \
                 $(OUTCX16)/OVL.GEN $(OUTCX16)/OVL.HELP $(OUTCX16)/OVL.UI $(OUTCX16)/OVL.ITEMS \
                 $(OUTCX16)/OVL.SPELL $(OUTCX16)/OVL.CHEST $(OUTCX16)/OVL.HOME \
                 $(OUTCX16)/OVL.STORAGE $(OUTCX16)/OVL.TITLE
# The monster catalog (Banks 22-23) replaced the tiers on this port; the tier
# rules below remain for builds without HAL_PLATFORM_MONSTER_CATALOG.
CX16_CATALOG_PRGS = $(OUTCX16)/MONSTER.CAT
CX16_MONSTER_EXT_PRG = $(OUTCX16)/MONSTER.EXT
CX16_ITEM_CAT_PRG = $(OUTCX16)/ITEM.CAT
CX16_TIER_PRGS = $(OUTCX16)/MONSTER.DB.1 $(OUTCX16)/MONSTER.DB.2 $(OUTCX16)/MONSTER.DB.3 $(OUTCX16)/MONSTER.DB.4
CX16_TITLE_PRG = $(OUTCX16)/TITLE
CX16_LICENSE   = $(OUTCX16)/LICENSE
CX16_SOURCE_OFFER = $(OUTCX16)/SOURCE-OFFER

CX16_ZIP_IMAGE = $(BUILD)/moria8-cx16.zip
CX16_MAIN_STAMP = $(OUTCX16)/.main.stamp

CX16_CART_IMAGE    = $(BUILD)/moria8-cx16.crt
CX16_CART_BIN      = $(CARTCX16_OUT)/moria8-cx16.bin
CX16_CART_MANIFEST = $(CARTCX16_OUT)/moria8-cx16.json
CX16_CART_MAIN_PRG = $(CARTCX16_OUT)/MORIA8.PRG
CX16_CART_BOOT_BIN = $(CARTCX16_OUT)/bootrom.bin
CX16_CART_STAMP    = $(CARTCX16_OUT)/.main.stamp
CX16_CART_BOOT_STAMP = $(CARTCX16_OUT)/.boot.stamp
CX16_CART_TITLE_PRG = $(CARTCX16_OUT)/TITLE
CX16_CART_MONSTER_EXT_PRG = $(CARTCX16_OUT)/MONSTER.EXT
CX16_CART_ITEM_CAT_PRG = $(CARTCX16_OUT)/ITEM.CAT
CX16_CART_LIVE_TEST_PRG = $(CARTCX16_OUT)/cartridge_test_live.prg
CX16_CART_OVL_NAMES = CX16.AUXDATA CX16.HUFFDATA MONSTER.CAT LEGALUI \
                      OVL.START OVL.TOWN OVL.DEATH OVL.MODAL \
                      OVL.GEN OVL.HELP OVL.UI OVL.ITEMS \
                      OVL.SPELL OVL.CHEST OVL.HOME OVL.STORAGE OVL.TITLE
CX16_CART_PRGS     = $(CX16_CART_MAIN_PRG) $(addprefix $(CARTCX16_OUT)/,$(CX16_CART_OVL_NAMES))

CX16_OVL_PRGS += $(OUTCX16)/LEGALUI
.PHONY: all build disk cartridge run run-cart test-memory-contract test-memory-contract-selftest test-runtime test-cartridge clean ensure-kickass kickass

all: build

build: $(CX16_MAIN_PRG) $(CX16_AUX_PRG) $(CX16_HUFF_PRG) $(CX16_OVL_PRGS) $(CX16_CATALOG_PRGS) $(CX16_MONSTER_EXT_PRG) $(CX16_ITEM_CAT_PRG) $(CX16_TITLE_PRG) $(CX16_LICENSE) $(CX16_SOURCE_OFFER) $(CX16_CART_IMAGE) $(CX16_CART_BIN) $(CX16_CART_MANIFEST)
	@mkdir -p "$(OUTCX16)"

disk: $(CX16_ZIP_IMAGE) $(CX16_CART_IMAGE) $(CX16_CART_BIN) $(CX16_CART_MANIFEST)

cartridge: $(CX16_CART_IMAGE) $(CX16_CART_BIN) $(CX16_CART_MANIFEST)

run: build
	"$(X16EMU)" $(X16ROM_FLAG) -fsroot "$(OVL_OUTCX16)" -prg "$(OVL_OUTCX16)/MORIA8.PRG" -run

run-cart: cartridge
	"$(X16EMU)" $(X16ROM_FLAG) -cart "$(abspath $(CX16_CART_IMAGE))"

test-memory-contract: build
	python3 -B check_memory_contract.py
	python3 -B check_memory_contract.py --build-dir "$(CARTCX16_OUT)"
	python3 -B ../../tools/check_cx16_cart.py --crt "$(CX16_CART_IMAGE)" --bin "$(CX16_CART_BIN)" --manifest "$(CX16_CART_MANIFEST)" --build-dir "$(CARTCX16_OUT)" --data-dir ../../data

test-memory-contract-selftest:
	python3 -B check_memory_contract.py --selftest
	python3 -B ../../tools/check_cx16_cart.py --selftest
	python3 -B test_cartridge.py --selftest

test-cartridge: build $(CX16_CART_LIVE_TEST_PRG) test-memory-contract
	@if ! command -v "$(X16EMU)" >/dev/null 2>&1 && [ ! -x "$(X16EMU)" ]; then \
		echo "WARNING: x16emu not found ($(X16EMU)) - skipping CX16 cartridge runtime harness."; \
	else \
		X16EMU="$(X16EMU)" X16ROM="$(X16ROM)" python3 -B test_cartridge.py; \
	fi

test-runtime: build test-memory-contract
	@if ! command -v "$(X16EMU)" >/dev/null 2>&1 && [ ! -x "$(X16EMU)" ]; then \
		echo "WARNING: x16emu not found ($(X16EMU)) - skipping CX16 runtime harness."; \
	else \
		failed=""; for s in $$(python3 -B -c "import sys; sys.path.insert(0,'.'); import harness_smoke as h; print(' '.join(h.SCENARIOS))"); do \
			echo "=== cx16 scenario: $$s ==="; \
			X16EMU="$(X16EMU)" X16ROM="$(X16ROM)" python3 -B harness_smoke.py "$$s" || failed="$$failed $$s"; \
		done; \
		if [ -n "$$failed" ]; then echo "FAILED cx16 scenarios:$$failed"; exit 1; fi; \
	fi

clean:
	rm -rf "$(OUTCX16)" "$(CARTCX16_OUT)" "$(CX16_ZIP_IMAGE)" "$(CX16_CART_IMAGE)" "$(BUILD)/test/cx16-cartridge" __pycache__

ensure-kickass:
	@test -f "$(KICKASS_RESOLVED)" || $(MAKE) --no-print-directory kickass

kickass:
	@mkdir -p "$(KICKASS_DIR)"
	@echo "Downloading Kick Assembler..."
	@curl -sL "$(KICKASS_URL)" -o "$(KICKASS_DIR)/kickass.zip"
	@unzip -o "$(KICKASS_DIR)/kickass.zip" -d "$(KICKASS_DIR)"
	@rm -f "$(KICKASS_DIR)/kickass.zip"

$(VERSION_INC): $(VERSION_FILE) $(VERSION_INC_TOOL) | $(BUILD)
	python3 "$(VERSION_INC_TOOL)" "$(VERSION_FILE)" "$(VERSION_INC)"

$(TRAMPOLINES_INC): $(GEN_TRAMPOLINES_TOOL) $(TRAMPOLINE_MANIFEST) | $(BUILD)
	python3 -B "$(GEN_TRAMPOLINES_TOOL)" --port cx16 --output "$@"

$(BUILD):
	mkdir -p "$(BUILD)"

$(OUTCX16):
	mkdir -p "$(OUTCX16)"

$(CX16_MAIN_STAMP) $(CX16_MAIN_PRG) $(CX16_AUX_PRG) $(CX16_HUFF_PRG) $(CX16_OVL_PRGS) $(CX16_CATALOG_PRGS) $(OUTCX16)/main.sym &: $(CX16_SOURCES) $(VERSION_INC) $(TRAMPOLINES_INC) | ensure-kickass $(OUTCX16)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" ":OVL_OUT=$(OVL_OUTCX16)" "$(CX16_MAIN_SRC)" $(KA_FLAGS) -symbolfile -o "$(CX16_MAIN_PRG)"
	touch "$(CX16_MAIN_STAMP)"

$(OUTCX16)/MONSTER.DB.1: $(CX16_TIER_DIR)/tier1_prg.s ../commodore/c64/creature_data/tier1.s | ensure-kickass $(OUTCX16)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" "$(CX16_TIER_DIR)/tier1_prg.s" -symbolfiledir "$(OVL_OUTCX16)" -o "$@"

$(OUTCX16)/MONSTER.DB.2: $(CX16_TIER_DIR)/tier2_prg.s ../commodore/c64/creature_data/tier2.s | ensure-kickass $(OUTCX16)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" "$(CX16_TIER_DIR)/tier2_prg.s" -symbolfiledir "$(OVL_OUTCX16)" -o "$@"

$(OUTCX16)/MONSTER.DB.3: $(CX16_TIER_DIR)/tier3_prg.s ../commodore/c64/creature_data/tier3.s | ensure-kickass $(OUTCX16)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" "$(CX16_TIER_DIR)/tier3_prg.s" -symbolfiledir "$(OVL_OUTCX16)" -o "$@"

$(OUTCX16)/MONSTER.DB.4: $(CX16_TIER_DIR)/tier4_prg.s ../commodore/c64/creature_data/tier4.s | ensure-kickass $(OUTCX16)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" "$(CX16_TIER_DIR)/tier4_prg.s" -symbolfiledir "$(OVL_OUTCX16)" -o "$@"

$(CX16_TITLE_PRG): $(CX16_TITLE_SRC) $(VERSION_INC) | ensure-kickass $(OUTCX16)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" "$(CX16_TITLE_SRC)" -symbolfiledir "$(OVL_OUTCX16)" -o "$@"

$(CX16_LICENSE): $(LICENSE_FILE) | $(OUTCX16)
	LC_ALL=C tr '\012' '\015' < "$<" > "$@"

$(CX16_SOURCE_OFFER): $(SOURCE_OFFER) | $(OUTCX16)
	LC_ALL=C tr '\012' '\015' < "$<" > "$@"

$(CX16_MONSTER_EXT_PRG): ../../platforms/shared/catalog/monster_catalog_spec.json ../../tools/build_catalog.py | $(OUTCX16)
	python3 -B ../../tools/build_catalog.py ext-rows --prg-addr 0xa000 --out "$@"

$(CX16_CART_MONSTER_EXT_PRG): ../../platforms/shared/catalog/monster_catalog_spec.json ../../tools/build_catalog.py | $(CARTCX16_OUT)
	python3 -B ../../tools/build_catalog.py ext-rows --prg-addr 0xa000 --out "$@"

$(CX16_ITEM_CAT_PRG): ../../platforms/shared/item_catalog/item_cat_data.s ../../platforms/shared/item_catalog/item_cat_layout.s ../../tools/catalog_disk.py | $(OUTCX16)
	python3 -B -c "import sys; from pathlib import Path; sys.path.insert(0, '../../tools'); import catalog_disk; p = Path('$@'); p.write_bytes(b'\x00\xa0' + catalog_disk.item_catalog_bytes())"

$(CX16_CART_ITEM_CAT_PRG): ../../platforms/shared/item_catalog/item_cat_data.s ../../platforms/shared/item_catalog/item_cat_layout.s ../../tools/catalog_disk.py | $(CARTCX16_OUT)
	python3 -B -c "import sys; from pathlib import Path; sys.path.insert(0, '../../tools'); import catalog_disk; p = Path('$@'); p.write_bytes(b'\x00\xa0' + catalog_disk.item_catalog_bytes())"

$(CX16_ZIP_IMAGE): $(CX16_MAIN_PRG) $(CX16_AUX_PRG) $(CX16_HUFF_PRG) $(CX16_OVL_PRGS) $(CX16_CATALOG_PRGS) $(CX16_MONSTER_EXT_PRG) $(CX16_ITEM_CAT_PRG) $(CX16_TITLE_PRG) $(CX16_LICENSE) $(CX16_SOURCE_OFFER)
	rm -f "$@"
	cd "$(OUTCX16)" && zip -q "$(abspath $(CX16_ZIP_IMAGE))" \
		MORIA8.PRG CX16.AUXDATA CX16.HUFFDATA \
		OVL.START OVL.TOWN OVL.DEATH OVL.MODAL OVL.GEN OVL.HELP \
		OVL.UI OVL.ITEMS OVL.SPELL OVL.CHEST OVL.HOME OVL.STORAGE OVL.TITLE \
		MONSTER.CAT MONSTER.EXT ITEM.CAT \
		TITLE LICENSE SOURCE-OFFER LEGALUI

$(CARTCX16_OUT):
	mkdir -p "$(CARTCX16_OUT)"

$(CX16_CART_STAMP) $(CX16_CART_PRGS) $(CARTCX16_OUT)/main.sym &: $(CX16_SOURCES) $(VERSION_INC) $(TRAMPOLINES_INC) | ensure-kickass $(CARTCX16_OUT)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" ":OVL_OUT=$(CARTCX16_OUT)" "$(CX16_MAIN_SRC)" $(KA_CART_FLAGS) -symbolfile -o "$(CX16_CART_MAIN_PRG)"
	touch "$(CX16_CART_STAMP)"

$(CX16_CART_BOOT_STAMP) $(CX16_CART_BOOT_BIN) $(CARTCX16_OUT)/cartridge_boot.sym &: cartridge_boot.s cartridge_contract.s | ensure-kickass $(CARTCX16_OUT)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" ":CART_OUT=$(CARTCX16_OUT)" cartridge_boot.s -afo -showmem -symbolfiledir "$(CARTCX16_OUT)" -symbolfile -o "$(CARTCX16_OUT)/boot-unused.prg"
	rm -f "$(CARTCX16_OUT)/boot-unused.prg"
	touch "$(CX16_CART_BOOT_STAMP)"

$(CX16_CART_TITLE_PRG): $(CX16_TITLE_SRC) $(VERSION_INC) | ensure-kickass $(CARTCX16_OUT)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" "$(CX16_TITLE_SRC)" -symbolfiledir "$(CARTCX16_OUT)" -o "$@"

$(CX16_CART_LIVE_TEST_PRG): cartridge_test_live.s $(CARTCX16_OUT)/main.sym | ensure-kickass $(CARTCX16_OUT)
	cp "$(CARTCX16_OUT)/main.sym" "$(CARTCX16_OUT)/cartridge_product_symbols.inc"
	$(JAVA) -jar "$(KICKASS_RESOLVED)" cartridge_test_live.s -libdir "$(CARTCX16_OUT)" -symbolfiledir "$(CARTCX16_OUT)" -symbolfile -o "$@"

$(CX16_CART_IMAGE) $(CX16_CART_BIN) $(CX16_CART_MANIFEST) &: $(CX16_CART_PRGS) $(CARTCX16_OUT)/main.sym $(CX16_CART_BOOT_BIN) $(CARTCX16_OUT)/cartridge_boot.sym $(CX16_CART_TITLE_PRG) $(CX16_CART_MONSTER_EXT_PRG) $(CX16_CART_ITEM_CAT_PRG) $(LICENSE_FILE) $(SOURCE_OFFER) $(VERSION_FILE) ../../tools/make_cx16_cart.py
	python3 -B ../../tools/make_cx16_cart.py \
		--build-dir "$(CARTCX16_OUT)" \
		--data-dir ../../data \
		--out-crt "$(CX16_CART_IMAGE)" \
		--out-bin "$(CX16_CART_BIN)" \
		--out-manifest "$(CX16_CART_MANIFEST)" \
		--version-file "$(VERSION_FILE)"
