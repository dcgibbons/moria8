# Moria C64/C128 — Active Build Plan

> Active outstanding work only.
> See [DESIGN.md](DESIGN.md) for architecture reference and [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed phases, fixes, and reviews.

---

## Current State (2026-03-22)

- All core phases 1–9 are complete.
- C128 split, extended-memory database path, larger dungeon, hardened execution boundary, and the current 80-column baseline are complete.
- Recent resolved items include BUG-1, BUG-LIT, BUG-M1, BUG-X, OPT-1, OPT-2, REF-1, the major C128 loader / banking stability repairs, and the resident C128 banked combat relocation plus cached `OVL.UI`.
- C128 VDC optimization work is paused after the verified left-scroll rollback and subsequent stability regressions; any restart needs a fresh design pass.

## Open Bugs

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
| None | None at the moment. | — | — | — | Recent gameplay bugs BUG-LIT and BUG-1 are both closed. |

## Open Phases / Display Work

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
| Medium | `10.4` Enhanced display: VDC color attributes for threat-coded monsters and special effects | Medium | Medium | No | Product improvement, not a stability blocker. |
| Medium | `UI-80` refine the C128 80-column layout to a true Umoria-style left status panel | High | Medium | No | Treat as a refinement of the shipped 80-column baseline, not a contradiction of 10.7 completion. |

## Open Performance Work

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
| Medium | `PERF-DG-C128` reduce C128 dungeon-generation latency on larger maps | High | High | Prefer | Larger `198x66` C128 dungeons are functionally correct but level generation is noticeably slow in real play. Focus should stay on generation-time hot paths and avoid reopening the stable banking/overlay contracts. |

## Open Test / Cleanup Work

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
| Medium | `TST-5` add isolated tests for disk swap, palette mapping, and rendering draw routines | Medium | Medium | Prefer | Good merge hardening if branch scope remains broad. |
| Medium | Platformize `spell_effects.s:574` screen-to-color RAM assumption | Medium | Medium | Prefer | Most correctness-sensitive remaining `common/` platform assumption. |
| Medium | Platformize `dungeon_gen.s` BFS queue screen-RAM scratch assumption (`BFS_QUEUE = $0400`) | Medium | Medium | Prefer | Important if common dungeon generation logic continues to evolve. |
| Low | Platformize `overlay.s` / `tier_manager.s` CIA2 VIC-bank restore assumptions | Medium | Low | No | Cleanup unless future C128 overlay work reopens the area. |
| Low | Clean up remaining 40-column layout assumptions in `ui_messages.s`, `title_data.s`, `ui_help.s`, `ui_status.s`, and `disk_swap.s` | Medium | Low | No | Mostly polish and consistency work. |
| Low | `A6` split large file `item.s` | Medium | Low | No | Opportunistic maintainability work. |
| Low | `OPT-5` further overlays for magic/spells/UI | High | Low | No | Only useful if main-segment pressure returns. |

## Open Features

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
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

- Land `TST-5` or equivalent targeted coverage for disk swap, palette mapping, and rendering draw routines.
- Resolve or explicitly defer the two highest-risk remaining shared-code assumptions:
  - `spell_effects.s:574`
  - `dungeon_gen.s` BFS queue scratch region (`BFS_QUEUE = $0400`)

### Not Required

- `10.4` VDC threat/effect color work
- `UI-80` refinement
- `FEAT1`
- `FEAT-AUD`
- cleanup/refactor backlog items that do not affect merge safety

## Merge Notes

- This file should contain actual open work only.
- Ongoing engineering guardrails belong in `AGENTS.md`, `tasks/lessons.md`, asserts, and test coverage, not in the backlog table.
