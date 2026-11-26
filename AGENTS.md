# AGENTS.md

This file provides project-wide instructions for coding agents working in this
repository. It is organized by rule criticality: the sections at the top are
hard, non-negotiable gates; the sections at the bottom are reference material.

## Hard Gates

These actions are durable, history-altering, or externally visible. NEVER
perform them unless the user's message in the current session explicitly names
the action:

- `git commit`, `git push`, `git tag`, `git stage`/`git add`, branch
  creation/deletion, PR creation, or any other repo-history mutation.

"proceed", "go ahead", "looks good", "save it", "done", and "add that to the
backlog" are NOT authorization. Authorization must name the action (e.g.
"commit that", "push these"). Intent inferred from task completion is invalid:
finishing requested work ends at edited, verified files in the working tree.

Before any gated action, output exactly one line:
`COMMIT GATE: user said "<the user's words>" which authorizes <action>.`
If the quote does not name the action, stop and ask.

## Non-Negotiable Rules

1. Memory layout violations usually cause silent corruption, wild jumps, CPU
   JAMs, or VICE timeouts. Never delete or weaken boundary-checking `.assert`
   statements. If an assert fails, fix the code or memory layout, not the
   assert. The hard boundaries are listed under Memory And Verification
   Details below.
2. User-visible strings are not scratch space for byte recovery. Do not
   shorten, abbreviate, rename, truncate, or degrade player-visible text unless
   explicitly requested. Recover bytes from code structure, dead helpers, data
   ownership, overlays, deduplication, compression, or banking first.
3. Fix root causes. Never weaken tests, assertions, timeouts, or player-facing
   text to make a change pass.
4. If the user reports a failing command, that exact command is the active
   verification gate until it passes. Direct harness runs, monitor traces,
   narrower filters, or partial suites are diagnostics only unless the user
   named them as the gate.
5. If a product-code task exposes a test, harness, tooling, or infrastructure
   defect, stop and report it; do not expand the task by editing that
   infrastructure automatically. Report the product change, the infrastructure
   defect, why it blocks or does not block validation, and the smallest
   proposed follow-up. Ask whether to backlog it or fix it now. Only edit
   infrastructure without asking when the user explicitly requested
   infrastructure work or the product fix cannot be validated at all without
   that infrastructure change. This stop-and-report rule overrides "loop until
   verified": looping applies only while the blocker is in product code.
6. Do not commit credentials, secrets, private environment files, generated
   build outputs, VICE snapshots, downloaded toolchains, or monitor logs. Do
   not leave generated `.prg`, `.sym`, `.vs`, `.ovl`, `.lst`, `.com`, or `out/`
   artifacts in source directories.
7. Release compliance: every shipping disk and cartridge image must include
   `data/LICENSE` and `data/SOURCE-OFFER` (LF→CR converted, LF→`$9B` ATASCII
   EOL on Atari 8-bit disk, `LF→CRLF` + `0x1A` EOF padded to 128 B CP/M
   records on CP/M disk images, `LF→CRLF` in the CP/M `.zip` bundle, or
   raw/NUL-padded ROM assets in cartridges). Commodore disk images carry them
   as SEQ files `license,s`/`source-offer,s`; the Apple IIe image carries
   ProDOS TXT files `LICENSE`/`SOURCE.OFFER`; the Commander X16 `.zip` bundle
   carries `LICENSE` and `SOURCE-OFFER`; the Atari 8-bit `.atr` image carries
   DOS 2.5 files `LICENSE.TXT` and `SRCOFFER.TXT`; the BBC Master 128 `.ssd`
   image carries DFS files `LICENSE` and `SRCOFFR`; `build/moria8-cpm.zip`
   carries `LICENSE` and `SOURCE-OFFER` (plus `README.TXT`), while
   `build/moria8-cpm-kaypro2.dsk`, `build/moria8-cpm-kaypro4.dsk`, and
   `build/moria8-cpm-c128.d71` carry `LICENSE.TXT` and `SRCOFFR.TXT`;
   `build/cpm/MORIA8.DAT` (`'M8CP'`) embeds both (`DAT_ID_LICENSE`,
   `DAT_ID_SRCOFFR`) for Title `A` (`About`) and Help `L`; and the five shipping cartridges (`moria8-c64.crt`, `moria8-c128.crt`,
   `moria8-plus4.crt`, `moria8-cx16.crt`, `moria8-atari8.car`) embed both
   documents in ROM for Title `A` (`About`) and Help `L`. New platform ports and
   cartridges must do the same.
