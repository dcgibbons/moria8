# UI Status Redesign Plan

## Purpose

This document is the implementation plan for the shared gameplay-HUD redesign on `C64` and `C128`.

The goal is to restore the important upstream live-status semantics while preserving the bottom-bar Moria8 identity. This is not a C128-only left-panel plan. It is a shared status-model redesign with a roomier C128 presentation tier.

This plan is decision-complete. It records the locked product choices, the shared status contract, the platform layout strategy, the rendering approach, the character-screen follow-through, and the spell-test overlap.

## Locked Product Decisions

The following choices are fixed for this feature:

- Keep the bottom HUD as the default gameplay presentation on both `C64` and `C128`.
- Do not move to a side status panel in `v1`.
- Use one shared semantic status model on both platforms.
- Remove race from the persistent HUD on both platforms.
- Keep player name in the persistent HUD.
- Use one shared mixed-compact vocabulary and abbreviation policy on both platforms.
- Allow `C128` to show more of the same information at once, but not a different status contract.
- Treat the character screen as the home for displaced identity/detail data.
- Keep row-based dirty redraws in the first implementation pass.
- Do not fold `OPT-STATUS-ROW23` field-level redraw work into this feature unless correctness requires it.

## Shared Status Model

Both `C64` and `C128` gameplay HUDs should surface the same important status concepts:

- level
- depth
- HP
- MP
- AC
- AU
- hunger
- blind
- confused
- afraid
- poisoned
- searching
- rest
- repeat count
- paralysis
- speed state
- study availability

### Shared wording policy

Use mixed compact wording by default:

- prefer readable short words where they fit:
  - `Blind`
  - `Afraid`
  - `Poison`
  - `Study`
  - `Fast`
- use compact movement/count forms where space is tighter:
  - `Rest 12`
  - `Rpt 8`
- abbreviate only when width requires it; do not make the whole HUD cryptic by default

### Shared precedence rules

Movement/command state precedence is fixed:

1. `Paralysed`
2. `Rest`
3. `Repeat`
4. `Searching`
5. blank

If a narrower platform cannot show every transient token at once, apply deterministic priority rather than ad hoc omissions:

- critical conditions win over lower-priority progression/identity fields
- core vitals win over decorative identity text
- the displaced information must remain available on the character screen

## Platform Layout Strategy

The layout is one design with two density tiers.

### C128

Keep the current 3-row bottom-HUD identity, but repack it around shared status priorities:

- one row for player name plus core progression/vitals
- one compressed six-stat row
- one transient-state row carrying:
  - hunger
  - blind
  - confused
  - afraid
  - poisoned
  - movement/command state
  - speed
  - study

`C128` should spend its extra width on readability, not on different semantics.

### C64

Keep the same bottom-HUD identity and the same semantic model, but accept denser packing.

If `40` columns cannot carry every field cleanly at once, use one fixed priority model:

1. HP / MP / AC / depth
2. hunger and movement state
3. blind / confused / afraid / poisoned
4. level / gold / study / speed
5. spacious six-stat readability

This means `C64` and `C128` may not show the exact same simultaneous field count, but they must share the same vocabulary, status meaning, and prioritization rules.

## Rendering and Implementation Guidance

Refactor [ui_status.s](common/ui_status.s) into:

- shared state-synthesis logic
- platform-specific layout anchors and formatting widths

Add cached previous-state tracking for newly visible live-state data, including:

- hunger
- blind
- confused
- afraid
- poisoned
- searching
- rest active/count
- repeat active/count
- paralysis
- speed bucket
- study availability
- any relocated progression/vitals fields

The first implementation pass should keep row-based dirty redraws:

- row 1 dirty when identity/progression/vitals change
- row 2 dirty when any visible stat changes
- row 3 dirty when transient conditions, movement state, speed, or study change

Do not combine this redesign with field-level micro-redraw optimization unless needed for correctness.

## Character Screen Follow-Through

The character screen on both platforms becomes the stable home for information removed or compressed from the persistent HUD.

Minimum required character-screen contract:

- race
- class
- level
- XP
- HP current/max
- mana current/max
- AC
- gold
- depth
- six stats

`C128` may get a richer `80`-column composition, but not a different data model. `C64` and `C128` should still present the same essential information.

## Side-Panel Trade-Off

Do not move to a side status panel in `v1`.

Reason:

- `80` columns are enough for full live-status parity if the bottom HUD is repacked
- the shared `C64`/`C128` direction is now bottom-bar parity, not a `C128`-only panel fork
- a side panel would widen scope into viewport partitioning, map presentation, and a larger product-identity change

Decision rule for later:

- if the goal remains shared live-status parity, keep the bottom HUD
- if the goal later becomes full upstream always-visible stat-block parity during gameplay, revisit a side-panel design, most likely as a `C128` refinement

## Spell-Test Overlap

This redesign does affect spell/prayer test expectations, but mainly through visible HUD/status output, not through core spell mechanics.

Most exposed categories:

- poison-clearing spells and prayers
- fear-clearing prayers
- haste/speed spells
- mana/status redraw expectations
- study visibility after learning/recalculation

Examples of overlapping spell/prayer rows from the completed spell-test
baseline:

- `Cure Poison`
- `Slow Poison`
- `Neutralize Poison`
- `Remove Fear`
- `Haste Self`
- `Holy Word`

What changes:

- tests that assert internal state mutation should remain valid
- tests that assert visible HUD tokens, redraw timing, or exact status strings will likely need updates
- new status-focused fixtures should be shared where possible instead of duplicating HUD assertions per spell

Required sequencing:

1. start from the completed spell-test baseline
2. treat that baseline as the source of truth for spell mechanics and message contracts
3. during the HUD redesign, update only the spell tests whose assertions include visible status/render expectations

## Verification Contract

Minimum future verification gates:

- `make test64`
- `make test128-fast`
- `make test128-fast-smoke`
- `make -C commodore build128`

Add or extend status-focused runtime tests so they verify:

- condition visibility on both platforms
- movement-state precedence
- speed visibility
- study visibility
- stable layout bounds on `40` and `80` columns
- redraw coherence when transient status changes rapidly
