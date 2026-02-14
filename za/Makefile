# Makefile — Moria C64/C128
#
# Targets:
#   make          Build moria.prg
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
KICKASS     ?= /Applications/C64/KickAssembler/KickAss.jar
VICE        ?= x64sc
C1541       ?= c1541
JAVA        ?= java

# ── Project layout ────────────────────────────────────────
OUT         = out
MAIN_SRC    = main.s
MAIN_PRG    = $(OUT)/moria.prg
DISK_IMAGE  = $(OUT)/moria.d64
DISK_NAME   = "moria,m6"

# All source files that main.s imports (dependency list)
SOURCES     = $(wildcard *.s)
TEST_SOURCES = $(wildcard tests/*.s)

# ── KickAssembler flags ──────────────────────────────────
KA_FLAGS    = -showmem -vicesymbols

# ── VICE flags ────────────────────────────────────────────
# For interactive play
RUN_FLAGS   = -autostartprgmode 1 -sound -sounddev coreaudio

# ── Targets ───────────────────────────────────────────────
.PHONY: all build run rundisk debug test disk clean

all: build

build: $(MAIN_PRG)

# Main program — rebuild if ANY .s file changes.
# KickAssembler resolves all #imports from main.s in one pass,
# so there are no intermediate .o files to track.
$(MAIN_PRG): $(SOURCES) | $(OUT)
	$(JAVA) -jar $(KICKASS) $(MAIN_SRC) $(KA_FLAGS) -o $(MAIN_PRG)

# Launch in VICE emulator
run: $(MAIN_PRG)
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

# Create a 1541 .d64 disk image
disk: $(MAIN_PRG) | $(OUT)
	$(C1541) -format $(DISK_NAME) d64 $(DISK_IMAGE) \
	         -attach $(DISK_IMAGE) \
	         -write $(MAIN_PRG) "moria"

$(OUT):
	mkdir -p $(OUT)

clean:
	rm -rf $(OUT)
	rm -f tests/*.prg tests/*.vs tests/*.sym
	rm -f /tmp/test_*.mon
