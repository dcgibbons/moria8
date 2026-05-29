# Combat Accuracy Audit

Status: source-backed audit plus repair notes for the combat-parity fixes in
this branch.

Primary oracle: a local Umoria source checkout. A local VMS Moria source
checkout was also used as lineage evidence, but this audit treats Umoria as the
active behavior oracle because Moria8 comments and data-table ports already
cite Umoria.

Verdicts:

- `Matches`: Moria8 behavior appears equivalent for the audited case.
- `Acceptable approximation`: different implementation, deliberately bounded.
- `Mismatch`: implemented behavior differs and should not be called accurate.
- `Missing`: behavior is absent.
- `Needs deeper runtime test`: static audit is insufficient.

## Executive Result

Confidence: high for static tables and resident formulas; moderate for runtime
paths that need seeded RNG and visibility-state tests.

Moria8 is closer to Umoria than the old backlog note claimed for blow counts:
the runtime melee blow matrix matches Umoria's 7x6 table, including the reported
gnome rogue dagger case.

Repair status for this branch:

- Fixed: exceptional STR/DEX/CON combat and HP bonus thresholds.
- Fixed: exceptional DEX disarm thresholds.
- Fixed: too-heavy melee to-hit penalty and bare-hand to-hit penalty.
- Fixed: unlit melee target BTH reduction.
- Fixed: bless/hero BTH/BOW effects, bless AC effect, hero fear cancellation,
  hero +10 HP, and hero expiration HP clamp.
- Fixed: player damage order now applies dice, ego/slay/brand, critical, then
  signed `PL_TODMG` with a floor at zero.
- Fixed: thrown damage now uses exceptional STR damage adjustment.
- Fixed: monster confusion-on-hit now uses random Umoria-like duration/stacking
  instead of a fixed 20 turns.
- Fixed: direct floor trap disarm now uses Umoria-style effective ability,
  trap-level threshold, and bad-fail roll.
- Still open: super-heroism, unsupported monster attack types, full launcher/ammo
  parity, protection-from-evil contact parity, and direct C128 combat unit tests.

## Static Data

| Area | Umoria behavior | Moria8 behavior | Verdict | Evidence | Follow-up |
| --- | --- | --- | --- | --- | --- |
| Race combat properties | `character_races[]` stores base BTH, bow BTH, save, hit die, and class mask. Gnome is BTH -8, bow +12, save +12, HD 7. | `race_properties` mirrors compact HD, infra, XP, disarm, search, stealth, fos, BTH, BOW, SAVE. Gnome row is HD 7, BTH -8, BOW +12, SAVE +12. | Matches | Umoria `data_player.cpp`; Moria8 `commodore/common/tables.s` | Add a static table guard if race data is edited again. |
| Class combat properties | `classes[]` stores HP die, BTH, BOW, save, disarm; Rogue is HD 6, BTH 60, BOW 66, save 30, disarm 45. | `class_properties` mirrors these fields in compact order. Rogue row is HD 6, BTH 60, BOW 66, save 30, disarm 45. | Matches | Umoria `data_player.cpp`; Moria8 `commodore/common/tables.s` | Add a static table guard if class data is edited again. |
| Class per-level progression | `class_level_adj[class][bth,bthb,device,disarm,save]`; Rogue is `3,4,3,4,3`. | `class_level_adj` has the same rows and order. | Matches | Umoria `data_player.cpp`; Moria8 `commodore/common/tables.s` | None. |
| Blow-count table | Umoria C++ uses `blows_table[7][6]`, DEX thresholds `<10,<19,<68,<108,<118,else`, STR/weight thresholds `<2,<3,<4,<5,<7,<9,else`. | Runtime `combat_calc_blows` uses the same thresholds and table. | Matches | Umoria `data_tables.cpp`, `player_stats.cpp`; Moria8 `commodore/common/tables.s`, `commodore/common/combat.s`; tests `test_combat.s` 31-33 | Keep tests for gnome rogue, max exceptional DEX, too-heavy, and ammo-as-melee. |
| Too-heavy weapon | If `STR * 15 < weight`, Umoria forces 1 blow and returns a negative weight-to-hit penalty. | Moria8 now forces 1 blow and applies the signed weight-to-hit penalty in melee total-to-hit. | Matches | Umoria `player_stats.cpp::playerAttackBlows`; Moria8 `combat_calc_blows`, `combat_calc_melee_total_tohit_bonus`; test `test_combat.s` 38 | Keep regression coverage. |
| Unarmed handling | Bare hands get 2 blows and total-to-hit penalty -3. Damage is 1d1 in Umoria's current C++ path. | Moria8 gives 2 blows and subtracts 9 from final hit chance, equivalent to -3 at `BTH_PER_PLUS_TO_HIT_ADJUST=3`; damage is 1d2. | Acceptable approximation | Umoria `player.cpp::playerCalculateToHitBlows`; Moria8 `combat_calc_tohit`, `combat_calc_blows`, `combat_roll_damage` | Decide whether 1d2 unarmed damage is intentional; add one explicit test if retained. |
| Missile or launcher as melee | Umoria forces sling ammo through spike categories to 1 blow; missile launchers used as melee are effectively not normal melee weapons. | Moria8 forces missile ID range to 1 blow and treats ranged launchers as unarmed damage. | Matches for blow count; approximation for damage | Umoria `player.cpp::playerCalculateToHitBlows`; Moria8 `combat_calc_blows`, `combat_roll_damage`; tests `test_combat.s`, `test_ranged.s` | Add a launcher-as-melee damage test that documents the approximation. |

