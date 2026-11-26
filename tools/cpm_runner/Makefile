CC        ?= gcc
CFLAGS    ?= -std=c11 -Wall -Wextra -Werror -O2
BUILD     ?= ../../build
OUT_DIR   ?= $(BUILD)/cpm
OUT_BIN   ?= $(OUT_DIR)/cpm_runner
HOST_ID    := $(shell uname -s)-$(shell uname -m)
HOST_STAMP := $(OUT_DIR)/.cpm_runner.host
CUR_HOST   := $(shell cat "$(HOST_STAMP)" 2>/dev/null)
SJASMPLUS ?= ../../tools/sjasmplus/sjasmplus
RUNCPM    ?= ../../tools/runcpm/RunCPM

SRCS = main.c bdos.c ansi.c json.c z80.c
HDRS = vm.h bdos.h ansi.h json.h z80.h

ifneq ($(CUR_HOST),$(HOST_ID))
.PHONY: $(HOST_STAMP)
endif

ifneq ($(filter clean,$(MAKECMDGOALS)),)
all test $(OUT_BIN) $(HOST_STAMP): | clean
endif

.PHONY: all test clean

all: $(OUT_BIN)

$(HOST_STAMP):
	@mkdir -p "$(dir $@)"
	@printf '%s\n' "$(HOST_ID)" > "$@"

$(OUT_BIN): $(SRCS) $(HDRS) Makefile $(HOST_STAMP)
	@mkdir -p "$(dir $@)"
	$(CC) $(CFLAGS) -o "$@" $(SRCS)

test: $(OUT_BIN)
	@if [ "$(SJASMPLUS)" = "../../tools/sjasmplus/sjasmplus" ]; then \
		../../tools/ensure_sjasmplus.sh ../../tools/sjasmplus "$(SJASMPLUS)"; \
	else \
		../../tools/ensure_sjasmplus.sh --custom ../../tools/sjasmplus "$(SJASMPLUS)"; \
	fi
	@if [ "$(RUNCPM)" = "../../tools/runcpm/RunCPM" ]; then \
		../../tools/ensure_runcpm.sh ../../tools/runcpm "$(RUNCPM)"; \
	else \
		../../tools/ensure_runcpm.sh --custom ../../tools/runcpm "$(RUNCPM)"; \
	fi
	SJASMPLUS="$(SJASMPLUS)" RUNCPM="$(RUNCPM)" python3 -B test_cpm_runner.py

clean:
	rm -f "$(OUT_BIN)" "$(HOST_STAMP)"
