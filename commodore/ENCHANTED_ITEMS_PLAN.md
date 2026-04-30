# Enchanted Items / Item Stats Plan

> Status: Complete as of 2026-04-29. This is now an archived implementation
> plan for `FEAT-ITEM-STATS`, not an active work queue. Current architecture
> notes live in `DESIGN.md`; completion history lives in `BUILDPLAN_HISTORY.md`.

## Purpose

This document records the completed implementation plan for `FEAT-ITEM-STATS`.

The goal is to restore upstream-style item stat semantics and visibility across the Commodore port. This is not a UI-only suffix pass. The feature must make item-instance data, gameplay behavior, and displayed descriptions agree.

This plan is decision-complete. It records the feature scope, the locked product decisions, the required data-model changes, the spell-system overlap, and the test contract.

## Original Problem

The pre-feature Commodore item model overloaded a single per-instance numeric
field:

- `inv_p1` was reused for:
  - weapon enchantment
  - armor enchantment
  - wand/staff charges
  - light fuel
  - other type-specific payloads
- UI printed base item names plus ego prefix/suffix text, but did not print
  stat-aware descriptions.
- Gameplay behavior was simplified around the same overloading:
  - weapon bonus acted as both `to_hit` and `to_dam`
  - armor bonus shared the same storage model as non-combat `p1`
  - enchant flows mutate the old shared field directly

That simplification was the blocker. A UI-only exposure of `inv_p1` would have
preserved the wrong semantics, fought the requested upstream reveal rules, and
made later correction more expensive.

## Locked Product Decisions

The following choices are fixed for this feature:

- Use split per-instance combat/armor stat fields, not `inv_p1` exposure.
- Match exact upstream semantics for visible item stat text and gameplay behavior.
- Show stat-aware item descriptions everywhere descriptions currently appear.
- Break old save compatibility cleanly rather than add migration logic.
- Keep `p1` only for type-specific payloads such as charges, fuel, and other meaningful non-combat values.
- Include all meaningful `p1` values in the first shipping pass.
- Use exact upstream-style knowledge / reveal rules for unidentified, sensed, cursed, known, and identified items.
- Fix behavior too, not display only.

## Historical Required Sequencing

The feature was planned to start only after the spell-test branch based on
`commodore/SPELL_TEST_PLAN.md` landed.

Reason:

- FEAT-ITEM-STATS directly overlaps the item-facing spell/prayer seams and their new tests.
- If the spell-test branch is still moving, FEAT-ITEM-STATS will force duplicate expectation churn on:
  - `Identify`
  - `Remove Curse`
  - `Enchant Weapon`
  - `Enchant Armor`
  - `Recharge Item I`
  - `Recharge Item II`

Correct order:

1. land the spell-test branch
2. rebase FEAT-ITEM-STATS on that baseline
3. update the affected item-facing spell/prayer expectations once

## Target Architecture

### Item-instance model

Split combat and armor bonuses into distinct per-instance fields.

Add parallel storage for:

- `to_hit`
- `to_dam`
- `to_ac`

Required surfaces:

- inventory instances
- floor-item instances
- store inventory instances

Keep existing `p1` only for type-specific payloads, including:

- wand charges
- staff charges
- light fuel
- other meaningful non-combat values that upstream descriptions expose

Do not use `p1` as a generic “item bonus” field after this feature lands.

### Description architecture

Replace the current “base name with ego text” contract with one shared stat-aware formatter driven by:

- item type
- item instance fields
- ego state
- flags
- knowledge / reveal state

All item-description surfaces must route through the same description contract:

- inventory
- equipment
- store and home listings where item descriptions are shown
- identify flows
- item-result messages that print affected item names/descriptions

The formatter must be category-aware. Do not try to retrofit stat placeholders into the existing static base-name strings.

## Data and Persistence Plan

### New storage

Add split stat arrays for:

- carried/equipped inventory
- floor items
- store inventory

Update all item movement/copy paths so the split fields travel with the instance:

- generation/spawn
- floor placement
- pickup
- drop
- equip / takeoff
- store buy / sell
- home deposit / withdraw
- save / load

### Save format

Save compatibility is intentionally broken for this feature.

Requirements:

- update save layout in one clean pass
- serialize the new split fields explicitly
- do not add legacy load translation
- document that pre-feature save files are unsupported after landing

## Gameplay Semantics

### Combat and equipment math

Equipment and combat code must consume the split fields directly.

Required outcomes:

- weapon `to_hit` and `to_dam` are independent
- armor/shield/wearable AC bonuses use `to_ac`
- `player_recalc_equipment` and related combat math stop reading generic `p1` as “the item bonus”

### Enchant and curse flows

Behavior changes are in scope, not optional.

Required updates:

- `Enchant Weapon` mutates the correct weapon stat field(s) under upstream semantics
- `Enchant Armor` mutates the correct armor `to_ac` field
- curse-clearing flows stop assuming “zero the shared bonus field” is the whole model
- recharging and fuel flows remain `p1`-based