## Stat-Derived Bonuses

| Area | Umoria behavior | Moria8 behavior | Verdict | Evidence | Follow-up |
| --- | --- | --- | --- | --- | --- |
| STR to-hit | Exceptional values have distinct thresholds: 18-18/75 gives +1, 18/76-18/90 +2, 18/91-18/98 +3, 18/99+ +4. | Moria8 now uses explicit exceptional thresholds instead of `stat_bonus_index`. | Matches | Umoria `player_stats.cpp::playerToHitAdjustment`; Moria8 `player.s::player_str_tohit_adj`; test `test_combat.s` 35 | Keep regression coverage. |
| STR damage | Exceptional values matter: 18-18/75 gives +3, 18/76-18/90 +4, 18/91-18/98 +5, 18/99+ +6. | Moria8 now uses explicit exceptional thresholds. | Matches | Umoria `player_stats.cpp::playerDamageAdjustment`; Moria8 `player.s::player_str_damage_adj`; tests `test_combat.s` 31, 35, 40 | Keep regression coverage. |
| DEX to-hit | Exceptional values matter: 18-18/50 gives +3, 18/51-18/99 +4, 18/100 +5. | Moria8 now uses explicit exceptional thresholds. | Matches | Umoria `player_stats.cpp::playerToHitAdjustment`; Moria8 `player.s::player_dex_tohit_adj`; test `test_combat.s` 35 | Keep regression coverage. |
| DEX AC | Exceptional values matter: 18-18/40 +2, 18/41-18/75 +3, 18/76-18/98 +4, 18/99+ +5. | Moria8 now uses explicit exceptional thresholds. | Matches | Umoria `player_stats.cpp::playerArmorClassAdjustment`; Moria8 `player.s::player_dex_ac_adj`; test `test_combat.s` 35 | Keep regression coverage. |
| CON HP | Exceptional values matter: 18-18/75 +2, 18/76-18/98 +3, 18/99+ +4. | Moria8 now uses explicit exceptional thresholds in HP calculation. | Matches | Umoria `player_stats.cpp::playerStatAdjustmentConstitution`; Moria8 `player.s::player_con_hp_adj` | Add a direct HP exceptional-stat unit test. |
| DEX disarm | Exceptional values matter: 18-18/40 +4, 18/41-18/75 +5, 18/76-18/98 +6, 18/99+ +8. | Moria8 now uses explicit exceptional thresholds for disarm. | Matches | Umoria `player_stats.cpp::playerDisarmAdjustment`; Moria8 `disarm_helpers.s::player_disarm_dex_adj`; tests `test_dungeon.s` | Keep direct disarm formula coverage. |

## Player Melee Formulas

