# Commodore Code Audit Plan

Date: 2026-03-25

Scope:
- `commodore/common/`
- `commodore/c64/`
- `commodore/c128/`

Goal:
- identify common 6502 mistakes and fragile idioms
- identify duplicated code that should be shared or table-driven
- identify wasteful code, either in bytes or cycles
- identify style/structure/alignment inconsistencies that make future bugs more likely

Method:
- reused current local audit context from `commodore/AUDIT.md`, `commodore/DESIGN.md`, `tasks/6502_gotchas.md`, and `tasks/todo.md`
- inspected shared hot paths, both screen backends, both input drivers, item/UI helpers, message handling, and C128 runtime wrappers
- treated savings as estimates unless explicitly measured
- kept current C64/C128 banking and segment constraints in scope for every recommendation

## Governance And Risk Management

These items take priority over opportunistic cleanup. They harden the project against silent layout drift, platform-contract regressions, and the C64/C128 memory ceilings.

| ID | Title | Goal | Priority |
|---|---|---|---|
| `HEADROOM-1` | Central Memory Governance | Consolidate scattered boundary checks into one memory/headroom report plus shared safety sentinels. | Critical |
| `ALIGN-1` | Hot-Path Alignment Audit | Identify page-crossing penalties and misaligned tables in render, combat, and input hot paths. | High |
| `ZP-1` | Automated ZP Ownership Scan | Detect raw `$90-$FF` usage outside explicitly blessed KERNAL-transient or MMU-helper cases. | High |
| `LINT-1` | 6502 Anti-Pattern Linter | Automate recurring instruction-shape nits so manual audits stay architectural. | Medium |
| `API-1` | Canonical C128 Text Contract | Define one caller-visible text API and hide PETSCII/screen-code/backend translation behind it. | High |

## Integrated Findings

### `HEADROOM-1` C64 And C128 Headroom Must Become A First-Class Report

Evidence:
- `commodore/c64/main.s:825-894`
- `commodore/c128/main.s:3131-3243`
- `commodore/c128/memory128.s:809-832`

What is happening:
- the tree already has many important `.assert` guards
- they are distributed across multiple files and protect individual regions well
- what is missing is one report that tells the engineer, in one place, how much headroom remains in each constrained region

Why this matters:
- the C64 main image is already pinned to a hard `MAP_BASE` boundary
- the C128 has many more guards, but they are fragmented across staged payload, Bank 1 ownership, overlay cache, trampolines, and I/O-hole exclusions
- pass/fail alone is not enough when the project is this close to physical limits

Required deliverable:
- one generated memory report that emits exact byte margins for:
  - C64 main image vs `MAP_BASE`
  - C64 banked payload vs `$D000` and `<= $FFFA`
  - each C64 overlay vs `$F000`
  - C128 staged payload source vs overlay window
  - C128 resident/banked payload vs `<= $FFFA`
  - C128 key Bank 1 ownership windows, especially DB, tier cache, overlay cache, reserved gaps, and I/O avoidance

Recommended implementation:
- keep platform-specific assertions where they belong
- add one shared boundary-spec source and one report/manifest output so both builds speak the same language about remaining margin

Phase 2 result:
- executed on `2026-03-25`; exact numbers are recorded in `commodore/HEADROOM_REPORT.md`
- the report was refreshed after phases 3 through 6 because the live layout changed
- current highest-risk measured margins are:
  - C128 `RuntimeLowData` to floor items: `0` bytes
  - C64 runtime banked code to `$FFFA`: `2` bytes
  - C64 staged banked payload source to `$D000`: `3` bytes
  - C128 startup overlay to `$F000`: `35` bytes
  - C64 main image to `MAP_BASE`: `40` bytes
  - C64 startup overlay to `$F000`: `44` bytes
  - C128 staged source / program image to `$E000`: `54` bytes

### `ALIGN-1` Hot-Path Page Crossing Is Real, But The Live High-ROI Cases Are Narrow

Evidence:
- current explicit page-alignment checks are narrow:
  - `commodore/c64/memory.s:214`
  - `commodore/c128/memory128.s:812`
- live hot-path sweep completed against:
  - `commodore/c64/dungeon_render.s`
  - `commodore/c128/dungeon_render_vdc.s`
  - `commodore/common/combat.s`
  - `commodore/c64/input.s`
  - `commodore/c128/input128.s`
  - `commodore/c64/out/main.vs`
  - `commodore/c128/out/main.vs`

What is happening:
- the tree has a few targeted alignment assertions
- phase 8 checked the current symbol layout for the indexed tables used in render, combat, and input
- most of the genuinely hot row/tile tables are already page-safe in the live binaries
- the remaining crossings are concentrated in a small set of creature/input tables rather than the core row/tile walkers

