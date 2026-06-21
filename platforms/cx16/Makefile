# Commander X16 Makefile
#
# First milestone:
#   make buildcx16       Build the boot-to-title PRG
#   make runcx16         Launch the PRG under x16emu
#   make testcx16-smoke  Verify the PRG builds and x16emu is discoverable
#   make testcx16-runtime
#                         Run x16emu testbench smoke checks
#   make testcx16-shared-link
#                         Link-only probe for guarded shared-gameplay imports
#   make testcx16-memory-contract
#                         Validate CX16 PRG/symbol memory placement contracts
#   make testcx16-memory-contract-selftest
#                         Unit-test the CX16 memory contract checker
#   make testcx16        Run all current CX16 checks

KICKASS_DIR ?= ../../tools/kickass
KICKASS     ?= $(KICKASS_DIR)/KickAss.jar
KICKASS_URL  = https://theweb.dk/KickAssembler/KickAssembler.zip
JAVA        ?= java
X16EMU      ?= x16emu
X16_ROM     ?=
BUILD       ?= ../../build
OUT         ?= $(BUILD)/cx16
VERSION_FILE ?= ../../version.json
VERSION_INC_TOOL ?= ../../tools/make_version_include.py
VERSION_INC = $(BUILD)/version_strings.inc
CX16_MEMORY_CONTRACT_TOOL = check_memory_contract.py

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

CX16_MAIN_SRC = main.s
CX16_TITLE_SRC = ../../core/title_data.s
CX16_TIER_DIR = creature_data
ROOT_DIR = ../..
CX16_MAIN_PRG = $(OUT)/moria16.prg
CX16_SHARED_PROBE_PRG = $(OUT)/moria16-shared-probe.prg
CX16_TITLE_PRG = $(OUT)/TITLE
CX16_TIER_PRGS = $(OUT)/MONSTER.DB.1 $(OUT)/MONSTER.DB.2 $(OUT)/MONSTER.DB.3 $(OUT)/MONSTER.DB.4
CX16_MODULE_PRGS = $(OUT)/DUNGEON.GEN
CX16_DUNGEON_CONSTS_SRC = ../../core/dungeon_consts.s
CX16_DUNGEON_MODULE_CONTRACT_SRC = dungeon_module_contract.s
CX16_SOURCES  := $(shell find . -type f -name '*.s' -print)
X16EMU_ROM_ARGS = $(if $(strip $(X16_ROM)),-rom "$(X16_ROM)",)

.PHONY: buildcx16 runcx16 testcx16 testcx16-smoke testcx16-runtime testcx16-shared-link testcx16-memory-contract testcx16-memory-contract-selftest ensure-kickass clean

buildcx16: $(CX16_MAIN_PRG) $(CX16_TITLE_PRG) $(CX16_TIER_PRGS) $(CX16_MODULE_PRGS)

testcx16: testcx16-smoke testcx16-runtime testcx16-shared-link

runcx16: $(CX16_MAIN_PRG) $(CX16_TITLE_PRG) $(CX16_TIER_PRGS) $(CX16_MODULE_PRGS)
	@command -v "$(X16EMU)" >/dev/null 2>&1 || { echo "ERROR: x16emu not found. Set X16EMU=/path/to/x16emu."; exit 1; }
	cd "$(OUT)" && "$(X16EMU)" $(X16EMU_ROM_ARGS) -prg "moria16.prg" -run

testcx16-smoke: $(CX16_MAIN_PRG) $(CX16_TITLE_PRG) $(CX16_TIER_PRGS) $(CX16_MODULE_PRGS)
	@command -v "$(X16EMU)" >/dev/null 2>&1 || { echo "ERROR: x16emu not found. Set X16EMU=/path/to/x16emu."; exit 1; }
	@echo "CX16 smoke setup passed: $(CX16_MAIN_PRG) and $(CX16_TITLE_PRG) build; $(X16EMU) is available."
	@echo "Run make runcx16 X16EMU=$(X16EMU) X16_ROM=/path/to/rom.bin to launch manually when needed."

testcx16-runtime: $(CX16_MAIN_PRG) $(CX16_TITLE_PRG) $(CX16_TIER_PRGS) $(CX16_MODULE_PRGS)
	@command -v "$(X16EMU)" >/dev/null 2>&1 || { echo "ERROR: x16emu not found. Set X16EMU=/path/to/x16emu."; exit 1; }
	python3 harness_smoke.py --x16emu "$(X16EMU)" $(if $(strip $(X16_ROM)),--rom "$(X16_ROM)",) --prg "$(CX16_MAIN_PRG)" --symbols "$(OUT)/main.sym" --cwd "$(OUT)"

testcx16-memory-contract-selftest:
	python3 tests/check_memory_contract_test.py