| Area | Umoria behavior | Moria8 behavior | Verdict | Evidence | Follow-up |
| --- | --- | --- | --- | --- | --- |
| Lit target to-hit | `hit_chance = bth + plus_to_hit*3 + level*class_adj`; natural 1 misses, natural 20 hits; normal hit if random in hit chance beats monster AC. | `combat_calc_tohit` computes class BTH + race BTH + `PL_TOHIT*3` + level adj, and `combat_roll_tohit` implements natural 1/20 plus equivalent AC probability. | Matches | Umoria `player.cpp::playerTestBeingHit`; Moria8 `combat_calc_tohit_common`, `combat_roll_tohit`; tests `test_combat.s` | Add a seeded probability/threshold test if RNG harness supports it. |
| Unlit target to-hit | If monster is not lit, Umoria reduces base/level BTH and to-hit contribution before `playerTestBeingHit`. | Moria8 now captures the target tile lit flag and applies reduced melee BTH for unlit targets. | Matches for audited threshold | Umoria `player.cpp::playerCalculateBaseToHit`; Moria8 `player_attack_monster`, `combat_calc_tohit_common`; test `test_combat.s` 36 | Add a full attack-path lit/unlit monster test when practical. |
| Invisibility/unknown monster | Umoria's audited melee branch uses `monster.lit` for both name and base-to-hit reduction. | Moria8 has visibility systems and sense-invisible spells, but the melee hit formula does not inspect target lit/visibility. | Needs deeper runtime test | Umoria `player.cpp::playerAttackMonster`; Moria8 `combat.s`, `dungeon_los.s` | Add a runtime test for invisible/unlit/unknown target melee before declaring parity. |
| Blow loop | Umoria rolls each blow independently and stops remaining blows on monster death. | Moria8 loops `zp_combat_blows`, rolls each blow, stops on death, but prints one aggregate result for the round. | Matches mechanically; UI approximation | Umoria `player.cpp::playerAttackMonster`; Moria8 `player_attack_monster`; backlog `docs/BACKLOG.md` | Backlog per-blow feedback if player-visible accuracy matters. |
| Damage order | Umoria rolls dice, applies ego/slay/brand damage, applies critical, then adds stat/equipment damage and floors at zero. | Moria8 now applies `PL_TODMG` after ego/slay/brand and critical, clamped to `[0,255]`. | Matches for audited order | Umoria `player.cpp::playerAttackMonster`; Moria8 `combat_roll_damage`, `combat_critical_blow`, `combat_add_damage_bonus`; test `test_combat.s` 40 | Add slay+critical+to-damage integration tests. |
| Critical chance | Umoria chance is `randint(5000) <= weapon_weight + 5*plus_to_hit + class_adj*level`; tiers are weight plus `randint(650)` into x2+5, x3+10, x4+15, x5+20. | Moria8 uses weapon weight, `5*PL_TOHIT`, class adj*level, and same tiers. It uses zero-based RNG comparison, so boundary exactness needs seeded confirmation. | Needs deeper runtime test | Umoria `player.cpp::playerWeaponCriticalBlow`; Moria8 `combat_critical_blow`; test `test_combat.s` 34 | Add deterministic RNG boundary tests for `<=` vs zero-based `<` edge. |
| Monster AC interaction | Umoria checks hit chance against creature AC after natural 1/20 handling. | Moria8 stores `cr_ac` in `zp_combat_atk` and compares RNG result to AC with equivalent probability. | Matches | Umoria `playerTestBeingHit`; Moria8 `combat_roll_tohit` | None beyond seeded tests. |

## Monster Melee