Why this matters:
- on 6502/8502, page crossing adds cost in exactly the loops this project runs constantly
- the problem is especially relevant for render and combat tables because those loops are dense and repeated

Required deliverable:
- a hot-path sweep of indexed `lda table,x`, `lda table,y`, and indirect-indexed map/table accesses in the render/combat/input cores
- explicit notes on which tables should be page-aligned or split to avoid routine boundary crossings

Guardrail:
- do not claim percentage wins unless they are measured on this codebase

Phase 8 result:
- implemented on `2026-03-25`
- confirmed page-safe hot tables in the live builds:
  - C64 `map_row_*`, `screen_row_*`, `color_row_*`, `tile_screen_codes`, `tile_colors`
  - C128 `map_row_*`, `screen_row_*`, `color_row_*`, `tile_screen_codes`, `tile_vdc_colors`, `cia_scancode_table`, `key_map_petscii`, `key_map_cmd`, `vic_to_vdc_color`
- real remaining crossings in or near the audited paths:
  - C64 `key_map_petscii` at `$10E6`: linear search crosses for indices `>= 26`
  - C64 `cr_color` at `$35E0`: crosses for monster types `>= 32`
  - C128 `cr_display` at `$5EF3`: crosses for monster types `>= 13`
  - C128 `cr_level` at `$5FF7`: crosses for monster types `>= 9`
- expected impact:
  - C64 key-search path: worst case `27` extra cycles on a full-table scan; common movement keys avoid the penalty because they live in the front half
  - creature-table lookups: `+1` cycle per crossed lookup, real but modest
  - C128 render remains dominated by VDC register I/O, so creature-table realignment is lower value than it would be on pure RAM-backed rendering
- recommendation:
  - do not spend scarce headroom on blind `.align $100` padding
  - if this is optimized later, prefer table reordering/packing for the specific crossings above, starting with the C64 input lookup table
- focused verification completed:
  - `make -C commodore/c64 build` → `PASS`
  - `make -B -C commodore/c128 build128` → `PASS`
  - `commodore/c64/run_tests.sh` → `33 passed, 0 failed`
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12` → `PASS`

### `ZP-1` Zero-Page Governance Was Commented, And Is Now Enforced

Evidence:
- `commodore/common/zeropage.s:1-98`
- `commodore/common/zeropage.s:225-228`
- `tools/check_zp_usage.py`
- `Makefile`

What is happening:
- the project has a declared ZP contract and boundary assertions
- phase 7 adds an opcode-aware scanner plus a reproducible `make check-zp` entry point
- the scanner now fails on raw `$90-$FF` zero-page memory operands and warns on raw `$02-$8F` operands where named labels should normally be used

Why this matters:
- manual discipline alone is brittle
- this is exactly the kind of drift that can silently break disk I/O or IRQ-time behavior

Required deliverable:
- a scan that flags raw `$90-$FF` zero-page usage except for explicitly blessed cases such as MMU/KERNAL helper scratch
- ideally also flag raw literal ZP use when a named label should have been used instead

Phase 7 result:
- implemented on `2026-03-25`
- added `tools/check_zp_usage.py` with self-test coverage for:
  - raw volatile operands
  - raw safe-zone operands
  - immediate-expression false positives such as `#$ff` and `#... & $ff`
  - `.byte` data and comment text
- the first live run exposed intentional but previously unnamed raw accesses to:
  - `$90` KERNAL status / `READST`
  - `$C6` KERNAL keyboard buffer count
  - `$CC` Screen Editor state
  - `$D8` C128 Screen Editor 80-column mode byte
