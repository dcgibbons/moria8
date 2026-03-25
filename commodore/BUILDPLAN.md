# Moria C64/C128 — Active Build Plan

> Active outstanding work only.
> See [DESIGN.md](DESIGN.md) for architecture reference and [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed phases, fixes, and reviews.

---

## Current State (2026-03-24)

- All core phases 1–9 are complete.
- C128 split, extended-memory database path, larger dungeon, hardened execution boundary, and the current 80-column baseline are complete.
- Recent resolved items include BUG-1, BUG-LIT, BUG-M1, BUG-X, BUG-RECALL, BUG-EGO-NAME, BUG-DEEP-SPAWN, BUG-XP-PACE, BUG-GEN-CLEAR-C64, OPT-1, OPT-2, REF-1, the major C128 loader / banking stability repairs, the resident C128 banked combat relocation plus cached `OVL.UI`, 10.4 VDC threat/effect color work, the first `PERF-DG-C128` pass (faster dungeon generation plus visible `GENERATING...` feedback on dungeon transitions), the `dungeon_gen` BFS scratch cleanup, the high-value `TST-5` isolated coverage for disk swap plus renderer decision trees, and `FEAT-WIZ` Wizard Mode.
- C128 VDC optimization work is paused after the verified left-scroll rollback and subsequent stability regressions; any restart needs a fresh design pass.

## Open Bugs

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
| Medium | `BUG-GAMEOVER-CLEAR-C64` C64 game-over / save-and-quit menu does not fully clear the prior gameplay status rows | Low | Medium | No | User-reported C64 UI bug: after saving and reaching the `Reboot / Restart / Quit` menu, the screen is not fully cleared and stale player status remains visible at the bottom. |
| High | `BUG-HAGGLE-UI` store haggling input / reactions do not behave correctly | Medium | High | No | User-reported store-haggling regression. Audit buy/sell haggle prompts, offer parsing, reaction text, convergence, and insult/kick behavior against expected classic flow. |
| Medium | `BUG-SEARCH-VERIFY` verify whether searching is actually available and working end-to-end, then implement/fix if not | Medium | Medium | No | The codebase already contains a `do_search` path, so this is not yet proven to be an unimplemented feature. Confirm command mapping and user-visible behavior in real play before deciding whether this is missing, broken, or merely undiscoverable. |
| Medium | `BUG-HELP-PAGING` multi-page help is not implemented | Medium | Medium | No | Extend the help UI so longer help content can paginate cleanly instead of truncating to a single screen. |
| High | `BUG-DIG-SHIFT-D` digging via `Shift+D` / digging tools is not behaving correctly | Medium | High | No | User report: digging into a vein can yield `Nothing interesting happens.` even while carrying or wielding a shovel. Audit command mapping, digging-tool recognition, and vein resolution on the active runtime path. |
| Medium | `BUG-PROMPT-FILTER` inventory-selection prompts should only list relevant item letters, not the entire inventory | Medium | Medium | No | Any prompt that offers an inventory subset should filter the displayed letters/items to the ones valid for that action, instead of showing unrelated slots. |
| Low | `BUG-LOOK-HILITE` look command does not move/highlight the found target like original Umoria | Medium | Low | No | Original Umoria moves the cursor to the found monster/item/feature during `look`; the current port reports the target in text only. Treat as a fidelity/UI bug rather than a gameplay blocker. |

## Open Phases / Display Work

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
| Medium | `UI-80` refine the C128 80-column layout to a true Umoria-style left status panel | High | Medium | No | Treat as a refinement of the shipped 80-column baseline, not a contradiction of 10.7 completion. |

## Open Test / Cleanup Work

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
| Medium | `AUDIT-IO-C128` full audit of C128 callable code vs I/O-hole / residency contracts | Medium | High | Prefer | Inventory every callable C128 routine path, confirm final execution residency (`< $D000`, `OVL.*`, or resident `$F000`), add missing asserts for both trampolines and callees, and catch future `$D000-$DFFF` regressions before manual play does. |
| Medium | `REF-HAL` formalize platform service hooks so shared gameplay code stops accumulating `#if C128` branches | High | Medium | No | Introduce a thin platform-services layer for shared gameplay entry points such as pre-turn hooks, platform guard restore, and other runtime quirks. Treat this as the main structural refactor; it should precede further trampoline cleanups. |
| Low | `REF-INPUT-TABLES` centralize shared command/input tables and direction constants in `commodore/common/` | Medium | Medium | No | Move truly shared `CMD_*` command codes, direction tables, and PETSCII-to-command lookup tables into common data. Do not try to unify the C64/C128 keyscan or modifier-chord implementations themselves. |
| Low | `REF-CONSTS` consolidate shared `CMD_*`, `SC_*`, and `COL_*` constants into common headers | Low | Medium | No | Cleanup for constants that are genuinely platform-neutral. Keep platform-specific screen-code or scan-code quirks local. |
| Low | `REF-NUMFMT` move duplicated numeric formatting helpers into shared screen helper code | Low | Low | No | `screen_put_hex`, `screen_put_decimal`, and `screen_put_decimal_16` are duplicated in the VIC-II and VDC backends but only depend on a `screen_put_char` primitive. Share the formatter logic without merging the platform screen drivers themselves. |
| Low | `REF-C128-TRAMP` macro-generate repetitive C128 trampoline boilerplate in `commodore/c128/main.s` | Medium | Low | No | Many C128 trampolines share the same save-bank / switch / call / restore shape. This cleanup should follow `REF-HAL`, once the callable surface is stable. |
| Low | Platformize `overlay.s` / `tier_manager.s` CIA2 VIC-bank restore assumptions | Medium | Low | No | Cleanup unless future C128 overlay work reopens the area. |
| Low | `A6` split large file `item.s` | Medium | Low | No | Opportunistic maintainability work. |
| Low | `REF-MON-SOA` evaluate converting the active monster table from AoS to SoA | High | High | No | Potential 6502 performance win, but risky: it touches AI, accessors, save/load, and tests. Keep it firmly backlog-only until profiling proves the win is worth the churn. |
| Low | `OPT-5` further overlays for magic/spells/UI | High | Low | No | Only useful if main-segment pressure returns. |

## Open Features

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
| Medium | `FEAT-DISK` separate persistence media from the program disk | High | High | No | Probe available save drives, let the player pick a save target, reject the program disk for save/load/high-score persistence, and validate before destructive scratch/delete actions. |
| Medium | `FEAT-DEPTH` restore original Moria depth semantics (`0-1200` feet in `50`-foot increments) | High | Medium | No | The original games use dungeon depth in feet rather than a hard `0-99` floor abstraction. Rework UI, save/load, recall/wizard depth entry, generation/state contracts, and any tier/deep-spawn assumptions so the port can represent original-style depth values faithfully. |
| Medium | `FEAT-PERMADEATH-OPTION` make permadeath a player-selectable creation-time option, potentially via a broader difficulty choice | Medium | Medium | No | Add a character-creation choice that lets the player opt into permadeath rules instead of hardwiring one death policy. Final UI shape is open: standalone permadeath toggle or folded into a difficulty selection. |
| Low | `FEAT1` expand mage/priest spells from 16 to 31 each | High | Medium | No | Requires UI pagination and likely extra overlay pressure. |
| Low | `FEAT-AUD` audible hunger warning (buzz/beep) | Low | Medium | No | Add sound cue for Weak/Faint/Starve states to prevent surprise deaths. |

## C128 -> `main` Merge Checklist

### Must

- Keep C128 verification green:
  - `make test128-fast`
  - `make test128-fast-smoke`
  - `make test128`
- Reconfirm real-play stability on C128:
  - boot and title flow
  - new game
  - town
  - descend / ascend
  - save / load resume
  - death / game-over flow
- Reconfirm no shared-code regressions on C64 from the merged gameplay changes.
- Keep the C128 memory/layout contract intact:
  - main segment below `$C000`
  - banked payload below `$FFFA`
  - staged `banked_payload` source below `$E000`
  - overlays fit their windows
  - low-RAM runtime loader contract remains valid
  - no callable code executes from the I/O hole

### Strongly Preferred

- Keep the new isolated disk-swap and renderer tests in the regular pre-merge verification path.

### Not Required

- `UI-80` refinement
- `FEAT-DISK`
- `FEAT-DEPTH`
- `FEAT1`
- `FEAT-AUD`
- cleanup/refactor backlog items that do not affect merge safety

## Merge Notes

- This file should contain actual open work only.
- Ongoing engineering guardrails belong in `AGENTS.md`, `tasks/lessons.md`, asserts, and test coverage, not in the backlog table.