| Area | Umoria behavior | Moria8 behavior | Verdict | Evidence | Follow-up |
| --- | --- | --- | --- | --- | --- |
| Monster normal to-hit | VMS and Umoria use attack-type base to-hit plus monster level scaling, checked against player AC with natural 1/20 rules. | Moria8 uses `base_to_hit[attack_type] + cr_level*3`, natural 1/20, and `zp_player_ac`. | Matches for implemented attack types | Umoria `monster.cpp` and VMS `creature.inc::make_attack`; Moria8 `monster_attack.s` | Add seeded AC threshold tests for representative monster levels. |
| Player AC damage reduction | Umoria normal attacks reduce damage by AC proportion; special effects generally keep full dice damage. | Moria8 normal attacks call `mon_atk_ac_reduce` with `damage -= AC*damage/200`; poison/confuse/fear/paralyze/acid/corrode skip AC reduction. | Matches for implemented types | Umoria `monster.cpp`; VMS `creature.inc`; Moria8 `monster_attack.s` | Keep `test_monster_attack.s`; add one test per special type if missing. |
| Implemented special attacks | Umoria/VMS include more attack types than Moria8 currently supports: stat drains, blindness, stealing, disenchant, eating food/light/charges, elemental cold/fire/lightning, etc. | Moria8 supports normal, poison, confuse, paralyze, acid, fear, corrode, aggravate. | Missing | VMS `creature.inc::make_attack`; Umoria `monster.cpp`; Moria8 `monster_attack.s` | Backlog unsupported monster attack types separately from combat math. |
| Invulnerability | Umoria damage application sets damage to zero while invulnerable; display AC also increases. | Moria8 `mon_atk_apply_damage` returns without subtracting HP while `eff_invuln_timer` is set; display/stat side effects are not fully audited. | Matches for damage prevention | Umoria `player.cpp::playerTakesHit`, `playerRecalculateBonuses`; Moria8 `monster_attack.s` | Add UI/AC status audit separately if needed. |
| Protection from evil | Umoria protection affects evil monster contact/movement, not ordinary damage formula directly. | Moria8 has `zp_eff_protect` timer and protection spell plumbing; monster-contact parity was not proven in this combat audit. | Needs deeper runtime test | Umoria `monster.cpp`; Moria8 `player_magic_execute_overlay.s`, `monster_ai.s` | Add runtime test for evil monster contact while protected. |

## Ranged And Thrown Combat

| Area | Umoria behavior | Moria8 behavior | Verdict | Evidence | Follow-up |
| --- | --- | --- | --- | --- | --- |
| Shared BOW to-hit | Umoria thrown/fired paths reuse `playerTestBeingHit` with BTHB and bow class adjustment. | Moria8 `throw_calc_tohit` and ranged fire reuse `combat_calc_tohit_common` with BOW offset and `combat_roll_tohit`. | Matches structurally | Umoria `player_throw.cpp`; Moria8 `throw.s`, `ranged_fire.s` | Add parity tests for distance penalties and launcher/ammo combinations. |
| Thrown damage | Umoria thrown damage applies item dice and selected bonuses through `weaponMissileFacts`; exact distance and combination logic is richer. | Moria8 throws item dice, exceptional STR damage bonus, and `PL_TODMG`; it still uses the simplified item catalog. | Acceptable approximation | Umoria `player_throw.cpp`; Moria8 `throw.s`; tests `test_throw.s` | Document item-catalog approximation and add launcher/ammo matrix tests if combat parity is expanded. |
| Ranged damage | Umoria launcher/ammo combinations can alter damage and to-hit by missile facts. | Moria8 fires ammo dice and adds `PL_TODMG`; no audited critical path. | Needs deeper runtime test | Umoria `player_throw.cpp`; Moria8 `ranged_fire.s`; tests `test_ranged.s` | Add launcher/ammo combination parity matrix. |

## Status Effects

