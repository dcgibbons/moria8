# Apple IIe Makefile — moria8 (ProDOS 8 / MAME apple2ee)
#
# Primary targets:
#   make build        Assemble all payloads into ../../build/apple2
#   make disk         Build the shipping image ../../build/moria8-apple2.po
#   make run          Launch the image in MAME apple2ee (needs A2ROMS)
#   make test-memory-contract[-selftest]  Static placement gate
#
# Tooling mirrors the Commodore Makefile: Kick Assembler auto-downloads into
# ../../tools/kickass; AppleCommander (ac 13.2) auto-downloads into
# ../../tools/applecommander. The ProDOS kernel and boot blocks auto-download
# from the ProDOS8-Releases repo (2.4.3, SHA256-pinned) into
# ../../tools/prodos (override with PRODOS/BOOTBLOCKS env vars).

KICKASS_DIR ?= ../../tools/kickass
KICKASS     ?= $(KICKASS_DIR)/KickAss.jar
KICKASS_URL  = https://theweb.dk/KickAssembler/KickAssembler.zip
ifeq ($(filter /%,$(KICKASS)),)
KICKASS_RESOLVED = $(CURDIR)/$(KICKASS)
else
KICKASS_RESOLVED = $(KICKASS)
endif
JAVA        ?= ../../tools/kickass_java.sh

AC_VERSION  ?= 13.2
AC_DIR      ?= ../../tools/applecommander
AC_BIN      ?= $(AC_DIR)/ac
UNAME_S     := $(shell uname -s)
UNAME_M     := $(shell uname -m)
ifeq ($(UNAME_S),Darwin)
ifeq ($(UNAME_M),arm64)
AC_ASSET     = ac-darwin-arm64.zip
AC_SHA256    = 86e0dc142c8acaca25ebc93536465f98f0f51d59f2dec8c64a36bc61c79247b2
else
AC_ASSET     = ac-darwin-x86_64.zip
AC_SHA256    = a4c3d20374c000194c2e1e5f12abb28b7375f7830e4112e0e005d1d9acc5bfa3
endif
else
AC_ASSET     = ac-linux-x86_64.zip
AC_SHA256    = 92e72d6538dc0c04bf3f1d587a97128974a24a428049fe536d79648397fe1a01
endif
AC_URL       = https://github.com/AppleCommander/AppleCommander/releases/download/$(AC_VERSION)/$(AC_ASSET)

PRODOS      ?= ../../tools/prodos/PRODOS
BOOTBLOCKS  ?= ../../tools/prodos/bootblocks.bin
PRODOS_VERSION ?= 2.4.3
PRODOS_URL    = https://raw.githubusercontent.com/ProDOS-8/ProDOS8-Releases/master/ProDOS_2_4_3.po
PRODOS_SHA256 = 398d333cb2ab92df9f8bb2cf64b946f2567116910eb8359cf4bdee5d4194f0fa

BUILD       ?= ../../build
OUTA2        = $(BUILD)/apple2
OVL_OUTA2    = $(abspath $(OUTA2))

KA_FLAGS     = -showmem -vicesymbols -libdir ../../core -libdir . -libdir hal -libdir ../commodore/common -define APPLE2 -afo
PRG2BIN      = python3 ../../tools/prg_to_bin.py
VERSION_FILE = ../../version.json
VERSION_INC_TOOL = ../../tools/make_version_include.py
VERSION_INC = $(BUILD)/version_strings.inc

A2_MAIN_SRC  = main.s
A2_BOOT_SRC  = boot.s
TITLE_SRC    = ../../core/title_data.s
A2_TIER_DIR  = creature_data
A2_SOURCES   := $(shell find . ../../core ../../platforms/shared ../../platforms/commodore/common -type f -name '*.s' -print)

