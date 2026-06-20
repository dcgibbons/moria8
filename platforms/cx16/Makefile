# Commander X16 Makefile
#
# First milestone:
#   make buildcx16       Build the boot-to-title PRG
#   make runcx16         Launch the PRG under x16emu
#   make testcx16-smoke  Verify the PRG builds and x16emu is discoverable

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
CX16_MAIN_PRG = $(OUT)/moria16.prg
CX16_TITLE_PRG = $(OUT)/TITLE
CX16_SOURCES  := $(shell find . -type f -name '*.s' -print)
X16EMU_ROM_ARGS = $(if $(strip $(X16_ROM)),-rom "$(X16_ROM)",)

.PHONY: buildcx16 runcx16 testcx16-smoke ensure-kickass clean

buildcx16: $(CX16_MAIN_PRG) $(CX16_TITLE_PRG)

runcx16: $(CX16_MAIN_PRG) $(CX16_TITLE_PRG)
	@command -v "$(X16EMU)" >/dev/null 2>&1 || { echo "ERROR: x16emu not found. Set X16EMU=/path/to/x16emu."; exit 1; }
	cd "$(OUT)" && "$(X16EMU)" $(X16EMU_ROM_ARGS) -prg "moria16.prg" -run

testcx16-smoke: $(CX16_MAIN_PRG) $(CX16_TITLE_PRG)
	@command -v "$(X16EMU)" >/dev/null 2>&1 || { echo "ERROR: x16emu not found. Set X16EMU=/path/to/x16emu."; exit 1; }
	@echo "CX16 smoke setup passed: $(CX16_MAIN_PRG) and $(CX16_TITLE_PRG) build; $(X16EMU) is available."
	@echo "Run make runcx16 X16EMU=$(X16EMU) X16_ROM=/path/to/rom.bin to launch manually when needed."

$(VERSION_INC): $(VERSION_FILE) $(VERSION_INC_TOOL) | $(BUILD)
	python3 "$(VERSION_INC_TOOL)" "$(VERSION_FILE)" "$(VERSION_INC)"

$(CX16_MAIN_PRG): $(CX16_SOURCES) | ensure-kickass $(OUT)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" "$(CX16_MAIN_SRC)" -define CX16 -showmem -vicesymbols -o "$(CX16_MAIN_PRG)"
	@if [ -f main.sym ]; then mv -f main.sym "$(OUT)/main.sym"; fi

$(CX16_TITLE_PRG): $(CX16_TITLE_SRC) $(VERSION_INC) | ensure-kickass $(OUT)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" "$(CX16_TITLE_SRC)" -define TITLE_PLATFORM_CX16 -o "$(CX16_TITLE_PRG)"
	@if [ -f ../../core/title_data.sym ]; then mv -f ../../core/title_data.sym "$(OUT)/title_data.sym"; fi

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
