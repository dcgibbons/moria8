# AGENTS.md

Project-wide instructions for coding agents, ordered from hard gates down to
reference material.

## Hard Gates

NEVER perform durable, history-altering, or externally visible actions unless the
user's message in the current session explicitly names the action:

- `git commit`, `git push`, `git tag`, `git stage`/`git add`, branch
  creation/deletion, PR creation, or any other repo-history mutation.

"proceed", "go ahead", "looks good", "save it", "done", and "add that to the
backlog" are NOT authorization. Work ends at edited, verified files in the
working tree.

Before any gated action, output one line:
`COMMIT GATE: user said "<the user's words>" which authorizes <action>.`
If the quote does not name the action, stop and ask.

## Non-Negotiable Rules

1. **Boundary asserts are sacred:** Never delete or weaken `.assert` or Z80
   `ASSERT` guards. When one fails, fix the code or memory layout. Hard
   boundaries and port layouts live in `docs/INTERNAL_MANDATES.md` and each
   port's memory contract.
2. **Player text is not scratch space:** Never shorten, abbreviate, rename, or
   degrade player-visible strings to recover bytes unless explicitly requested.
   Recover bytes from code structure, dead helpers, ownership, overlays,
   deduplication, compression, or banking first.
3. **Fix root causes:** Never weaken tests, assertions, timeouts, or
   player-facing text to make a check pass.
4. **User-named gate is active:** If the user reports a failing command, that
   exact command is the active gate until it passes (narrower runs are
   diagnostics only).
5. **Stop and report infrastructure defects:** If a product-code task exposes a
   test, harness, tooling, or infrastructure defect, stop looping and report the
   product change, the infra defect, whether it blocks validation, and the
   smallest fix (ask to fix now vs backlog). Only edit infra unasked when the
   task is infra work or validation is completely blocked without it.
6. **Repo hygiene:** Never commit secrets, env files, build outputs, snapshots,
   downloaded toolchains, or monitor logs, and leave zero generated `.prg`,
   `.sym`, `.vs`, `.ovl`, `.lst`, `.com`, or `out/` artifacts in source dirs.
7. **Release compliance:** Every shipping disk, archive, `MORIA8.DAT`
   (`'M8CP'`), and cartridge must ship `data/LICENSE` and `data/SOURCE-OFFER`
   for Title `A` (`About`) and Help `L` (per-port filenames and EOL rules in
   `docs/INTERNAL_MANDATES.md`).
8. **Emulator sandboxing & timeouts:** Runtime verification uses warp mode and
   timeouts `<= 30 s`. Commands launching VICE (`x64sc`, `x128`, `xplus4`),
   MAME, or `x16emu` require unsandboxed localhost access (`PermissionError` in
   sandbox)—request escalation on the first attempt and output one line before
   running:
   `ESCALATE: <command> launches VICE/MAME.`
   Keep `make build`, `make check-*`, Python static checks, `make playtest-check`,
   `git diff`, `make buildcpm`/`diskcpm`/`testcpm`, and `*-memory-contract`
   sandboxed (CP/M `cpm_runner`/`RunCPM` uses stdio, zero sockets; only initial
   missing-toolchain downloads need network). Long operational jobs
   (`make playtest-session`/`qualify`/`regress`/`m0-report`/`disk`,
   `make playtest-gate`, `make test128-soak-long`) have no overall time limit
   (60 s per-command timeout in sessions); `make playtest-check` and
   `make playtest-smoke` stay `<= 30 s`. Root-Makefile emulator targets isolate
   automatically via `tools/isolated.sh`.
9. **Project-relative paths only:** Never hardcode `$HOME`, `~`, `/tmp`, or host
   paths in Makefiles, scripts, harnesses, or sources. External ROM/tool env
   vars (`A2ROMS`, `X16ROM`, `ATARI8ROMS`, `BBCMROMS`, etc.) must default empty
   (`?=`) in Makefiles.

Load `docs/INTERNAL_MANDATES.md` before memory, banking, zero-page, C128,
Commodore I/O, or shared-code work.

## Behavioral Change Protocol

For gameplay, lifecycle, generation, rendering, or platform memory/banking/TPA
changes, load `docs/BEHAVIOR_CHANGE_PROTOCOL.md` plus every matching contract:

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

Before editing a matched domain, output:
`PROTOCOL GATE: loading <contract> because the change touches <row>.`

- **Visibility routing:** detection/inspection semantics/targeting → monster +
  turn/render; pure renderer/inspection flags → turn/render only; AI use of
  visibility without redraw changes → monster only; C128 VDC access/layout →
  also C128 memory.