- phase 7 resolved those hits by naming them in `commodore/common/zeropage.s` and converting the live call sites to symbolic operands
- focused verification completed:
  - `make check-zp` → `0 error(s), 0 warning(s)`
  - `commodore/c64/run_tests.sh` → `33 passed, 0 failed`
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12` → `PASS`

### `API-1` The C128 Text Contract Needs One External Rule

Evidence:
- `commodore/c128/screen_vdc.s:279-300`
- `commodore/c128/screen_vdc.s:338-372`

What is happening:
- the VDC backend used to expose a mixed contract:
  - `screen_put_char` translated PETSCII
  - `screen_put_string` expected screen-code strings
- phase 5 normalizes the public string path so both public text entry points accept PETSCII while still tolerating embedded direct VDC/control bytes already used by packed UI data

Why this matters:
- this is survivable today, but it is architectural debt
- runtime-generated text and future UI work will continue to pay for this ambiguity

Required deliverable:
- one caller-visible text contract for C128 UI/screen code
- backend translation/storage details stay internal to the screen layer

Guardrail:
- do not hardwire the audit to “PETSCII everywhere” until implementation work proves that is the cleanest shape
- the contract requirement is external consistency, not a premature internal storage decision

Phase 5 result:
- implemented on `2026-03-25`
- updated `commodore/c128/screen_vdc.s` so `screen_put_string` now applies the same PETSCII-to-VDC Set 1 translation rule as `screen_put_char`
- preserved compatibility for existing embedded direct VDC/control bytes by keeping the translator pass-through behavior outside PETSCII lowercase
- focused verification completed:
  - `commodore/c128/tests/test_vdc_attr128.s` passed with new coverage for lowercase PETSCII string translation and direct VDC-byte passthrough
  - the fast C128 batch passed via `python3 -u commodore/c128/harness128_batch.py --mode compare --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12`

### `LINT-1` Repeated 6502 Nits Should Move Into Tooling

Context:
- both audits and the source sweep found recurring instruction-shape issues such as redundant zero compares and branch-through-jump ladders

What is happening:
- these patterns are still found manually

Why this matters:
- staff-level manual review time should go to architecture, contracts, and performance cliffs
- the repo should automate the simple checks

Required deliverable:
- a lightweight static check for:
  - redundant `cmp #0` after flag-setting instructions
  - suspicious branch-then-immediate-jump shapes
  - raw zero-page literals outside approved files/ranges
  - possibly duplicate local constants already declared in shared headers

Phase 9 result:
- implemented on `2026-03-25`
- added `tools/check_6502_lint.py` and root `make check-6502-lint`
- the first hard-fail rule is intentionally narrow:
  - only `cmp/cpx/cpy #0`
  - only when the previous real instruction already set the relevant N/Z flags
  - only when the next real instruction branches on those same flags (`beq/bne/bmi/bpl`)
- cleaned the first six live hits in shipping code:
  - three in `commodore/c128/input128.s`
  - two in `commodore/common/dungeon_gen.s`
  - one in `commodore/common/ui_character.s`
- the branch-then-jump ladder rule currently remains advisory:
  - live first-pass result is `320` warnings
  - these are reported as warnings only because many are deliberate branch-range workarounds
- focused verification completed:
  - `make check-6502-lint` → `0 error(s), 320 warning(s)`
  - `make check-zp` → `0 error(s), 0 warning(s)`
  - `commodore/c64/run_tests.sh` → `33 passed, 0 failed`
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12` → `PASS`

### `WRAP-1` C128 KERNAL Wrapper IRQ-State Contract Was Live And Is Now Fixed

Evidence:
- historical finding:
  - `commodore/AUDIT.md:28-32`
- current wrapper scaffold:
  - `commodore/c128/main.s:456-690`
- focused cold-boot verification probe:
  - `commodore/c128/tests/test_wrapper_irq128.s`

What is happening:
- the old wrapper scaffold captured processor flags only after the KERNAL call had already run inside the `EnterKernal` / `ExitKernal` regime
- phase 1 confirmed the live failure on the first `CLI` case:
  - stage `#$11` (`w_readst` from caller-`CLI`)
  - captured interrupt bit `#$04`
- phase 4 replaces that contract with a wrapper epilogue that restores the KERNAL return flags while splicing back the caller's original `I` bit

Why this matters:
- this is not a cosmetic flag issue; it breaks the caller-visible interrupt contract
- any path that expects IRQs to remain enabled after a wrapper call can silently lose STOP-key checks or other IRQ-driven runtime behavior
- `CA-09` macro-generation work was correctly blocked until this correctness bug was fixed

Required deliverable:
- fix the wrapper contract first, then refactor the repetition
- the likely repair is to preserve the caller processor state before `:EnterKernal()` and restore it only after `:ExitKernal()`
- verify the fix across the shared wrapper shape and the `w_load` special case

Expected savings / cost if fixed:
- code size: likely neutral
- runtime: likely neutral to a very small cycle cost increase
- correctness/stability: high

Phase 4 result:
- implemented on `2026-03-25`
- updated the shared wrapper scaffold in `commodore/c128/main.s` so the wrappers:
  - save caller status before `:EnterKernal()`
  - preserve KERNAL return flags
  - restore the caller's original `I` bit on exit
- covered the common scaffold plus `w_load`, `kernal_load_safe`, and `safe_setbnk`
- focused verification completed:
  - `commodore/c128/tests/test_wrapper_irq128.s` passed
  - `make test128-fast` passed

## Tactical Cleanup Summary

These items remain valid unless noted as already completed, and they now sit beneath the governance layer above.

