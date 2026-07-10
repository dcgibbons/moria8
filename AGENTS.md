# AGENTS.md

This file provides project-wide instructions for coding agents working in this
repository.

## Most Important Rules
1. state assumptions, never guess silently
2. minimum code, nothing speculative
3. surgical changes, don't refactor adjacent code
4. define success, loop until verified

## Working Style

Be direct and evidence-driven. State assumptions, uncertainty, and confidence.
Distinguish evidence from inference. Do not accept unsupported premises, and
change position when the evidence changes. Prefer concise findings with exact
source references over performative certainty or exhaustive narration.

## Repository Contract
This is a Commodore 64 / Commodore 128 / Plus/4 6502 assembly project built
with Kick Assembler and tested with VICE headless harnesses.

Primary entry points:

- `platforms/commodore/c64/main.s`
- `platforms/commodore/c128/main.s`
- `platforms/commodore/plus4/main.s`

Prefer small, local changes that preserve nearby assembly style, labels, memory
ownership, and test patterns.

## Behavioral Change Protocol

For gameplay, lifecycle, generation, rendering, or C128 memory changes, first
load `docs/BEHAVIOR_CHANGE_PROTOCOL.md`, then every matching domain contract:

| Change touches | Load |
| --- | --- |
| Monster records, AI, sleep, awareness, attacks, monster-mutating spells, detection or targeting | `docs/MONSTER_STATE_CONTRACT.md` |
| Generation stages, topology, placement, generation RNG or performance | `docs/DUNGEON_GENERATION_CONTRACT.md` |
| Turn consumption, visibility lifecycle, dirty flags, redraw, repeat commands | `docs/TURN_RENDER_CONTRACT.md` |
| C128 addresses, banks, overlays, copied/runtime code, physical VDC access | `docs/C128_MEMORY_CONTRACT.md` |

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
evidence. Routine work needs only the record required by its tier. Unknowns
that could change semantics, representation, ownership, memory safety, or
verification block implementation. Passing tests do not replace final contract
review.

## Current Source Layout

- `core/`: platform-agnostic gameplay, UI, data, and shared logic.
- `platforms/commodore/hal/`: shared Commodore HAL interfaces.
- `platforms/commodore/common/`: shared Commodore implementation code.
- `platforms/commodore/c64/`: C64 platform code, tests, and harness scripts.
- `platforms/commodore/c128/`: C128 platform code, tests, and harness scripts.
- `platforms/commodore/plus4/`: Plus/4 platform code, tests, and harness
  scripts.
- `build/`: generated binaries, disk images, symbols, snapshots, and test
  scratch output. Source directories should not accumulate generated `.prg`,
  `.sym`, `.vs`, or `out/` artifacts.

## Build And Test
Run commands from the repository root.

- `make` or `make build`: build C64, C128, and Plus/4 payloads
- `make test`: default regression mix
- `make test64`: C64 tests
- `make testplus4`: Plus/4 tests
- `make test128-fast`: stable C128 unit batch
- `make test128-fast-smoke`: high-value C128 runtime smoke subset
- `make test128`: authoritative full C128 suite
- `make disk`: build shipping C64, C128, and Plus/4 disk images
- `make run`, `make run64`, `make run128`, `make runplus4`: launch under VICE
- `make clean`: remove build artifacts

Kick Assembler downloads into `tools/kickass/` unless `KICKASS` is provided.

## Verification Rules
If the user reports a failing command, that exact command is the active
verification gate until it passes. Direct harness runs, monitor traces, narrower
filters, or partial suites are diagnostics only unless the user named them as
the gate.

If a product-code task exposes a test, harness, tooling, or infrastructure
defect, do not expand the task by editing that infrastructure automatically.
Stop and report the product change, the infrastructure defect, why it blocks or
does not block validation, and the smallest proposed follow-up. Ask whether to
backlog it or fix it now. Only edit infrastructure without asking when the user
explicitly requested infrastructure work or the product fix cannot be validated
at all without that infrastructure change.

Use VICE warp mode for headless tests. Do not raise runtime test timeouts above
30 seconds. For broad C128 banking, loader, layout, or memory changes, run
`make test128` before declaring completion.

VICE runtime harnesses use localhost monitor automation and must run with
escalated permissions on the first attempt. Do not try a sandboxed run first.
The sandbox blocks local monitor/socket access and produces known false
failures such as `PermissionError`.

Escalate any verification command that launches VICE or a VICE harness,
including commands that invoke `x64sc`, `x128`, or `xplus4`; `make test64`;
`make testplus4`; `make testplus4-runtime`; `make test128-fast`;
`make test128-fast-smoke`; `make test128`; direct `harness128.py`,
`harness128_batch.py`, or `harnessplus4.py` runs; and filtered runtime harness
targets. Static/build-only checks stay sandboxed: `make build`,
`make check-hal-boundaries`, Python static checkers, `git diff`, and similar
commands that do not launch VICE.

## Memory And Banking Contracts
Memory layout violations usually cause silent corruption, wild jumps, CPU JAMs,
or VICE timeouts.

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

Never delete or weaken boundary-checking `.assert` statements. If an assert
fails, fix the code or memory layout, not the assert.

After C128 layout, banking, runtime-loaded, copied, or trampolined-code changes,
verify linked address, PRG load header, load destination bank, visible execution
bank, and copy source/destination safety together.

## Runtime Test Hazards
A new C64 runtime test hang after an assembly/layout change is presumptively a
memory/layout overlap regression until proven otherwise.

Test files whose `test_start` would land at or above `$A000` must use a
bootstrap stub below BASIC ROM that banks RAM visible before jumping to
`test_start`.

## User-Facing Text
User-visible strings are not scratch space for byte recovery. Do not shorten,
abbreviate, rename, truncate, or degrade player-visible text unless explicitly
requested. Recover bytes from code structure, dead helpers, data ownership,
overlays, deduplication, compression, or banking first.

## Future Platforms
Treat current C64/C128 code as the active implementation, not the final
architecture for every future port. Do not add new hardware assumptions to
shared game logic. Keep platform-specific rendering, input, storage, memory
banking, and loader behavior behind platform-owned code.

Consult `docs/CROSS_PLATFORM_STRATEGY.md` before starting any new platform port.
Expand that strategy document when adding each port instead of bloating this
agent startup context.

## Architecture Notes
- Display is PETSCII-character based.
- C64 gameplay is 40-column.
- C128 gameplay is 80-column.
- BASIC is used for the loader stub only; do not rely on BASIC routines after
  machine-code startup.
- KERNAL routines are allowed where appropriate.
- Preserve intentional disk-loading and memory-ownership boundaries.

## Coding Standards
Use canonical 6502 / Kick Assembler conventions already present in nearby code.
Add or update `.assert` guards and runtime tests for behavior or memory-contract
changes. Prefer root-cause fixes over weakening tests, assertions, timeouts, or
player-facing text.
