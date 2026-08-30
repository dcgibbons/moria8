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
   not leave generated `.prg`, `.sym`, `.vs`, or `out/` artifacts in source
   directories.
7. Release compliance: every shipping disk image must include `data/LICENSE`
   and `data/SOURCE-OFFER` (LF→CR converted). Commodore images carry them as
   SEQ files `license,s`/`source-offer,s`; the Apple IIe image carries ProDOS
   TXT files `LICENSE`/`SOURCE.OFFER`. New platform ports must do the same.
8. Runtime verification uses VICE warp mode and never relies on timeouts above
   30 seconds. Commands that launch VICE or MAME need localhost monitor/socket
   access, which sandboxed execution blocks (you'll see `PermissionError`) —
   request escalated permission on the first attempt; do not try a sandboxed
   run first. See Memory And Verification Details for the full escalation list.

Additional durable invariants for memory, banking, zero-page, C128, and
shared-code work live in `docs/INTERNAL_MANDATES.md`; load it before any such
work.

## Behavioral Change Protocol

For gameplay, lifecycle, generation, rendering, or C128 memory changes, first
load `docs/BEHAVIOR_CHANGE_PROTOCOL.md`, then every matching domain contract:

| Change touches | Load |
| --- | --- |
| Monster records, AI, sleep, awareness, attacks, monster-mutating spells, detection or targeting | `docs/MONSTER_STATE_CONTRACT.md` |
| Generation stages, topology, placement, generation RNG or performance | `docs/DUNGEON_GENERATION_CONTRACT.md` |
| Turn consumption, visibility lifecycle, dirty flags, redraw, repeat commands | `docs/TURN_RENDER_CONTRACT.md` |
| C128 addresses, banks, overlays, copied/runtime code, physical VDC access | `docs/C128_MEMORY_CONTRACT.md` |
| Apple IIe addresses, banks, aux/main ownership, overlays, copied/runtime code | `docs/APPLE2_MEMORY_POLICY.md` |
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

VICE/MAME escalation list (these launch an emulator and need unsandboxed
localhost access): commands that invoke `x64sc`, `x128`, or `xplus4`; `make
test64`; `make testplus4`; `make testplus4-runtime`; `make test128-fast`;
`make test128-fast-smoke`; `make test128`; direct `harness128.py`,
`harness128_batch.py`, or `harnessplus4.py` runs; and filtered runtime harness
targets. Static/build-only checks stay sandboxed: `make build`, `make
check-hal-boundaries`, Python static checkers, `git diff`, and similar commands
that do not launch an emulator. Before running one of these, output one line:
`ESCALATE: <command> launches VICE/MAME.`

The Apple IIe harness (`platforms/apple2/harness_smoke.py`) drives headless
MAME apple2ee instead of VICE and requires Apple IIe ROMs via the `A2ROMS`
env var or `--rompath` (ROMs are not redistributable). Run one scenario per
invocation; the suite is 14 scenarios plus `boot_title`.

## Working Style

Be direct and evidence-driven. State assumptions, uncertainty, and confidence.
Distinguish evidence from inference. Do not accept unsupported premises, and
change position when the evidence changes. Prefer concise findings with exact
source references over performative certainty or exhaustive narration.

Operational rules:

- When you make an assumption, state it explicitly in your reply before acting
  on it; never guess silently.
- Write only the product code needed to satisfy the stated task and the
  verification gate. Do not add features, helpers, or abstractions the task did
  not request. Required tests and `.assert` guards are not optional.
- Make surgical changes; don't refactor adjacent code. Preserve nearby assembly
  style, labels, memory ownership, and test patterns.
- Define success as: the user's failing command passes, or `make test` passes
  if no command was given. Loop until verified. Stop and ask the user when a
  gate action is needed, infrastructure is broken, or the 30-second timeout cap
  blocks verification (see Non-Negotiable Rules).

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

This is a Commodore 64 / Commodore 128 / Plus/4 / Apple IIe 6502 assembly
project built with Kick Assembler and tested with VICE and MAME headless
harnesses.

Primary entry points:

- `platforms/commodore/c64/main.s`
- `platforms/commodore/c128/main.s`
- `platforms/commodore/plus4/main.s`
- `platforms/apple2/main.s`

Source layout:

- `core/`: platform-agnostic gameplay, UI, data, and shared logic.
- `platforms/commodore/hal/`: shared Commodore HAL interfaces.
- `platforms/commodore/common/`: shared Commodore implementation code.
- `platforms/commodore/c64/`: C64 platform code, tests, and harness scripts.
- `platforms/commodore/c128/`: C128 platform code, tests, and harness scripts.
- `platforms/commodore/plus4/`: Plus/4 platform code, tests, and harness
  scripts.
- `platforms/apple2/`: Apple IIe platform code, MAME harness scripts, and
  memory-contract checker.
- `build/`: generated binaries, disk images, symbols, snapshots, and test
  scratch output.

Build and test (run from the repository root):

- `make` or `make build`: build C64, C128, Plus/4, and Apple IIe payloads
- `make test`: default regression mix; also runs the Apple IIe MAME runtime
  suite (all `harness_smoke.py` scenarios) when `A2ROMS` is set, with a
  skip warning otherwise
- `make test64`: C64 tests
- `make testplus4`: Plus/4 tests
- `make test128-fast`: stable C128 unit batch
- `make test128-fast-smoke`: high-value C128 runtime smoke subset
- `make test128`: authoritative full C128 suite
- `make testapple2`: Apple IIe memory-contract gate (static)
- `make disk`: build shipping C64, C128, Plus/4, and Apple IIe disk images
- `make run`, `make run64`, `make run128`, `make runplus4`: launch under VICE
- `make runapple2`: launch under MAME apple2ee (requires `A2ROMS`)
- `make clean`: remove build artifacts

Kick Assembler downloads into `tools/kickass/` unless the `KICKASS` env var is
set.

Architecture notes:

- Display is character-cell based (PETSCII screen codes; the Apple IIe
  translates to Apple display codes at write time).
- C64 gameplay is 40-column. C128 and Apple IIe gameplay are 80-column.
- BASIC is used for the loader stub only; do not rely on BASIC routines after
  machine-code startup. KERNAL routines are allowed where appropriate.
- Preserve intentional disk-loading and memory-ownership boundaries.

Coding standards: use canonical 6502 / Kick Assembler conventions already
present in nearby code. Add or update `.assert` guards and runtime tests for
behavior or memory-contract changes.

Future platforms: treat current C64/C128 code as the active implementation, not
the final architecture for every port. Do not add new hardware assumptions to
shared game logic. Keep platform-specific rendering, input, storage, memory
banking, and loader behavior behind platform-owned code. Consult
`docs/CROSS_PLATFORM_STRATEGY.md` before starting any new platform port, and
expand that document when adding each port.

Related documents: `docs/INTERNAL_MANDATES.md` (repository hygiene, zero-page
and KERNAL ownership, C128 banking detail, shared-code rules),
`docs/CROSS_PLATFORM_STRATEGY.md` (new ports), `docs/BACKLOG.md` (deferred
work).