| ID | Priority | Theme | Expected savings / cost if fixed |
|---|---|---|---|
| `WRAP-1` | Critical | restore caller IRQ-state across C128 KERNAL wrappers | completed in phase 4; small byte/cycle cost, high correctness win |
| `CA-11` | High | fix melee to-hit overflow / sign handling | no meaningful byte win; small cycle cost increase, large correctness win |
| `CA-12` | Medium | advance RNG by a real byte step instead of one-bit output | completed in phase 6; cycle cost increase, meaningful quality win |
| `CA-01` | High | unify numeric formatting kernels/tables | roughly `140-260` bytes per build, plus reduced drift |
| `CA-02` | High | stop rescanning filtered inventory/equipment views | roughly `200-600` cycles per filtered prompt path; code size small positive or neutral |
| `CA-03` | Medium | unify hunger-state thresholds and recompute logic | roughly `20-40` bytes per build, plus removes sync risk |
| `CA-04` | Medium | collapse repeated modal UI restore/dismiss paths | roughly `20-50` bytes per build, plus more consistent return behavior |
| `CA-06` | Medium | remove message-history offset recomputation | roughly `15-25` cycles per message save and a small byte win |
| `CA-07` | Medium | benchmark/replace full-screen row-by-row clears where safe | time-only win on every safe full-screen clear; larger on C128 |
| `CA-05` | Low | reduce item-effect compare ladders with table/range dispatch | likely `10-30` bytes and fewer worst-case branches in affected commands |
| `CA-08` | Low | factor repeated `fi_add_*` field zeroing | roughly `15-35` bytes per build, plus less partial-init risk |
| `CA-09` | Low | macro-generate repetitive C128 KERNAL wrappers | byte savings likely `0-30` bytes, maintenance gain high |
| `CA-10` | Low | normalize screen/input contracts and shared tables | runtime savings mostly none; correctness/style gain high |

## Findings

### `CA-01` Shared Numeric Formatting Is Duplicated Four Ways

Evidence:
- `commodore/c64/screen.s:272-430`
- `commodore/c128/screen_vdc.s:625-764`
- `commodore/common/score.s:96-169`
- `commodore/common/combat.s:1159-1262`

What is happening:
- both screen backends contain nearly identical `screen_put_hex`, `screen_put_decimal`, `screen_put_decimal_rj2`, `screen_put_decimal_lz2`, and `screen_put_decimal_16`
- `score.s` has its own 24-bit decimal formatter and power-of-10 tables
- `combat.s` then duplicates the decimal-conversion logic again for buffered combat messages
- `combat_append_decimal_16` also depends on `decimal_powers_lo/hi`, which currently live in the screen backend, so combat formatting is coupled to screen formatting data

Why this matters:
- this is the clearest same-build redundancy in the current tree
- the formatter logic already drifted into four maintenance surfaces
- the cross-module dependency from gameplay code into screen tables is structurally fragile

Recommended refactor:
- move the decimal/hex conversion kernels and power-of-10 tables into a shared `commodore/common/numeric_format.s`
- keep only tiny output adapters per call site:
  - screen-emitter adapter for `screen_put_char`
  - combat-buffer adapter for `combat_msg_buf`
- explicitly move the power-of-10 tables out of the screen backends so combat stops importing formatting data indirectly

Expected savings:
- code size: roughly `140-260` bytes per build if the shared conversion core replaces the duplicated backend-local, score-local, and combat-local loops cleanly
- maintenance: high; one formatter bug fix instead of four
- correctness risk reduced: removes screen/backend ownership confusion around decimal tables

Verification:
- unit-check decimal output at `0`, `9`, `10`, `99`, `100`, `255`, `9999`, `10000`, `65535`
- verify both VIC-II and VDC text paths still render correctly
- verify score screen 24-bit output still formats `0`, `1`, `999999`, and `16777215` correctly
- verify combat messages that append numbers still terminate correctly

### `CA-02` Filtered Inventory Selection Does Multiple Full Rescans

Evidence:
- `commodore/common/player_items.s:113-248`
- `commodore/common/ui_inventory.s:20-180`

What is happening:
- `piw_inv_slot_matches_filter` is the source of truth for visibility
- `piw_count_filtered_inv` scans all slots to count visible items
- `piw_pick_filtered_inv_key` scans all slots again to map a letter back to a sparse slot
- the filtered inventory overlay does another full scan to render visible entries

Why this matters:
- this path is correct, but computationally repetitive
- the same filter decision is recomputed multiple times for the same prompt lifecycle
- it also keeps prompt text, overlay text, and input mapping coupled only by re-running the same logic repeatedly