8. Runtime verification uses VICE warp mode and never relies on timeouts above
   30 seconds. Commands that launch VICE, MAME, or `x16emu` need localhost
   monitor/socket access, which sandboxed execution blocks (you'll see
   `PermissionError`) — request escalated permission on the first attempt; do
   not try a sandboxed run first. See Memory And Verification Details for the
   full escalation list. Exception: AI playtest *sessions* and measurement
   runs (`make playtest-session`, `make playtest-qualify`, `make
   playtest-regress`, `make playtest-m0-report`, `make playtest-disk`), the
   pre-commit bot gate (`make playtest-gate`, minutes), and the opt-in full C128
   generation soak (`make test128-soak-long`) are long-running operational
   jobs, not runtime verification. They have no overall time limit and run until their goal is
   reached. Every emulator command and resume inside a session has a
   60-second response timeout, after which the emulator process is killed and
   restarted. `make playtest-check` and `make playtest-smoke` remain ≤30-second
   verification gates. See `docs/AI_PLAYTEST_DESIGN.md`.
9. Never hardcode or reference any paths outside the project directory in
   Makefiles, scripts, harnesses, or source files (no `$HOME`/`~`, user home
   directories, `/tmp`, or host-specific filesystem locations). External
   environment variables (`A2ROMS`, `X16ROM`, `ATARI8ROMS`, `BBCMROMS`, etc.)
   must have empty defaults (`?=`) in Makefiles and be supplied solely via the
   caller's environment.

Additional durable invariants for memory, banking, zero-page, C128, and
shared-code work live in `docs/INTERNAL_MANDATES.md`; load it before any such
work.

## Behavioral Change Protocol

For gameplay, lifecycle, generation, rendering, or platform memory/banking/TPA
changes, first load `docs/BEHAVIOR_CHANGE_PROTOCOL.md`, then every matching
domain contract:

| Change touches | Load |
| --- | --- |
| Monster records, AI, sleep, awareness, attacks, monster-mutating spells, detection or targeting | `docs/MONSTER_STATE_CONTRACT.md` |
| Generation stages, topology, placement, generation RNG or performance | `docs/DUNGEON_GENERATION_CONTRACT.md` |
| Turn consumption, visibility lifecycle, dirty flags, redraw, repeat commands | `docs/TURN_RENDER_CONTRACT.md` |
| C128 addresses, banks, overlays, copied/runtime code, physical VDC access | `docs/C128_MEMORY_CONTRACT.md` |
| Apple IIe addresses, banks, aux/main ownership, overlays, copied/runtime code | `docs/APPLE2_MEMORY_POLICY.md` |
| Commander X16 addresses, RAM banks, overlays, VERA access | `docs/CX16_MEMORY_CONTRACT.md` |
| Atari 8-bit addresses, `PORTB` / 130XE banking, overlays, `SIOV` bounce, ANTIC/POKEY/GTIA access | `docs/ATARI8_MEMORY_CONTRACT.md` |
| BBC Master 128 addresses, `ROMSEL` / `ACCCON` / `LYNNE` / `ANDY` banking, overlays, MOS/DFS calls | `docs/BBCMASTER_MEMORY_CONTRACT.md` |
| CP/M 2.2 Z80 addresses, TPA map, overlays, BDOS/BIOS calls, ADM-3A/ANSI terminal HAL, `MORIA8.DAT` container | `docs/CPM_MEMORY_CONTRACT.md` |
| None of the above | No contract load required |