# Payloads (PRG with 2-byte header, straight from Kick)
A2_MAIN_PRG  = $(OUTA2)/moria8a2.prg
A2_PLAY_PRG  = $(OUTA2)/a2.play
A2_AUX_PRG   = $(OUTA2)/a2.auxdata
A2_OVL_PRGS  = $(OUTA2)/ovl.start $(OUTA2)/ovl.town $(OUTA2)/ovl.death $(OUTA2)/ovl.modal \
               $(OUTA2)/ovl.gen $(OUTA2)/ovl.help $(OUTA2)/ovl.ui $(OUTA2)/ovl.items \
               $(OUTA2)/ovl.spell $(OUTA2)/ovl.storage $(OUTA2)/ovl.title
A2_TIER_PRGS = $(OUTA2)/monster.db.1 $(OUTA2)/monster.db.2 $(OUTA2)/monster.db.3 $(OUTA2)/monster.db.4
A2_TITLE_PRG = $(OUTA2)/title.prg
A2_BOOT_PRG  = $(OUTA2)/moria8.system.prg

# Disk contents (headerless BIN with auxtype = load address)
A2_DISK_IMAGE = $(BUILD)/moria8-apple2.po
A2_MAIN_STAMP = $(OUTA2)/.main.stamp
MAME_OUTPUT_ROOT = $(abspath $(OUTA2)/mame)

.PHONY: all build disk run test-memory-contract test-memory-contract-selftest clean ensure-kickass kickass ac prodos

all: build

build: $(A2_MAIN_PRG) $(A2_PLAY_PRG) $(A2_AUX_PRG) $(A2_OVL_PRGS) $(A2_TIER_PRGS) $(A2_TITLE_PRG) $(A2_BOOT_PRG)
	@mkdir -p "$(OUTA2)"

disk: $(A2_DISK_IMAGE)

run: $(A2_DISK_IMAGE)
	@test -n "$(A2ROMS)" || { echo "A2ROMS env var required (Apple IIe ROMs are not redistributable)"; exit 1; }
	@mkdir -p "$(MAME_OUTPUT_ROOT)/cfg" "$(MAME_OUTPUT_ROOT)/nvram" \
		"$(MAME_OUTPUT_ROOT)/inp" "$(MAME_OUTPUT_ROOT)/sta" \
		"$(MAME_OUTPUT_ROOT)/snap" "$(MAME_OUTPUT_ROOT)/diff" \
		"$(MAME_OUTPUT_ROOT)/comments" "$(MAME_OUTPUT_ROOT)/share"
	mame apple2ee -rompath "$(A2ROMS)" -window -nomaximize \
		-cfg_directory "$(MAME_OUTPUT_ROOT)/cfg" \
		-nvram_directory "$(MAME_OUTPUT_ROOT)/nvram" \
		-input_directory "$(MAME_OUTPUT_ROOT)/inp" \
		-state_directory "$(MAME_OUTPUT_ROOT)/sta" \
		-snapshot_directory "$(MAME_OUTPUT_ROOT)/snap" \
		-diff_directory "$(MAME_OUTPUT_ROOT)/diff" \
		-comment_directory "$(MAME_OUTPUT_ROOT)/comments" \
		-share_directory "$(MAME_OUTPUT_ROOT)/share" \
		-flop1 "$(A2_DISK_IMAGE)"

test-memory-contract: build
	python3 check_memory_contract.py

test-memory-contract-selftest:
	python3 check_memory_contract.py --selftest

clean:
	rm -rf "$(OUTA2)" "$(A2_DISK_IMAGE)"

# ── Tooling ───────────────────────────────────────────────
ensure-kickass:
	@test -f "$(KICKASS_RESOLVED)" || $(MAKE) --no-print-directory kickass

kickass:
	@mkdir -p "$(KICKASS_DIR)"
	@echo "Downloading Kick Assembler..."
	@curl -sL "$(KICKASS_URL)" -o /tmp/kickass.zip
	@unzip -o /tmp/kickass.zip -d "$(KICKASS_DIR)"
	@rm /tmp/kickass.zip