Recommended refactor:
- build a visible-slot list once for the active filter when entering a filtered prompt
- store:
  - visible count
  - visible carried slot list
  - visible equipment slot list for takeoff if needed
- then reuse that cache for:
  - prompt range
  - overlay letters
  - input mapping

Expected savings:
- time: roughly `200-600` cycles per filtered prompt interaction, depending on how many passes get removed
- code size: probably neutral to slightly positive; a small slot-list buffer may trade a few bytes of RAM for less code duplication
- maintainability: better parity between prompt, overlay, and parser because they consume the same cached list

Verification:
- sparse inventory prompt/filter regression tests
- takeoff prompt with non-adjacent occupied equipment slots
- zero-match behavior

### `CA-03` Hunger Thresholds And Hunger-State Recompute Are Duplicated

Evidence:
- `commodore/common/turn.s:13-15`
- `commodore/common/player_items.s:23-26`
- `commodore/common/player_items.s:705-724`
- `commodore/common/turn.s:191-223`

What is happening:
- hunger thresholds are duplicated in `turn.s` and `player_items.s`
- the state transition logic for `FULL/HUNGRY/WEAK/FAINT` is duplicated as well

Why this matters:
- this is a classic drift trap and the source already says so
- a future threshold tweak can quietly desync turn-time decay from eat-time recomputation

Recommended refactor:
- move the thresholds into one shared location
- add one shared `player_update_hunger_state` helper that:
  - reads the current food counter
  - updates `zp_hunger_state`
  - optionally leaves starvation damage to the turn path only

Expected savings:
- code size: roughly `20-40` bytes per build
- runtime: negligible
- correctness: moderate, because it removes a known “must stay in sync” hazard

Verification:
- eat ration and slime mold around each threshold edge
- starvation still damages only from the turn path

### `CA-04` Modal UI Return/Dismiss Logic Is Repeated Across Shared Code

Evidence:
- `commodore/common/player_items.s:71-107`
- `commodore/common/game_loop_helpers.s:18-50`
- `commodore/common/game_loop_helpers.s:196-245`
- `commodore/common/player_magic.s:146-149`
- `commodore/common/wizard.s:529-543`

What is happening:
- multiple commands do the same “wait for dismiss key, clear modal UI, restore viewport, redraw status” dance
- there is already partial centralization in `ui_view_return_to_gameplay_view` and `vp_render_status_loop`, but some callers still open-code nearly identical sequences

Why this matters:
- this is exactly the kind of UI drift that caused prior full-screen cleanup bugs
- repeated restore code makes it easy for one path to miss a buffer flush, status redraw, or C128 key-release rule

Recommended refactor:
- add one shared helper for “dismiss modal overlay and restore gameplay view”
- split variants only where behavior truly differs:
  - full-screen clear return
  - help-style modal return
  - read-only overlay with fresh-key requirement

Expected savings:
- code size: roughly `20-50` bytes per build
- runtime: negligible
- correctness: moderate, because one restore policy is easier to audit than several nearly-identical ones

Verification:
- inventory/equipment/help/character/wizard modal round-trips on both C64 and C128
- confirm stale keypresses still do not auto-dismiss the next prompt

### `CA-05` Potion And Scroll Effect Dispatch Uses Long Compare/Jump Ladders

Evidence:
- `commodore/common/player_items.s:864-899`
- `commodore/common/player_items.s:1178-1218`

What is happening:
- potion effects and scroll effects dispatch through long `cmp` plus `beq/bne/jmp` chains
- several cases use the especially branch-heavy form `cmp #imm / bne next / jmp handler`

Why this matters:
- this is branchy, hard to scan, and expensive in the worst case
- it also encourages style drift because each new item effect extends the ladder differently

Recommended refactor:
- if IDs remain dense enough, normalize by subtracting the first in-range ID and dispatch through a compact handler table
- if the ID space stays sparse, use a `(item_id, handler)` table walker instead of hardwired chains

Expected savings:
- code size: likely `10-30` bytes in the affected command paths if a compact table replaces the current ladders
- runtime: fewer branches for later-case items; generic fallthrough also gets cheaper
- maintainability: high, because adding one effect becomes a table edit, not a branch-maze edit

Verification:
- potion and scroll regression tests for every implemented effect
- unknown/default item IDs still hit the generic message path

### `CA-06` Message History Save Recomputes Slot Offsets Every Time

Evidence:
- `commodore/common/ui_messages.s:259-336`

What is happening:
- `msg_save_history` multiplies `msg_hist_idx` by `40` or `80` on every message save using shift/add arithmetic
- the copy itself is fine; the repeated offset math is the avoidable part

