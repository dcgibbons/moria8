# Moria8 C128 Port — Architecture (C4 Baseline + 10.8 Gate B)

> Updated for 10.8 ownership refactor, Gate B overlay-cache validation, and the 10.8 follow-up hardening pass.
> This document tracks the shipping C128 memory/banking model, including the named Bank 1 ownership manifest enforced in `memory128.s`.

---

## Overview

The C128 build keeps gameplay logic shared with C64 while using C128-specific platform hooks for MMU banking, VDC rendering, and keyboard input.

Key C4 outcome:
- Dungeon map is no longer in Bank 0.
- Map storage is now Bank 1 RAM at `$4000-$4EFF` (`80x48`, 3840 bytes).

---

## 1. Memory Model

### 1.1 Bank 0 (operational code/data)

| Range | Purpose |
| :--- | :--- |
| `$0000-$03FF` | ZP, stack, vectors |
| `$0400-$07FF` | scratch/test/BFS queue path |
| `$1A00-$1AFF` | floor-item table (`FLOOR_ITEM_BASE`) |
| `$1B00-$1BFF` | creature scratch (`CREATURE_BASE`) |
| `$1C01-$BFFF` | main program/code/data (`entry` at `$1C0E`) |
| `$E000-$EFFF` | overlay load window in RAM under KERNAL |
| `$E000-$FFFF` | RAM-visible only when KERNAL ROM is hidden |

### 1.2 Bank 1 (runtime ownership after boot)

| Range | Purpose |
| :--- | :--- |
| `$0000-$0FFF` | 4 KB bottom common RAM (shared across banks; not cache-safe) |
| `$1000-$3FFF` | reclaimed low Bank 1 RAM after staged-image scrub; currently unassigned |
| `$4000-$4EFF` | dungeon/town map (`MAP_BASE..MAP_END`) |
| `$5000-$7FFF` | Bank 1 DB/data region retained from earlier C128 work (`BANK1_DB_BASE..BANK1_DB_END`) |
| `$8000-$94F7` | active tier-cache window for `MONSTER.DB.1-4` |
| `$A000-$AFFF` | overlay cache slot for `OVL_STARTUP` |
| `$B000-$BFFF` | overlay cache slot for `OVL_TOWN` |
| `$C000-$CFFF` | overlay cache slot for `OVL_DEATH` |
| `$E000-$EFFF` | overlay cache slot for `OVL_DUNGEON_GEN` |
| `$94F8-$9FFF` | reserved gap between tier cache and overlay cache |
| `$D000-$DFFF` | reserved I/O-visible gap; standard Bank 1 helpers do not treat this as cache-safe |
| `$F000-$FEFF` | reserved top gap; available only after an explicit ownership change and new asserts |

10.8.0 ownership conclusions:
- `boot128` previously left the staged Bank 1 program image resident, which made Bank 1 ownership ambiguous and invalidated preload-cache assumptions.
- `boot128` now scrubs each staged source page in Bank 1 immediately after buffering it into common RAM during the copy to Bank 0.
- That reclaim step removes the staged-image overlap from the post-boot ownership model.
- The current layout now has a documented reclaimed high Bank 1 region at `$8000-$FEFF`, which is large enough for the 5368-byte tier-preload footprint.
- Startup now preloads the four monster tiers into `$8000-$94F7`.
- Overlay cache is also active for fixed slots at `$A000-$AFFF`, `$B000-$BFFF`, `$C000-$CFFF`, and `$E000-$EFFF`.
- MMU gateway hardening for map/DB access is in place for the tier-cache path.
- `$D000-$DFFF` is intentionally left unused by the standard overlay-cache helpers because Bank 1 helper mode keeps I/O visible there.
- The ownership manifest, overlap asserts, and overlay-slot base tables now live in `c128/memory128.s` as the source of truth for future Bank 1 edits.

Map invariants:
- `MAP_COLS=80`
- `MAP_ROWS=48`
- `MAP_SIZE=3840`

---

## 2. MMU and Banking

Primary constants:
- `MMU_NORMAL = $0E` (Bank 0, ROM-visible mode for KERNAL paths)
- `MMU_ALL_RAM = $3E` (Bank 0, all RAM, I/O visible; normal game mode)
- `MMU_RAM_BANK1 = $7E` (Bank 1, all RAM, I/O visible)

Rules used by shipping code:
1. Runtime stays in Bank 0 (`MMU_ALL_RAM`) except for scoped map accesses.
2. Single-tile map access flows through `map_get_tile` / `map_set_tile`.
3. Those accessors consume C128 MMU-safe pointer wrappers (`mmu_safe_map_*`).
4. Bulk map work uses centralized `map_bulk_*` helpers and does not hold an ambient Bank 1 execution context while running overlay code at `$E000`.
5. MMU select/restore helpers preserve caller IRQ state.
6. C128 VDC rendering paths (`render_viewport` / `render_single_tile`) read map tiles through MMU-safe map macros, not raw Bank 0 pointer dereferences.

