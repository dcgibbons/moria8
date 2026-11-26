# Moria8 CP/M 2.2 Z80 Platform Makefile

SJASMPLUS_DIR ?= ../../../tools/sjasmplus
SJASMPLUS     ?= $(SJASMPLUS_DIR)/sjasmplus
RUNCPM_DIR    ?= ../../../tools/runcpm
RUNCPM        ?= $(RUNCPM_DIR)/RunCPM
CTOOLS_DIR    ?= ../../../tools/ctools
CTOOLS        ?= $(CTOOLS_DIR)/ctools
CFORMAT       ?= $(CTOOLS_DIR)/cformat
CPM_RUNNER    ?= ../../../build/cpm/cpm_runner
CPM_MILESTONE ?= m5
CPM_RUN_ARGS  ?= /V

# Python tools and harnesses must not leave __pycache__ in source directories.
export PYTHONDONTWRITEBYTECODE := 1

OUT       ?= ../../../build
OUTCPM    = $(OUT)/cpm
ABSOUTCPM = $(abspath $(OUTCPM))

MAIN_ASM  = main.asm
OVL_ASMS  := $(sort $(wildcard ovl_*.asm))
OVL_BINS  := $(patsubst %.asm,$(OUTCPM)/%.ovl,$(OVL_ASMS))
OVL_SYMS  := $(patsubst %.asm,$(OUTCPM)/%.sym,$(OVL_ASMS))
OVL_LSTS  := $(patsubst %.asm,$(OUTCPM)/%.lst,$(OVL_ASMS))

COM_OUT   = $(OUTCPM)/MORIA8.COM
MAIN_SYM  = $(OUTCPM)/main.sym
MAIN_EXP  = $(OUTCPM)/main_exp.inc
MAIN_LST  = $(OUTCPM)/main.lst
DAT_OUT   = $(OUTCPM)/MORIA8.DAT
ASSETS_STAMP = $(OUTCPM)/.assets.stamp

ASSET_GEN = ../../../tools/build_z80_assets.py
DAT_GEN   = ../../../tools/make_cpm_dat.py
HARNESS   = harness_smoke.py

ASSET_INPUTS = ../../../data/huffman_strings.txt \
               ../../../platforms/shared/catalog/monster_catalog_spec.json \
               ../../../platforms/shared/item_catalog/item_catalog_spec.json \
               ../../../data/LICENSE \
               ../../../data/SOURCE-OFFER \
               ../../../version.json \
               $(ASSET_GEN) \
               $(DAT_GEN)

ZIP_OUT   = $(OUT)/moria8-cpm.zip
KP2_OUT   = $(OUT)/moria8-cpm-kaypro2.dsk
DSK_OUT   = $(OUT)/moria8-cpm-kaypro4.dsk
D71_OUT   = $(OUT)/moria8-cpm-c128.d71

SJ_FLAGS  = --nologo -I. -I../../../core/z80 -I$(OUTCPM) --outprefix=$(ABSOUTCPM)/

CPM_SOURCES := $(shell find . ../../../core/z80 -type f \( -name '*.asm' -o -name '*.inc' \) 2>/dev/null)

DAT_ALLOW_MISSING = $(if $(filter-out m4 m5 all,$(CPM_MILESTONE)),--allow-missing-overlays)

ifneq ($(filter clean,$(MAKECMDGOALS)),)
$(filter-out clean,$(MAKECMDGOALS)) $(OUTCPM) $(DAT_OUT) $(MAIN_SYM) $(MAIN_EXP) $(MAIN_LST) $(OVL_SYMS) $(OVL_LSTS) build disk run test test-memory-contract test-memory-contract-selftest test-runtime cpm-runner ensure-sjasmplus ensure-runcpm ensure-ctools: | clean
$(ASSETS_STAMP) $(COM_OUT) $(OVL_BINS): clean
endif

.PHONY: all build disk run test test-memory-contract test-memory-contract-selftest test-runtime clean ensure-sjasmplus ensure-runcpm ensure-ctools cpm-runner

all: build

ensure-sjasmplus:
ifeq ($(origin SJASMPLUS),file)
	@../../../tools/ensure_sjasmplus.sh "$(SJASMPLUS_DIR)" "$(SJASMPLUS)"
else
	@../../../tools/ensure_sjasmplus.sh --custom "$(SJASMPLUS_DIR)" "$(SJASMPLUS)"
endif

ensure-runcpm:
ifeq ($(origin RUNCPM),file)
	@../../../tools/ensure_runcpm.sh "$(RUNCPM_DIR)" "$(RUNCPM)"
else
	@../../../tools/ensure_runcpm.sh --custom "$(RUNCPM_DIR)" "$(RUNCPM)"
endif

ensure-ctools:
ifneq ($(origin CTOOLS),file)
ifneq ($(origin CFORMAT),file)
	@../../../tools/ensure_ctools.sh --custom "$(CTOOLS_DIR)" "$(CTOOLS)" "$(CFORMAT)"
else
	@../../../tools/ensure_ctools.sh "$(CTOOLS_DIR)" "$(CTOOLS)" "$(CFORMAT)"
endif
else
	@../../../tools/ensure_ctools.sh "$(CTOOLS_DIR)" "$(CTOOLS)" "$(CFORMAT)"
