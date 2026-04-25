# Spell Test Plan

## Purpose

This document is the coverage contract for the full Commodore spell matrix. It defines the minimum automated test coverage required for all `31` mage-affinity spells and all `31` priest-affinity prayers on both `C64` and `C128`.

This is not a wishlist and not a historical audit. A spell is not considered covered unless its row requirements are satisfied.

## Coverage Standard

- Every spell/prayer must have at least one success test on `C64` and one success test on `C128`.
- Every spell/prayer must have cast-failure coverage when the spell can fail its cast roll.
- Every spell/prayer must have successful-cast-but-no-effect or blocked coverage when that outcome is meaningful.
- Every spell/prayer must define explicit success criteria.
- Every spell/prayer must define message expectations for all applicable outcomes.
- No spell/prayer may be treated as covered only because a similar family member is covered.
- Shared harnesses are allowed only when parameterized by spell identity and when the row-level spell contract remains explicit.

## Outcome Taxonomy

- `Gate Failure`: command rejected before execution.
  - wrong spell type / no cast
  - insufficient class level
  - no known spell in selected book
  - validation reject
  - cancel / input abort
- `Cast Failure`: valid selection reaches the failure roll and fizzles.
- `Success`: intended gameplay effect occurs.
- `Success, No Effect`: cast executes but conditions make the result null.
- `Success, Blocked`: cast executes but occupancy/environment blocks the result.
- `Visible-Only Success`: success is intentionally message-light and is proven by state/render outcome.
- `Explicit-Message Success`: success requires player-facing feedback because the result would otherwise be silent or ambiguous.

## Platform Contract

- Gameplay outcome must match on `C64` and `C128`.
- Message contract must match on `C64` and `C128` unless a row explicitly documents a justified platform-specific exception.
- Every row requires `C64 + C128`.
- Every row must have at least one product-path success case and at least one product-path failure case.
- Product-path proof and row-proof are different obligations:
  - product-path proof shows the real cast/pray flow reaches the intended runtime owner on that platform
  - row-proof shows the row's exact negative/message/bookkeeping contract, which may require a focused harness beyond the product smoke
- Helper-path tests may supplement coverage, but they cannot be the only proof for a row.
- Product-path tests must respect existing platform risks:
  - `C64`: overlay ownership, resident-vs-overlay seams, and memory-growth boundaries.
  - `C128`: bank visibility, load destination, trampoline safety, and I/O-hole exclusions.

## Shared Harness Contracts

These contracts reduce duplication but never replace spell rows.

- `Common pre-cast seam`
  - Canonical source: `commodore/common/player_magic.s`
  - Proves wrong spell type, insufficient class level, no known spell, validation reject, cancel, and input-abort seams.
- `Detect result/no-result`
  - Proves positive detection vs no-eligible-target messaging and state.
- `Heal family`
  - Proves HP increase, cap-at-max, full-HP no-op, and heal-tier messaging.
- `Timed buff/protection`
  - Proves onset, refresh, already-active semantics, timer mutation, and message policy.
- `Directional single-target`
  - Proves prompt, target acquisition, hit path, and target mutation.
- `Directional miss/no-target`
  - Proves miss or absent target feedback when meaningful.
- `Sleep/control`
  - Proves asleep/controlled result, resistant/unaffected result, and no-target result.
- `Placement/blocking`
  - Proves successful placement vs blocked-by-tile/object occupancy.
- `Area-effect`
  - Proves affected-area success plus empty/unaffected area when meaningful.
- `Inventory utility / targeted item`
  - Proves eligible-item success, no-eligible-item failure, and destructive/backfire paths where relevant.
- `Dispel / flagged-target`
  - Proves matching-target success vs no-matching-target no-effect.
- `Map/terrain mutation`
  - Proves terrain changes, redraw flags, and preserved invariants.

## Matrix Columns

Each matrix row below defines:

- `Platforms`: always `C64+C128`
- `Success Scenario`: minimum productive cast case
- `Success Criteria`: gameplay facts that must be asserted
- `Gate`: required shared gate coverage plus any spell-specific gate note
- `Cast Fail`: whether a forced failure-roll test is required
- `No Effect / Blocked`: required negative outcome if the cast executes successfully but does not accomplish the intended result
- `Messages`: exact success/failure/silence expectations
- `Harness`: allowed shared harness family