- For behavioral/architectural work, complete the change record (mark
  safety-critical N/A fields with evidence) and list unresolved questions before
  coding if answers affect layout, ownership, or observable behavior. Before
  declaring done, re-read and confirm every applicable contract verification
  row.

## Verification & Working Style

Be direct and evidence-driven. State assumptions before acting, distinguish
evidence from inference, write only requested code (surgical edits; match local
assembly style/labels), keep "backlog" strictly for `docs/BACKLOG.md` (edit only
if named), and check `docs/FEATURE_MAP.md` when gameplay/catalog parity looks
ambiguous (update it when adding/changing gameplay features or port behavior).

- **Scope verification to the change:**
  - *Localized / single-port edit:* static checks (`make check-hal-boundaries`,
    `check_overlay_calls.py`, port `*-memory-contract`) plus the narrowest
    affected suite/smoke (e.g., one `.s` test, `make test128-fast` /
    `make test128-fast-smoke`, or `PORT=<port>` smoke). Do NOT run `make test`,
    full `make test128`, or `make playtest-gate`.
  - *Broad C128 layout/banking/loader/MMU or shared/cross-port edit:* run the
    affected port suite (`make test128` for broad C128 changes) or `make test`
    for multi-port gameplay changes, plus `make playtest-tour PORT=<port>`
    (~5–10 s/port) when gameplay, UI, or overlay paths change.
  - *Pre-PR / release bot gate (`make playtest-gate`):* optional before local
    commits because `moria8-playtest-queue` continuously exercises every active
    port on `clvl10`; run before PRs/releases or major cross-port gameplay/UI
    changes, scoped via `TARGETS=<ports>` when specific ports changed.
  - *No redundant re-runs on commit:* once the current working tree has passed
    its gate and the user asks to commit, commit directly without re-running
    tests or launching `make playtest-gate`.
  - *Commodore storage / disk-setup UI edits* (`ui_disk_setup.s`, `save.s`,
    `disk_*.s`, `save_slot_menu.s`, `hal/storage*.s`): verify the Commodore I/O
    checklist in `docs/INTERNAL_MANDATES.md` and run `make playtest-disk
    SCENARIOS=absent_save_drive,empty_drive,status_lost_save`.
- **On failure:** read the failing test/harness before re-running. Two identical
  failures → stop and analyze, never loop blind retries.
- **Done criteria:** user's failing command or applicable tier gate passed;
  diff reviewed and clean; zero stray build artifacts in source dirs; contract
  verification rows confirmed; then stop without committing/pushing unless named.

## Code Review Personalities

When asked for "the standard personalities", spawn one review-only reviewer each
reporting `file:line`, severity, and a concrete failure scenario:

1. **Grumpy staff engineer, tired of AI slop.** Rejects unneeded code,
   speculative abstraction, comment noise, untested claims, and scope creep.
2. **Worried engineering manager.** Weighs reliability, maintainability, gate/cost
   tradeoffs, what breaks next, and what remains unverified.
3. **6502 / Z80 performance guru.** Audits 6502/65C02 cycles, byte budgets, ZP,
   stack, banking/page-crossings, and Z80 T-states, register pressure, `IX`/`IY`,
   `MORIA8.COM`/BSS budgets, overlay thrash, BDOS/BIOS cost, and `0xD100` limits.

## Repository Map

- **6502/65C02 (`Kick Assembler`):** `core/6502/` (shared gameplay/UI/data);
  `platforms/commodore/{hal,common,c64,c128,plus4}/`, `platforms/{apple2,cx16,atari8,bbcmaster}/`.
- **Z80 (`sjasmplus`):** `core/z80/` and `platforms/z80/cpm/` (`MORIA8.COM` + 19 overlays in `'M8CP'` `MORIA8.DAT`).
- **Build & test targets:** see `Makefile` (`make build`, `make disk`,
  `make test`, `make test64`, `make test128{,-fast,-fast-smoke}`, `make testplus4`,
  `make test{apple2,cx16,atari8,bbcmaster,cpm}`, `make playtest-{check,smoke,tour,gate,disk}`).
- **Architecture:** C64, Plus/4, and Atari 8-bit are 40-col; C128, Apple IIe,
  CX16, BBC Master, and CP/M are 80-col. BASIC is loader stub only. Keep all
  hardware/banking/rendering/storage behind platform HALs (`docs/CROSS_PLATFORM_STRATEGY.md`).
- **Key docs:** `docs/INTERNAL_MANDATES.md`, `docs/FEATURE_MAP.md`,
  `docs/BEHAVIOR_CHANGE_PROTOCOL.md`, `docs/CROSS_PLATFORM_STRATEGY.md`, `docs/BACKLOG.md`.