KERNAL call safety:
- `$FFC3..$FFD2` ROM entry points are indirect stubs on C128; RAM mirror patching must not rewrite them as direct JMP operands.
- Asset loading runs in explicit `EnterKernal` context with direct `$FF68` (SETBNK) and `$FFD5` (LOAD) calls.

---

## 3. Boot and Program Start

`boot128.s` behavior:
1. Relocates loader to safe RAM.
2. Loads `MORIA128` into Bank 1 via KERNAL LOAD path.
3. Uses a common-RAM copy stub to copy staged pages into Bank 0 program space.
4. Scrubs each staged Bank 1 source page once buffered, reclaiming the staged image during the copy.
5. Restores normal bank mode and jumps to `$1C0E`.

10.8.0 clarification:
- `boot128` now actively reclaims the staged Bank 1 image during the copy-to-Bank-0 step.
- Any later Bank 1 feature must still use documented ownership ranges and compile-time assertions instead of informal "free RAM" assumptions.

Diagnostics:
- `BOOT_DIAG` mode writes signature bytes for transfer-stage debugging.
- C128 test harness includes boot smoke and boot-copy diagnostic suites.

### 3.1 Preflight Checklist for Low-RAM / Bank 1 Changes

Before adding or moving C128 data/code in low RAM or Bank 1:
1. Name the exact ownership region being changed in `memory128.s`.
2. State whether the bytes live in common RAM, Bank 0 only, or Bank 1 only.
3. Decide whether `$D000-$DFFF` visibility matters and keep helpers out of that window unless the change explicitly needs it.
4. Decide whether the bytes must survive boot, title, new-game, summary, and town transitions.
5. Add or update the relevant compile-time assert for the region boundary/overlap.
6. Update at least one smoke that exercises the survival or fallback contract affected by the change.

### 3.2 Runtime-Loaded Code Checklist (MANDATORY)

For any C128 routine that is loaded from disk, copied at startup, recopied later, or entered through a trampoline, verify the full runtime contract:

1. **Linked address** — symbol location in `out/main.vs` / `main.sym`
2. **Load address** — PRG header / emitted segment base
3. **Load bank** — which bank receives the bytes
4. **Execution bank** — which bank is visible when the CPU calls it
5. **Source-span survival** — whether any staged source used for later recopies remains valid after overlays or boot scrubs

These are separate checks. The last C128 stability wave came from failing them independently:
- `$1000` runtime code existed but was not loaded into the executing bank
- banked UI destination was safe, but its staged recopy source overlapped the overlay window
- a trampoline stayed below `$D000`, but its callee drifted into the I/O hole

Operational rules:
- Do not assume low RAM is common RAM; in shipping C128 mode, only `$0000-$0FFF` is common.
- Do not place normal runtime code in `$D000-$DFFF` unless the entire path explicitly runs with I/O hidden and that design is documented.
- When asserting safety, cover both the trampoline and the callee, and both the resident runtime block and its staged recopy source.

---

## 4. Test Harness (C4-Coverage)

C128 harness target:
- `make -C commodore/c128 test128`

Current suites:
1. `minimal128`
2. `memory128`
3. `dungeon128`
4. `soak128` (200 deterministic generation iterations)
5. `boot_d64_smoke`
6. `boot_title_idle_smoke`
7. `boot_title_newgame_smoke`
8. `boot_tier_transition_smoke`
9. `town_overlay_smoke`
10. `town_overlay_female_smoke`
11. `town_overlay_state_smoke`
12. `scripted_summary_to_town_smoke`
13. `cache_survival_smoke`
14. `death_overlay_smoke`
15. `preload_partial_failure_smoke`
16. `overlay_partial_failure_smoke`
17. `boot_diag_copy`

---

## 5. 10.8.0 Implications

For the current build:
- the Bank 1 ownership blocker has been addressed by reclaiming the staged image during boot
- tier-only preload cache now uses the documented high Bank 1 window
- overlay cache now uses fixed Bank 1 slots and falls back to disk if that cache class is unavailable
- runtime now reasserts IRQ/vector/CHRIN/helper guard state across overlay and dungeon-generation boundaries
- boot coverage now includes idle-title soak, scripted summary-to-town, cache survival across title/new-game/town, explicit town overlay coverage for both male and female new-game flows, death overlay coverage, missing-tier preload fallback, missing-overlay preload fallback, and boot-copy diagnostics
- any future overlay cache design must continue to use documented reclaimed ranges and explicit MMU gateways

Active overlay slot map:
- `$A000-$AFFF` -> `OVL_STARTUP`
- `$B000-$BFFF` -> `OVL_TOWN`
- `$C000-$CFFF` -> `OVL_DEATH`
- `$E000-$EFFF` -> `OVL_DUNGEON_GEN`

## 6. Out of Scope (Post-C4 / Pre-MMU-Gateway-Hardening)

Not part of the current shipping baseline:
- `198x66` map rollout (Phase 10.3 follow-on effort)
- Gameplay redesign tied to enlarged map geometry
- Re-enabling overlay preload/cache before the upgraded 10.8 smoke coverage exists
- Non-essential refactors unrelated to C128 banking correctness