| Area | Umoria behavior | Moria8 behavior | Verdict | Evidence | Follow-up |
| --- | --- | --- | --- | --- | --- |
| Bless timer and bonuses | Umoria bless adds +5 BTH, +5 BOW, +2 AC on activation; removes them on expiration. | Moria8 now applies bless to melee/ranged BTH and monster-contact effective AC while the timer is active. | Matches for combat effects | Umoria `game_run.cpp::playerUpdateBlessedStatus`; Moria8 `combat_calc_tohit_common`, `monster_attack.s::mon_atk_effective_ac`; tests `test_combat.s` 37, `test_monster_attack.s` 14 | Keep timer/message tests. |
| Heroism | Umoria heroism adds +12 BTH, +12 BOW, +10 max/current HP; cancels fear. | Moria8 now applies hero BTH/BOW, adds/removes +10 HP, clamps HP on expiration, and blocks/cancels fear. | Matches for audited heroism effects | Umoria `game_run.cpp::playerUpdateHeroStatus`; Moria8 `player_item_commands.s::iq_effect_heroism`, `turn.s`, `combat_calc_tohit_common`, `monster_attack.s`; tests `test_combat.s` 37, `test_monster_attack.s` 15-16 | Add potion activation integration coverage. |
| Super-heroism | Umoria super-heroism adds +24 BTH, +24 BOW, +20 max/current HP; cancels fear. | No audited Moria8 super-heroism gameplay effect path was found. | Missing | Umoria `game_run.cpp::playerUpdateHeroStatus`; Moria8 status searches | Backlog potion/effect implementation and tests. |
| Fear blocks melee/open/tunnel/bash | Umoria fear blocks melee and bash; fear state interacts with hero/shero. | Moria8 blocks bump attack, bash, and tunnel when `eff_fear_timer` is active; heroism now cancels/blocks fear. | Matches for audited hero/fear interaction | Umoria `player.cpp`, `player_bash.cpp`, `player_tunnel.cpp`, `game_run.cpp`; Moria8 `player_move.s`, `bash.s`, `tunnel.s`, `player_item_commands.s`, `monster_attack.s`; test `test_monster_attack.s` 15 | Add command-by-command fear matrix tests. |
| Player confusion direction | Umoria can randomize movement/tunnel/bash direction and blocks spell/prayer/scroll-like actions. | Moria8 has confusion timers, movement/tunnel/bash randomization, spell tests, and monster magic confusion. | Needs deeper runtime test | Umoria `player_move.cpp`, `player_tunnel.cpp`, `player_bash.cpp`; Moria8 `player_move.s`, `tunnel.s`, `bash.s`, tests `test_confusion.s` | Add command-by-command confusion matrix before declaring parity. |
| Monster confusion on hit | Umoria one-time confuse-on-hit clears the player flag and sets monster confusion to `2 + randint(16)` or adds 3 if already confused, with resistance check. | Moria8 now uses a random `2..17` duration for first confusion and +3 stacking capped at 255. Resistance parity still needs a monster-trait test. | Matches for duration/stacking; needs resistance test | Umoria `player.cpp::playerAttackMonster`; Moria8 `combat.s::player_attack_monster` | Add resistant monster test. |

## Current Test Coverage

| Area | Existing coverage | Verdict | Evidence | Follow-up |
| --- | --- | --- | --- | --- |
| Core melee math | C64 `combat` tests cover to-hit arithmetic, blow buckets, damage range, apply damage, XP, level-up, critical chance, gnome rogue case, exceptional stats, unlit target BTH, status BTH, too-heavy to-hit, ranged BOW table selection, and signed damage bonus floor. | Good but not complete | `commodore/c64/tests/test_combat.s`; `commodore/c64/run_tests.sh` | Add slay+critical+to-damage integration tests and direct CON HP/disarm exceptional-stat tests. |
| Direct disarm | C64 `dungeon` tests cover effective disarm ability, trap threshold, and bad-fail behavior. | Good for direct floor trap formula | `commodore/c64/tests/test_dungeon.s`; `commodore/common/disarm_helpers.s` | Add command-path coverage for success/failure messages if UI parity matters. |
| Monster attack | C64 `monster_attack` tests cover to-hit, AC reduction, special effect plumbing, bless AC, hero fear blocking, hero expiration, and invulnerability damage prevention. | Good for implemented types | `commodore/c64/tests/test_monster_attack.s` | Add unsupported attack type backlog tests only when implementing those attacks. |
| Ranged/thrown | C64 `ranged` and `throw` tests exist. | Partial | `commodore/c64/tests/test_ranged.s`, `test_throw.s` | Add Umoria launcher/ammo matrix and exceptional STR damage cases. |
| Status effects | Bless, remove fear, protection from evil, confusion tests exist on C64 and many C128 spell/prayer tests exist. | Timer-heavy, combat-light | `commodore/c64/run_tests.sh`; `commodore/c128/run_tests128.sh` | Add tests proving BTH/BOW/AC/HP/fear effects, not just timers/messages. |
| C128 combat runtime | C128 fast suite does not list direct `combat128` or `monster_attack128` unit tests, though smokes include dungeon attack stability. | Missing | `commodore/c128/run_tests128.sh` | Port high-value combat math tests to C128 or add static cross-platform guards. |