## Matrix Rules

- `Gate` defaults to `Shared seam + row mapping confirmation`.
- `Cast Fail` defaults to `Yes` unless explicitly marked `N/A`.
- `No Effect / Blocked` must be one of:
  - `Required`
  - `Covered by different negative mode`
  - `N/A`
- Every `N/A` must have a semantic reason, not a convenience reason.
- Every row must define:
  - one concrete success scenario
  - exact gameplay success criteria
  - exact message expectations
  - whether explicit silence is required
  - whether prompt/selection behavior is part of the row
  - RNG handling policy

Negative-case priority for every row:

1. Require `Cast Fail` if the spell goes through the failure-roll path.
2. Require `No Effect / Blocked` if an executed cast can do nothing or be refused.
3. Require resistant/unaffected coverage if target logic supports it.
4. Require miss/no-target coverage for directional or target-dependent effects.
5. Use `N/A` only if none of the above are meaningful.

## Mage Spell Matrix

| # | Spell | Book | Family | Platforms | Success Scenario | Success Criteria | Gate | Cast Fail | No Effect / Blocked | Messages | Harness |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Magic Missile | M1 | Directional Bolt | C64+C128 | Hit adjacent visible monster | projectile resolves, target takes damage or dies, mana/worked bookkeeping updates | Shared seam + spell-id mapping | Yes | Required: no target or miss path | success is message-light; cast fail explicit; no-target uses miss/fizzle contract | Directional single-target + directional miss/no-target |
| 2 | Detect Monsters | M1 | Detect | C64+C128 | Cast with active monster present | detect state enabled and active-monster result is reported | Shared seam + spell-id mapping | Yes | Required: no active monsters | success uses detect-present text; no-effect uses no-creatures text | Detect result/no-result |
| 3 | Phase Door | M1 | Teleport | C64+C128 | Short self-teleport to valid nearby floor | player relocates within phase-door distance limit, occupancy flags update, redraw/visibility updates | Shared seam + spell-id mapping | Yes | N/A: successful execution always relocates if destination search succeeds | success is message-light; cast fail explicit | Area-effect with deterministic RNG |
| 4 | Light Area | M1 | Terrain/Map Utility | C64+C128 | Light current room/corridor | room/tile light state updates and redraw flag is set | Shared seam + spell-id mapping | Yes | N/A: execution always lights current room/corridor | explicit light message on success; cast fail explicit | Map/terrain mutation |
| 5 | Cure Light Wounds | M1 | Heal | C64+C128 | Heal while injured | HP increases by valid range and caps at max | Shared seam + spell-id mapping | Yes | Required: full-HP cast stays no-op | heal-tier success text when injured; silence at full HP; cast fail explicit | Heal family |
| 6 | Find Hidden Traps/Doors | M1 | Detect | C64+C128 | Reveal tracked hidden traps/doors | eligible hidden features become revealed and redraw updates | Shared seam + spell-id mapping | Yes | Required: no eligible traps/doors | success is message-light unless explicit current behavior differs; no-effect uses detect-none contract if implemented, otherwise silence requirement must be asserted | Detect result/no-result + map/terrain mutation |
| 7 | Stinking Cloud | M1 | Ball | C64+C128 | Poison ball hits monster in radius | flash/ball path runs, target HP/status changes, kill path valid | Shared seam + spell-id mapping | Yes | Required: empty target area | success is message-light; cast fail explicit; empty-area no-effect contract required | Area-effect |
| 8 | Confusion | M2 | Directional Control | C64+C128 | Confuse valid target monster | target confuse flag/timer set | Shared seam + spell-id mapping | Yes | Required: no target or miss | success uses current confuse-hit feedback if any; no-target/unaffected text required | Directional single-target + directional miss/no-target |
| 9 | Lightning Bolt | M2 | Directional Bolt | C64+C128 | Hit target with lightning bolt | projectile resolves, damage applied, kill path valid | Shared seam + spell-id mapping | Yes | Required: no target or miss path | success message-light; cast fail explicit; miss/fizzle contract required | Directional single-target + directional miss/no-target |
| 10 | Trap/Door Destruction | M2 | Terrain/Map Utility | C64+C128 | Destroy eligible traps/doors in area | eligible traps are cleared and doors are opened/destroyed per current behavior | Shared seam + spell-id mapping | Yes | Required: no eligible traps/doors | success message-light unless current build prints one; no-effect contract required | Map/terrain mutation |
| 11 | Sleep I | M2 | Sleep | C64+C128 | Put one target monster to sleep | targeted monster sleep timer set and awake state cleared | Shared seam + spell-id mapping | Yes | Required: no target or resistant/unaffected target | success may be message-light or explicit per current behavior; unaffected/no-target feedback required | Sleep/control + directional miss/no-target |
| 12 | Cure Poison | M2 | Utility Cleanse | C64+C128 | Cast while poisoned | poison state clears | Shared seam + spell-id mapping | Yes | Required: not poisoned | explicit success text when poison clears; no-effect text or silence requirement when already clear; cast fail explicit | Timed buff/protection |
| 13 | Teleport Self | M2 | Teleport | C64+C128 | Long self-teleport to valid floor | player relocates, occupancy flags update, redraw/visibility updates | Shared seam + spell-id mapping | Yes | N/A: successful execution always relocates if destination search succeeds | success is message-light; cast fail explicit | Area-effect with deterministic RNG |
| 14 | Remove Curse | M2 | Inventory Utility | C64+C128 | Equipped cursed item is cleansed | curse flag cleared from eligible equipped item(s) | Shared seam + spell-id mapping | Yes | Required: no equipped cursed items | explicit cleansed text on success; no-effect text or silence policy must be asserted | Inventory utility / targeted item |
| 15 | Frost Bolt | M2 | Directional Bolt | C64+C128 | Hit target with frost bolt | projectile resolves, damage applied, kill path valid | Shared seam + spell-id mapping | Yes | Required: no target or miss path | success message-light; cast fail explicit; miss/fizzle contract required | Directional single-target + directional miss/no-target |
| 16 | Turn Stone to Mud | M2 | Terrain/Map Utility | C64+C128 | Target diggable wall | selected wall becomes floor/mud and map updates | Shared seam + spell-id mapping | Yes | Required: non-wall or invalid target | success message-light unless current build prints one; blocked/no-valid-wall outcome required | Map/terrain mutation + directional miss/no-target |
| 17 | Create Food | M3 | Placement | C64+C128 | Create food on eligible player tile | food item appears under player per current replacement rules | Shared seam + spell-id mapping | Yes | Required: blocked tile/object case per current semantics | explicit success text if current path uses it; blocked/no-target text required | Placement/blocking |
| 18 | Recharge Item I | M3 | Inventory Utility | C64+C128 | Recharge eligible wand/staff | selected item charges/p1 increase or valid recharge mutation occurs | Shared seam + spell-id mapping | Yes | Covered by different negative mode: no eligible item and backfire/break risk | explicit success text; no-eligible-item text; destructive/backfire outcome validated | Inventory utility / targeted item |
| 19 | Sleep II | M3 | Sleep | C64+C128 | Sleep adjacent monster(s) | adjacent eligible monster sleeps | Shared seam + spell-id mapping | Yes | Required: no adjacent monsters or resistant target | success and unaffected/no-target texts required | Sleep/control |
| 20 | Polymorph Other | M3 | Directional Control | C64+C128 | Polymorph valid target monster | target monster is replaced according to current invariants and map occupancy remains valid | Shared seam + spell-id mapping | Yes | Required: no target or resistant/unaffected target if current behavior supports it | success is message-light unless current build prints one; no-target/unaffected contract required | Directional single-target with deterministic RNG |
| 21 | Identify | M3 | Inventory Utility | C64+C128 | Identify eligible inventory item | knowledge flag updates and item instance is marked identified | Shared seam + spell-id mapping | Yes | Required: cancel/no eligible item path | success prints correct identify message; cancel or no-item path prints current failure message | Inventory utility / targeted item |
| 22 | Sleep III | M3 | Sleep | C64+C128 | Sleep visible eligible monsters | one or more visible monsters sleep | Shared seam + spell-id mapping | Yes | Required: no visible eligible monsters | success and no-effect texts required | Sleep/control |
| 23 | Fire Bolt | M3 | Directional Bolt | C64+C128 | Hit target with fire bolt | projectile resolves, damage applied, kill path valid | Shared seam + spell-id mapping | Yes | Required: no target or miss path | success message-light; cast fail explicit; miss/fizzle contract required | Directional single-target + directional miss/no-target |
| 24 | Slow Monster | M3 | Directional Control | C64+C128 | Slow valid target monster | target speed state mutates and target is no longer treated as fast/current-speed | Shared seam + spell-id mapping | Yes | Required: no target or unaffected target | explicit slowed-target text on success; current no-target contract required | Directional single-target + directional miss/no-target |
| 25 | Frost Ball | M4 | Ball | C64+C128 | Frost ball affects monster in radius | flash/ball path runs and target takes damage or dies | Shared seam + spell-id mapping | Yes | Required: empty target area | success is message-light; cast fail explicit; empty-area no-effect contract required | Area-effect |
| 26 | Recharge Item II | M4 | Inventory Utility | C64+C128 | Recharge eligible wand/staff with stronger recharge | selected item mutates by stronger recharge path | Shared seam + spell-id mapping | Yes | Covered by different negative mode: no eligible item and destructive/backfire path | explicit success text; no-eligible-item text; destructive/backfire outcome validated | Inventory utility / targeted item |
| 27 | Teleport Other | M4 | Directional Control | C64+C128 | Teleport valid target monster away | target monster relocates and occupancy state remains valid | Shared seam + spell-id mapping | Yes | Required: no target or unaffected target if supported | success is message-light unless current build prints one; no-target/unaffected contract required | Directional single-target with deterministic RNG |
| 28 | Haste Self | M4 | Timed Buff | C64+C128 | Gain speed while not hasted | speed timer/status increases | Shared seam + spell-id mapping | Yes | Required: refresh/already-active case | explicit speed text on onset; refresh policy must match current behavior; cast fail explicit | Timed buff/protection |
| 29 | Fire Ball | M4 | Ball | C64+C128 | Fire ball affects monster in radius | flash/ball path runs and target takes damage or dies | Shared seam + spell-id mapping | Yes | Required: empty target area | success is message-light; cast fail explicit; empty-area no-effect contract required | Area-effect |
| 30 | Word of Destruction | M4 | Area/Map Utility | C64+C128 | Destroy surrounding area in valid dungeon scene | surrounding terrain mutates per current rules and redraw updates | Shared seam + spell-id mapping | Yes | N/A: successful execution always mutates surrounding area | success is message-light unless current build prints one; cast fail explicit | Area-effect + map/terrain mutation |
| 31 | Genocide | M4 | Area/Selection Utility | C64+C128 | Remove monsters of chosen glyph/type | all matching eligible monsters are removed and nonmatching monsters remain | Shared seam + spell-id mapping | Yes | Required: no monsters of chosen type remain | explicit prompt and no-match text required if current build has it; success may be message-light except selection feedback | Area-effect with deterministic RNG/input |