Before editing a matched domain, output one line:
`PROTOCOL GATE: loading <contract> because the change touches <row>.`

For cross-domain changes, load each matching contract but apply only the
relevant sections. Do not load all contracts by default.

Visibility routing:

- monster visibility production, detection lifecycle, inspection semantics, or
  targeting: load monster and turn/render
- pure renderer or inspection presentation that only consumes authoritative
  flags: load turn/render only
- AI use of visibility without redraw changes: load monster only
- physical C128 VDC access or layout: also load C128 memory

For behavioral and architectural work, complete the protocol change record and
the applicable verification rows in every matching contract; descriptive
inventories and ledgers are reference material unless the change modifies a
settled decision. Mark safety-critical irrelevant record fields `N/A` with
evidence. Routine work needs only the record required by its tier. Before
writing code, list unresolved questions; if an answer would change data layout,
ownership, representation, memory safety, or observable behavior, ask the user
rather than guessing. Passing tests do not replace final contract review:
before declaring done, re-read the verification rows of each loaded contract
and confirm each applicable row.

## Memory And Verification Details

Hard boundaries:

- C64 main/default must end below `$C000`; its `MAP_BASE` lives at `$C000`
- C128 ownership and `$D000-$DFFF` I/O rules come from
  `docs/C128_MEMORY_CONTRACT.md` and `platforms/commodore/c128/memory128.s`
- Plus/4 follows its target assertions; do not apply C64 `$D000` assumptions
- C64 banked runtime starts at `$F000` and must end at or below `$FFFA`
- C128 banked runtime starts at `$F000` and must end at or below `$FF00`
- Each overlay segment must fit within `$E000-$EFFF`
- Test startup code must be reachable below `$A000` unless it uses a bootstrap
  stub
- Apple IIe ownership comes from `docs/APPLE2_MEMORY_POLICY.md` and
  `platforms/apple2/memory.s`: resident ends below `$7C00`, the play slot
  spans `$7C00-$9FFF`, overlays share the `$A400-$B9FF` window, and aux RAM
  owns the map (`$0800-$3B0B`), auxdata (`$3B0C-$59FF`), and the overlay
  cache (`$5A00-$BFFF`); aux reads execute only from the ZP thunks in
  `platforms/apple2/memory_aux.s` (ZP address labels are in `memory.s`)
- Commander X16 ownership comes from `docs/CX16_MEMORY_CONTRACT.md` and
  `platforms/cx16/memory.s`: unified resident/play ends at or below `$9AFF`,
  the tier-name pool spans `$9B00-$9EFF`, `$9F00-$9FFF` is the VERA/VIA I/O
  hole, and the `$A000-$BFFF` banked RAM window (switched via `$00`) hosts
  KERNAL `KVARSB0` Bank 0, map Banks 1–2, auxdata Bank 3, huffdata + monster
  catalog Huffman names Bank 4, `MONSTER.EXT` Bank 5, `ITEM.CAT` Bank 6,
  reserved extension Banks 7–8, 13 overlays Banks 9–21, title art Bank 22,
  `MONSTER.CAT` Bank 23, cold `LEGALUI` Bank 24, and free/warm pool Banks 25–63
- Atari 8-bit ownership comes from `docs/ATARI8_MEMORY_CONTRACT.md` and
  `platforms/atari8/memory.s`: low resident banking/SIO/130XE/interrupt helpers
  end at or below `$4000`, `Default` resident ends at or below `$C100`,
  `MAP_BASE` spans `$C100-$CFFF` (`3,840` B), `$D000-$D7FF` is the immovable
  GTIA/POKEY/PIA/ANTIC hardware I/O hole, `$D800-$DFFF` holds high resident
  tables (`PLATFORM_TIER_NAME_POOL_BASE`, `FLOOR_ITEM_BASE`, Huffman decode,
  `zp_save_buf`, `msg_history`), overlays and monster tiers share `$E000-$EFFF`,
  and `RuntimeBanked` spans `$F000-$FFF9` below the RAM CPU vectors
  (`$FFFA-$FFFF`)