Why this matters:
- message printing is a frequent path
- the current implementation is correct but spends extra instructions on bookkeeping every time a message is archived

Recommended refactor:
- keep either:
  - a rolling destination pointer, or
  - a per-slot pointer table initialized once
- then advance/wrap the pointer instead of recomputing the offset from scratch every message

Expected savings:
- time: roughly `15-25` cycles per message save
- code size: small win, likely `8-16` bytes depending on chosen shape
- clarity: better separation between “which slot” and “copy message bytes”

Verification:
- message history wraparound after more than `8` messages
- both screen widths still archive the full line width correctly

### `CA-07` `ui_help_clear_all` Is A Full-Screen Row Loop, Not A True Full-Screen Clear

Evidence:
- `commodore/common/ui_help_clear.s:8-22`

What is happening:
- `ui_help_clear_all` clears the screen by calling `screen_clear_row` for all `25` rows
- this is used by many modal screens

Why this matters:
- for callers that genuinely want a full-screen clear, this repeats row setup and per-row overhead that `screen_clear` already knows how to do in bulk
- the cost is larger on the VDC path because each row clear does two VDC address-set sequences

Recommended refactor:
- classify full-screen clears into two buckets:
  - paths that truly need the safer row-by-row clear behavior
  - paths that can safely use `screen_clear`
- switch only the proven-safe bucket to a shared full-screen fast clear helper

Expected savings:
- time only; no meaningful code-size change unless the helper replaces repeated setup
- likely noticeable on modal screen entry/exit, especially on C128
- do not assume every call site is safe to change

Guardrail:
- prior lessons in `tasks/lessons.md` show that some C64 full-screen bugs required row-by-row clearing, so this must be caller-by-caller, not a blanket replacement

Verification:
- visual regression pass for help, character, inventory, wizard, title-adjacent screens
- status rows must still redraw correctly after the return path

### `CA-08` `fi_add_*` Metadata Zeroing Is Repeated In Several Producers

Evidence:
- `commodore/common/item.s:1340-1346`
- `commodore/common/wizard.s:110-115`
- `commodore/common/wizard.s:380-383`
- `commodore/common/ui_wizard.s:343-348`
- `commodore/common/special_rooms.s:400-404`

What is happening:
- multiple item/gold producers zero overlapping subsets of:
  - `fi_add_qty_hi`
  - `fi_add_p1`
  - `fi_add_flags`
  - `fi_add_ego`

Why this matters:
- repeated setup code is easy to partially update
- this is a common source of stale-field bugs in 6502 code, where one leftover byte silently changes item behavior

Recommended refactor:
- add one or two tiny helpers:
  - clear full item metadata
  - clear gold/simple metadata
- use those helpers from the producers that are not cycle-sensitive

Expected savings:
- code size: roughly `15-35` bytes per build depending on the final helper shape
- runtime: negligible; these are cold paths
- correctness: moderate, because it reduces stale field carryover risk

Verification:
- floor gold, wizard item spawn, special-room gold, and wizard prompt item creation

### `CA-09` C128 KERNAL Wrappers Are Mechanically Repetitive

Evidence:
- `commodore/c128/main.s:456-706`

What is happening:
- `w_readst`, `w_setlfs`, `w_setnam`, `w_open`, `w_close`, `w_chkin`, `w_chkout`, `w_clrchn`, `w_chrin`, `w_chrout`, and `w_load` all repeat the same prologue/epilogue shape

Why this matters:
- this area is historically bug-prone because it combines banking, IRQ state, and KERNAL entry/exit contracts
- repetition makes it easy to fix one wrapper and miss the others

Recommended refactor:
- generate the simple wrappers from one macro or one shared wrapper template
- keep `w_load` special-cased if its extra diagnostics require it

Expected savings:
- code size: likely `0-30` bytes if a shared wrapper template or macro collapses the repeated prologues/epilogues
- runtime: no meaningful change expected
- maintainability: high, because the call contract becomes one thing to review

Verification:
- C128 preload/overlay/tier load tests
- any wrapper change must preserve flags, register restoration, and runtime-vector restore assumptions
- `CA-09` should only be attempted after `WRAP-1` is fixed and re-verified

### `CA-10` Shared Contracts Are Present But Not Named Consistently Enough

Evidence:
- command IDs and direction tables duplicated in:
  - `commodore/c64/input.s:26-83`
  - `commodore/c128/input128.s:56-112`
- run-cancel edge detector duplicated in:
  - `commodore/c64/input.s:152-182`
  - `commodore/c128/input128.s:198-226`
- C128 screen contract mismatch:
  - `commodore/c128/screen_vdc.s:279-300`
  - `commodore/c128/screen_vdc.s:338-372`

