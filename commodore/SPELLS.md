# Additional Spells Audit

## Scope

- Commodore now uses the full `31 mage + 31 priest` catalogs instead of the old reduced `16 + 16` model.
- Spell tables, book masks, and subclass access follow `umoria`.
- Spell behavior is VMS-first where the two upstreams differ materially.
- `Legacy` below means the old Commodore baseline spell set (`1-16`).
- `Added` below means spells/prayers restored by this feature (`17-31`).

## Data And Memory

- Player spell state moved from a 2-byte learned-mask model to a full `learned/worked/forgotten/order` model.
- `player_data` grew from `82` bytes to `111` bytes.
- Net new spell-state payload is `45` bytes:
  - `4` bytes learned mask
  - `4` bytes worked mask
  - `4` bytes forgotten mask
  - `1` byte pending new spells
  - `32` bytes spell order
- The struct only grew by `29` bytes because `14` bytes came out of the old reserved tail.
- Save compatibility intentionally changed:
  - C64 `SAVE_VERSION`: `$0c -> $0d`
  - C128 `SAVE_VERSION`: `$0d -> $0e`
- C64 ownership:
  - `UiOverlay`: spell names, list data, selection UI, study/learn UI
  - `DeathOverlay`: spell execution dispatcher and low-frequency effect code
  - resident main RAM keeps the hot cast/pray command flow and only trampolines into overlay-owned selection/execution
- C128 ownership:
  - `UiOverlay`: spell names, list data, selection UI, study/learn UI
  - `DeathOverlay`: spell execution dispatcher and low-frequency effect code
- Glyph support added one small resident table: `MAX_GLYPHS = 4`, stored as `glyph_x`, `glyph_y`, `glyph_active` for `12` bytes total.

## Known Deviations

- `Resist Heat and Cold` currently sets the existing packed resistance flags directly instead of upstream split timers.
- The current tree now uses those flags to reduce the implemented elemental breath-damage path, but broader fire/cold consumers are still not modeled yet.
- `Glyph of Warding` is mechanically active, but there is no special dungeon-tile rendering for glyphs yet.
- Glyph break chance is currently a simplified approximation rather than the exact upstream formula.
- Class tables and book splits intentionally follow `umoria`; effect semantics intentionally prefer VMS when they differ.

## Feedback Audit

- Commodore now follows the locked hybrid upstream rule:
  - no generic `You cast...` / `You pray...` success banner
  - explicit feedback only when the effect would otherwise be silent, misleading, or easy to miss
  - obvious projectile/map/teleport/control results stay message-light
- Mage spells audited for explicit feedback:
  - direct confirmation or failure text: `2 Detect Monsters`, `4 Light Area`, `5 Cure Light Wounds`, `12 Cure Poison`, `14 Remove Curse`, `17 Create Food`, `18 Recharge Item I`, `26 Recharge Item II`, `28 Haste Self`
  - no extra cast banner by design because the outcome is already visible: `1`, `3`, `6-11`, `13`, `15-16`, `19-25`, `27`, `29-31`
- Priest prayers audited for explicit feedback:
  - direct confirmation or failure text: `1 Detect Evil`, `2 Cure Light Wounds`, `3 Bless`, `4 Remove Fear`, `5 Call Light`, `14 Create Food`, `15 Remove Curse`, `16 Resist Heat and Cold`, `17 Neutralize Poison`, `19 Cure Serious Wounds`, `20 Sense Invisible`, `21 Protection from Evil`, `24 Cure Critical Wounds`, `26 Prayer`, `28 Heal`, `31 Holy Word`
  - no extra cast banner by design because the outcome is already visible: `6-13`, `18`, `22-23`, `25`, `27`, `29-30`
- Current Commodore messaging choices after the audit:
  - `Bless`, `Chant`, and `Prayer` now show an explicit onset message when the blessed state starts
  - `Haste Self`, `Protection from Evil`, and `Sense Invisible` keep explicit onset feedback
  - `Resist Heat and Cold` now has explicit onset feedback, but it is still tied to the current packed-flag implementation rather than exact upstream timers
  - `Create Food`, `Glyph of Warding`, and `Recharge` now explain blocked/no-target cases instead of failing silently
  - timed expiry text for bless/haste/protection is still intentionally omitted on Commodore; this remains a documented deviation from richer `umoria` status messaging

## Coverage Audit