## Worked Example: Reported Gnome Rogue

Assumption: the reported case is the backlog example, a level-3 gnome rogue
wielding a dagger, with STR 16 and DEX 18/36. Moria8 encodes 18/36 as `54`
because `19..118` represent `18/01..18/100`.

Source calculation:

- Umoria/Moria8 dagger weight in the current test is 12 tenths of a pound.
- Adjusted weight is `STR * 10 / weapon_weight = 16 * 10 / 12 = 13`.
- Weight row is `>=9`, so row 6.
- DEX 54 is `<68`, so DEX column 2.
- `blows_table[6][2] = 3`.

Result: current Moria8 runtime blow count is 3, not 4. This is now covered by
`commodore/c64/tests/test_combat.s` test 31. The visible combat message can
still make a three-blow round look like a single hit, because Moria8 aggregates
the attack result into one message.

Hit chance for the same character at level 3, before weapon enchantment and
temporary statuses:

- Rogue class BTH 60 plus gnome race BTH -8 gives base 52.
- Rogue level adjustment is `3 * 3 = 9`.
- STR 16 gives +1 to hit in Umoria and Moria8; DEX 18/36 gives +3 in Umoria and
  Moria8, because 18/36 is below Umoria's next DEX threshold.
- Total plus-to-hit is +4, worth `4 * 3 = 12`.
- Lit-target hit chance before monster AC is `52 + 9 + 12 = 73`.

This specific DEX value does not expose the exceptional DEX to-hit mismatch.
The mismatch starts at DEX 18/51, where Umoria gives one more to-hit point than
Moria8.

## Follow-Up Classification

| Finding | Classification | Proposed disposition |
| --- | --- | --- |
| Exceptional STR/DEX/CON combat bonuses collapse to plain 18. | Fixed | Implemented explicit helper thresholds; add direct HP/disarm edge tests. |
| Bless lacks BTH/BOW/AC effects. | Fixed | Covered by focused combat/monster-attack tests. |
| Heroism lacks BTH/BOW/HP/fear gameplay effects. | Fixed | Covered by focused combat/monster-attack tests; potion activation can use more coverage. |
| Super-heroism lacks BTH/BOW/HP/fear gameplay effects. | Missing | Backlog with potion/status tests. |
| Unlit monster melee does not reduce BTH. | Fixed | Covered by focused combat test; add full attack-path visibility test later. |
| Damage order multiplies `PL_TODMG` through ego/critical. | Fixed | Add slay/brand/critical integration regression tests. |
| Too-heavy weapon to-hit penalty is not applied. | Fixed | Covered by focused combat test. |
| Monster confuse-on-hit uses fixed 20 turns and lacks Umoria resistance/random stacking. | Partially fixed | Duration/stacking fixed; add resistant monster test. |
| Direct trap disarm used flattened chance and always-safe failure. | Fixed | Formula, threshold, and bad-fail helper tests added; C128 preloads cached `128.disarm` overlay. |
| Unsupported monster attack types. | Missing | Backlog as content expansion, not a combat core blocker. |
| Aggregate melee feedback hides multiple blows. | Acceptable approximation mechanically, UX mismatch | Backlog per-blow messages if player-facing clarity is desired. |

## Verification Performed

Original audit used static source inspection. The repair branch was then
validated with build and runtime tests.

Commands/paths inspected:

- `rg` and `sed` over a local Umoria source checkout.
- `rg` and `sed` over a local VMS Moria source checkout.
- `rg` and `sed` over `commodore/common`, `commodore/c64/tests`, and
  `commodore/c128/tests`.

- `make build`
- `make test64`: 149 passed, 0 failed.
- `make test128`: 118 passed, 0 failed.
- `make testplus4`: 10 passed, 0 failed.