## Priest Prayer Matrix

| # | Prayer | Book | Family | Platforms | Success Scenario | Success Criteria | Gate | Cast Fail | No Effect / Blocked | Messages | Harness |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Detect Evil | P1 | Detect | C64+C128 | Cast with evil monster present in current panel | evil monster tile is revealed immediately, no detect timer is armed, and evil-present result is reported from the effect result | Shared seam + spell-id mapping | Yes | Required: no evil monsters or evil outside current panel | explicit evil-present text; no-evil text | Detect result/no-result |
| 2 | Cure Light Wounds | P1 | Heal | C64+C128 | Heal while injured | HP increases by valid range and caps at max | Shared seam + spell-id mapping | Yes | Required: full-HP cast stays no-op | heal-tier success text when injured; silence at full HP; cast fail explicit | Heal family |
| 3 | Bless | P1 | Timed Buff | C64+C128 | Gain bless while not blessed | bless timer/status increases | Shared seam + spell-id mapping | Yes | Required: refresh/already-active case | explicit onset text; refresh policy must match current behavior | Timed buff/protection |
| 4 | Remove Fear | P1 | Utility Cleanse | C64+C128 | Cast while afraid | fear timer/status clears | Shared seam + spell-id mapping | Yes | Required: not afraid | explicit success text when fear clears; no-effect text or silence policy when already clear | Timed buff/protection |
| 5 | Call Light | P1 | Terrain/Map Utility | C64+C128 | Light current room/corridor | room/tile light state updates and redraw flag is set | Shared seam + spell-id mapping | Yes | N/A: execution always lights current room/corridor | explicit light message on success; cast fail explicit | Map/terrain mutation |
| 6 | Find Traps | P1 | Detect | C64+C128 | Reveal tracked hidden traps | eligible hidden traps become revealed | Shared seam + spell-id mapping | Yes | Required: no eligible traps | success message-light unless current build differs; detect-none contract required if implemented, otherwise silence requirement must be asserted | Detect result/no-result + map/terrain mutation |
| 7 | Detect Doors/Stairs | P1 | Detect | C64+C128 | Reveal tracked doors/stairs | eligible hidden doors/stairs become revealed under current restored rules | Shared seam + spell-id mapping | Yes | Required: no eligible doors/stairs | message policy must match current build; no-effect outcome required | Detect result/no-result + map/terrain mutation |
| 8 | Slow Poison | P1 | Utility Cleanse | C64+C128 | Cast while poisoned | poison severity decreases according to current rules | Shared seam + spell-id mapping | Yes | Required: not poisoned | reduced-poison feedback on actual reduction; already-clear remains silent | Timed buff/protection |
| 9 | Blind Creature | P2 | Directional Control | C64+C128 | Blind valid target monster | shared directional-confuse path sets confuse and does not mutate stun | Shared seam + spell-id mapping | Yes | Required: no target or unaffected target | shared confuse-hit feedback; no-target feedback required | Directional single-target + directional miss/no-target |
| 10 | Portal | P2 | Teleport | C64+C128 | Self-teleport to valid floor | player relocates, occupancy flags update, redraw/visibility updates | Shared seam + spell-id mapping | Yes | N/A: successful execution always relocates if destination search succeeds | success is message-light; cast fail explicit | Area-effect with deterministic RNG |
| 11 | Cure Medium Wounds | P2 | Heal | C64+C128 | Heal while injured | HP increases by valid range and caps at max | Shared seam + spell-id mapping | Yes | Required: full-HP cast stays no-op | heal-tier success text when injured; silence at full HP; cast fail explicit | Heal family |
| 12 | Chant | P2 | Timed Buff | C64+C128 | Gain stronger bless while not blessed | bless timer/status increases by chant path | Shared seam + spell-id mapping | Yes | Required: refresh/already-active case | explicit onset text per current behavior; refresh policy must match current build | Timed buff/protection |
| 13 | Sanctuary | P2 | Sleep | C64+C128 | Sleep adjacent eligible monster | adjacent monster sleeps | Shared seam + spell-id mapping | Yes | Required: no adjacent monsters and resistant target | explicit success, unaffected, and no-target texts required | Sleep/control |
| 14 | Create Food | P2 | Placement | C64+C128 | Create food on eligible player tile | food item appears under player per current replacement rules | Shared seam + spell-id mapping | Yes | Required: blocked tile/object case per current semantics | explicit success text if current path uses it; blocked/no-target text required | Placement/blocking |
| 15 | Remove Curse | P2 | Inventory Utility | C64+C128 | Carrying/equipped cursed item is cleansed | curse flags clear from eligible inventory/equipment set | Shared seam + spell-id mapping | Yes | Required: no cursed carried/equipped items | explicit cleansed text on success; no-effect text or silence policy required | Inventory utility / targeted item |
| 16 | Resist Heat and Cold | P2 | Timed Buff | C64+C128 | Gain resist while not already resisted and verify damage reduction | resist state/timer increases and hostile elemental path is reduced under current Commodore semantics | Shared seam + spell-id mapping | Yes | Required: refresh/already-active case | explicit onset text; refresh policy must match current behavior | Timed buff/protection |
| 17 | Neutralize Poison | P3 | Utility Cleanse | C64+C128 | Cast while poisoned | poison state clears | Shared seam + spell-id mapping | Yes | Required: not poisoned | explicit success text when poison clears; no-effect text or silence policy required | Timed buff/protection |
| 18 | Orb of Draining | P3 | Ball | C64+C128 | Holy ball affects eligible monster | ball path runs and target takes damage or dies | Shared seam + spell-id mapping | Yes | Required: empty target area | success is message-light unless current build prints one; empty-area no-effect contract required | Area-effect |
| 19 | Cure Serious Wounds | P3 | Heal | C64+C128 | Heal while injured | HP increases by valid range and caps at max | Shared seam + spell-id mapping | Yes | Required: full-HP cast stays no-op | heal-tier success text when injured; silence at full HP; cast fail explicit | Heal family |
| 20 | Sense Invisible | P3 | Timed Buff | C64+C128 | Gain see-invisible while not already active | see-invisible state/timer updates | Shared seam + spell-id mapping | Yes | Required: refresh/already-active case | explicit onset text; refresh policy must match current behavior | Timed buff/protection |
| 21 | Protection from Evil | P3 | Timed Buff | C64+C128 | Gain protection while not already active | protection timer/status updates | Shared seam + spell-id mapping | Yes | Required: refresh/already-active case | explicit onset text; refresh policy must match current behavior | Timed buff/protection |
| 22 | Earthquake | P3 | Area/Map Utility | C64+C128 | Earthquake mutates nearby tiles | terrain mutates under current rules, redraw/scene-dirty updates, occupancy invariants remain valid | Shared seam + spell-id mapping | Yes | Required: low-impact/empty-area case if current semantics allow minimal visible change | explicit cast text if current build prints one; otherwise message-light requirement must be asserted | Area-effect + map/terrain mutation |
| 23 | Sense Surroundings | P3 | Map Utility | C64+C128 | Reveal surrounding map area | map area reveals according to current rules and redraw updates | Shared seam + spell-id mapping | Yes | Required: no newly revealable area or hidden-feature-preservation case | success may be message-light; no-effect contract required if meaningful | Map/terrain mutation |
| 24 | Cure Critical Wounds | P3 | Heal | C64+C128 | Heal while injured | HP increases by valid range and caps at max | Shared seam + spell-id mapping | Yes | Required: full-HP cast stays no-op | heal-tier success text when injured; silence at full HP; cast fail explicit | Heal family |
| 25 | Turn Undead | P3 | Dispel / Flagged Target | C64+C128 | Affect visible undead target(s) | visible/LOS low-level undead are turned; resistant visible undead remain unchanged; hidden undead are ignored | Shared seam + spell-id mapping | Yes | Required: no visible undead targets and resistant visible undead | per-target `runs frantically!` / `is unaffected.`; no-visible-undead prints `Nothing seems to happen.` | Dispel / flagged-target |
| 26 | Prayer | P4 | Timed Buff | C64+C128 | Gain strongest bless while not blessed | bless timer/status increases by prayer path | Shared seam + spell-id mapping | Yes | Required: refresh/already-active case | explicit onset text per current behavior; refresh policy must match current build | Timed buff/protection |
| 27 | Dispel Undead | P4 | Dispel / Flagged Target | C64+C128 | Damage/remove visible undead target(s) | eligible visible/LOS undead take damage or die per current implementation | Shared seam + spell-id mapping | Yes | Required: no visible undead targets | damaged targets print `The <monster> shudders.`; killed targets print `The <monster> dissolves!`; no-undead outcome required | Dispel / flagged-target |
| 28 | Heal | P4 | Heal | C64+C128 | Large heal while injured | HP increases by fixed heal path and caps at max | Shared seam + spell-id mapping | Yes | Required: full-HP cast stays no-op | strongest-heal success text when injured; silence at full HP; cast fail explicit | Heal family |
| 29 | Dispel Evil | P4 | Dispel / Flagged Target | C64+C128 | Damage/remove visible evil target(s) | eligible visible/LOS evil targets take damage or die per current implementation | Shared seam + spell-id mapping | Yes | Required: no visible evil targets | damaged targets print `The <monster> shudders.`; killed targets print `The <monster> dissolves!`; no-evil outcome text required | Dispel / flagged-target |
| 30 | Glyph of Warding | P4 | Placement | C64+C128 | Place glyph on eligible tile | glyph record/tile state is created and redraw updates | Shared seam + spell-id mapping | Yes | Required: blocked by object/occupancy | explicit success text; blocked text required | Placement/blocking |
| 31 | Holy Word | P4 | Composite Utility | C64+C128 | Full composite cast with injured, poisoned, afraid player and evil target present | full heal, poison clear, fear clear, stat restore, invulnerability timer set, dispel effect applied | Shared seam + spell-id mapping | Yes | Required: no evil targets and/or already-clean/full state for unaffected subeffects | explicit high-end heal/success text plus any composite message policy must match current build | Heal family + dispel / flagged-target + timed buff/protection |