- Shared family coverage added during hardening:
  - bolts/projectiles:
    - `Magic Missile` now has a shared runtime regression proving bolt flashes originate from the correct viewport cell and do not end in `HSTR_EB_FIZZLE` on an immediate hit
    - `Magic Missile` now also has row-level coverage on `C64+C128` for explicit cast-fail handling, silent no-target behavior, and mana/worked bookkeeping
  - `Lightning Bolt` now also has row-level coverage on `C64+C128` for spell-id mapping, silent no-target behavior, and cast-fail/success mana/worked bookkeeping
  - `Teleport Self` now also has row-level coverage on `C64+C128` for spell-id mapping, deterministic long-range relocation, and cast-fail/success mana/worked bookkeeping
    - C128 also has a direct unit guard that `screen_flash_set_color` preserves the row register used by `screen_flash_at`
  - balls / area spells:
    - shared `eff_ball` runtime coverage already proves visible ball travel, target-area damage, and lethal kill-path handling
    - `Stinking Cloud` now also has row-level coverage on `C64+C128` for spell-id mapping, message-light empty-area behavior, and cast-fail/success mana/worked bookkeeping
  - heals:
    - shared spell/prayer heal coverage now proves:
      - tiny heals emit `You feel a little better.`
      - modest heals emit `You feel better.`
      - large heals emit `You feel much better.`
      - strongest heals emit `You feel very good.`
      - capped heals stop at max HP
      - full-HP spell/prayer heals stay silent instead of printing a bogus success message
    - `Cure Light Wounds` now also has row-level coverage on `C64+C128` for spell-id mapping, explicit cast-fail handling, injured-vs-full-HP behavior, and mana/worked bookkeeping
    - priest `Cure Light Wounds` now also has row-level coverage on `C64+C128` for prayer-id mapping, explicit cast-fail handling, injured-vs-full-HP behavior, and mana/worked bookkeeping
  - timed buff/protection feedback:
    - dedicated runtime coverage now exists for bless onset/refresh and resist onset/refresh
    - priest `Bless` now also has row-level coverage on `C64+C128` for prayer-id mapping, explicit onset text, silent refresh policy, and cast-fail/success mana/worked bookkeeping
    - priest `Remove Fear` now also has row-level coverage on `C64+C128` for prayer-id mapping, explicit fear-clear text, calm/no-op silence, and cast-fail/success mana/worked bookkeeping
    - priest `Call Light` now also has row-level coverage on `C64+C128` for prayer-id mapping, shared room-light seam dispatch, explicit light feedback, redraw flagging, and cast-fail/success mana/worked bookkeeping
    - priest `Slow Poison` now also has row-level coverage on `C64+C128` for prayer-id mapping, current poison-severity reduction semantics, already-clear silence/no-op behavior, and cast-fail/success mana/worked bookkeeping
    - `Resist Heat and Cold` now also has a direct runtime regression proving it reduces hostile breath damage
  - adjacent monster-control feedback:
    - dedicated runtime coverage now exists for `Sanctuary` no-target feedback and for actually sleeping an adjacent monster
    - `Sleep I` now also has row-level coverage on `C64+C128` for directional single-target sleep mutation, current message-light no-target behavior, and cast-fail/success bookkeeping
    - `Sleep II` now also has row-level coverage on `C64+C128` for adjacent local-sleep success plus explicit success/unaffected/no-target feedback and cast-fail/success bookkeeping
  - directional control:
    - shared directional-confuse runtime coverage now proves hit feedback (`The monster looks confused.`) and miss feedback (`Nothing seems to happen.`)
    - `Confusion` now also has row-level coverage on `C64+C128` for spell-id mapping, confuse-timer mutation, and cast-fail/success mana/worked bookkeeping
    - priest `Blind Creature` now also has row-level coverage on `C64+C128` for prayer-id mapping and the current shared directional-confuse behavior: confuse-timer mutation on hit, current no-target feedback on miss, and cast-fail/success mana/worked bookkeeping
    - `Polymorph Other` now also has row-level coverage on `C64+C128` for silent successful target replacement, preserved occupied-tile invariants, silent no-target behavior, and cast-fail/success bookkeeping
  - detect/reveal feedback:
    - dedicated runtime coverage now exists for `Detect Monsters` result/no-result behavior
    - dedicated runtime coverage now exists for `Detect Evil` result/no-result behavior
    - `Detect Evil` now also has row-level coverage on `C64+C128` for prayer-id mapping, instant evil-only current-panel reveal semantics, explicit evil-present/no-evil feedback, and cast-fail/success mana/worked bookkeeping
    - priest `Find Traps` now also has row-level coverage on `C64+C128` for prayer-id mapping, tracked hidden-trap reveal, current silent no-eligible-trap behavior, redraw flagging, and cast-fail/success mana/worked bookkeeping
    - priest `Detect Doors/Stairs` now also has row-level coverage on `C64+C128` for prayer-id mapping, secret-door plus tracked-stairs reveal under current restored rules, current silent no-eligible-target behavior, redraw flagging, and cast-fail/success mana/worked bookkeeping
    - `Find Hidden Traps/Doors` now also has row-level coverage on `C64+C128` for combined secret-door plus hidden-trap reveal, message-light no-effect behavior, and cast-fail/success bookkeeping
    - `Trap/Door Destruction` now also has row-level coverage on `C64+C128` for adjacent closed/secret door opening, adjacent trap-table removal, message-light no-effect behavior when only out-of-area fixtures remain, and cast-fail/success bookkeeping
  - area / utility / high-end priest effects:
    - dedicated runtime coverage now exists for `Sense Surroundings` map reveal behavior
    - dedicated runtime coverage now exists for `Glyph of Warding` success and blocked-by-object behavior
    - dedicated runtime coverage now exists for `Holy Word` heal/cleanse/dispel behavior