The display layer and the gameplay layer must move together. Do not split the model first and leave combat/equipment/enchant logic on the old interpretation.

## Knowledge / Reveal Contract

Use the local `umoria` and `vms-moria` trees as the source of truth for reveal rules.

Requirements:

- unidentified items hide gated numeric bonuses when upstream does
- sensed items reveal only what upstream reveal state allows
- cursed/known/identified cases follow upstream rules exactly enough to match player-visible intent
- store items remain fully visible because the store path already treats them as identified

Target visible forms include, at minimum:

- weapons: `(+to_hit,+to_dam)`
- armor / shields / wearables: `[base_ac,+to_ac]`
- charges, fuel, and other relevant non-combat payloads where upstream exposes them

Do not simplify reveal policy to “full identification only” unless a later explicit product decision reopens that choice.

## Spell-System Overlap

FEAT-ITEM-STATS is not a general spell-system feature, but it does directly impact the item-facing spell/prayer paths.

Affected seams include:

- `Identify`
  - knowledge flags
  - instance identified state
  - item-description output
- `Remove Curse`
  - curse flag handling
  - item stat reset/retention semantics
- `Enchant Weapon`
  - split-field mutation
  - resulting item text
- `Enchant Armor`
  - split-field mutation
  - resulting item text
- `Recharge Item I/II`
  - keeps `p1` semantics for charges
  - still depends on stat-aware item descriptions and item persistence

Most non-item spells are unaffected. The conflict surface is specifically the item-utility spell/prayer family plus any tests or messages that assert item descriptions after those actions.

## Implementation Order

Implement in this order:

1. land the current spell-test branch
2. add split item-instance fields for inventory, floor items, and stores
3. update item copy/move/save/load seams so the new fields persist correctly
4. update combat/equipment/enchant behavior to use the split fields
5. introduce the shared stat-aware formatter
6. route all item-description surfaces through that formatter
7. update the item-facing spell/prayer paths and their expectations on top of the landed spell-test baseline
8. run cross-platform verification and fix memory/layout fallout locally

## Test Contract

### Item-model correctness

Add or update tests for:

- generation/spawn producing correct split stat fields
- floor-to-inventory transfer preserving all fields
- inventory-to-equipment transfer preserving all fields
- store/home transfer preserving all fields
- save/load round-trip preserving all fields

### Gameplay correctness

Add or update tests for:

- weapon `to_hit` and `to_dam` independence
- armor `to_ac` behavior
- enchant weapon updates the correct field(s)
- enchant armor updates `to_ac`
- recharge remains `p1`-based
- light fuel remains `p1`-based

### Description and reveal correctness

Add or update tests for:

- weapon description form under each relevant knowledge state
- armor description form under each relevant knowledge state
- charges/fuel/type-specific `p1` display where upstream exposes it
- identified vs sensed vs cursed vs unknown transitions
- store descriptions showing full stat-aware data

### Spell/item overlap

After the spell-test branch lands, update the affected spell/prayer tests so item-facing expectations match the new item model and description contract for:

- `Identify`
- `Remove Curse`
- `Enchant Weapon`
- `Enchant Armor`
- `Recharge Item I/II`

### Cross-platform gates

Planned minimum required gates before closure:

- `make test64`
- `make test128-fast-smoke`
- `make -C commodore build128`

If memory/layout asserts fail after adding the new arrays or formatter, recover bytes locally. Do not simplify the player-visible contract to buy space.

## Non-Goals

The following are out of scope for this feature unless a later decision explicitly reopens them:

- old-save migration
- a second temporary formatter contract
- preserving the old shared-bonus behavior under a new display layer
- turning this document into a full spell test matrix
- unrelated item-system redesign beyond what the split-field model requires

## Acceptance Criteria

The feature is complete only when all of the following are true:

- item-instance combat/armor stats are split into separate persistent fields
- `p1` is no longer used as a generic combat/armor bonus field
- gameplay behavior and displayed descriptions agree
- item descriptions are stat-aware everywhere descriptions appear
- reveal rules follow upstream semantics
- item-facing spell/prayer seams are updated on top of the landed spell-test baseline
- old saves are intentionally unsupported and the new save format is coherent
- the required C64/C128 verification gates are green

## Completion Notes

The implementation landed with split persistent item-stat fields for inventory,
floor, and store/home instances; stat-aware descriptions; item-facing spell and
scroll updates; save/load persistence; ammo stack visibility; and C64/C128
runtime/layout fixes needed to keep the feature stable.

Final verification for the feature included:

- `make test64` passing 129/129 tests
- `make test128-fast` passing cold and snapshot batches
- `make test128-fast-smoke` passing 8/8 smokes
- `make -C commodore build128` passing
- manual C64/C128 verification of enchant display, save/load persistence for
  equipped enchanted items, ammo stack counts, bolt consumption, and C128
  boot/save/load/modal flows