## Cross-Cutting Verification Rules

### Message validation

- Use exact player-visible strings or stable string IDs/Huffman IDs.
- `Some message happened` is not sufficient.
- Explicit silence is a valid and required assertion for message-light spells.
- Message-light spells must not grow a generic `You cast...` or `You pray...` success banner.
- When a row calls for message-light success or no-effect handling, assert the intended silence on that exact path; do not treat omitted message checks as equivalent coverage.

### C128 proof model

- On `C128`, a row is complete only when both of these exist:
  - a product-path proof that exercises the real cast/pray dispatch on the built runtime
  - a row-level proof for any exact negative, message-light, or bookkeeping contract not already covered by that product path
- Focused C128 row proofs may use a narrow harness around the stable shared seam when the product smoke would otherwise be too coarse.

### Prompt and selection validation

- Directional spells must validate:
  - correct prompt entry
  - valid target direction
  - cancel path
  - no-target or miss path when meaningful
- Item-targeted spells must validate:
  - eligible-item filtering
  - selection by visible filtered key, not absolute slot
  - cancel path
  - no-eligible-item path when meaningful
- Book and spell selection tests must validate the correct affinity/book/spell set for the requested spell.

### RNG policy

- RNG-sensitive spells must use deterministic seeding when asserting exact results.
- If exact results are not stable or not useful, assert invariants instead.
- Spells that require explicit RNG handling include:
  - all heal dice spells
  - all bolt/ball damage spells
  - Phase Door, Portal, Teleport Self, Teleport Other
  - Polymorph Other
  - Earthquake
  - Recharge Item I/II
  - Genocide