- BBC Master 128 ownership comes from `docs/BBCMASTER_MEMORY_CONTRACT.md` and
  `platforms/bbcmaster/memory.s`: low resident banking/blitter/MOS helpers end
  at or below `$3000`, `Default` resident ends at or below `$8000`, 20 KB Shadow
  RAM `LYNNE` (`$3000-$7FFF`) holds the C64-ordered font (`$3000-$33FF`),
  dungeon-gen scan scratch (`$3400-$37FF`), `beeb_char_shadow` (`$3800-$3F7F`),
  and the Mode 0 display bitmap (`$4400-$7FFF`), 4 KB Private RAM `ANDY`
  (`$8000-$8FFF`) holds `BeebHuffData`, and Sideways RAM Banks 4–7 (`$8000-$BFFF`)
  hold `BeebPlaySlot` (`$8000-$A3FF`), `PLATFORM_TIER_NAME_POOL_BASE`
  (`$A400-$A7FF`), the `$A800-$BFFF` overlay/tier window (Bank 4), `MAP_BASE`
  (`$8000-$B30B`, Bank 5), `BeebAuxData` (`$8000-$96FF`, Bank 6), and cached
  hot overlays/tier 1 (Banks 5–7)
- CP/M 2.2 Z80 ownership comes from `docs/CPM_MEMORY_CONTRACT.md` and
  `platforms/z80/cpm/memory.inc`: 52 KB TPA minimum (`BDOS_MIN_TOP = 0xD100`),
  resident `MORIA8.COM` (`0x0100-0x55FF`), shared overlay window `0x5600-0x69FF`
  (`5,120` B = `40 × 128` B records, 19 overlays streamed from `'M8CP'`
  `MORIA8.DAT`), resident BSS `0x6A00-0x8BFF` (`z80_state` 64 B pinned at
  `0x6A00-0x6A3F`), 512 B stack `0x8C00-0x8DFF` (`'M8SK'` canary at
  `0x8C00-0x8C03`, `SP = 0x8E00`), `cpm_char_shadow` `0x8E00-0x957F` (reused as
  `GEN_SCAN_SCRATCH_BASE` inside `ovl_gen.asm`), `cpm_color_shadow`
  `0x9580-0x9CFF`, `MAP_BASE` `0x9D00-0xD00B` (`198×66` = `13,068` B;
  overwrites CCP so exit MUST use `BDOS 0` / `JP 0x0000`), FCB pool
  `0xD00C-0xD07F`, and 128 B `cpm_dma_buf` `0xD080-0xD0FF` strictly below
  `0xD100`

After C128 layout, banking, runtime-loaded, copied, or trampolined-code changes,
verify linked address, PRG load header, load destination bank, visible execution
bank, and copy source/destination safety together. For broad C128 banking,
loader, layout, or memory changes (banking/loader/overlay/MMU changes that
touch shared layout), run `make test128` before declaring completion; use
`make test128-fast` for unit iteration and `make test128-fast-smoke` for fast
runtime smoke coverage.

A new C64 runtime test hang after an assembly/layout change is usually a
memory/layout overlap: check the assembler memory map and the boundary asserts
first.

Test files whose `test_start` would land at or above `$A000` must use a
bootstrap stub below BASIC ROM that banks RAM visible before jumping to
`test_start`.