endif

cpm-runner:
ifeq ($(origin CPM_RUNNER),file)
	$(MAKE) -C ../../../tools/cpm_runner all
else
	@(test -x "$(CPM_RUNNER)" || command -v "$(CPM_RUNNER)" >/dev/null 2>&1) || { echo "ERROR: custom CPM_RUNNER not found or not executable: $(CPM_RUNNER)" >&2; exit 1; }
endif

$(OUTCPM):
	@mkdir -p "$(OUTCPM)"

$(ASSETS_STAMP): $(ASSET_INPUTS) | $(OUTCPM)
	@mkdir -p "$(OUTCPM)"
	python3 -B "$(ASSET_GEN)" --out-dir "$(OUTCPM)"
	python3 -B "$(DAT_GEN)" --out-dir "$(OUTCPM)" --emit-inc-only
	@touch "$@"

$(COM_OUT): $(MAIN_ASM) $(CPM_SOURCES) $(ASSETS_STAMP) | ensure-sjasmplus $(OUTCPM)
	@mkdir -p "$(OUTCPM)"
	"$(SJASMPLUS)" $(SJ_FLAGS) --sym="$(MAIN_SYM)" --exp="$(MAIN_EXP)" --lst="$(MAIN_LST)" "$(MAIN_ASM)"

$(MAIN_SYM): $(COM_OUT)
	@test -f "$@"

$(MAIN_EXP): $(COM_OUT)
	@test -f "$@"

$(MAIN_LST): $(COM_OUT)
	@test -f "$@"

$(OUTCPM)/ovl_%.ovl: ovl_%.asm $(MAIN_SYM) $(MAIN_EXP) $(CPM_SOURCES) $(ASSETS_STAMP) | ensure-sjasmplus $(OUTCPM)
	@mkdir -p "$(OUTCPM)"
	"$(SJASMPLUS)" $(SJ_FLAGS) --sym="$(OUTCPM)/ovl_$*.sym" --lst="$(OUTCPM)/ovl_$*.lst" "$<"

$(OUTCPM)/ovl_%.sym: $(OUTCPM)/ovl_%.ovl
	@test -f "$@"

$(OUTCPM)/ovl_%.lst: $(OUTCPM)/ovl_%.ovl
	@test -f "$@"

build: $(ASSETS_STAMP)
ifeq ($(wildcard $(MAIN_ASM)),)
	@echo "INFO: $(MAIN_ASM) not yet created (M0 contract phase); packing MORIA8.DAT data assets."
	python3 -B "$(DAT_GEN)" --out-dir "$(OUTCPM)" $(DAT_ALLOW_MISSING)
else
	@$(MAKE) "$(COM_OUT)" $(OVL_BINS)
	python3 -B "$(DAT_GEN)" --out-dir "$(OUTCPM)" $(DAT_ALLOW_MISSING)
endif

disk: build ensure-ctools
ifeq ($(wildcard $(MAIN_ASM)),)
	@echo "INFO: $(MAIN_ASM) not yet created (M0 contract phase); skipping disk image packaging."
else
	python3 -B ../../../tools/make_cpm_disk.py --build-dir "$(OUTCPM)" --zip "$(ZIP_OUT)" --kaypro2 "$(KP2_OUT)" --kaypro4 "$(DSK_OUT)" --c128-d71 "$(D71_OUT)" --ctools "$(CTOOLS)" --cformat "$(CFORMAT)"
endif

test-memory-contract-selftest: | ensure-sjasmplus
	python3 -B "$(ASSET_GEN)" --selftest
	python3 -B "$(DAT_GEN)" --selftest
	python3 -B ../../../tools/make_cpm_disk.py --selftest
	python3 -B check_memory_contract.py --selftest

test-memory-contract: build test-memory-contract-selftest
	python3 -B check_memory_contract.py --build-dir "$(OUTCPM)" --lst-dir "$(OUTCPM)" --milestone "$(CPM_MILESTONE)"

test-runtime: build cpm-runner ensure-runcpm ensure-sjasmplus
	$(MAKE) -C ../../../tools/cpm_runner test
ifeq ($(wildcard $(MAIN_ASM)),)
	@echo "INFO: $(MAIN_ASM) not yet created (M0 contract phase); skipping CP/M game harness."
else ifeq ($(wildcard $(HARNESS)),)
	@echo "INFO: $(HARNESS) not yet created; skipping CP/M game harness."
else
	python3 -B "$(HARNESS)" --runner "$(CPM_RUNNER)" --runcpm "$(RUNCPM)" --sjasmplus "$(SJASMPLUS)" --build-dir "$(OUTCPM)" --all
endif

test: test-memory-contract test-runtime

run: build cpm-runner
ifeq ($(wildcard $(MAIN_ASM)),)
	@echo "ERROR: $(MAIN_ASM) not yet created; cannot launch MORIA8.COM." >&2; exit 1
else
	"$(CPM_RUNNER)" --max-steps 0 --workdir "$(OUTCPM)" "$(COM_OUT)" $(CPM_RUN_ARGS)
endif

clean:
	rm -rf "$(OUTCPM)" "$(ZIP_OUT)" "$(KP2_OUT)" "$(DSK_OUT)" "$(D71_OUT)"
