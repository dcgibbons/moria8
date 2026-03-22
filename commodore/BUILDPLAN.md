# Moria C64/C128 — Active Build Plan

> Active outstanding work only.
> See [DESIGN.md](DESIGN.md) for architecture reference and [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed phases, fixes, and reviews.

---

## Current State (2026-03-22)

- All core phases 1–9 are complete.
- C128 split, extended-memory database path, larger dungeon, hardened execution boundary, and the current 80-column baseline are complete.
- Recent resolved items include BUG-1, BUG-LIT, BUG-M1, BUG-X, OPT-1, OPT-2, REF-1, and the major C128 loader / banking stability repairs.
- C128 VDC optimization work is paused after the verified left-scroll rollback and subsequent stability regressions; any restart needs a fresh design pass.

## Active Outstanding Items

| Priority | Item | Type | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|---|
| High | Maintain 100% C128 suite pass rate | Merge gate | Medium | High | Yes | Ongoing requirement, not feature work. |
| High | Preserve `memory128.s` ownership / overlap guarantees | Merge gate | Medium | High | Yes | Bank/layout regressions remain a primary C128 risk. |
| High | Preserve low-RAM runtime loader contract for callable `$1000` code | Merge gate | Medium | High | Yes | Past `JAM` regressions make this non-negotiable. |
| High | Keep C128 smoke seed / `load_resume_game` path deterministic | Merge gate | Low | Medium | Yes | Needed to trust smoke coverage on the branch. |
| Medium | `TST-5` add isolated tests for disk swap, palette mapping, and rendering draw routines | Test coverage | Medium | Medium | Prefer | Good merge hardening if branch scope remains broad. |
| Medium | `10.4` Enhanced display: VDC color attributes for threat-coded monsters and special effects | Phase item | Medium | Medium | No | Product improvement, not a stability blocker. |
| Medium | `UI-80` refine the C128 80-column layout to a true Umoria-style left status panel | UI / backlog | High | Medium | No | Treat as a refinement of the shipped 80-column baseline, not a contradiction of 10.7 completion. |
| Medium | Platformize `spell_effects.s:574` screen-to-color RAM assumption | Shared-code cleanup | Medium | Medium | Prefer | Most correctness-sensitive remaining `common/` platform assumption. |
| Medium | Platformize `dungeon_gen.s:1901` screen-RAM scratch queue | Shared-code cleanup | Medium | Medium | Prefer | Important if common dungeon generation logic continues to evolve. |
| Low | Platformize `overlay.s` / `tier_manager.s` CIA2 VIC-bank restore assumptions | Shared-code cleanup | Medium | Low | No | Cleanup unless future C128 overlay work reopens the area. |
| Low | Clean up remaining 40-column layout assumptions in `ui_messages.s`, `title_data.s`, `ui_help.s`, `ui_status.s`, and `disk_swap.s` | UI cleanup | Medium | Low | No | Mostly polish and consistency work. |
| Low | `FEAT1` expand mage/priest spells from 16 to 31 each | Feature | High | Medium | No | Requires UI pagination and likely extra overlay pressure. |
| Low | `FEAT-AUD` audible hunger warning (buzz/beep) | Feature | Low | Medium | No | Add sound cue for Weak/Faint/Starve states to prevent surprise deaths. |
| Low | `A6` split large file `item.s` | Refactor | Medium | Low | No | Opportunistic maintainability work. |
| Low | `OPT-5` further overlays for magic/spells/UI | Optimization | High | Low | No | Only useful if main-segment pressure returns. |

## Merge Readiness Summary

- **Must be true before merging C128 to `main`:**
- C128 fast and authoritative suites remain green.
- Memory ownership, low-RAM loader, and smoke-seed stability gates remain intact.

- **Strongly preferred before merge:**
- `TST-5` lands or an equivalent targeted test expansion covers the same risk areas.
- The two most sensitive remaining shared-code assumptions (`spell_effects.s` and `dungeon_gen.s`) are either platformized or explicitly judged safe to defer.