What is happening:
- the same `CMD_*` namespace and direction tables live in both platform input files
- the same run-cancel state machine lives in both files
- on C128, `screen_put_char` translates PETSCII while `screen_put_string` explicitly expects screen codes

Why this matters:
- some of this is source-only duplication, not same-build code bloat
- the bigger issue is contract drift and API ambiguity
- the screen API naming in particular is a correctness trap for future runtime-generated strings

Recommended refactor:
- centralize the true shared input constants/tables in `commodore/common/`
- move the run-cancel state machine to one shared implementation if the build system can include it cleanly
- rename or document the VDC string/char split more explicitly:
  - for example `screen_put_petscii_char` vs `screen_put_screencode_string`

Expected savings:
- runtime/code-size: mostly none unless the shared-state-machine extraction can remove per-target duplication cleanly
- maintainability: high
- correctness: moderate, especially for future C128 UI/string work

Verification:
- C64 and C128 input command-mapping tests
- C128 lowercase/runtime string rendering tests

### `CA-11` Melee To-Hit Still Risks 8-Bit Overflow And Sign Drift

Evidence:
- `commodore/common/combat.s:225-256`

What is happening:
- `PL_TOHIT * 3` is still done with 8-bit arithmetic
- positive bonuses above roughly `85` can wrap before the final clamp
- negative bonuses are also folded through an 8-bit absolute-value path

Why this matters:
- this is a classic 6502 arithmetic bug: the code looks saturating because it clamps at the end, but the intermediate multiply can still corrupt the result
- it directly affects combat balance and can make high-bonus or high-penalty cases behave incorrectly

Recommended refactor:
- promote the multiply/add path to 16-bit arithmetic before the final clamp, or
- use explicit saturation logic before the `*3` result is merged into `zp_combat_tohit`

Expected savings / cost:
- no meaningful byte win
- small cycle cost increase in the combat path
- large correctness and balance win

Verification:
- hit chance tests at low, medium, and extreme positive/negative `PL_TOHIT`
- confirm the final result still clamps cleanly to `0..255`

Phase 3 result:
- implemented on `2026-03-25`
- the shared melee path now saturates `PL_TOHIT * 3` before 8-bit wrap in both sign branches
- focused verification completed:
  - `commodore/c64/tests/test_combat.s` passed `25/25`
  - `commodore/c64/tests/test_throw.s` passed `6/6`

### `CA-12` RNG Byte Output Was A One-Bit Step And Is Now A Real Byte-Step

Evidence:
- `commodore/common/rng.s:60-77`

What is happening:
- the old `rng_next` advanced the 32-bit Galois LFSR by one shift, then returned the low byte
- successive calls were therefore highly correlated byte-shifts of the same state
- both `rng_range` and `rng_range_word` inherited that correlation

Why this matters:
- this is a quality and design tradeoff, not a functional correctness bug
- the result is weaker-than-necessary distribution quality in game systems that assume fresh bytes

Recommended refactor:
- either advance the LFSR eight times per `rng_next` call, or
- split the API so the current one-bit step is explicit and a separate byte-step generator is used by gameplay code

Expected savings / cost:
- no byte win
- significant cycle cost increase if `rng_next` is upgraded to a real byte-step
- large quality win for `rng_range` and any other consumers of random bytes

Verification:
- compare distribution quality in `rng_range` and `rng_range_word`
- re-check any gameplay systems that depend on tightly coupled random bytes

Phase 6 result:
- implemented on `2026-03-25`
- updated `commodore/common/rng.s` so `rng_next` / `rng_byte` now advance the LFSR eight times before returning a byte
- the final implementation intentionally stayed byte-budget aware:
  - an earlier split-API draft overflowed the C64 banked payload past `$D000`
  - the final version recovered C64 headroom while keeping the byte-step quality fix
