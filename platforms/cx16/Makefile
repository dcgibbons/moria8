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

KA_FLAGS     = -showmem -libdir ../../core -libdir . -libdir hal -libdir ../commodore/common -define CX16 -afo -symbolfiledir "$(OVL_OUTCX16)"
VERSION_FILE = ../../version.json
VERSION_INC_TOOL = ../../tools/make_version_include.py
VERSION_INC  = $(BUILD)/version_strings.inc

CX16_MAIN_SRC  = main.s
CX16_TITLE_SRC = title_data_cx16.s
CX16_TIER_DIR  = creature_data
CX16_SOURCES   = $(wildcard *.s hal/*.s creature_data/*.s ../../core/*.s ../../platforms/shared/*.s ../../platforms/commodore/common/*.s)

CX16_MAIN_PRG  = $(OUTCX16)/MORIA8.PRG
CX16_AUX_PRG   = $(OUTCX16)/CX16.AUXDATA
CX16_HUFF_PRG  = $(OUTCX16)/CX16.HUFFDATA
CX16_OVL_PRGS  = $(OUTCX16)/OVL.START $(OUTCX16)/OVL.TOWN $(OUTCX16)/OVL.DEATH $(OUTCX16)/OVL.MODAL \
                 $(OUTCX16)/OVL.GEN $(OUTCX16)/OVL.HELP $(OUTCX16)/OVL.UI $(OUTCX16)/OVL.ITEMS \
                 $(OUTCX16)/OVL.SPELL $(OUTCX16)/OVL.CHEST $(OUTCX16)/OVL.STORAGE $(OUTCX16)/OVL.TITLE
CX16_TIER_PRGS = $(OUTCX16)/MONSTER.DB.1 $(OUTCX16)/MONSTER.DB.2 $(OUTCX16)/MONSTER.DB.3 $(OUTCX16)/MONSTER.DB.4
CX16_TITLE_PRG = $(OUTCX16)/TITLE
CX16_LICENSE   = $(OUTCX16)/LICENSE
CX16_SOURCE_OFFER = $(OUTCX16)/SOURCE-OFFER

CX16_ZIP_IMAGE = $(BUILD)/moria8-cx16.zip
CX16_MAIN_STAMP = $(OUTCX16)/.main.stamp

.PHONY: all build disk run test-memory-contract test-memory-contract-selftest test-runtime clean ensure-kickass kickass

all: build

build: $(CX16_MAIN_PRG) $(CX16_AUX_PRG) $(CX16_HUFF_PRG) $(CX16_OVL_PRGS) $(CX16_TIER_PRGS) $(CX16_TITLE_PRG) $(CX16_LICENSE) $(CX16_SOURCE_OFFER)
	@mkdir -p "$(OUTCX16)"

disk: $(CX16_ZIP_IMAGE)

run: build
	"$(X16EMU)" $(X16ROM_FLAG) -fsroot "$(OVL_OUTCX16)" -prg "$(OVL_OUTCX16)/MORIA8.PRG" -run

test-memory-contract: build
	python3 -B check_memory_contract.py

test-memory-contract-selftest:
	python3 -B check_memory_contract.py --selftest

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
	rm -rf "$(OUTCX16)" "$(CX16_ZIP_IMAGE)" __pycache__

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

$(BUILD):
	mkdir -p "$(BUILD)"

$(OUTCX16):
	mkdir -p "$(OUTCX16)"

$(CX16_MAIN_STAMP): $(CX16_SOURCES) $(VERSION_INC) | ensure-kickass $(OUTCX16)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" ":OVL_OUT=$(OVL_OUTCX16)" "$(CX16_MAIN_SRC)" $(KA_FLAGS) -symbolfile -o "$(CX16_MAIN_PRG)"
	touch "$(CX16_MAIN_STAMP)"

$(CX16_MAIN_PRG) $(CX16_AUX_PRG) $(CX16_HUFF_PRG) $(CX16_OVL_PRGS) $(OUTCX16)/main.sym: $(CX16_MAIN_STAMP)
	@test -f "$@" || { rm -f "$(CX16_MAIN_STAMP)"; $(MAKE) "$(CX16_MAIN_STAMP)"; }
	@test -f "$@"

$(OUTCX16)/MONSTER.DB.1: $(CX16_TIER_DIR)/tier1_prg.s | ensure-kickass $(OUTCX16)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" "$(CX16_TIER_DIR)/tier1_prg.s" -symbolfiledir "$(OVL_OUTCX16)" -o "$@"

$(OUTCX16)/MONSTER.DB.2: $(CX16_TIER_DIR)/tier2_prg.s | ensure-kickass $(OUTCX16)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" "$(CX16_TIER_DIR)/tier2_prg.s" -symbolfiledir "$(OVL_OUTCX16)" -o "$@"

$(OUTCX16)/MONSTER.DB.3: $(CX16_TIER_DIR)/tier3_prg.s | ensure-kickass $(OUTCX16)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" "$(CX16_TIER_DIR)/tier3_prg.s" -symbolfiledir "$(OVL_OUTCX16)" -o "$@"

$(OUTCX16)/MONSTER.DB.4: $(CX16_TIER_DIR)/tier4_prg.s | ensure-kickass $(OUTCX16)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" "$(CX16_TIER_DIR)/tier4_prg.s" -symbolfiledir "$(OVL_OUTCX16)" -o "$@"

$(CX16_TITLE_PRG): $(CX16_TITLE_SRC) $(VERSION_INC) | ensure-kickass $(OUTCX16)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" "$(CX16_TITLE_SRC)" -symbolfiledir "$(OVL_OUTCX16)" -o "$@"

$(CX16_LICENSE): $(LICENSE_FILE) | $(OUTCX16)
	LC_ALL=C tr '\012' '\015' < "$<" > "$@"

$(CX16_SOURCE_OFFER): $(SOURCE_OFFER) | $(OUTCX16)
	LC_ALL=C tr '\012' '\015' < "$<" > "$@"

$(CX16_ZIP_IMAGE): build
	rm -f "$@"
	cd "$(OUTCX16)" && zip -q "$(abspath $(CX16_ZIP_IMAGE))" \
		MORIA8.PRG CX16.AUXDATA CX16.HUFFDATA \
		OVL.START OVL.TOWN OVL.DEATH OVL.MODAL OVL.GEN OVL.HELP \
		OVL.UI OVL.ITEMS OVL.SPELL OVL.CHEST OVL.STORAGE OVL.TITLE \
		MONSTER.DB.1 MONSTER.DB.2 MONSTER.DB.3 MONSTER.DB.4 \
		TITLE LICENSE SOURCE-OFFER