ac:
	@mkdir -p "$(AC_DIR)"
	@echo "Downloading AppleCommander $(AC_VERSION) ($(AC_ASSET))..."
	@curl -sL "$(AC_URL)" -o /tmp/ac.zip
	@echo "$(AC_SHA256)  /tmp/ac.zip" | shasum -a 256 -c -
	@unzip -o /tmp/ac.zip -d "$(AC_DIR)"
	@rm /tmp/ac.zip
	@bin=$$(find "$(AC_DIR)" -type f -name 'ac-*' | head -1); \
	 test -n "$$bin" || { echo "no binary found in AppleCommander archive"; exit 1; }; \
	 cp "$$bin" "$(AC_BIN)"; chmod +x "$(AC_BIN)"

ensure-ac:
	@test -f "$(AC_BIN)" || $(MAKE) --no-print-directory ac

prodos: ensure-ac
	@mkdir -p "$(dir $(PRODOS))"
	@echo "Downloading ProDOS $(PRODOS_VERSION)..."
	@curl -sL "$(PRODOS_URL)" -o /tmp/prodos.po
	@echo "$(PRODOS_SHA256)  /tmp/prodos.po" | shasum -a 256 -c -
	@"$(AC_BIN)" -g /tmp/prodos.po PRODOS > "$(PRODOS)"
	@dd if=/tmp/prodos.po of="$(BOOTBLOCKS)" bs=512 count=2 2>/dev/null
	@rm /tmp/prodos.po

ensure-prodos:
	@test -f "$(PRODOS)" -a -f "$(BOOTBLOCKS)" || $(MAKE) --no-print-directory prodos

# ── Assembly ──────────────────────────────────────────────
$(VERSION_INC): $(VERSION_FILE) $(VERSION_INC_TOOL) | $(BUILD)
	python3 "$(VERSION_INC_TOOL)" "$(VERSION_FILE)" "$(VERSION_INC)"

$(BUILD):
	mkdir -p "$(BUILD)"

$(OUTA2):
	mkdir -p "$(OUTA2)"

$(A2_MAIN_STAMP): $(A2_SOURCES) $(VERSION_INC) | ensure-kickass $(OUTA2)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" ":OVL_OUT=$(OVL_OUTA2)" "$(A2_MAIN_SRC)" $(KA_FLAGS) -o "$(A2_MAIN_PRG)"
	touch "$(A2_MAIN_STAMP)"

$(A2_MAIN_PRG) $(A2_PLAY_PRG) $(A2_AUX_PRG) $(A2_OVL_PRGS): $(A2_MAIN_STAMP)
	@test -f "$@" || { rm -f "$(A2_MAIN_STAMP)"; $(MAKE) "$(A2_MAIN_STAMP)"; }
	@test -f "$@"

$(OUTA2)/monster.db.1: $(A2_TIER_DIR)/tier1_prg.s | ensure-kickass $(OUTA2)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" "$(A2_TIER_DIR)/tier1_prg.s" -o "$@"

$(OUTA2)/monster.db.2: $(A2_TIER_DIR)/tier2_prg.s | ensure-kickass $(OUTA2)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" "$(A2_TIER_DIR)/tier2_prg.s" -o "$@"

$(OUTA2)/monster.db.3: $(A2_TIER_DIR)/tier3_prg.s | ensure-kickass $(OUTA2)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" "$(A2_TIER_DIR)/tier3_prg.s" -o "$@"

$(OUTA2)/monster.db.4: $(A2_TIER_DIR)/tier4_prg.s | ensure-kickass $(OUTA2)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" "$(A2_TIER_DIR)/tier4_prg.s" -o "$@"

$(A2_TITLE_PRG): $(TITLE_SRC) $(VERSION_INC) | ensure-kickass $(OUTA2)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" "$(TITLE_SRC)" -define TITLE_PLATFORM_A2 -o "$@"

$(A2_BOOT_PRG): $(A2_BOOT_SRC) cache_layout.s | ensure-kickass $(OUTA2)
	$(JAVA) -jar "$(KICKASS_RESOLVED)" "$(A2_BOOT_SRC)" -o "$@"