- added focused runtime coverage in `commodore/c64/tests/test_rng.s` proving `rng_next` matches eight reference one-bit steps
- broader verification completed:
  - `commodore/c64/run_tests.sh` passed `33/33`
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12` passed

## Style And 6502 Idiom Sweep

These items are worth doing, but they should follow the higher-value refactors above.

### `CA-S1` Prefer One Source Of Truth For Range/Threshold Constants

Current example:
- hunger thresholds duplicated between `turn.s` and `player_items.s`

Savings:
- already accounted for in `CA-03`

### `CA-S2` Avoid Long `cmp / branch / jmp` Chains When A Table Or Reordered Fallthrough Will Do

Current examples:
- potion and scroll dispatch in `player_items.s`
- small avoidable branch-through-jump shapes in the decimal formatters

Savings:
- already accounted for in `CA-01` and `CA-05`

### `CA-S3` Normalize Repeated “Swap With Last And Decrement Count” Removal Idioms

Current examples:
- `commodore/common/dungeon_features.s:268-276`
- `commodore/common/dungeon_features.s:320-329`
- `commodore/common/spell_effects.s:754+`

Recommendation:
- use one macro for the pattern when the tables are structurally identical

Expected savings:
- runtime/code-size: usually none if done as a macro
- maintainability/correctness: moderate

### `CA-S4` Keep API Names Honest About Encoding And Ownership

Current example:
- C128 screen code path mixes PETSCII and screen-code expectations in one module

Expected savings:
- runtime/code-size: none
- correctness/debugging: meaningful

## Immediate Execution Priority

1. Use `commodore/HEADROOM_REPORT.md` as the baseline for any layout-sensitive change; the C128 staged-source margin is now `79` bytes.
2. Keep any future alignment work tightly targeted to the specific live crossings already identified; do not spend bytes on blanket padding.
3. Start tactical deduplication with `CA-01` now that `ZP-1`, `ALIGN-1`, and `LINT-1` have established the perimeter/tooling baseline.
4. Treat C64 banked payload growth as explicit change-control: `5` bytes remain below `$D000`.
5. Treat the `320` advisory branch-jump warnings from `LINT-1` as a cleanup backlog, not as immediate correctness bugs.

## Suggested Execution Order

1. `CA-01` shared numeric formatting
2. `CA-02` filtered inventory visible-slot cache
3. `CA-03` shared hunger-state helper/constants
4. `CA-04` modal UI return helper cleanup
5. `CA-06` message-history destination simplification
6. `CA-05` item-effect dispatch cleanup
7. `CA-08` item-field init helper
8. `CA-07` full-screen clear benchmark and safe-callsite split
9. `CA-09` C128 KERNAL wrapper refactor
10. `CA-10` shared contract naming/constants cleanup

## Verification Strategy

For every item above:
- rebuild and inspect the memory map if segment placement moves
- prefer targeted C64 unit suites for shared gameplay/UI refactors
- run `make test128-fast` for any shared helper refactor that affects C128 behavior
- for C128 banking/runtime wrapper edits, include the preload/cache/overlay smoke coverage already called out in project docs
- do not trade away segment safety, overlay safety, or C128 runtime residency guarantees for minor byte wins

## Notes

- This audit deliberately separates:
  - same-build redundancies that can actually save bytes or cycles
  - cross-platform source duplication that mostly saves maintenance/debug time
- This revision intentionally shifts the plan from tactical cleanup toward perimeter safety, memory governance, and contract hardening.
- Phase 1 re-verification proved the older C128 wrapper/IRQ bug was still live for the common wrapper shape, which is why the audit promoted it from historical note to active fix item.
- Phase 2 headroom measurement is complete: `commodore/HEADROOM_REPORT.md` is now the concrete baseline for memory-sensitive work.
- Phase 3 `CA-11` is complete: the shared melee to-hit path now saturates the `PL_TOHIT * 3` contribution before 8-bit wrap, and the focused combat regression coverage passes.
- Phase 4 `WRAP-1` is complete: the common C128 KERNAL wrapper contract now preserves caller IRQ state, the focused cold-boot probe passes, and the fast C128 unit batch passes.
- Phase 5 `API-1` is complete: the public C128 VDC string/char paths now share one PETSCII-facing contract, and the focused VDC regression plus the explicit-`x128` fast batch both pass.
- Phase 6 `CA-12` is complete: the shared RNG byte path now advances eight LFSR steps per returned byte, the full C64 suite passes, and the explicit-`x128` fast C128 batch still passes.
- Phase 7 `ZP-1` is complete: raw volatile zero-page accesses are now enforced by `make check-zp`, the shared KERNAL / Screen Editor bytes have names instead of magic literals, and both the full C64 suite and fast C128 batch pass on the updated tree.
- Phase 8 `ALIGN-1` is complete: the live symbol audit showed that most hot row/tile tables are already page-safe, and the remaining real crossings are narrow enough that the next queue item should be `LINT-1`, not blanket alignment churn.
- Phase 9 `LINT-1` is complete: the repo now has an automated 6502 anti-pattern check for provably redundant zero-compares, the first six live hits are fixed, and the remaining branch-jump ladders are tracked as advisory warnings instead of blocking the build.
- Several older audit ideas in `commodore/AUDIT.md` are still useful context, but this document is specifically focused on current code-shape, reuse opportunities, and 6502 idiom cleanup rather than broad bug hunting.