VICE/MAME/`x16emu` escalation list (these launch an emulator and need
unsandboxed localhost access): commands that invoke `x64sc`, `x128`, `xplus4`,
`mame`, or `x16emu`; `make test`; `make test64`; `make test64-cartridge`;
`make test64-cartridge-persistence`; `make test64-legal`; `make test128-legal`;
`make testplus4-legal`; direct `test_legal.py` runs; direct `test_cartridge.py` and
`test_cartridge_persistence.py` runs; `make testplus4`; `make testplus4-runtime`;
`make testplus4-cartridge`; `make testplus4-cartridge-assets`;
`make testplus4-cartridge-persistence`; `make testapple2-smoke`;
`make testapple2-runtime`; `make test128-fast`; `make test128-fast-smoke`;
`make test128`; `make test128-cartridge`; `make test128-soak-long`;
`make testcx16`; `make testcx16-smoke`; `make testcx16-runtime`;
`make testcx16-cartridge`; `make testatari8`; `make testatari8-smoke`;
`make testatari8-runtime`; `make testatari8-fast-smoke`;
`make testatari8-cartridge`; `make testbbcmaster`; `make testbbcmaster-smoke`;
`make testbbcmaster-runtime`; `make testbbcmaster-fast-smoke`;
`make playtest-smoke`; `make playtest-gate`; `make playtest-session`; `make playtest-repro`;
`make playtest-m0-report`; `make playtest-qualify`; `make playtest-regress`;
`make playtest-disk`; `make playtest-selftest`; `make playtest-queue`;
`make playtest-ab`; direct `harness128.py`, `harness128_batch.py`,
`harnessplus4.py`, or `harness_smoke.py` runs; and filtered runtime harness
targets (except CP/M `platforms/z80/cpm/harness_smoke.py`). Static/build-only
checks and CP/M `cpm_runner` / `RunCPM` runs stay sandboxed: `make build`,
`make check-hal-boundaries`, Python static checkers, `git diff`, `make buildcpm`,
`make diskcpm`, `make testcpm`, `tools/cpm_runner`,
`platforms/z80/cpm/harness_smoke.py`, and similar commands that require zero
sockets and do not launch VICE/MAME/`x16emu` (note `ensure-sjasmplus`,
`ensure-runcpm`, and `ensure-ctools` only need network on initial toolchain
download when absent from `tools/`). Before running one of these, output one line:
`ESCALATE: <command> launches VICE/MAME.`

Root-Makefile emulator test targets and playtest runs execute inside a private
network namespace (`tools/isolated.sh`; `ISOLATE=auto|1|0`, default `auto`),
so concurrent runs on the same machine cannot share fixed monitor ports.
Direct `make -C platforms/...` and harness invocations are not isolated;
prefix them with `tools/isolated.sh` when other agents may be testing.

The Apple IIe harness (`platforms/apple2/harness_smoke.py`) drives headless
MAME apple2ee instead of VICE and requires Apple IIe ROMs via the `A2ROMS`
env var or `--rompath` (ROMs are not redistributable). Run one scenario per
invocation; the suite is 24 scenarios plus `boot_title` and `save_reboot_load`
(26 total). The Commander X16 harness (`platforms/cx16/harness_smoke.py`)
drives headless `x16emu -testbench` when `X16EMU` and `X16ROM` are available
(27 scenarios). The Atari 8-bit harness (`platforms/atari8/harness_smoke.py`)
drives headless MAME `a800xl` and `a130xe` when `ATARI8ROMS` is set (16
`a800xl` scenarios plus 5 `a130xe` scenarios = 21 total). The BBC Master 128
harness (`platforms/bbcmaster/harness_smoke.py`) drives headless MAME `bbcm`
when `BBCMROMS` is set (18 scenarios). The CP/M 2.2 Z80 harness
(`platforms/z80/cpm/harness_smoke.py`, 27 scenarios) drives `tools/cpm_runner`
and `RunCPM` over stdio with zero sockets; `make diskcpm` packages
`build/moria8-cpm.zip`, `build/moria8-cpm-kaypro2.dsk`,
`build/moria8-cpm-kaypro4.dsk`, and `build/moria8-cpm-c128.d71` via
`tools/make_cpm_disk.py` using `tools/ctools/` (or `CTOOLS`/`CFORMAT`).