### Resource and bookkeeping validation

- Success rows must assert mana/resource consumption and `worked` bookkeeping where the path is expected to update them.
- Failure rows must explicitly state whether mana/resource consumption should or should not occur.
- Product-path tests must not ignore selection and return-path bookkeeping.

### Known deviations

- Current Commodore behavior is the expected contract unless a row explicitly states otherwise.
- Known documented deviations in `commodore/SPELLS.md` must be treated as current expected behavior until deliberately changed:
  - `Resist Heat and Cold` uses the current packed-resist implementation
  - glyph rendering and glyph break behavior use current Commodore rules

### Spell identity, not subclass duplication

- The test unit is spell identity, not subclass.
- Mage/Rogue/Ranger or Priest/Paladin do not need duplicate rows unless class-specific gating or table behavior materially changes the user-visible contract being tested.

### Composite spells

- Composite spells must validate every constituent effect, not a representative subset.
- `Holy Word` specifically requires validation of:
  - full heal
  - poison clear
  - fear clear
  - stat restore
  - invulnerability timer
  - dispel-on-evil effect
  - message contract

## Acceptance Criteria

- The matrix contains all `62` spells/prayers with no omissions.
- Every row names `C64 + C128`.
- Every row defines at least one success scenario and exact success criteria.
- Every row defines message expectations for all applicable outcomes.
- Every row either requires or justifies:
  - gate failure
  - cast failure
  - success-no-effect/blocked coverage
- Every shared harness named by a row is defined earlier in this document.
- No row relies on `covered by similar spell` without a spell-specific parameterized contract.