testcx16-memory-contract: testcx16-memory-contract-selftest $(CX16_MAIN_PRG) $(CX16_SHARED_PROBE_PRG) $(CX16_TIER_PRGS) $(CX16_MODULE_PRGS)
	python3 "$(CX16_MEMORY_CONTRACT_TOOL)" --main-prg "$(CX16_MAIN_PRG)" --main-symbols "$(OUT)/main.sym" --shared-prg "$(CX16_SHARED_PROBE_PRG)" --shared-symbols "$(OUT)/shared_probe.sym" $(foreach prg,$(CX16_TIER_PRGS),--tier-prg "$(prg)") $(foreach prg,$(CX16_MODULE_PRGS),--module-prg "$(prg)")

testcx16-shared-link: testcx16-memory-contract
	@echo "CX16 shared-gameplay link probe passed: $(CX16_SHARED_PROBE_PRG)"
	@echo "NOTE: this is link-only; it is not a runtime-safe CX16 memory placement yet."

$(VERSION_INC): $(VERSION_FILE) $(VERSION_INC_TOOL) | $(BUILD)
	python3 "$(VERSION_INC_TOOL)" "$(VERSION_FILE)" "$(VERSION_INC)"

$(CX16_MAIN_PRG): $(CX16_SOURCES) $(VERSION_INC) | ensure-kickass $(OUT)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" ":CX16_OUT=$(abspath $(OUT))" "$(CX16_MAIN_SRC)" -define CX16 -afo -showmem -vicesymbols -o "$(CX16_MAIN_PRG)"
	@if [ -f main.sym ]; then mv -f main.sym "$(OUT)/main.sym"; fi

$(CX16_SHARED_PROBE_PRG): $(CX16_SOURCES) $(VERSION_INC) | ensure-kickass $(OUT)
	@mkdir -p "$(OUT)/shared-probe"
	$(JAVA) -jar "$(KICKASS_RESOLVED)" ":CX16_OUT=$(abspath $(OUT))/shared-probe" "$(CX16_MAIN_SRC)" -define CX16 -define CX16_IMPORT_SHARED_GAME_LOOP -afo -showmem -vicesymbols -o "$(CX16_SHARED_PROBE_PRG)"
	@if [ -f "$(OUT)/main.vs" ]; then mv -f "$(OUT)/main.vs" "$(OUT)/shared_probe.vs"; fi
	@if [ -f main.sym ]; then mv -f main.sym "$(OUT)/shared_probe.sym"; fi

$(CX16_TITLE_PRG): $(CX16_TITLE_SRC) $(VERSION_INC) | ensure-kickass $(OUT)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" "$(CX16_TITLE_SRC)" -define TITLE_PLATFORM_CX16 -o "$(CX16_TITLE_PRG)"
	@if [ -f ../../core/title_data.sym ]; then mv -f ../../core/title_data.sym "$(OUT)/title_data.sym"; fi

$(OUT)/MONSTER.DB.1: $(CX16_TIER_DIR)/tier1_prg.s ../../platforms/commodore/c64/creature_data/tier1.s | ensure-kickass $(OUT)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" "$(CX16_TIER_DIR)/tier1_prg.s" -o "$@"
	@rm -f "$(CX16_TIER_DIR)/tier1_prg.sym"

$(OUT)/MONSTER.DB.2: $(CX16_TIER_DIR)/tier2_prg.s ../../platforms/commodore/c64/creature_data/tier2.s | ensure-kickass $(OUT)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" "$(CX16_TIER_DIR)/tier2_prg.s" -o "$@"
	@rm -f "$(CX16_TIER_DIR)/tier2_prg.sym"

$(OUT)/MONSTER.DB.3: $(CX16_TIER_DIR)/tier3_prg.s ../../platforms/commodore/c64/creature_data/tier3.s | ensure-kickass $(OUT)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" "$(CX16_TIER_DIR)/tier3_prg.s" -o "$@"
	@rm -f "$(CX16_TIER_DIR)/tier3_prg.sym"

$(OUT)/MONSTER.DB.4: $(CX16_TIER_DIR)/tier4_prg.s ../../platforms/commodore/c64/creature_data/tier4.s | ensure-kickass $(OUT)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" "$(CX16_TIER_DIR)/tier4_prg.s" -o "$@"
	@rm -f "$(CX16_TIER_DIR)/tier4_prg.sym"

$(OUT)/DUNGEON.GEN: $(CX16_MAIN_PRG)
	@test -f "$@" || { echo "ERROR: DUNGEON.GEN was not emitted by $(CX16_MAIN_SRC)"; exit 1; }

ensure-kickass: | $(OUT)
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
	mkdir -p "$(OUT)"

$(BUILD):
	mkdir -p "$(BUILD)"

clean:
	rm -rf "$(OUT)"
	rm -f *.sym *.vs