## Working Style

Be direct and evidence-driven. State assumptions, uncertainty, and confidence.
Distinguish evidence from inference. Do not accept unsupported premises, and
change position when the evidence changes. Prefer concise findings with exact
source references over performative certainty or exhaustive narration.

Operational rules:

- Terminology: "TODO" or "task list" means the OpenCode structured session
  task list. "Backlog" means `docs/BACKLOG.md`. Never edit `docs/BACKLOG.md`
  unless the user explicitly says "backlog" or names that file.
- When gameplay behavior, formulas, item/monster/spell catalog data, or
  cross-port parity seems amiss, ambiguous, or inconsistent with original
  Moria, consult `docs/FEATURE_MAP.md` to verify intended VMS Moria 4.8 /
  Umoria 5.7.15 semantics versus intentional Moria8 8-bit adaptations. Keep
  `docs/FEATURE_MAP.md` updated when adding or changing gameplay features,
  catalogs, or port capabilities.
- When you make an assumption, state it explicitly in your reply before acting
  on it; never guess silently.
- Write only the product code needed to satisfy the stated task and the
  verification gate. Do not add features, helpers, or abstractions the task did
  not request. Required tests and `.assert` guards are not optional.
- Make surgical changes; don't refactor adjacent code. Preserve nearby assembly
  style, labels, memory ownership, and test patterns.
- Verification scope matches change scope. Small/localized edits verify
  with the narrowest affected suite or target (e.g. one test file, one
  smoke), not full gates. The full gate (`make test`, which includes
  `make test128`) runs after feature work, multi-file or shared-code
  changes, and before declaring a feature complete. For a test-only failure that does not
  obviously connect to the change, read the failing test and harness
  before running anything. Never burn gate cycles on repeated blind
  reruns: two identical failures means stop and analyze, not rerun.
- Before committing a product-code change (`core/6502/`, `core/z80/`,
  `platforms/`), run
  `make playtest-gate` after the verification gate: the bot plays every port
  and cartridge from fixed seeds, and a game finding fails it. Unit and
  harness suites passed builds whose first store buy crashed two ports.
- Changes touching Commodore storage or disk-setup UI (`core/6502/ui_disk_setup.s`,
  `platforms/shared/save.s`, `platforms/commodore/common/disk_*.s`,
  `save_slot_menu.s`, `platforms/commodore/*/hal/storage*.s`) must satisfy the
  Commodore Storage And KERNAL I/O checklist in `docs/INTERNAL_MANDATES.md` and
  run targeted `make playtest-disk` fault scenarios (`absent_save_drive`,
  `empty_drive`, `status_lost_save`).
- Define success as: the user's failing command passes, or `make test` passes
  if no command was given. Loop until verified. Stop and ask the user when a
  gate action is needed, infrastructure is broken, or the 30-second timeout cap
  blocks verification (see Non-Negotiable Rules).

## Code Review Personalities

When asked for a multi-agent code review with "the standard personalities",
spawn one reviewer for each, review-only (no edits), each reporting findings
with file:line, severity and a concrete failure scenario:

1. **Grumpy staff engineer, tired of AI slop.** Rejects unneeded code,
   speculative abstraction, comment noise, untested claims, and changes that
   go past the request.
2. **Worried engineering manager.** Weighs reliability, maintainability and
   cost: what breaks next, who can maintain it, what the gates and runtime
   cost, and what is left unverified.
3. **6502 / Z80 performance guru.** Adapt focus to the target ISA(s) in the
   diff (6502, Z80, or both for cross-ISA work): for 6502/65C02, audit cycle
   counts, byte budgets, zero-page and stack use, banking/MMU overhead,
   page-crossing penalties, and memory layout; for Z80/CP/M, audit T-states,
   register pressure, `IX`/`IY` and stack cost, `MORIA8.COM`/BSS TPA budgets,
   overlay reload thrashing, BDOS/BIOS call overhead, and `0xD100` ceilings.