# ── Disk image ────────────────────────────────────────────
# PRG -> BIN conversion strips the Kick header and asserts each load
# address. PRODOS kernel and boot blocks auto-download (see prodos target).
$(A2_DISK_IMAGE): ensure-ac ensure-prodos $(A2_MAIN_PRG) $(A2_PLAY_PRG) $(A2_AUX_PRG) $(A2_OVL_PRGS) $(A2_TIER_PRGS) $(A2_TITLE_PRG) $(A2_BOOT_PRG)
	@mkdir -p "$(OUTA2)/bin"
	$(PRG2BIN) "$(A2_BOOT_PRG)" "$(OUTA2)/bin/MORIA8.SYSTEM" --expect-addr 0x2000
	$(PRG2BIN) "$(A2_MAIN_PRG)" "$(OUTA2)/bin/MORIA8.RES" --expect-addr 0x0A00
	$(PRG2BIN) "$(A2_PLAY_PRG)" "$(OUTA2)/bin/A2.PLAY" --expect-addr 0x7C00
	@for f in START TOWN DEATH MODAL GEN HELP UI ITEMS SPELL STORAGE TITLE; do \
	  lower=$$(echo $$f | tr 'A-Z' 'a-z'); \
	  $(PRG2BIN) "$(OUTA2)/ovl.$$lower" "$(OUTA2)/bin/OVL.$$f" --expect-addr 0xA400 || exit 1; \
	done
	$(PRG2BIN) "$(OUTA2)/a2.auxdata" "$(OUTA2)/bin/A2.AUXDATA" --expect-addr 0x3B0C
	@for n in 1 2 3 4; do \
	  $(PRG2BIN) "$(OUTA2)/monster.db.$$n" "$(OUTA2)/bin/MONSTER.DB.$$n" --expect-addr 0xA400 || exit 1; \
	done
	$(PRG2BIN) "$(A2_TITLE_PRG)" "$(OUTA2)/bin/TITLE" --expect-addr 0x4000
	rm -f "$@"
	"$(AC_BIN)" -pro140 "$@" MORIA8
	"$(AC_BIN)" -p "$@" PRODOS sys 0x2000 < "$(PRODOS)"
	"$(AC_BIN)" -p "$@" MORIA8.SYSTEM sys 0x2000 < "$(OUTA2)/bin/MORIA8.SYSTEM"
	python3 ../../tools/make_pak.py "$(OUTA2)/bin/MORIA8.PAK" \
	  "$(OUTA2)/bin/MORIA8.RES" "$(OUTA2)/bin/A2.AUXDATA" \
	  "$(OUTA2)/bin/OVL.TOWN" "$(OUTA2)/bin/OVL.UI" "$(OUTA2)/bin/OVL.ITEMS" \
	  "$(OUTA2)/bin/OVL.SPELL" "$(OUTA2)/bin/OVL.MODAL" "$(OUTA2)/bin/OVL.GEN"
	"$(AC_BIN)" -p "$@" MORIA8.PAK bin 0x0000 < "$(OUTA2)/bin/MORIA8.PAK"
	"$(AC_BIN)" -p "$@" A2.PLAY bin 0x7C00 < "$(OUTA2)/bin/A2.PLAY"
	@for f in START DEATH GEN HELP STORAGE TITLE; do \
	  "$(AC_BIN)" -p "$@" OVL.$$f bin 0xA400 < "$(OUTA2)/bin/OVL.$$f" || exit 1; \
	done
	@for n in 1 2 3 4; do \
	  "$(AC_BIN)" -p "$@" MONSTER.DB.$$n bin 0xA400 < "$(OUTA2)/bin/MONSTER.DB.$$n" || exit 1; \
	done
	"$(AC_BIN)" -p "$@" TITLE bin 0x4000 < "$(OUTA2)/bin/TITLE"
	dd if="$(BOOTBLOCKS)" of="$@" bs=512 count=2 conv=notrunc
	"$(AC_BIN)" -l "$@"
