# Makefile — Moria8 C64/C128
#
# Targets:
#   make          Build moria8.prg (auto-downloads KickAssembler if needed)
#   make run      Build and launch in VICE
#   make rundisk  Build D64 + launch with true drive emulation
#   make debug    Build + launch with VICE monitor watchpoints
#   make test     Assemble + run all tests in VICE headless
#   make disk     Build a .d64 disk image
#   make clean    Remove all build artifacts
#
# Override tool paths:
#   make KICKASS=/other/path/KickAss.jar VICE=x64sc

# ── Tool paths ────────────────────────────────────────────
KICKASS_DIR ?= ../../tools/kickass
KICKASS     ?= $(KICKASS_DIR)/KickAss.jar
KICKASS_URL  = https://theweb.dk/KickAssembler/KickAssembler.zip
VICE        ?= x64sc
C1541       ?= c1541
JAVA        ?= java

# ── Project layout ────────────────────────────────────────
OUT         = out
MAIN_SRC    = main.s
MAIN_PRG    = $(OUT)/moria8.prg
BOOT_SRC    = boot.s
BOOT_PRG    = $(OUT)/boot.prg
TITLE_SRC   = title_data.s
TITLE_PRG   = $(OUT)/title
TIER_PRGS   = $(OUT)/monster.db.1 $(OUT)/monster.db.2 $(OUT)/monster.db.3 $(OUT)/monster.db.4
OVL_TOWN    = $(OUT)/ovl.town
OVL_START   = $(OUT)/ovl.start
OVL_DEATH   = $(OUT)/ovl.death
DISK_IMAGE  = $(OUT)/moria8.d64
DISK_NAME   = "moria8,m8"
DISKART     = ../../tools/diskart.py

# All source files that main.s imports (dependency list)
SOURCES     = $(wildcard *.s)
TEST_SOURCES = $(wildcard tests/*.s)

# ── KickAssembler flags ──────────────────────────────────
KA_FLAGS    = -showmem -vicesymbols

# ── VICE flags ────────────────────────────────────────────
# For interactive play
RUN_FLAGS   = -autostartprgmode 1 -sound -sounddev coreaudio

# ── Targets ───────────────────────────────────────────────
.PHONY: all build run rundisk debug test disk savedisk clean

all: build

build: $(MAIN_PRG)

# Main program — rebuild if ANY .s file changes.
# KickAssembler resolves all #imports from main.s in one pass,
# so there are no intermediate .o files to track.
$(MAIN_PRG): $(SOURCES) $(KICKASS) | $(OUT)
	$(JAVA) -jar $(KICKASS) $(MAIN_SRC) $(KA_FLAGS) -o $(MAIN_PRG)

# Overlays — produced as side-effect of main assembly (segment outPrg)
$(OVL_TOWN): $(MAIN_PRG)
$(OVL_START): $(MAIN_PRG)
$(OVL_DEATH): $(MAIN_PRG)

# Title screen art — standalone PRG loaded from disk at runtime
$(TITLE_PRG): $(TITLE_SRC) | $(OUT)
	$(JAVA) -jar $(KICKASS) $(TITLE_SRC) -o $(TITLE_PRG)

# Creature tier data — standalone PRGs loaded at runtime ($E000)
# Output filenames match PETSCII names for VICE FileSystemDevice compatibility
$(OUT)/monster.db.1: creature_data/tier1_prg.s creature_data/tier1.s | $(OUT)
	$(JAVA) -jar $(KICKASS) creature_data/tier1_prg.s -o $@
$(OUT)/monster.db.2: creature_data/tier2_prg.s creature_data/tier2.s | $(OUT)
	$(JAVA) -jar $(KICKASS) creature_data/tier2_prg.s -o $@
$(OUT)/monster.db.3: creature_data/tier3_prg.s creature_data/tier3.s | $(OUT)
	$(JAVA) -jar $(KICKASS) creature_data/tier3_prg.s -o $@
$(OUT)/monster.db.4: creature_data/tier4_prg.s creature_data/tier4.s | $(OUT)
	$(JAVA) -jar $(KICKASS) creature_data/tier4_prg.s -o $@

# Bootloader — chain-loads MORIA64 from disk
$(BOOT_PRG): $(BOOT_SRC) | $(OUT)
	$(JAVA) -jar $(KICKASS) $(BOOT_SRC) -o $(BOOT_PRG)

# Launch in VICE emulator
run: $(MAIN_PRG) $(TITLE_PRG) $(TIER_PRGS)
	$(VICE) $(RUN_FLAGS) -autostart $(MAIN_PRG)

# Launch with D64 disk image + true drive emulation (bypasses FileSystemDevice)
rundisk: disk
	$(VICE) -drive8truedrive -drive8type 1541 +iecdevice8 -sound -sounddev coreaudio -autostart $(DISK_IMAGE)

# Launch with VICE monitor commands for save/load debugging
debug: $(MAIN_PRG) disk
	$(VICE) -drive8truedrive -drive8type 1541 +iecdevice8 -sound -sounddev coreaudio     -8 $(DISK_IMAGE) -moncommands debug_load.mon -autostart $(MAIN_PRG)

# Delegate to existing test runner (assembles tests + runs in VICE headless)
test: $(MAIN_PRG)
	./run_tests.sh

# Create a 1541 .d64 disk image with PETSCII directory art
disk: $(MAIN_PRG) $(BOOT_PRG) $(TITLE_PRG) $(TIER_PRGS) $(OVL_TOWN) $(OVL_START) $(OVL_DEATH) | $(OUT)
	printf '\x01\x08' > $(OUT)/empty.prg
	$(C1541) -format $(DISK_NAME) d64 $(DISK_IMAGE) \
	         -attach $(DISK_IMAGE) \
	         -write $(OUT)/empty.prg "art1" \
	         -write $(OUT)/empty.prg "art2" \
	         -write $(OUT)/empty.prg "art3" \
	         -write $(OUT)/empty.prg "art4" \
	         -write $(OUT)/empty.prg "art5" \
	         -write $(BOOT_PRG) "moria8" \
	         -write $(MAIN_PRG) "moria64" \
	         -write $(TITLE_PRG) "title" \
	         -write $(OUT)/monster.db.1 "monster.db.1" \
	         -write $(OUT)/monster.db.2 "monster.db.2" \
	         -write $(OUT)/monster.db.3 "monster.db.3" \
	         -write $(OUT)/monster.db.4 "monster.db.4" \
	         -write $(OVL_TOWN) "ovl.town" \
	         -write $(OVL_START) "ovl.start" \
	         -write $(OVL_DEATH) "ovl.death"
	python3 $(DISKART) $(DISK_IMAGE)
	rm -f $(OUT)/empty.prg

SAVE_IMAGE  = $(OUT)/moria8_save.d64

savedisk: | $(OUT)
	$(C1541) -format "moria8 save,sv" d64 $(SAVE_IMAGE)

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

clean:
	rm -rf $(OUT)
	rm -f tests/*.prg tests/*.vs tests/*.sym
	rm -f /tmp/test_*.mon
