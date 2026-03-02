# Moria8 C128 Port — Architecture (C4 Baseline + Stability Fixes)

> Updated for C4 completion state (2026-03-02), including post-lock stability fixes.
> This document tracks the shipping C128 memory/banking model after map relocation.

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

### 1.2 Bank 1 (map storage)

| Range | Purpose |
| :--- | :--- |
| `$4000-$4EFF` | dungeon/town map (`MAP_BASE..MAP_END`) |

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
4. Restores normal bank mode and jumps to `$1C0E`.

Diagnostics:
- `BOOT_DIAG` mode writes signature bytes for transfer-stage debugging.
- C128 test harness includes boot smoke and boot-copy diagnostic suites.

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
6. `boot_diag_copy`

---

## 5. Out of Scope (Post-C4)

Not part of the current shipping baseline:
- `198x66` map rollout (Phase 10.3 follow-on effort)
- Gameplay redesign tied to enlarged map geometry
- Non-essential refactors unrelated to C128 banking correctness