- Current focused runtime suites:
  - `commodore/c64/tests/test_effects.s`
    - shared bolt/projectile regression coverage
    - shared spell/prayer heal-family coverage
    - shared light-room mutation and redraw coverage
  - `commodore/c64/tests/test_effects_magic.s`
    - `Magic Missile` cast-fail bookkeeping
    - shared spell/prayer command bookkeeping
  - `commodore/c64/tests/test_light_area.s`
    - `Light Area` explicit light feedback
    - `Light Area` cast success/fail mana/worked bookkeeping
  - `commodore/c64/tests/test_call_light_prayer.s`
    - priest `Call Light` prayer-id mapping and shared room-light seam dispatch
    - priest `Call Light` explicit light feedback, redraw flagging, and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_find_traps_prayer.s`
    - priest `Find Traps` prayer-id mapping and shared trap-reveal dispatch
    - priest `Find Traps` hidden-trap reveal, silent no-eligible-trap behavior, and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_detect_doors_stairs_prayer.s`
    - priest `Detect Doors/Stairs` prayer-id mapping and shared door/stair reveal dispatch
    - priest `Detect Doors/Stairs` secret-door and stair reveal, silent no-eligible-target behavior, and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_slow_poison_prayer.s`
    - priest `Slow Poison` prayer-id mapping and current poison-severity reduction
    - priest `Slow Poison` already-clear silence/no-op and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_blind_creature_prayer.s`
    - priest `Blind Creature` prayer-id mapping and current shared directional-confuse hit behavior
    - priest `Blind Creature` current no-target feedback and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_cure_light_wounds.s`
    - `Cure Light Wounds` injured heal feedback
    - `Cure Light Wounds` full-HP silence and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_find_hidden_traps_doors.s`
    - `Find Hidden Traps/Doors` combined door/trap reveal behavior
    - `Find Hidden Traps/Doors` no-effect silence and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_stinking_cloud.s`
    - `Stinking Cloud` spell-id mapping and target-area kill behavior
    - `Stinking Cloud` empty-area silence and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_frost_ball.s`
    - `Frost Ball` spell-id mapping and target-area kill behavior
    - `Frost Ball` empty-area silence and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_fire_ball.s`
    - `Fire Ball` spell-id mapping and target-area kill behavior
    - `Fire Ball` empty-area silence and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_word_of_destruction.s`
    - `Word of Destruction` spell-id mapping plus deterministic adjacent kill and nearby terrain mutation
    - `Word of Destruction` redraw updates and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_genocide.s`
    - `Genocide` spell-id mapping, current glyph-prompt feedback, and removal of all matching monsters while leaving nonmatches alive
    - `Genocide` cast-fail preservation and mana/worked bookkeeping
  - `commodore/c64/tests/test_confusion.s`
    - `Confusion` spell-id mapping and directional confuse-hit behavior
    - `Confusion` no-target feedback and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_lightning_bolt.s`
    - `Lightning Bolt` spell-id mapping and directional bolt kill-path behavior
    - `Lightning Bolt` silent no-target behavior and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_frost_bolt.s`
    - `Frost Bolt` spell-id mapping and directional bolt kill-path behavior
    - `Frost Bolt` silent no-target behavior and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_turn_stone_to_mud.s`
    - `Turn Stone to Mud` spell-id mapping and directional wall-to-floor mutation behavior
    - `Turn Stone to Mud` silent blocked/no-effect behavior and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_create_food.s`
    - `Create Food` spell-id mapping and underfoot placement/replacement behavior
    - `Create Food` explicit blocked message and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_recharge_item_i.s`
    - `Recharge Item I` spell-id mapping and eligible-item recharge behavior
    - `Recharge Item I` no-eligible-item text, destructive backfire path, and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_recharge_item_ii.s`
    - `Recharge Item II` spell-id mapping and stronger eligible-item recharge behavior
    - `Recharge Item II` no-eligible-item text, destructive backfire path, and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_trap_door_destruction.s`
    - `Trap/Door Destruction` spell-id mapping and adjacent trap/door mutation behavior
    - `Trap/Door Destruction` silent no-effect behavior and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_sleep_i.s`
    - `Sleep I` spell-id mapping and directional single-target sleep mutation
    - `Sleep I` message-light no-target behavior and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_sleep_ii.s`
    - `Sleep II` spell-id mapping and adjacent local-sleep behavior
    - `Sleep II` explicit success/unaffected/no-target feedback and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_sleep_iii.s`
    - `Sleep III` spell-id mapping and visible-monster sleep-all behavior
    - `Sleep III` explicit success/no-target feedback and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_fire_bolt.s`
    - `Fire Bolt` spell-id mapping and directional bolt kill-path behavior
    - `Fire Bolt` silent no-target behavior and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_slow_monster.s`
    - `Slow Monster` spell-id mapping and directional slow-state mutation behavior
    - `Slow Monster` current success/no-target behavior and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_polymorph_other.s`
    - `Polymorph Other` spell-id mapping and deterministic target replacement behavior
    - `Polymorph Other` silent no-target behavior and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_identify_spell.s`
    - `Identify` spell-id mapping and exact built identify-message behavior
    - `Identify` cancel/no-eligible-item paths and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_teleport_self.s`
    - `Teleport Self` spell-id mapping and long-range relocation behavior
    - `Teleport Self` cast-fail/success bookkeeping
  - `commodore/c64/tests/test_teleport_other.s`
    - `Teleport Other` spell-id mapping and deterministic target relocation behavior
    - `Teleport Other` silent no-target behavior and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_haste_self.s`
    - `Haste Self` spell-id mapping and deterministic speed-timer onset/refresh behavior
    - `Haste Self` explicit speed message and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_phase_door.s`
    - `Phase Door` validated-near-target teleport behavior
    - `Phase Door` cast-fail and success bookkeeping
  - `commodore/c64/tests/test_directional_effects.s`
    - `Magic Missile` no-target stays silent
  - `commodore/c128/tests/test_magic_missile128.s`
    - `Magic Missile` silent no-target path
    - `Magic Missile` cast-fail bookkeeping
    - `Magic Missile` success bookkeeping
  - `commodore/c64/tests/test_utility_effects.s`
    - `Sense Surroundings`
    - `Glyph of Warding`
    - `Holy Word`
  - `commodore/c64/tests/test_prayer_feedback.s`
    - `Chant`
    - `Sanctuary`
    - `Resist Heat and Cold`
  - `commodore/c64/tests/test_detect_feedback.s`
    - `Detect Monsters`
    - `Detect Evil`
  - `commodore/c64/tests/test_detect_evil.s`
    - `Detect Evil` prayer-id mapping, detect-state semantics, and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_detect_monsters128.s`
    - `Detect Monsters` result/no-result feedback
    - `Detect Monsters` spell-id mapping and cast-fail bookkeeping
  - `commodore/c128/tests/test_detect_evil128.s`
    - `Detect Evil` prayer-id mapping, detect-state semantics, and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_cure_light_wounds128.s`
    - `Cure Light Wounds` injured heal feedback
    - `Cure Light Wounds` spell-id mapping and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_cure_light_wounds_prayer.s`
    - priest `Cure Light Wounds` injured heal feedback
    - priest `Cure Light Wounds` prayer-id mapping and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_cure_light_wounds_prayer128.s`
    - priest `Cure Light Wounds` injured heal feedback
    - priest `Cure Light Wounds` prayer-id mapping and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_bless_prayer.s`
    - priest `Bless` onset/refresh behavior
    - priest `Bless` prayer-id mapping and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_bless_prayer128.s`
    - priest `Bless` onset/refresh behavior
    - priest `Bless` prayer-id mapping and cast-fail/success bookkeeping
  - `commodore/c64/tests/test_remove_fear_prayer.s`
    - priest `Remove Fear` fear-clear vs calm/no-op behavior
    - priest `Remove Fear` prayer-id mapping and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_remove_fear_prayer128.s`
    - priest `Remove Fear` fear-clear vs calm/no-op behavior
    - priest `Remove Fear` prayer-id mapping and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_find_hidden_traps_doors128.s`
    - `Find Hidden Traps/Doors` combined door/trap reveal behavior
    - `Find Hidden Traps/Doors` spell-id mapping and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_stinking_cloud128.s`
    - `Stinking Cloud` spell-id mapping and target-area kill behavior
    - `Stinking Cloud` empty-area silence and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_frost_ball128.s`
    - `Frost Ball` spell-id mapping and target-area kill behavior
    - `Frost Ball` empty-area silence and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_fire_ball128.s`
    - `Fire Ball` spell-id mapping and target-area kill behavior
    - `Fire Ball` empty-area silence and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_word_of_destruction128.s`
    - `Word of Destruction` spell-id mapping plus deterministic adjacent kill and nearby terrain mutation
    - `Word of Destruction` redraw updates and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_genocide128.s`
    - `Genocide` spell-id mapping, current glyph-prompt feedback, and removal of all matching monsters while leaving nonmatches alive
    - `Genocide` cast-fail preservation and mana/worked bookkeeping
  - `commodore/c128/tests/test_confusion128.s`
    - `Confusion` spell-id mapping and directional confuse-hit behavior
    - `Confusion` no-target feedback and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_lightning_bolt128.s`
    - `Lightning Bolt` spell-id mapping and directional bolt kill-path behavior
    - `Lightning Bolt` silent no-target behavior and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_frost_bolt128.s`
    - `Frost Bolt` spell-id mapping and directional bolt kill-path behavior
    - `Frost Bolt` silent no-target behavior and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_turn_stone_to_mud128.s`
    - `Turn Stone to Mud` spell-id mapping and directional wall-to-floor mutation behavior
    - `Turn Stone to Mud` silent blocked/no-effect behavior and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_create_food128.s`
    - `Create Food` spell-id mapping and underfoot placement/replacement behavior
    - `Create Food` explicit blocked message and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_recharge_item_i128.s`
    - `Recharge Item I` spell-id mapping and eligible-item recharge behavior
    - `Recharge Item I` no-eligible-item text, destructive backfire path, and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_recharge_item_ii128.s`
    - `Recharge Item II` spell-id mapping and stronger eligible-item recharge behavior
    - `Recharge Item II` no-eligible-item text, destructive backfire path, and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_trap_door_destruction128.s`
    - `Trap/Door Destruction` spell-id mapping and adjacent trap/door mutation behavior
    - `Trap/Door Destruction` silent no-effect behavior and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_sleep_i128.s`
    - `Sleep I` spell-id mapping and directional single-target sleep mutation
    - `Sleep I` message-light no-target behavior and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_sleep_ii128.s`
    - `Sleep II` spell-id mapping and adjacent local-sleep behavior
    - `Sleep II` explicit success/unaffected/no-target feedback and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_sleep_iii128.s`
    - `Sleep III` spell-id mapping and visible-monster sleep-all behavior
    - `Sleep III` explicit success/no-target feedback and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_fire_bolt128.s`
    - `Fire Bolt` spell-id mapping and directional bolt kill-path behavior
    - `Fire Bolt` silent no-target behavior and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_slow_monster128.s`
    - `Slow Monster` spell-id mapping and directional slow-state mutation behavior
    - `Slow Monster` current success/no-target behavior and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_polymorph_other128.s`
    - `Polymorph Other` spell-id mapping and deterministic target replacement behavior
    - `Polymorph Other` silent no-target behavior and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_identify128.s`
    - `Identify` spell-id mapping and exact built identify-message behavior
    - `Identify` cancel/no-eligible-item paths and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_teleport_self128.s`
    - `Teleport Self` spell-id mapping and long-range relocation behavior
    - `Teleport Self` cast-fail/success bookkeeping
  - `commodore/c128/tests/test_teleport_other128.s`
    - `Teleport Other` spell-id mapping and deterministic target relocation behavior
    - `Teleport Other` silent no-target behavior and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_haste_self128.s`
    - `Haste Self` spell-id mapping and deterministic speed-timer onset/refresh behavior
    - `Haste Self` explicit speed message and cast-fail/success bookkeeping
  - `commodore/c128/tests/test_phase_door128.s`
    - `Phase Door` validated-near-target teleport behavior
    - `Phase Door` spell-id mapping and cast-fail/success bookkeeping
- Coverage still shallow or missing for:
  - higher-end priest book 3/4 dispel and utility prayers
  - area-effect spell families beyond the existing shared smokes and utility representatives above

## Book Layout

- Mage `M1 [Beginners-Magick]`: `1-7`
- Mage `M2 [Magick I]`: `8-16`
- Mage `M3 [Magick II]`: `17-24`
- Mage `M4 [The Mages' Guide to Power]`: `25-31`
- Priest `P1 [Beginners Handbook]`: `1-8`
- Priest `P2 [Words of Wisdom]`: `9-16`
- Priest `P3 [Chants and Blessings]`: `17-25`
- Priest `P4 [Exorcisms and Dispellings]`: `26-31`

## Mage-Affinity Catalog

`Mage`, `Rogue`, and `Ranger` use the mage-affinity catalog. Table values are `level/mana/fail`; `--` means that class cannot learn the spell.

| # | Status | Book | Spell | Mage | Rogue | Ranger | Effect | Notes |
|---|---|---|---|---|---|---|---|---|
| 1 | Legacy | M1 | Magic Missile | 1/1/22 | -- | 3/1/30 | Directional magic bolt `2d6` | Row-covered on `C64+C128`: product success, cast fail, silent no-target, mana/worked bookkeeping |
| 2 | Legacy | M1 | Detect Monsters | 1/1/23 | 5/1/50 | 3/2/35 | Monster detection | Row-covered on `C64+C128`: generic live cast flow stays green, focused row coverage proves detect-present/no-creatures feedback plus cast-fail mana/worked bookkeeping |
| 3 | Legacy | M1 | Phase Door | 1/2/24 | 7/2/55 | 3/2/35 | Short self-teleport | Row-covered on `C64+C128`: fixed validated-near-target teleport seam, focused row coverage proves near-range relocation, occupancy/visibility updates, explicit cast fail, and message-light success bookkeeping |
| 4 | Legacy | M1 | Light Area | 1/2/26 | 9/3/60 | 5/3/35 | Lights room/corridor | Row-covered on `C64+C128`: focused C64 coverage proves room light mutation, redraw flag, explicit light feedback, and cast success/fail mana/worked bookkeeping; generic C128 spell-cast smoke remains green as the product-path proof for the shared dispatch |
| 5 | Legacy | M1 | Cure Light Wounds | 3/3/25 | 11/4/65 | 5/3/40 | Heal `4d4` | Row-covered on `C64+C128`: focused heal-row coverage proves spell-id mapping, injured heal feedback, full-HP silence/no-op, and cast-fail/success mana/worked bookkeeping |
| 6 | Legacy | M1 | Find Hidden Traps/Doors | 3/3/25 | 13/5/70 | 5/4/45 | Detect traps and doors | Row-covered on `C64+C128`: focused coverage proves combined secret-door plus hidden-trap reveal, message-light no-effect behavior, and cast-fail/success mana/worked bookkeeping |
| 7 | Legacy | M1 | Stinking Cloud | 3/3/27 | -- | 7/5/40 | Poison-gas ball `9` | Row-covered on `C64+C128`: shared ball-family coverage proves travel/damage/kill behavior, and focused row coverage proves spell-id mapping, empty-area silence, and cast-fail/success mana/worked bookkeeping |
| 8 | Legacy | M2 | Confusion | 3/4/30 | 15/6/75 | 7/6/40 | Directional confusion | Row-covered on `C64+C128`: shared directional-confuse coverage proves hit/miss feedback, and focused row coverage proves spell-id mapping, confuse-timer mutation, and cast-fail/success mana/worked bookkeeping |
| 9 | Legacy | M2 | Lightning Bolt | 5/4/30 | -- | 9/7/40 | Directional lightning bolt `3d8` | Row-covered on `C64+C128`: shared bolt coverage proves the projectile hit/miss contract, and focused row coverage proves spell-id mapping, silent no-target behavior, and cast-fail/success mana/worked bookkeeping |
| 10 | Legacy | M2 | Trap/Door Destruction | 5/5/30 | 17/7/80 | 9/8/45 | Destroy traps and doors | Row-covered on `C64+C128`: focused coverage proves adjacent secret/closed door opening, adjacent trap removal from map+table, message-light no-effect when only out-of-area fixtures remain, and cast-fail/success mana/worked bookkeeping |
| 11 | Legacy | M2 | Sleep I | 5/5/30 | 19/8/85 | 11/8/40 | Put one monster to sleep | Row-covered on `C64+C128`: focused coverage proves directional single-target sleep mutation, current message-light no-target behavior, and cast-fail/success mana/worked bookkeeping |
| 12 | Legacy | M2 | Cure Poison | 5/5/35 | 21/9/90 | 11/9/45 | Clear poison | - |
| 13 | Legacy | M2 | Teleport Self | 7/6/35 | -- | 13/10/45 | Long self-teleport | Row-covered on `C64+C128`: focused coverage proves deterministic long-range relocation, occupancy/visibility updates, message-light success, and cast-fail/success mana/worked bookkeeping |
| 14 | Legacy | M2 | Remove Curse | 7/6/50 | 23/10/95 | 13/11/55 | Remove curse from equipped items | Row-covered on `C64+C128`: focused coverage proves equipped-only curse removal, carried curse preservation, current explicit `CLEANSED` feedback even with no cursed equipment, and cast-fail/success mana/worked bookkeeping; priest version remains broader |
| 15 | Legacy | M2 | Frost Bolt | 7/6/40 | -- | 15/12/50 | Directional frost bolt `4d8` | Row-covered on `C64+C128`: shared bolt coverage proves the projectile hit/miss contract, and focused row coverage proves spell-id mapping, silent no-target behavior, and cast-fail/success mana/worked bookkeeping |
| 16 | Legacy | M2 | Turn Stone to Mud | 9/7/44 | -- | 15/13/50 | Convert wall to mud | Row-covered on `C64+C128`: focused coverage proves directional wall-to-floor mutation with room redraw/update flagging, current silent blocked/no-effect behavior on non-wall targets, and cast-fail/success mana/worked bookkeeping |
| 17 | Added | M3 | Create Food | 9/7/45 | 25/12/95 | 17/17/55 | Create food on player tile | Row-covered on `C64+C128`: focused coverage proves underfoot item replacement on success, current blocked semantics when no floor-item slot is free, explicit success/blocked feedback, and cast-fail/success mana/worked bookkeeping |
| 18 | Added | M3 | Recharge Item I | 9/7/75 | 27/15/99 | 17/17/90 | Recharge wand/staff, with break risk | Row-covered on `C64+C128`: focused coverage proves eligible-item recharge mutation, explicit no-eligible-item feedback, destructive bright-flash backfire behavior, and cast-fail/success mana/worked bookkeeping |
| 19 | Added | M3 | Sleep II | 9/7/45 | -- | 21/17/55 | Sleep adjacent monsters | Row-covered on `C64+C128`: focused coverage proves adjacent local-sleep success, explicit success/unaffected/no-target feedback, and cast-fail/success mana/worked bookkeeping |
| 20 | Added | M3 | Polymorph Other | 11/7/45 | -- | 21/19/60 | Replace target monster with another | Row-covered on `C64+C128`: focused coverage proves silent successful target replacement at the same coordinates with occupied-tile invariants preserved, silent no-target behavior, and cast-fail/success mana/worked bookkeeping |
| 21 | Added | M3 | Identify | 11/7/99 | 29/18/99 | 23/25/95 | Item identify prompt | Row-covered on `C64+C128`: focused coverage proves eligible-item identification with the exact built identify message, current cancel/no-eligible-item feedback behavior, and cast-fail/success mana/worked bookkeeping |
| 22 | Added | M3 | Sleep III | 13/7/50 | -- | 23/20/60 | Sleep all visible monsters | Row-covered on `C64+C128`: focused coverage proves visible monsters sleep while hidden monsters remain unaffected, current explicit success/no-target feedback, and cast-fail/success mana/worked bookkeeping |
| 23 | Added | M3 | Fire Bolt | 15/9/50 | -- | 25/20/60 | Directional fire bolt `6d8` | Row-covered on `C64+C128`: shared bolt coverage proves the projectile hit/miss contract, and focused row coverage proves spell-id mapping, silent no-target behavior, and cast-fail/success mana/worked bookkeeping |
| 24 | Added | M3 | Slow Monster | 17/9/50 | -- | 25/21/65 | Slow target monster | Row-covered on `C64+C128`: focused coverage proves directional slow-state mutation with sleep cleared, current success/no-target behavior, and cast-fail/success mana/worked bookkeeping |
| 25 | Added | M4 | Frost Ball | 19/12/55 | -- | 27/21/65 | Frost ball `33` | Row-covered on `C64+C128`: shared ball coverage proves visible travel, area damage, and kill-path handling, and focused row coverage proves spell-id mapping, empty-area silence, and cast-fail/success mana/worked bookkeeping |
| 26 | Added | M4 | Recharge Item II | 21/12/90 | -- | 29/23/95 | Stronger recharge with break risk | Row-covered on `C64+C128`: focused coverage proves stronger eligible-item recharge mutation, explicit no-eligible-item feedback, destructive bright-flash backfire behavior, and cast-fail/success mana/worked bookkeeping |
| 27 | Added | M4 | Teleport Other | 23/12/60 | -- | 31/25/70 | Teleport target monster away | Row-covered on `C64+C128`: focused coverage proves deterministic target relocation with occupied-tile invariants preserved, sleep cleared on the moved monster, silent no-target behavior, and cast-fail/success mana/worked bookkeeping |
| 28 | Added | M4 | Haste Self | 25/12/65 | -- | 33/25/75 | Temporary self-speed boost | Row-covered on `C64+C128`: focused coverage proves deterministic speed-timer onset and refresh growth, explicit speed-onset feedback on both paths, and cast-fail/success mana/worked bookkeeping |
| 29 | Added | M4 | Fire Ball | 29/18/65 | -- | 35/25/80 | Fire ball `49` | Row-covered on `C64+C128`: shared ball coverage proves visible travel, area damage, and kill-path handling, and focused row coverage proves spell-id mapping, empty-area silence, and cast-fail/success mana/worked bookkeeping |
| 30 | Added | M4 | Word of Destruction | 33/21/80 | -- | 37/30/95 | Destroy surrounding area | Row-covered on `C64+C128`: focused coverage proves deterministic adjacent kill plus nearby secret-door/trap mutation, redraw updates, and cast-fail/success mana/worked bookkeeping |
| 31 | Added | M4 | Genocide | 37/25/95 | -- | -- | Remove one creature type | Row-covered on `C64+C128`: focused coverage proves current glyph-prompt genocide removes all matching monsters while leaving nonmatches alive, has no extra no-match text, and preserves cast-fail/success mana/worked bookkeeping |

## Priest-Affinity Catalog

`Priest` and `Paladin` use the priest-affinity catalog. Table values are `level/mana/fail`.

| # | Status | Book | Prayer | Priest | Paladin | Effect | Notes |
|---|---|---|---|---|---|---|---|
| 1 | Legacy | P1 | Detect Evil | 1/1/10 | 1/1/30 | Detect hostile/evil creatures | Row-covered on `C64+C128`: focused coverage proves prayer-id mapping, instant evil-only current-panel reveal with no detect timer, explicit evil-present/no-evil feedback, and cast-fail/success mana/worked bookkeeping |
| 2 | Legacy | P1 | Cure Light Wounds | 1/2/15 | 2/2/35 | Heal `3d3` | Row-covered on `C64+C128`: focused heal-row coverage proves prayer-id mapping, injured heal feedback, full-HP silence/no-op, and cast-fail/success mana/worked bookkeeping |
| 3 | Legacy | P1 | Bless | 1/2/20 | 3/3/35 | Bless timer `12-23 + current` | Row-covered on `C64+C128`: focused timed-buff coverage proves prayer-id mapping, explicit onset text, silent refresh behavior, and cast-fail/success mana/worked bookkeeping |
| 4 | Legacy | P1 | Remove Fear | 1/2/25 | 5/3/35 | Clear fear | Row-covered on `C64+C128`: focused cleanse-row coverage proves prayer-id mapping, explicit fear-clear text, calm/no-op silence, and cast-fail/success mana/worked bookkeeping |
| 5 | Legacy | P1 | Call Light | 3/2/25 | 5/4/35 | Lights room/corridor | Row-covered on `C64+C128`: focused light-row coverage proves prayer-id mapping, shared room-light seam dispatch, explicit light feedback, redraw flagging, and cast-fail/success mana/worked bookkeeping |
| 6 | Legacy | P1 | Find Traps | 3/3/27 | 7/5/40 | Detect traps | Row-covered on `C64+C128`: focused detect-row coverage proves prayer-id mapping, tracked hidden-trap reveal, current silent no-eligible-trap behavior, redraw flagging, and cast-fail/success mana/worked bookkeeping |
| 7 | Legacy | P1 | Detect Doors/Stairs | 3/3/27 | 7/5/40 | Detect doors and stairs | Row-covered on `C64+C128`: focused detect-row coverage proves prayer-id mapping, secret-door plus tracked-stairs reveal under the restored rules, current silent no-eligible-target behavior, redraw flagging, and cast-fail/success mana/worked bookkeeping |
| 8 | Legacy | P1 | Slow Poison | 3/3/28 | 9/7/40 | Reduce poison severity | Row-covered on `C64+C128`: focused cleanse-row coverage proves prayer-id mapping, current poison-severity reduction semantics, already-clear silence/no-op behavior, and cast-fail/success mana/worked bookkeeping |
| 9 | Legacy | P2 | Blind Creature | 5/4/29 | 9/7/40 | Directional blind/stun effect | Row-covered on `C64+C128`: focused control-row coverage proves prayer-id mapping and the current shared directional-confuse behavior, with confuse-timer mutation on hit, current no-target feedback on miss, and cast-fail/success mana/worked bookkeeping |
| 10 | Legacy | P2 | Portal | 5/4/30 | 9/8/40 | Self-teleport | Row-covered on `C64+C128`: focused coverage proves prayer-id mapping, deterministic long-range relocation, occupied-tile invariants, message-light success, and cast-fail/success mana/worked bookkeeping |
| 11 | Legacy | P2 | Cure Medium Wounds | 5/4/32 | 11/9/40 | Heal `4d4` | Row-covered on `C64+C128`: focused heal-row coverage proves prayer-id mapping, current `4d4` heal-tier behavior, injured heal feedback, full-HP silence/no-op, and cast-fail/success mana/worked bookkeeping |
| 12 | Legacy | P2 | Chant | 5/5/34 | 11/10/45 | Bless timer `24-47 + current` | Row-covered on `C64+C128`: focused timed-buff coverage proves prayer-id mapping, explicit onset text, silent refresh behavior, stronger bless-timer growth, and cast-fail/success mana/worked bookkeeping |
| 13 | Legacy | P2 | Sanctuary | 7/5/36 | 11/10/45 | Sleep adjacent monsters | Row-covered on `C64+C128`: focused local-sleep coverage proves prayer-id mapping, adjacent sleep success, explicit unaffected/no-target feedback, and cast-fail/success mana/worked bookkeeping; uses the current VMS-style local sanctuary |
| 14 | Legacy | P2 | Create Food | 7/5/38 | 13/10/45 | Create food on player tile | Row-covered on `C64+C128`: focused placement coverage proves prayer-id mapping, underfoot item replacement on success, current blocked semantics when no floor-item slot is free, explicit success/blocked feedback, and cast-fail/success mana/worked bookkeeping |
| 15 | Legacy | P2 | Remove Curse | 7/6/38 | 13/11/45 | Remove curses from carried and equipped items | Row-covered on `C64+C128`: focused coverage proves the stronger priest all-items curse clear across carried and equipped slots, current explicit `CLEANSED` feedback even when nothing is cursed, and cast-fail/success mana/worked bookkeeping; broader than mage version |
| 16 | Legacy | P2 | Resist Heat and Cold | 7/7/38 | 15/13/45 | Reduce implemented elemental breath damage via packed resist flags | Row-covered on `C64+C128`: focused `C128` coverage plus stable shared `C64` seam coverage prove prayer-id mapping, current packed resist-timer onset/refresh behavior, hostile breath reduction under current Commodore semantics, and cast-fail/success mana/worked bookkeeping; still uses the packed-flag shortcut, not timed upstream duration |
| 17 | Added | P3 | Neutralize Poison | 9/6/38 | 15/15/50 | Clear poison | - |
| 18 | Added | P3 | Orb of Draining | 9/7/38 | 17/15/50 | Holy ball damage `3d6 + level` | Row-covered on `C64+C128`: focused prayer-path coverage proves prayer-id mapping, shared ball-path kill behavior on target-area hits, current message-light empty-area success, and cast-fail/success mana/worked bookkeeping |
| 19 | Added | P3 | Cure Serious Wounds | 9/7/40 | 17/15/50 | Heal `8d4` | Row-covered on `C64+C128`: focused prayer-path coverage proves prayer-id mapping, current `8d4` heal-tier behavior through the shared `ped_s18 -> heal_dice -> pmx_heal_and_report` seam, injured-heal mid-tier feedback, full-HP silence/no-op behavior, and cast-fail/success mana/worked bookkeeping |
| 20 | Added | P3 | Sense Invisible | 11/8/42 | 19/15/50 | See invisible / invis sense | Row-covered on `C64+C128`: focused prayer-path coverage proves prayer-id mapping, onset behavior that sets both `zp_eff_see_inv` and `zp_eff_invis` with explicit `HSTR_PIQ_EYES_TINGLE` feedback, current silent refresh behavior when either effect is already active, and cast-fail/success mana/worked bookkeeping |
| 21 | Added | P3 | Protection from Evil | 11/8/42 | 19/15/50 | Protection timer `25-49 + current` | Row-covered on `C64+C128`: focused prayer-path coverage proves prayer-id mapping, onset behavior that sets the protection timer and prints explicit `HSTR_PIQ_PROTECTED` feedback, current silent refresh behavior that adds onto the existing timer, and cast-fail/success mana/worked bookkeeping |
| 22 | Added | P3 | Earthquake | 11/9/55 | 21/17/50 | Local earthquake | Row-covered on `C64+C128`: focused prayer-path coverage proves prayer-id mapping, explicit `eq_cast_msg` feedback, current low-impact inert-area behavior, and cast-fail/success mana/worked bookkeeping; shared terrain-mutation/redraw behavior remains covered by the stable Earthquake seam tests |
| 23 | Added | P3 | Sense Surroundings | 13/10/45 | 23/17/50 | Map surrounding area | Row-covered on `C64+C128`: focused prayer-path coverage proves prayer-id mapping, current message-light success, hidden-feature preservation and inert-area no-op behavior under the current map rules, and cast-fail/success mana/worked bookkeeping; the broader stable map-area reveal contract continues to live in the shared seam tests |
| 24 | Added | P3 | Cure Critical Wounds | 13/11/45 | 25/20/50 | Heal `16d4` | Row-covered on `C64+C128`: focused heal-row coverage proves prayer-id mapping, current `16d4` heal-tier behavior through the shared `ped_s23 -> heal_dice -> pmx_heal_and_report` seam, injured-heal high-tier feedback, full-HP silence/no-op behavior, and cast-fail/success mana/worked bookkeeping |
| 25 | Added | P3 | Turn Undead | 15/12/50 | 27/21/50 | Turn undead in sight | Row-covered on `C64+C128`: focused prayer-path coverage proves prayer-id mapping, the current silent `eff_turn_undead` control semantics across all active undead (`MX_CONFUSE = player level`, `MX_SLEEP_CUR = 0`), silent no-undead behavior, and cast-fail/success mana/worked bookkeeping |
| 26 | Added | P4 | Prayer | 15/14/50 | 29/22/50 | Bless timer `48-95 + current` | Row-covered on `C64+C128`: focused timed-buff coverage proves prayer-id mapping, explicit onset text, silent refresh behavior, stronger bless-timer growth through the shipped `ped_s25 -> pmx_add_bless_msg` seam, and cast-fail/success mana/worked bookkeeping |
| 27 | Added | P4 | Dispel Undead | 17/14/55 | 31/24/60 | Dispel undead for `3 * level` | Row-covered on `C64+C128`: focused flagged-dispel coverage proves prayer-id mapping, the shared `ped_s26 -> eff_dispel_flagged` semantics across visible/LOS `CF_UNDEAD` targets for `rng(3*level)+1` damage, per-target `shudders.` / `dissolves!` feedback, explicit `HSTR_PIQ_NOTHING` on no visible undead casts, and cast-fail/success mana/worked bookkeeping |
| 28 | Added | P4 | Heal | 21/16/60 | 33/28/60 | Heal `200` HP | Row-covered on `C64+C128`: focused heal-row coverage proves prayer-id mapping, the current fixed `200`-HP `ped_s27 -> pmx_heal_and_report` behavior, strongest-heal feedback while injured, full-HP silence/no-op behavior, and cast-fail/success mana/worked bookkeeping |
| 29 | Added | P4 | Dispel Evil | 25/20/70 | 35/32/70 | Dispel evil for `3 * level` | Row-covered on `C64+C128`: focused flagged-dispel coverage proves prayer-id mapping, the shared `ped_s28 -> eff_dispel_flagged` semantics across visible/LOS `CF_EVIL` targets for `rng(3*level)+1` damage, per-target `shudders.` / `dissolves!` feedback, explicit `HSTR_PIQ_NOTHING` on no visible evil casts, and cast-fail/success mana/worked bookkeeping |
| 30 | Added | P4 | Glyph of Warding | 33/24/90 | 37/36/90 | Place a blocking glyph on the player tile | Row-covered on `C64+C128`: focused prayer-path coverage proves prayer-id mapping and cast-fail/success mana/worked bookkeeping on both platforms; `C128` focused row proof also proves success creates a glyph record with explicit `HSTR_PMU_GLYPH_OK` feedback, blocked-by-item casts print `HSTR_PMU_GLYPH_BLOCK`, and `vis_room_revealed` is set on success, while the `C64` shared glyph-placement/blocking seam remains covered in `test_utility_effects` (no special dungeon-tile render yet) |
| 31 | Added | P4 | Holy Word | 39/32/80 | 39/38/90 | Heal to full, remove fear/poison, restore stats, 3 turns invulnerability, dispel evil for `4 * level` | Row-covered on `C64+C128`: focused prayer-path coverage proves prayer-id mapping, full heal, poison clear, fear clear, stat restore, invulnerability timer onset, visible/LOS evil-target dispel behavior with per-target feedback, the current explicit `HSTR_PIQ_VERY_GOOD` message contract, and cast-fail/success mana/worked bookkeeping; the `C64` shared composite seam remains covered in `test_utility_effects`, while `C128` focused row proof also proves the current no-visible-evil/already-clean-full success behavior |

## Upstream Comparison Notes

- `umoria` is the source of truth for:
  - the full 31-entry class spell tables
  - subclass access (`rogue`, `ranger`, `paladin`)
  - per-book spell masks instead of fixed `4 spells/book`
  - the richer learned/worked/forgotten/order state model
- VMS is the source of truth for the main semantic choices:
  - `Sleep II` and `Sanctuary` are local sleep effects, not the broader alternatives found in some later ports
  - priest `Remove Curse` is treated as the stronger all-items version
- `umoria` is now the source of truth for `Holy Word`:
  - full heal
  - remove fear and poison
  - restore all stats
  - grant 3 turns of invulnerability
  - dispel evil for `4 * level`
- Remaining follow-up candidates if stricter parity is required:
  - exact evil-only detection for `Detect Evil`
  - exact timed handling for `Resist Heat and Cold`
  - exact glyph-render and glyph-break formulas
