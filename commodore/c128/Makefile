# Makefile — Moria8 C128 (80-column VDC mode)
#
# Targets:
#   make build128   Build moria128.prg + boot128.prg
#   make disk128    Build D64 disk image with all game files
#   make run128     Build D64 disk image + launch in VICE x128 (80-col mode)
#   make test128-fast  Run the Python Gate C compare harness against the stable C128 unit batch
#   make clean128   Remove C128 build artifacts

# ── Tool paths ────────────────────────────────────────────
KICKASS_DIR ?= ../../tools/kickass
KICKASS     ?= $(KICKASS_DIR)/KickAss.jar
KICKASS_URL  = https://theweb.dk/KickAssembler/KickAssembler.zip
VICE128     ?= x128
C1541       ?= c1541
JAVA        ?= java

# ── Project layout ────────────────────────────────────────
OUT         = out
MAIN_SRC    = main.s
MAIN_PRG    = $(OUT)/moria128.prg
BOOT_SRC    = boot128.s
BOOT_PRG    = $(OUT)/boot128.prg
TITLE_SRC   = ../common/title_data.s
TITLE_PRG   = $(OUT)/title

# Creature tier data — reuse C64 data sources
TIER_DIR    = ../c64/creature_data
TIER_PRGS   = $(OUT)/monster.db.1 $(OUT)/monster.db.2 $(OUT)/monster.db.3 $(OUT)/monster.db.4

# Overlays — produced as side-effect of main assembly
OVL_TOWN    = $(OUT)/ovl.town
OVL_START   = $(OUT)/ovl.start
OVL_DEATH   = $(OUT)/ovl.death
OVL_GEN     = $(OUT)/ovl.gen
BANK1_DAT   = $(OUT)/bank1.dat

# Disk image
DISK_IMAGE  = $(OUT)/moria128.d64
DISK_NAME   = "moria128,m8"

# Source dependencies
# Use recursive discovery so imported .s changes in shared trees always
# invalidate C128 outputs (even when not doing a clean build).
COMMON_SOURCES := $(shell find ../common ../c64 -type f -name '*.s')
C128_SOURCES   := $(shell find . -maxdepth 1 -type f -name '*.s')
SOURCES        := $(C128_SOURCES) $(COMMON_SOURCES)

# ── KickAssembler flags ──────────────────────────────────
KA_FLAGS    = -showmem -vicesymbols -libdir ../c64 -define C128 -define OVL_OUT='"$(OUT)"'
ifeq ($(PERF_P1),1)
KA_FLAGS    += -define PERF_P1
endif

# ── Targets ───────────────────────────────────────────────
.PHONY: build128 run128 disk128 clean128 test128 test128-fast

build128: $(MAIN_PRG) $(BOOT_PRG)

test128:
	./run_tests128.sh

test128-fast:
	python3 -u ./harness128_batch.py --mode compare --snapshot-path $(OUT)/ready.vsf --vice $(VICE128) --connect-timeout 12

# Main program
$(MAIN_PRG): $(SOURCES) $(KICKASS) | $(OUT)
	$(JAVA) -jar $(KICKASS) $(MAIN_SRC) $(KA_FLAGS) -o $(MAIN_PRG)

# Bootloader (chain-loads moria128.prg)
$(BOOT_PRG): $(BOOT_SRC) $(KICKASS) | $(OUT)
	$(JAVA) -jar $(KICKASS) $(BOOT_SRC) -o $(BOOT_PRG)

# Overlays — produced as side-effect of main assembly
$(OVL_TOWN): $(MAIN_PRG)
$(OVL_START): $(MAIN_PRG)
$(OVL_DEATH): $(MAIN_PRG)
$(OVL_GEN): $(MAIN_PRG)
$(BANK1_DAT): $(MAIN_PRG)

# Title screen art — pass -define C128 so title_data.s emits "Commodore 128 Edition"
$(TITLE_PRG): $(TITLE_SRC) | $(OUT)
	$(JAVA) -jar $(KICKASS) $(TITLE_SRC) -define C128 -o $(TITLE_PRG)

# Creature tier data — assembled from shared C64 data sources
$(OUT)/monster.db.1: $(TIER_DIR)/tier1_prg.s $(TIER_DIR)/tier1.s | $(OUT)
	$(JAVA) -jar $(KICKASS) $(TIER_DIR)/tier1_prg.s -o $@
$(OUT)/monster.db.2: $(TIER_DIR)/tier2_prg.s $(TIER_DIR)/tier2.s | $(OUT)
	$(JAVA) -jar $(KICKASS) $(TIER_DIR)/tier2_prg.s -o $@
$(OUT)/monster.db.3: $(TIER_DIR)/tier3_prg.s $(TIER_DIR)/tier3.s | $(OUT)
	$(JAVA) -jar $(KICKASS) $(TIER_DIR)/tier3_prg.s -o $@
$(OUT)/monster.db.4: $(TIER_DIR)/tier4_prg.s $(TIER_DIR)/tier4.s | $(OUT)
	$(JAVA) -jar $(KICKASS) $(TIER_DIR)/tier4_prg.s -o $@

# Create 1571 D64 disk image with all game files
# boot128 is the autostart entry — chain-loads moria128
disk128: $(DISK_IMAGE)

$(DISK_IMAGE): $(MAIN_PRG) $(BOOT_PRG) $(TITLE_PRG) $(TIER_PRGS) $(OVL_TOWN) $(OVL_START) $(OVL_DEATH) $(OVL_GEN) $(BANK1_DAT) Makefile | $(OUT)
	$(C1541) -format $(DISK_NAME) d64 $@ \
	         -attach $@ \
	         -write $(BOOT_PRG) "moria8.128" \
	         -write $(MAIN_PRG) "moria128" \
	         -write $(TITLE_PRG) "title" \
	         -write $(OUT)/monster.db.1 "monster.db.1" \
	         -write $(OUT)/monster.db.2 "monster.db.2" \
	         -write $(OUT)/monster.db.3 "monster.db.3" \
	         -write $(OUT)/monster.db.4 "monster.db.4" \
	         -write $(OVL_TOWN) "ovl.town" \
	         -write $(OVL_START) "ovl.start" \
	         -write $(OVL_DEATH) "ovl.death" \
	         -write $(OVL_GEN) "ovl.gen" \
	         -write $(BANK1_DAT) "bank1.dat"

# Launch in VICE x128 (80-column mode) with D64 disk image
run128: $(DISK_IMAGE)
	$(VICE128) -80col -drive8truedrive -drive8type 1541  \
		-sound -sounddev coreaudio -autostart $(DISK_IMAGE)

# Auto-download KickAssembler if not present
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

clean128:
	rm -rf $(OUT)