## Finishing A Task

A task is done when the requested change is edited, verified by its gate, and
reported. Before declaring done, confirm in your reply:

- the verification gate command passed (the exact named command, not a narrower
  one);
- the diff is reviewed and only intended files changed;
- no generated artifacts were left in source directories;
- applicable contract verification rows are complete, if the protocol applied;
- then stop. Do not commit, stage, push, clean up, or start follow-up work
  unless the user names that action (see Hard Gates).

## Reference

This is a Commodore 64 / Commodore 128 / Plus/4 / Apple IIe / Commander X16 /
Atari 8-bit / Acorn BBC Master 128 / CP/M 2.2 (Z80) assembly project built with
Kick Assembler (`core/6502/`) and `sjasmplus` (`core/z80/`) and tested with VICE,
MAME, `x16emu`, and `cpm_runner`/`RunCPM` headless harnesses.

Primary entry points:

- `platforms/commodore/c64/main.s`
- `platforms/commodore/c128/main.s`
- `platforms/commodore/plus4/main.s`
- `platforms/apple2/main.s`
- `platforms/cx16/main.s`
- `platforms/atari8/main.s`
- `platforms/bbcmaster/main.s`
- `platforms/z80/cpm/main.asm`

Source layout:

- `core/6502/`: platform-agnostic 6502/65C02 gameplay, UI, data, and shared logic.
- `core/z80/`: platform-agnostic Z80 gameplay, UI, and catalog logic.
- `platforms/commodore/hal/`: shared Commodore HAL interfaces.
- `platforms/commodore/common/`: shared Commodore implementation code.
- `platforms/commodore/c64/`: C64 platform code, tests, and harness scripts.
- `platforms/commodore/c128/`: C128 platform code, tests, and harness scripts.
- `platforms/commodore/plus4/`: Plus/4 platform code, tests, and harness
  scripts.
- `platforms/apple2/`: Apple IIe platform code, MAME harness scripts, and
  memory-contract checker.
- `platforms/cx16/`: Commander X16 platform code, `x16emu` TestBench harness
  scripts, and memory-contract checker.
- `platforms/atari8/`: Atari 8-bit (800XL/65XE/130XE) platform code, MAME
  harness scripts, and memory-contract checker.
- `platforms/bbcmaster/`: Acorn BBC Master 128 platform code, MAME harness
  scripts, and memory-contract checker.
- `platforms/z80/cpm/`: CP/M 2.2 Z80 HAL, 19 overlays, `cpm_runner` / `RunCPM`
  harness, and memory-contract checker.
- `build/`: generated binaries, disk images, symbols, snapshots, and test
  scratch output.

Build and test (run from the repository root):

- `make` or `make build`: build C64, C128, Plus/4, Apple IIe, CX16, Atari
  8-bit, BBC Master 128, and CP/M 2.2 Z80 payloads
- `make test`: default regression mix, including the full C128 suite
  (`make test128`), `test-stage-cpm` (CP/M contract + `cpm_runner`/`RunCPM`
  runtime), and MAME/`x16emu` stages when `A2ROMS`, `X16EMU`/`X16ROM`,
  `ATARI8ROMS`, and `BBCMROMS` are set. `make -j8 -O test` runs its eight
  isolated platform stages in parallel after `test-prebuild`
- `make test64`: C64 tests
- `make testplus4`: Plus/4 tests
- `make test128-fast`: stable C128 unit batch
- `make test128-fast-smoke`: high-value C128 runtime smoke subset
- `make test128`: authoritative full C128 suite
- `make testapple2`: Apple IIe memory-contract gate (static)
- `make testapple2-runtime`: Apple IIe memory-contract gate + MAME runtime
  suite (requires `A2ROMS`)
- `make testcx16`: Commander X16 memory-contract gate + `x16emu` runtime suite
- `make testatari8`: Atari 8-bit memory-contract gate + MAME runtime suite
- `make testbbcmaster`: BBC Master 128 memory-contract gate + MAME runtime suite
- `make buildcpm`: build `MORIA8.COM`, 19 overlays, and `'M8CP'` `MORIA8.DAT`
- `make diskcpm`: package `moria8-cpm.zip`, Kaypro II `.dsk`, Kaypro 4 `.dsk`, and C128 `.d71`
- `make testcpm-memory-contract`: CP/M static + built memory-contract gate
- `make testcpm` (`testcpm-runtime`, `testcpm-smoke`): CP/M memory-contract
  gate + `cpm_runner` / `RunCPM` 27-scenario runtime suite
- `make disk`: build shipping C64, C128, Plus/4, Apple IIe, CX16, Atari
  8-bit, BBC Master 128, and CP/M 2.2 Z80 packages
- `make run`, `make run64`, `make run128`, `make runplus4`: launch under VICE
- `make runapple2`: launch under MAME apple2ee (requires `A2ROMS`)
- `make runcx16`: launch under `x16emu`
- `make runatari8`: launch under MAME a800xl (requires `ATARI8ROMS`)
- `make runbbcmaster`: launch under MAME bbcm (requires `BBCMROMS`)
- `make runcpm`: launch `MORIA8.COM` under `tools/cpm_runner`
- `make clean`: remove build artifacts

Kick Assembler downloads into `tools/kickass/` unless `KICKASS` is set;
`sjasmplus`, `RunCPM`, and `ctools`/`cformat` download/build into `tools/`
unless `SJASMPLUS`, `RUNCPM`, `CTOOLS`, and `CFORMAT` are supplied.

Architecture notes:

- Display is character-cell based (PETSCII screen codes on Commodore; the Apple
  IIe translates to Apple display codes at write time; Atari 8-bit and BBC
  Master 128 build a 1 KB C64-screen-code-ordered RAM font at boot; CP/M 2.2
  Z80 outputs ASCII cells defaulting to ADM-3A monochrome (`/A`), with `/V`
  VT100/ANSI SGR 16-color, `/M` ANSI monochrome, and runtime `M`/`=` switching).
- C64, Plus/4, and Atari 8-bit gameplay are 40-column. C128, Apple IIe,
  Commander X16, BBC Master 128, and CP/M 2.2 Z80 gameplay are 80-column.
- BASIC is used for the loader stub only; do not rely on BASIC routines after
  machine-code startup. KERNAL routines are allowed where appropriate.
- Preserve intentional disk-loading and memory-ownership boundaries.

Coding standards: use canonical 6502 / Kick Assembler conventions in `core/6502/`
and 6502 platforms, and canonical Z80 / `sjasmplus` conventions (`0xNN` hex
literals, `DEVICE NOSLOT64K`, `ASSERT` guards) in `core/z80/` and
`platforms/z80/cpm/`. Add or update `.assert` / `ASSERT` guards and runtime
tests for behavior or memory-contract changes.

Future platforms: treat current C64/C128 code as the active implementation, not
the final architecture for every port. Do not add new hardware assumptions to
shared game logic. Keep platform-specific rendering, input, storage, memory
banking, and loader behavior behind platform-owned code. Consult
`docs/CROSS_PLATFORM_STRATEGY.md` before starting any new platform port, and
expand that document when adding each port.

Related documents: `docs/FEATURE_MAP.md` (authoritative VMS Moria 4.8 / Umoria
5.7.15 / Moria8 feature and catalog audit), `docs/INTERNAL_MANDATES.md`
(repository hygiene, zero-page and KERNAL ownership, C128 banking detail,
shared-code rules), `docs/CROSS_PLATFORM_STRATEGY.md` (new ports),
`docs/BACKLOG.md` (deferred work).
