# Monster State Contract

Load this document for monster records, AI, sleep/wake behavior, awareness,
visibility/detection, monster targeting, attacks, or spell effects on monsters.
Do not load it for renderer or inspection work that only consumes
already-authoritative monster flags; use `TURN_RENDER_CONTRACT.md` instead.

## Authority

- Moria8 state layout and production entry points: `core/monster.s`
- AI transitions: `core/monster_ai.s`
- Attack transitions: `core/monster_attack.s`, `core/monster_magic.s`
- Default upstream oracle: pinned VMS Moria
  `source/include/{misc,creature,spells}.inc`
- Secondary oracle: pinned Umoria `src/{monster,spells}.cpp`

## Live Record Inventory

Each live slot is a 12-byte record. `MX_TYPE == EMPTY_SLOT` is the sole empty
slot test and must precede mutation through table scans.

| State | Meaning | Authoritative consumer |
| --- | --- | --- |
| `MX_X`, `MX_Y` | Current map position | movement, combat, visibility |
| `MX_TYPE` | Active creature-table index or `EMPTY_SLOT` | every live-slot scan |
| `MX_HP_LO`, `MX_HP_HI` | Current 16-bit HP | combat, monster magic, door bash/pick/burst |
| `MX_FLAGS.MF_AWAKE` | Monster may proceed into active AI | `monster_process_one` |
| `MX_SLEEP_CUR` | Remaining compact sleep counter | `monster_wake_check` |
| `MX_SPEED_CNT` | Movement scheduling state | monster AI tick |
| `MX_STUN` | Turns unable to act | `monster_process_one` |
| `MX_CONFUSE` | Live confusion timer used by AI | combat and `monster_process_one` |
| `MX_RESERVED_0`, `MX_RESERVED_1` | Reserved, unused bytes 10–11 (formerly `MX_FLEE_LO`, `MX_FLEE_HI`; zeroed on spawn; retained to preserve the 12-byte record and Save Format V2) | none (MON-043) |
| `MF_PROVOKED` | Player hostility; permits town-creature retaliation | combat, bash, AI |
| `MF_VISIBLE` | Current ordinary sight and renderer authority | visibility, targeting, sighting & hostile-action disturbance (`zp_disturb`, MON-038 / TRN-014) |
| `MF_DETECTED` | Magical detection knowledge: timed Detect Monsters or immediate Detect Evil pending its post-redraw clear | renderer, free-look, and dirty tracking; not ordinary targeting |
| `MF_CONFUSED` | Defined flag with no production consumer found | not authoritative; use `MX_CONFUSE` |

`MF_VISIBLE` and `MF_DETECTED` are knowledge/render states. Detection may be
timer-owned or an immediate reveal latch; it does not grant ordinary LOS or
spell targeting. Current production also makes
`MF_VISIBLE` monsters wake-eligible outside `cr_aaf`; that behavior is disputed
and recorded below rather than silently treated as settled policy.

Ordinary wake pressure currently uses Chebyshev distance, while both upstream
oracles use `max(dx,dy) + floor(min(dx,dy)/2)`. The shared distance helper also
owns monster spell range, so convergence is tracked as a separate backlog item
with diagonal boundary tests rather than being changed incidentally here.

## Settled Transitions

| Event | Required transition | Production entry point | Existing coverage |
| --- | --- | --- | --- |
| Apply explicit sleep | Clear `MF_AWAKE`; store duration in `MX_SLEEP_CUR` | `monster_apply_sleep` | C64/C128 sleep and sanctuary suites |
| Ordinary active AI | Only `MF_AWAKE` monsters proceed past wake check | `monster_process_one` | C64 `test_monster_ai.s` |
| Empty-slot scan | Skip before writing any other field | all table scans | monster/attack tests |
| Detect Monsters | May set and expose `MF_DETECTED`; must not imply `MF_VISIBLE` | visibility producer, inspection, dirty tracking, renderers | platform detect/render tests |
| Explicit aggravation | Clear sleep and wake every live slot; upstream nearby haste remains unresolved | `monster_aggravate_all` | C64 attack and Plus/4 shared-producer coverage |
| Monster sighting (`MF_VISIBLE` `0 -> 1`) | Call `player_search_mode_off` and `inc zp_disturb`; unseen `CD_INVISIBLE` returns early without setting `MF_VISIBLE` or disturbing (TRN-012) | `muvo_apply_visible` (`core/monster.s`) | C64 `test_monster_ai2.s` t16 (MON-038) |
| Visible hostile monster action | Tag `mat_action_dirty` bit 1 (`$02`) for hostile moves (`$83`) and spells/breeding/door-open/glyph-break (`$03`), leaving bit 1 clear (`$81`) for unprovoked townies; at `!mpo_done`, `inc zp_disturb` iff `(mat_action_dirty & $02) != 0 && (zp_mon_flags & MF_VISIBLE) != 0`; sleeping monsters stay quiet (MON-005) | `monster_process_one` (`core/monster_ai.s`) | C64 `test_monster_ai2.s` t17-t19, t23 (MON-038) |
| Monster door burst | Print `HSTR_MAT_DOOR_BURST` unconditionally and `inc zp_disturb` mid-turn via shared `!mts_bash_set` tail (plain door open adds no extra door-tile LOS check) | `monster_try_step` (`!mts_stuck`, `!mts_bash` in `core/monster_ai.s`) | C64 `test_monster_ai2.s` t20 (MON-009, MON-038) |
| Monster melee round | Execute `inc zp_disturb` right after `!map_has_atk0:` (past the `ATK_NONE` early exit) | `monster_attack_player` (`core/monster_attack.s`) | C64 `test_monster_attack.s` t55 (MON-038) |

Numeric counters are unsigned bytes unless a field says otherwise. Arithmetic
must not wrap accidentally. For each changed formula, record every input and
intermediate width, carry state, mathematical range, and saturation/truncation
point. Exhaustive tests are preferred when the input domain is one byte.

Sleep spell resistance translates `rng_range(40)` from `0..39` to VMS Moria's
`randint(40)` range `1..40` before comparing against monster level.

## Decision Ledger

Accepted rows dated 2026-07-09 record explicit maintainer decisions from the
work16 behavior review; this ledger is their durable approval provenance.

| ID | Status | Owner/date | Scope and selected rule | Evidence/enforcement | Supersedes |
| --- | --- | --- | --- | --- | --- |
| MON-001 | Accepted | Project maintainer, 2026-07-09 | Detected-only monsters are renderable/inspectable knowledge but are not ordinary spell targets | maintainer decision; targeting and renderer tests; inspection test `NOT IMPLEMENTED` | none |
| MON-002 | Accepted | Project maintainer, 2026-07-09 | Explicit sleep clears `MF_AWAKE` and stores the compact duration | `monster_apply_sleep`; sleep/sanctuary tests | none |
| MON-003 | Disputed current behavior | Project maintainer, 2026-07-09 | Production lets `MF_VISIBLE` bypass `cr_aaf` for wake eligibility; eligible wake pressure is gated by race/class stealth as in VMS Moria | `monster_ai.s::monster_wake_check`; C64 stealth-gate regressions | none |
| MON-004 | Accepted | Project maintainer, 2026-07-09 | Initial sleep uses the compact randomized mapping and saturates at `$ff`; arithmetic must not wrap | `monster_initial_sleep`; C64 maximum-input regression | none |
| MON-005 | Accepted | Project maintainer, 2026-07-09 | Auto-rest suppresses ordinary deterministic wake pressure, matching VMS Moria | `monster_wake_check`; C64 AI rest regression | none |
| MON-006 | Accepted in part | Project maintainer, 2026-07-09 | Explicit/group wakes clear `MX_SLEEP_CUR`; Sleep I/II/III use monster-level resistance; aggravation wakes globally | shared helpers and C64/C128/Plus4 focused gates; `CD_NO_SLEEP` immunity implemented in MON-034; upstream nearby aggravation haste remains open | none |
| MON-007 | Accepted | Project maintainer, 2026-07-10 | Compact ordinary wake pressure uses distance steps `{8,8,4,3,2,2,1...}` scaled from VMS Moria's `floor(75/d)`; an eligible zero sleep counter wakes before rest/stealth gates | explicit maintainer direction to address staff review; C64 deterministic wake regressions | none |
| MON-008 | Superseded by MON-026 | Project maintainer, 2026-08-05 | Player haste/slow (`zp_eff_speed`) and Ring of Speed (`PFLAG_SPEED`) fold into the per-tick monster cadence: haste or ring steps a monster one cadence slower, an active slow timer one faster, clamped to the existing 0-2 cadence (floor = act every other turn, cap = double move); haste+ring stacking yields no extra effect; the fold is computed per-tick and never mutates stored monster speed state (`cr_speed`, `MX_SPEED_CNT`) | explicit maintainer direction 2026-08-05; oracle Umoria `playerChangeSpeed` (`player.cpp:367-377`) and `monsterMovementRate` (`monster.cpp:74-92`) with documented floor/cap deviations (Umoria -1 = every 3rd turn; Moria8 floor = every 2nd); C64 `test_monster_ai.s` t36-t40, `test_turn.s` t27-t29 | none |
| MON-009 | Accepted | Project maintainer, 2026-09-10 | Monster door-state engine (`!mts_door_block` in `core/monster_ai.s`): door-capable monsters (`cr_aaf` bit 7) pick locks (success unlocks without opening; turn spent either way) and burst stuck doors (open + 50% break); non-capable monsters bash with the |s|-adjusted terms. All three rolls share `mts_state_roll`, the exact Umoria `monsterOpenDoor` formula, translated from one-based `randomNumber(N) < T` to zero-based `rng_range_word(N) < T-1`: `rng_range_word((hp+1)*A) < 40*(hp-B)-1`, with pick A=50+p/B=10+p, burst/bash A=50+|s| or 80+|s|, B=10+|s| or 20+|s|; hp is clamped to 254 and hp <= B never succeeds (equality explicitly clears carry). The burst message "You hear a door burst open!" is printed unconditionally, matching upstream, which has no visibility/distance gate (extended by MON-038 to execute `inc zp_disturb` mid-turn alongside the burst message) | pinned Umoria `monster.cpp::monsterOpenDoor`; C64 `test_monster_ai.s` t47-t55 including the hp == B boundary set (red-green verified 2026-09-10); multi-platform build asserts | none |
| MON-010 | Accepted | Project maintainer, 2026-10-21 | Any monster within one step (including diagonally across a wall corner) is in line of sight for `MF_VISIBLE`, subject to the existing light/infravision range and blindness gates; line-of-sight tracing applies only at distance 2 and beyond. A monster that can attack the player is therefore never drawn as bare floor | explicit maintainer direction 2026-10-21; pinned Umoria `dungeon_los.cpp::los` adjacency return and VMS Moria `los`; AI playtest finding F-M2-3; C64 `test_monster.s` t20-t22 and `test_effects.s` Test 35 | PR #46 corner-hidden expectation in `test_effects.s` Test 35 |
| MON-011 | Accepted | Project maintainer, 2026-10-21 | Monster wound, blind, confuse and fear spells follow pinned VMS Moria `creature.inc` `cast_spell` (spells 8, 9, 11, 12, 13; Umoria `monster.cpp` identical): Cause Light Wounds 3d8 (`MSF_WOUND_LIGHT`, bit 0) and Cause Serious Wounds 8d8 (`MSF_WOUND_SERIOUS`, bit 6, formerly the unused monster heal) print "casts a spell."; blind 12+randint(3) or +6, confuse and fear randint(5)+3 or +2, saturating at 255; fear (`MSF_FEAR`, bit 7) is now cast and Heroism blocks it. Each is preceded by a player saving throw (`core/player_save.s`): `rng_range(100) < race save + class save + adjustment` (VMS `player_saves`), adjustment wis_adj + level for spells and con_adj for the paralysis touch, using Moria8's existing race/class save values. Deviations: saved spells print Umoria's "You resist the effects of the spell."; failed blind/confuse/fear keep Moria8's effect messages because the status line has no effect indicators. Breath, Hold Person and the 1-in-N cast roll are MON-025 (2026-11-08) | explicit maintainer direction 2026-10-21 (`docs/AI_PLAYTEST_DESIGN.md` §14.6-14.7); pinned VMS `creature.inc`, `misc.inc` (`player_saves`, `wis_adj`, `con_adj`); pinned Umoria `monster.cpp`; C64 `test_monster_magic.s` t5, t7, t8, t15-t26 (mutation-checked), `test_monster_ai.s` t15 | generic 2d8+level bolt without save; 1d10+10 blind and 1d5+5 confuse without save; monster self-heal spell; paralysis save of class save + level |
| MON-012 | Accepted | Project maintainer, 2026-10-23 | The monster fear attack (`ATK_FEAR`, `mon_atk_effect_fear`) follows pinned VMS Moria `creature.inc` (fear attack 4; Umoria `monster.cpp` case 4 identical apart from the save formula): after the hit's damage, the player gets `player_saves(wis_adj)` (`player_wis_save_adj`, `player_saving_throw`); if not saved, a player who is not afraid becomes afraid for 3 + randint(level) turns ("frightens you" message), and an afraid player gains 3 more turns (no message), saturating at 255. Heroism still blocks it (VMS clears fear each turn while heroic). Deviations: a resisted fear prints nothing (VMS "You resist the effects!"), as Moria8's paralysis touch already does; Moria8's own race/class save values (MON-011). | maintainer direction 2026-10-23 ("make recommended fixes as discovered", M4 goal) after the M4 baseline's Poltergeist deaths (`docs/AI_PLAYTEST_DESIGN.md` §15.2); pinned VMS/Umoria sources; C64 `test_monster_attack.s` t11, t14-t17 | no save; timer rng_range(level) + 3, replaced only when larger |
| MON-013 | Accepted | Project maintainer, 2026-10-23 | Monster random movement follows pinned Umoria `monsterMove` (VMS `creature.inc` uses the same CMOVE bits): after confusion and spell casting, a creature with `CM_75_RANDOM` (`$20`) moves randomly when `randomNumber(100) < 75`, else with `CM_40_RANDOM` (`$10`) when `< 40`, else with `CM_20_RANDOM` (`$08`) when `< 20`; otherwise it moves normally. The bits are kept in place in `cr_speed` bits 3-5 (speed code bits 0-1; `tools/parse_creatures.py` stores `speed | (cmove & $38)`, regenerated from the pinned Umoria revision: 53 shipped creatures carry at least one bit, e.g. Poltergeist `$3A`). `rng_range(100)` draws 0-99, so the thresholds are 74/39/19. A random move is `monster_move_random` (one of 8 directions; Umoria tries up to five of 9 including staying put), which attacks the player if it steps onto them. Town creatures keep their own wandering. | maintainer direction 2026-10-23 ("make recommended fixes as discovered", M4 goal): the M4 runs found the Poltergeist (88% random upstream) chasing and hitting the bot 50-70 times; `docs/AI_PLAYTEST_DESIGN.md` §15.4; C64 `test_monster_ai.s` t59 (22 of 40 trials step toward the player with `CM_75_RANDOM`, 40 of 40 with the roll removed) | creatures always moved toward the player |
| MON-014 | Accepted | Project maintainer, 2026-10-23 | Killed monsters drop treasure as in pinned VMS Moria `moria.inc` `monster_death`/`summon_object` (Umoria `monsterDeath` uses the same CMOVE bits 24-30): the creature's flags select object (bit 24), gold (25) or 50/50 mixed (both) drops, rolled as 60% one (26), 90% one (27), randint(2) (28), 2d2 (29) and 4d3 (30; Umoria 4d2), each placed in the 5x5 box around the kill with the chest-contents generator (`chest_generate_loot`, `docs/CHEST_DESIGN.md`: object or gold at the current depth, 10 placement attempts on a free floor or open-door tile). The flags are `cr_treasure` (`core/monster_death.s`), a tier SoA field after `cr_spell_flags` generated by `tools/parse_creatures.py` from the pinned Umoria list (67 of 120 shipped creatures carry treasure, e.g. Creeping Copper Coins `$12`, Orc `$0b`, Balrog `$7f`; town rows fixed). Only kills by the player stage a drop: melee, bash and `eff_kill_monster` (spells, missiles, earthquake, dispel) all reach `combat_note_kill`, which stages the flags at the position `monster_remove` left in `mfa_x`/`mfa_y`; genocide, polymorph and destruction remove without drops, as upstream `delete_monster`. Deviations: drops are placed when the command ends (`chest_fulfill_loot` at the top of `turn_post_action_searchable_or_die`), still before monsters act, rather than at the moment of the kill; at most 4 kills per command are staged (`MD_QUEUE_MAX`); occupied tiles are skipped and an object or gold amount follows the chest rules; the win flag (bit 31) stays with `combat_note_kill`. The queue is cleared with the monster table (new level) and on load. | maintainer direction 2026-10-23 ("why don't monsters drop stuff and can we fix that?" ... "yes proceed", option (a): a per-creature treasure byte) during the M4 goal; pinned VMS/Umoria sources; C64 `test_chest_loot.s` t10-t16 (production `chest_fulfill_loot`, `chest_generate_loot`, `eff_kill_monster`; t11 and t14 mutation-checked) | monsters dropped nothing (creature treasure bits were discarded by the generator) |
| MON-015 | Accepted | Project maintainer, 2026-10-24 | The monster acid attack (`ATK_ACID`, `mon_atk_effect_acid` in `core/monster_acid.s`) follows pinned VMS Moria `creature.inc` acid attack 6 -> `moria.inc` `acid_dam`/`minus_ac` (Umoria identical): after the attack's effect message, one worn armour piece is chosen with `rng_range(count)` among the occupied body, shield, head and hands slots (`EQUIP_BODY`-`EQUIP_HANDS`); if its base AC + to-AC is above 0 the game prints "Your <item description> is damaged!" (the description as the wear message gives it, before the change), lowers its to-AC by 1, recalculates equipment and halves the damage (`dam div 2`). Otherwise, or with nothing worn, the full damage lands. Deviations: VMS's cloak slot does not exist in Moria8; no Moria8 armour carries acid resistance and the player has no acid resistance, so VMS's "resists damage!" and divide-by-3/4 branches do not exist; acid damage to pack items (VMS `inven_damage`, "There is an acrid smell coming from your pack!") is not implemented. The C128 main image and the Apple IIe and BBC Master resident images carry the routine (`MON_ATK_ACID_EXTERNAL`) | maintainer direction 2026-10-24 ("Full VMS": rules and the named-item message) after M4's Green Naga deaths (`docs/AI_PLAYTEST_DESIGN.md` §15.4); pinned VMS `moria.inc` `acid_dam`, `minus_ac`; C64 `test_monster_attack.s` t18-t22 (production `mon_atk_effect_acid`; halving and random choice mutation-checked) | acid dealt full damage and left armour untouched |
| MON-016 | Accepted | Project maintainer, 2026-10-25 | Breeding (`CF_BREEDER`, upstream `CM_MULTIPLY`) follows pinned VMS Moria `creature.inc` `mon_move` (Umoria `monsterMultiplyCritter` identical): after its move, a breeder counts the creatures in its 3x3 square, itself included (`mpo_count_neighbours`: `FLAG_OCCUPIED` marks creatures only), as `n`; if `n < 4` it multiplies when `rng_range(7n) == 0` (`randint(n*7) = 1`), placing the clone with `find_adjacent_empty`. While auto-rest runs, a further `rng_range(7) == 0` stands in for upstream's `rest mod 7 = 0`. Deviations: the existing `zp_mon_count < MAX_MONSTERS - 4` limit stands in for `mon_tot_mult <= 75` (unreachable with 32 slots); the clone tile may hold an object; the rest check is a roll, not every 7th rest turn | maintainer direction 2026-10-25 ("compare the breeding logic/stats/tables", with the standing direction to fix port differences, `fix-port-differences` feedback) after M5b's Giant White Mouse deaths; pinned VMS `creature.inc:1066-1080`, `moria.inc:2217`; pinned Umoria `monster.cpp:985-1007, 1171-1177`; C64 `test_monster_ai.s` t60-t63 through production `monster_ai_tick` | flat `rng_range(12)` with no crowding or rest rule |
| MON-017 | Accepted | Project maintainer, 2026-10-25 | A creature takes its turn (waking, timers, spells, movement, attacks, breeding) only while it is within its alert radius (`cr_aaf & $7f`, Moria8's Chebyshev distance) or `MF_VISIBLE`, awake or asleep, as pinned VMS Moria `creature.inc` `creatures` (`if (cdis <= aaf) or (ml)`) and Umoria `monsterAttackingUpdate`. `monster_in_awareness` holds the test; `monster_process_one` applies it to awake creatures and `monster_wake_check` to sleeping ones (as before). Until 2026-10-25 an awake creature acted anywhere on the level, so a breeder that had lost the player kept multiplying out of sight. Deviations: Umoria also gives a turn to a non-phasing creature inside a wall (so it can dig out or die); Moria8 has no such case; the distance is Chebyshev (see the wake-pressure note above) | maintainer direction 2026-10-25 ("the breeders SHOULD NOT ACT DIFFERENTLY and definitely should not breed when the player isn't around"), answering the proposal to gate every creature as upstream; pinned VMS `creature.inc:1177`; pinned Umoria `monster.cpp:1264`; C64 `test_monster_ai.s` t64-t65 (t64 mutation-checked); tests 8, 9, 40 and 60-63 now place the player inside the creature's radius | awake creatures acting at any distance |
| MON-018 | Accepted | Project maintainer, 2026-10-26 | A fired missile (`ranged_fire`, `SHIFT+F`) follows pinned VMS Moria `moria.inc` `throw_object`/`facts`/`drop_throw` for range by launcher (Short Bow 25, Light Crossbow 25, Sling 20, Long Bow 30, Composite Bow 35, Heavy Crossbow 35; the last three added 2026-10-26), to-hit (full missile skill with the player's, ammunition's and launcher's to-hit) less one per square flown, a critical hit by the ammunition's weight, and a missed shot landing at the last open square when `rng_range(10) != 0` (`randint(10) > 1`); a hit uses the shot up. Damage follows Umoria `weaponMissileFacts` by its stated fix: `(dice + ammunition to-dam + launcher to-dam)`, floored at 0, times 2 (Sling, Short Bow), 3 (Light Crossbow, Long Bow) or 4 (Composite Bow, Heavy Crossbow), saturating at 255. Deviations: no 3x3 search for a free landing square and no "disappears" message; the critical chance uses the melee per-level gain and to-hit (`combat_critical_blow_weight`); no unlit-target penalty (VMS) | maintainer direction 2026-10-26 ("usually i prefer vms unless umoria was improving/fixing something" ... "go with recommendations") during M5d (`docs/AI_PLAYTEST_DESIGN.md` §18.2); pinned VMS `moria.inc:3163-3360`, Umoria `player_throw.cpp:26-110`; C64 `test_ranged.s` t11-t13 (production `rf_roll_damage`, `rf_calc_tohit`), `test_throw.s` t12-t13 (production `rf_fly`, `rf_shot_lands`), each mutation-checked; the appended launchers `test_ranged.s` t14-t16 (missile lookup, glyph, firing tables, melee as bare hands) | range 19 for every launcher, no distance penalty or critical, damage = ammunition dice + `PL_TODMG`, every shot lost |
| MON-019 | Accepted | Project maintainer, 2026-10-31 | Protection from Evil follows pinned VMS Moria `creature.inc` `make_attack` (Umoria `monster.cpp` `monsterAttackPlayer` identical): while `zp_eff_protect` is above 0, a melee round by a creature with `CF_EVIL` whose `cr_level` is at most `zp_player_lvl` (upstream `py.misc.lev + 1 > level`) is repelled before any to-hit roll: every attack, including the aggravation shriek, becomes type 99, so no damage, no effect and no recall attack count, and the timer is not consumed. Scroll and prayer add `randint(25) + 3*lev` (VMS `spells.inc` `protect_evil`), saturating at 255; the timer counts down silently (VMS; Umoria prints "You no longer feel safe from evil."). Deviation: one "The <name> is repelled." per round (`HSTR_MAT_REPELLED`), as Moria8 prints one summary line per round for hits and misses, where upstream prints it per attack. Spells and breath are not affected, as upstream | maintainer direction 2026-10-31 (fix the five audit findings: "Protection from Evil does nothing"); pinned VMS `creature.inc:288-293, 381`, `spells.inc:1592-1597`; pinned Umoria `monster.cpp:413-418, 349-351`; C64 `test_monster_attack.s` t23-t26 through production `monster_attack_player` (t23 fails on the pre-fix code), `test_timed_buffs.s` t7-t10 | the timer was set and counted down but never read |
| MON-020 | Superseded by MON-032 | Project maintainer, 2026-11-01 | Prior 2-slot attack selection (`select_attack_slots`) ranked up to 2 upstream attacks before Phase 5 widened species records to all 4 attack slots (`atk0..atk3`); Quylthulg `ATK_NONE` early-return rule retained | superseded by full 4-slot VMS attack loop in `core/monster_attack.s` (MON-032) | first two upstream slots kept |
| MON-021 | Superseded by MON-033 | Project maintainer, 2026-11-01 | Prior zeroing of `cr_spell_chance` when a caster only carried `MSF2_*` spells (blink, teleport self, summon undead, slow, drain mana); Phase 5 implements all 5 `MSF2_*` spells so all 279 VMS casters retain their upstream frequency | superseded by `cr_spell_flags2` (`MSF2_*` bits 0-4) in `core/monster_magic.s` (MON-033) | the upstream frequency kept with no spell |
| MON-022 | Accepted | Project maintainer, 2026-11-01 | `CF_ATTACK_ONLY` marks every creature that never moves upstream: neither `CM_MOVE_NORMAL` (`0x02`) nor a random-move bit (`0x38`) in CMOVE (VMS `creature.inc` `mon_move:1081-1157`; Umoria `monsterMove`), which adds the Quylthulg (`CM_ONLY_MAGIC 0x04`) to the `0x01` creatures | maintainer approval 2026-11-01 (item C); C64 `test_monster_attack.s` t42, `test_monster_tier3.s` t4 (data, fail before), `test_monster_ai.s` t66 (production `monster_ai_tick` with the shipped flags) | only CMOVE `& 0x3F == 0x01` |
| MON-023 | Accepted | Project maintainer, 2026-11-01 | `MSF_TELEPORT` is upstream Teleport To (VMS `creature.inc` spell 7 -> `spells.inc` `teleport_to`; Umoria `spellTeleportPlayerTo`): *"The <name> casts a spell."*, then `find_adjacent_empty_mon` (the caster's neighbours, shared with breeding) and `eff_teleport_apply_target` (destination in A/Y; search off, `vis_room_revealed`). Deviations: only the 8 neighbours are tried and never the player's own square; with all blocked the player stays (upstream widens the ring). Upstream has no spell that teleports the player away; the creatures' own blink/teleport (spells 5-6) remain unmapped (no free `MSF_*` bit). The orphaned `HSTR_MM_TELEPORT` (" teleports you!") was removed | maintainer approval 2026-11-01 (item D); C64 `test_monster_ai.s` t67-t68 through production `monster_pick_spell` (fail on the pre-change code) | `eff_teleport_self`: a random teleport away with "teleports you!" |
| MON-024 | Accepted | Project maintainer, 2026-11-01 | A creature with upstream `CD_MAX_HP` (cdefense `0x4000`; VMS `misc.inc` `place_monster` `max_hp`, Umoria `maxDiceRoll`) spawns with exactly `cr_hd_num x cr_hd_sides` HP (`math_multiply`, at most `255 x 255`; Balrog `75d40 = 3000`). The flag is `cr_speed` bit 7 (`CR_MAX_HP`), a spare bit whose other readers mask it (`CR_SPEED_MASK`, `CM_RANDOM_MOVE`); no layout change. 27 creatures (flee threshold removed by MON-043) | maintainer approval 2026-11-01 (item E); C64 `test_monster_attack.s` t44-t46 through production `monster_spawn_one` (t44-t45 fail before; t46 a rolled creature) | every creature rolled its hit dice |
| MON-025 | Accepted | Project maintainer, 2026-11-08 | Monster breath, Hold Person and the cast roll follow pinned VMS Moria `creature.inc` `cast_spell` (spells 10, 20-24; Umoria `monster.cpp` identical) in the limited faithful form the maintainer chose. `cr_spell_chance` holds the upstream 1-in-N frequency (bits 0-3; `randint(N) = 1` casts, a percent `int(100 / N)` before), the breath element (bits 4-6: 1-5 lightning, gas, acid, frost, fire; 6 all five) and Hold Person (bit 7, `MS_HOLD`); `tools/parse_creatures.py` `map_spells` writes it. Each spell bit is a choice (VMS `spell_choice`): Hold Person one more after the MSF bits, a Multi-Hued dragon's five breaths five. Breath (`monster_cast_breath`): "The <name> breathes lightning." (gas, acid, frost, fire), dam = the breather's HP / 4 for lightning, / 3 otherwise, 16-bit and uncapped (`mon_atk_apply_damage_16`), through VMS `moria.inc` `light_dam`, `poison_gas` (poisoned + 12 + randint(dam), the 8-bit timer saturating), `acid_dam` (`mon_atk_acid_armour`: a damaged worn piece halves it), `cold_dam` and `fire_dam` (div 3 for the Resist Cold / Fire ring, div 3 again for the timer), one divide for the whole divisor. Hold Person (`monster_cast_hold`): Free Action (`PFLAG_FREE_ACT`, the Amulet of the Magi) leaves the player unaffected, a wis_adj + level save resists, else paralysis randint(5) + 4, + 2 if paralysed; Free Action also guards the paralysis touch (after its save, as VMS) and the chest gas trap. Deviations (`docs/BACKLOG.md` "Faithful breath: what the limited version leaves out"): no radius-2 ball (other monsters, floor items, doors), no pack damage, no lightning/acid/poison resistance items, Moria8's Hold texts, Hold marks recall bit 0 | explicit maintainer direction 2026-11-08 ("so can we correct the dragon balance here to be faithful to upstream?", then "do your limited but faithful version"); pinned VMS `creature.inc` 860-1060, `moria.inc` 1683-1760, `misc.inc` `player_saves`; C64 `test_monster_magic.s` t6, t9, t10, t28-t37, `test_monster_ai.s` t14 | the percent cast chance; fire-only breath, HP / 3 capped at 255, resisted by fire resistance whatever the breather; Hold Person not cast (MON-021) |
| MON-026 | Accepted | Project maintainer, 2026-11-10 ("fix it": two Rings of Speed did nothing more than one) | Player speed steps add, as VMS and Umoria add every speed bonus: each Ring of Speed worn (`EQUIP_RING`, `EQUIP_RING2`), Boots of Speed (`+1`) / Boots of Slowness (`-1`) on `EQUIP_FEET`, and an active haste (`+1`) / slow (`-1`) timer combine into `mat_fast` (`-2..4`, computed once per AI tick). Each monster's cadence (base `cr_speed` with its `MX_SPEED_CNT` adjustment, 0-2) less `mat_fast` is `s` (`-4..4`): two moves at `s >= 2` (the double-move cap stays), one at 1, and at `s <= 0` one move when `mat_turn_mod[max(s + 3, 0)] == 0` over `{mod 5, mod 4, mod 3, mod 2}` — i.e., every `2 - s` turns for `-3 <= s <= 0` (`Umoria monsterMovementRate`), clamped to `mod 5` (every 5th turn) at `s = -4` (`+4` player speed vs speed-0 monster, preventing OOB `mat_turn_mod` reads), from the 16-bit turn (256 = 1 mod 3 and 5). Per tick, never stored in `cr_speed` or `MX_SPEED_CNT` | oracle Umoria `playerChangeSpeed` (`player.cpp:370`), `monsterMovementRate` (`monster.cpp:77`), ring `misc_use = 1` (`treasure.cpp:466`); VMS `moria.inc:141`; C64 `test_monster_ai.s` 36-40 (single steps unchanged), 69 (two rings: every 3rd turn, high byte counted), 70 (haste and two rings: every 4th), 71 (`+4` player speed via two rings + Boots of Speed + haste vs speed-0 monster: `s = -4` clamped to `mod 5` / every 5th turn) | MON-008 (no stacking; floor every other turn) |
| MON-027 | Accepted | Project maintainer, 2026-11-11 ("obviously if we can't resist anything then this is a game misbalance ... proceed"; options chosen: spelled-out names, faithful VMS rarity, armour + Defender + damage first) | Lightning and acid resistance as pinned VMS Moria: armour suffixes from `magic_treasure` (`misc.inc`): body armour and shields that rolled a positive magic bonus get one with `magik(trunc(min(15 + dlvl, 70) / 6))`, then `randint(9)`: (Resist) fire, cold, acid and lightning + 5 to-AC, (Resist Acid), (Resist Fire) x2, (Resist Cold) x2, (Resist Lightning) x3 (`roll_armour_ego`, ego IDs 9-13). Worn on the weapon, body or shield slot, an ego gives `pf_ego_table` flags (`PFLAG_RESIST_ACID`, `PFLAG_RESIST_LIGHT` new): Defender the four resistances, Free Action and See Invisible; Holy Avenger See Invisible. Breath (`monster_cast_breath`): lightning `div 3` resisted (`light_dam`); acid `div 2` for a piece that took it, `div 3` resisted, `div 4` both (`acid_dam`, also the acid touch `mon_atk_effect_acid`); a Resist or Resist Acid piece chosen by `minus_ac` is not damaged ("Your <item> resists damage!") but counts as taking it. Gas has no resistance, as upstream. Deviations: no store stocks an ego item and egos do not change prices (as the weapon egos); Defender regeneration, feather fall and stealth not modelled; the lightning touch stays a plain hit; Crown of the Magi, Ring of Lordly Protection (Acid) and Amulet of Resist Acid not yet implemented | explicit maintainer direction 2026-11-11 after clvl 40 Priests died to unresistable Ancient Multi-Hued Dragon breath; pinned VMS `misc.inc` `magic_treasure`, `moria.inc` `minus_ac`, `light_dam`, `acid_dam`; C64 `test_monster_magic.s` t38-t42, `test_monster_attack.s` t47-t49, `test_ego.s` t13-t19 | MON-015 and MON-025 "no lightning/acid resistance" deviations |
| MON-028 | Accepted | Project maintainer, 2026-11-11 ("proceed" on the proposed elemental touches) | The fire, cold and lightning touches (VMS `creature.inc` `make_attack` 5, 7, 8; Umoria identical): `ATK_FIRE`/`ATK_COLD`/`ATK_LIGHT` (5, 7, 8) from `tools/parse_creatures.py` and `tools/build_catalog.py`, to-hit base `10`, the effect message, full dice with no AC reduction, then `fire_dam` / `cold_dam` / `light_dam`: `div 3` for the lasting resistance, fire and cold `div 3` again for the timer (`mm_element_divisor`, `core/element_resist.s`, shared with the breath; `mat_div_dmg` shared with the acid touch). Deviations: Moria8's short messages ("burns you.", "freezes you.", "shocks you.") in place of VMS's "You are enveloped in flames!" and the others; no pack item burns or shatters. The catalog's availability rule now admits Crystal Ooze, Grey Ooze and the Giant Red and White Ant Lions; the attack-slot ranking (MON-020) counts the touches as effects | explicit maintainer direction 2026-11-11; pinned VMS `creature.inc:305-311, 432-447`, `moria.inc` `fire_dam`, `cold_dam`, `light_dam`; C64 `test_monster_attack.s` t50-t53 through production `mon_atk_effect_dispatch` | fire, cold and lightning touches mapped to `ATK_NORMAL` |
| MON-029 | Accepted | Project maintainer, 2026-11-11 ("proceed" on the crown, ring, amulet and lightning touch plan) | The pinned VMS resistance jewellery: Rings of Lordly Protection (Fire), (Acid) and (Cold) (`#146`-`#148`; VMS `#147`-`#149`: the resistance and `+5` AC, 1,200 gp, weight 2) and the Amulet of Resist Acid (`#149`; VMS `#171`, 300 gp, weight 3). `player_recalc_pflags_equipment` reads both ring hands through `pf_lordly_table` and the amulet slot; the AC is the rings' base AC. Deviations: VMS level 50 for the rings and 24 for the amulet are kept within Moria8's 12-level item scale (`pit_sorted`: the rings at the top, the amulet at 8); the `+5` is base AC, not to-AC, so Enchant Armor does not reach it; the Magic Shop and Black Market stock all four by category, as every Moria8 ring and amulet (`store_pick_item`), where VMS's Magic Shop list has the amulet alone (`values.inc` store item 54) | explicit maintainer direction 2026-11-11; pinned VMS `values.inc:1048-1053, 1096-1097`; C64 `test_ego.s` t20, `test_item_desc.s`, C128 `test_item_desc128.s` | the "not yet implemented" Lordly (Acid) and Amulet of Resist Acid deviation of MON-027 |
| MON-030 | Accepted | Project maintainer, 2026-11-11 ("proceed" on the crown plan; options chosen: "of the Magi" only, no save-format bump, the VMS flags) | The pinned VMS crowns and their Magi ego: Silver, Golden and Jewel Encrusted Crowns (`#150`-`#152`; VMS `#100`-`#102`: AC 0, 250/500/1,000 gp, weight 20/30/40) and `EGO_MAGI = 14` (`" of the Magi"`). `roll_armour_ego` gives an enchanted crown VMS's `magik(special)`, then `randint(6) = 3`: the Magi with `p1 = randint(3)` (`roll_crown_ego`). Worn on the head (`PflagsFromEgos` now runs weapon to head), it gives `PFLAG_SEE_INVIS`, `PFLAG_RESIST_FIRE`, `PFLAG_RESIST_ACID`, `PFLAG_RESIST_COLD` (VMS `%X'01380008'`; Umoria adds lightning) and INT `+p1` through the new shared `equip_stat_index` (`player_calc_stats` and every `player_adjust_equipment_stat`). The description shows a nonzero armour `p1` as `(+p1)` after the AC, as VMS `(%P1)`. Acid spares the crown as it spares (Resist) and (Resist Acid) pieces (`mon_atk_effect_acid`; VMS `minus_ac` tests `TR_RES_ACID`). A load marks every fixed-description item known (`load_read_known_items`), so the crowns and the Amulet of Resist Acid are known to a character saved before they existed. Deviations: the other crown egos (Might, Lordliness, Beauty, Seeing, Regeneration) and the helm egos are not modelled; VMS levels 44-50 sit at the top of Moria8's 12-level item scale (11, 12, 12); egos change no price; the stores stock crowns as any helm, never with an ego | explicit maintainer direction 2026-11-11; pinned VMS `misc.inc` `magic_treasure` (helms, subval 6-8), `values.inc:954-959`; C64 `test_ego.s` t21-t23, `test_item_desc.s` t12 and the every-name tables (C64 and C128) | the "Crown of the Magi not yet implemented" deviation of MON-027 |
| MON-031 | Accepted | Project maintainer, 2026-11-11 ("all 4 pls": add the missing VMS wands, Drain Life first) | The pinned VMS attack wands Moria8 lacked: Fire Bolts (`#153`, a `6d8` bolt, VMS `wands.inc` case 4), Drain Life (`#154`, `50` to the first creature in line that is not undead, `spells.inc` `drain_life`; an undead one stops it unharmed and unwoken), Lightning Balls (`#155`, a `24` ball, case 19) and Acid Balls (`#156`, a `40` ball, case 23). VMS cost and weight; levels 8, 11, 9, 11 on Moria8's 12-level scale (VMS 30, 50, 35, 48). They are the last item IDs and route through the Phase 3 wand dispatch (`core/scroll_effects_p3.s`: the C128 table, a range check elsewhere); Drain Life and the compact ports' Fire Bolts run `core/wand_bolt_entries.s`. Deviations, as Moria8's other wands: `[5,8]` charges, not VMS's per-wand rolls; elements unmodelled (no monster immunity to the ball's element); the hit message is the bolt's ("Your spell hits ..."), not VMS's "screams in agony"; the Magic Shop may stock them, as it stocks any wand by category. The Umoria figures FEATURE_MAP quoted (`9d8`, `75`, `32`, `60`) are not the oracle | explicit maintainer direction 2026-11-11; pinned VMS `wands.inc:52-108`, `spells.inc:891-925`, `values.inc:1300-1339`; C64 `test_scroll_p3.s` t17-t19 through the production dispatch, real `eff_bolt` and `eff_wand_drain_life` (living 200 to 150, undead 200 stays 200); `test_item_desc.s` (C64 and C128) names | "Wand of Fire Bolts / Drain Life / Lightning Balls / Acid Balls: Missing" (FEATURE_MAP 8.3.2) |
| MON-032 | Accepted | Project maintainer, 2026-11-16 (Phase 5 full VMS monster parity) | Widens species records to `29` SoA fields (`279/279` playable creatures across all 7 ports + 5 cartridges) with a full **4-slot melee attack loop** (`cr_atk0..3_*`), **all 19 VMS `ADESC_*` verbs** (`0..19`, packed in 5 bits across `sides[7:4]:type[7]` and decoded by `mon_atk_verb_to_ptr2`), and **all 24 VMS `ATK_*` effects** (`core/monster_attack.s`, `core/monster_attack_effects.s`): `mon_atk_calc_tohit` computes signed `base_to_hit[atk_type] + 3 * cr_level` clamped to `[0, 255]` (`ATK_LOSE_STR` `bth = -3`; `ATK_STEAL_GOLD` `12` and `ATK_STEAL_ITEM` `13` roll against `zp_player_lvl` instead of player AC per VMS `creature.inc:318-323`). AC damage reduction `dmg -= (AC * dmg) / 200` applies to `ATK_NORMAL` (`1`), `ATK_BLIND` (`10`), and all five stat drains (`ATK_LOSE_STR/DEX/CON/INT/WIS`: `2, 15..18`), whereas `ATK_CONFUSE` (`3`), `ATK_FEAR` (`4`), `ATK_PARALYZE` (`11`), `ATK_POISON` (`14`), `ATK_CORRODE` (`9`, `minus_ac` else `+1d8` HP), and elemental touches (`5..8`) apply unreduced dice (`0` HP for `12, 13, 19..24`). Extended effects match VMS `creature.inc`: `ATK_LOSE_STR` (`50%` roll when unsustained) & `ATK_LOSE_DEX/CON/INT/WIS` (`100%` when unsustained, `decrement_stat` + `mae_recalc_hp_combat`); `ATK_STEAL_GOLD/ITEM` (`randint(124) < DEX` anti-theft when unparalyzed, `au/10 + randint(25)` 24-bit gold theft or uniform pack theft, `50%` blink); `ATK_LOSE_EXP` (`2 * (XP / 100) + dice` 24-bit XP drain + multi-level drop recalc); `ATK_DISENCHANT` (random worn slot in `{WEAPON, BODY, SHIELD, HEAD, HANDS, FEET, CLOAK}`, `-randint(2)` floored at `0`); `ATK_EAT_FOOD` (1 pack food), `ATK_EAT_LIGHT` (`250 + randint(250)` lamp fuel), and `ATK_EAT_CHARGES` (drain charges from 1 charged pack wand/staff and heal monster `cr_level * p1` HP). | Phase 5 design (`docs/MEMORY_REDESIGN_PLAN.md`, `docs/MONSTER_CATALOG_DESIGN.md`); pinned VMS `creature.inc:280-660`, `moria.inc:1672`; C64 `test_monster_attack.s`, `test_monster_attack2.s` | MON-020 2-attack cap; unmapped `ATK_*` types and `ADESC_*` verbs |
| MON-033 | Accepted | Project maintainer, 2026-11-16 (Phase 5 monster magic parity) | Adds `cr_spell_flags2` bits `0..4` (`MSF2_BLINK $01`, `MSF2_TELE_SELF $02`, `MSF2_SUMMON_UNDEAD $04`, `MSF2_SLOW $08`, `MSF2_DRAIN_MANA $10`) in `core/monster_magic.s`: `monster_can_cast` requires `(cr_spell_chance & $0F) != 0` and at least one bit in `MSF | MSF2[4:0] | MS_HOLD`; `monster_pick_spell` chooses uniformly across all set `MSF + MSF2[4:0] + MS_HOLD` bits (with Multi-Hued's 5 breaths counted as 5). `MSF2_BLINK` (`range 10`) and `MSF2_TELE_SELF` (`range 60`) self-teleport the caster (`FLAG_OCCUPIED` moved, never onto the player); `MSF2_SUMMON_UNDEAD` picks uniformly from the 35-byte `cat_undead` bitmap (`catalog_index.s`); `MSF2_SLOW` checks `PFLAG_FREE_ACT` + `wis_adj + lev` save, else slows `zp_eff_speed` by `randint(5) + 3` (`+2` stack, clamped at `-128`); `MSF2_DRAIN_MANA` drains `min(MP, floor((rng_range(lev)+1)/2) + 1)` MP and heals the caster `6 * r1` HP (clamped at `$7FFF`). All 18 VMS `CSPELL` bits are now implemented (wounds consolidated into 3d8/8d8). | pinned VMS `creature.inc:860-1060`, `misc.inc:650-690`; C64 `test_monster_magic.s`, `test_monster_magic3.s` | MON-021 unmapped `MSF2_*` spells |
| MON-034 | Accepted | Project maintainer, 2026-11-16 (Phase 5 `cr_cdefense` & `CD_INVISIBLE`) | Adds `cr_cdefense` (`CD_FROST $01`, `CD_FIRE $02`, `CD_POISON $04`, `CD_ACID $08`, `CD_LIGHT $10`, `CD_STONE $20`, `CD_NO_SLEEP $40`, `CD_INVISIBLE $80`): (1) `eff_scale_elem_damage` (`core/spell_effects.s`) and `ball_target_damage` double (`2x`) elemental bolt/ball damage on matching `CD_*` and quarter (`/4`) damage when non-vulnerable and the target breathes that element (or `MS_BREATH_ALL`); (2) `ego_apply_damage` (`core/ego_items.s`) scales `cmb_damage` by `1.5x` (`trunc(dmg * 1.5)`) before `+2d4` for `EGO_FLAME_TONGUE` / `EGO_AMMO_FIRE` vs `CD_FIRE` and `EGO_FROST_BRAND` vs `CD_FROST`; (3) `eff_light_room` deals `2d8` + wake to `CD_LIGHT` creatures in the lit box, and `eff_wall_to_mud` deals `100` damage to `CD_STONE` creatures (dug wall occupant or traced ray); (4) `CD_NO_SLEEP` grants immunity to Sleep I/II/III, Sanctuary, Scroll/Staff/Wand of Sleep, Confuse Monster spell/wand, Blind Creature prayer, and melee confusion-on-hit (`combat.s`, `eff_item_p1.s`, `player_magic_feedback.s`); (5) `muvo_apply_visible` (`core/monster.s`) withholds `MF_VISIBLE` from `CD_INVISIBLE` creatures unless `(player_pflags & PFLAG_SEE_INVIS) | zp_eff_see_inv | zp_eff_invis` is nonzero (`MF_DETECTED` still reveals under Detect Monsters). | pinned VMS `spells.inc`, `moria.inc` (`tot_dam`, `light_room`, `wall_to_mud`), `creature.inc` (`update_mon`); C64 `test_monster_magic3.s`, `test_monster_ai2.s` | MON-006 open `CD_NO_SLEEP`; unmodelled elemental vuln/resist & `CD_INVISIBLE` |
| MON-035 | Accepted | Project maintainer, 2026-11-16 (Phase 5 `CM2_*` movement & 15-field recall) | Adds `cr_spell_flags2` bits `5..7` in `monster_try_step` (`core/monster_ai.s`) and 15-field `/` recall (`core/ui_recall.s`): (1) `CM2_PHASE ($20)` allows dungeon (`zp_player_dlvl > 0`) creatures to step onto non-walkable interior walls, veins, rubble, and closed/locked/jammed/secret doors without altering tile/door bytes (outer permanent boundary walls `x==0`, `x==MAP_COLS-1`, `y==0`, `y==MAP_ROWS-1` and town `dlvl == 0` buildings remain blocked); (2) `CM2_EATS_OTHER ($40)` lets a mover override an occupied tile when the target is not a win creature (`catalog_slot_is_balrog` / `cr_level >= 100`) and 16-bit `cr_xp[mover] >= cr_xp[target]`, calling `monster_remove` (no player XP or loot) and setting `mat_force_new_dirty` if the eaten target was `MF_VISIBLE | MF_DETECTED`; (3) `CM2_PICKS_UP ($80)` removes a non-gold floor item (`ICAT_GOLD` excluded; `glyph_*` lives in its own table and is unaffected) via `floor_item_remove` + `inc mat_force_new_dirty`; (4) `/` recall (`ui_recall_display`) renders all 15 VMS recall fields across all 279 species on all 7 ports + 5 cartridges. | pinned VMS `creature.inc:770-835` (`make_move`); C64 `test_monster_ai2.s`, `test_score.s` | walls/occupants always blocking; 2-attack tier-only recall |
| MON-036 | Accepted | Project maintainer, 2026-11-17 (VMS theft messages, gold refresh, `subval >= 512` stack rule, & `teleport_away` range) | `mae_steal` (`core/monster_attack_effects.s`, `ATK_STEAL_GOLD = 12` & `ATK_STEAL_ITEM = 13`) matches pinned VMS Moria 4.8 `creature.inc:483-520`, `spells.inc:1202-1230` (`teleport_away`), and `misc.inc:1419-1479, 2526-2548` (`inven_destroy`): (1) prints all five VMS messages via 5-bit packed `mae_print_steal_msg` (`"You quickly protect your money pouch!"` on gold dodge, `"Your purse feels lighter."` + immediate `status_mark_dirty` / `status_draw` gold refresh on gold theft, `"You grab hold of your backpack!"` on item dodge, `"Your backpack feels lighter."` when a pack item is stolen, and `"There is a puff of smoke!"` on the `50%` `randint(2) = 1` blink roll); (2) removes the entire carried slot (`inv_remove_item`) for VMS `subval >= 512` group-stacked kinds (`tval in [10..13]`: `Arrow`, `Bolt`, `Rock`, `Iron Shot`, `Iron Spike`) and one unit (`inv_consume_one`) for `subval < 512` kinds (food, potions, scrolls, oil flasks, torches, singletons); (3) `mae_find_blink_tile` teleports the thief to a uniform random in-bounds free floor square (excluding the player's square) within `+-20` (`max_sight`) of `(zp_mon_x, zp_mon_y)`, widening `dis += 5` after every `10` failed tries (`ctr > 9`), clearing `MF_VISIBLE`, moving `FLAG_OCCUPIED`, and incrementing `zp_dirty_count`. Deviation: an empty pack on an undodged `ATK_STEAL_ITEM` steals nothing and omits `"Your backpack feels lighter."` (as Umoria fixes VMS's `randint(0)`). | explicit maintainer bug report 2026-11-17; pinned VMS `creature.inc:483-520`, `spells.inc:1202-1230`, `misc.inc:1419-1479, 2526-2548`; C64 `test_monster_attack2.s` | silent `mae_steal`, full-map `find_random_floor` thief blink, and 1-unit `inv_consume_one` on `tval 10..13` stacks in MON-032 |
| MON-037 | Accepted | Project maintainer, 2026-11-18 (VMS per-stat & XP-drain melee messages) | `mae_lose_str` (`ATK_LOSE_STR = 2`), `mae_lose_stat` (`ATK_LOSE_DEX..WIS = 15..18`), and `mae_lose_exp` (`ATK_LOSE_EXP = 19`) in `core/monster_attack_effects.s` print the six distinct pinned VMS Moria 4.8 `creature.inc` messages via `mae_print_steal_msg` (`5..10` in 5-bit `mae_bits`/`mae_tail`): `"You feel weaker."` (`STR`, `creature.inc:398`), `"You feel more clumsy."` (`DEX`, `:535`), `"Your health is damaged!"` (`CON`, `:548`), `"You feel your memories fading..."` (`INT`, `:564`), `"Your wisdom is drained."` (`WIS`, `:577`), and `"You feel your life draining away!"` (`EXP`, `:584`). Deviation: sustained hits retain Moria8's shared `"You are unaffected."` (`HSTR_CHEST_UNAFFECTED`). | explicit maintainer bug report 2026-11-18 (Bug C); pinned VMS `creature.inc:392-403, 528-588`; C64 `test_monster_attack2.s` t33 | shared `"You feel weakened."` (`HSTR_DF_CON_DRAIN`) across all five monster stat drains and XP loss |
| MON-038 | Accepted | Project maintainer, 2026-11-19 (GitHub Issue #21: monster sighting, hostile-action, door-burst & melee disturbance; companion to TRN-014) | Monster disturbance feeds the unified `zp_disturb` (`$69`) latch without relying on render-only `turn_scene_dirty`: (1) `muvo_apply_visible` (`core/monster.s`) executes `inc zp_disturb` beside `player_search_mode_off` on every `MF_VISIBLE` `0 -> 1` sighting; town creatures start `MF_VISIBLE` on town entry so resting in town does not immediately false-trigger on pre-existing townies, and unseen `CD_INVISIBLE` creatures return before `!muvo_can_see` (TRN-012) without setting `MF_VISIBLE` or disturbing. (2) `core/monster_ai.s` tags `mat_action_dirty` bit 1 (`$02`) for hostile actions (`$83` on hostile moves; `$03` on spells, breeder spawns, door opens via `mts_write_open`, and glyph breaks) while leaving bit 1 clear (`$81`) for unprovoked townie wandering (`!mpo_not_town` bypass); at `!mpo_done` (after the breed check), if `mat_action_dirty != 0`, `(mat_action_dirty & $02) != 0 && (zp_mon_flags & MF_VISIBLE) != 0` executes `inc zp_disturb`. This catches all visible hostile moves (including inside `<= zp_light_radius + 1` where local redraws leave `turn_scene_dirty == 0`), silent `MSF2_BLINK`/`MSF2_TELE_SELF`, and visible breeding, while keeping sleeping monsters (MON-005), unprovoked wandering townies, and detected-only monsters behind walls (`MF_DETECTED` without `MF_VISIBLE`) quiet. (3) Door bursts (`!mts_stuck` and `!mts_bash`, extending MON-009) print `HSTR_MAT_DOOR_BURST` unconditionally and execute `inc zp_disturb` mid-turn via a shared `!mts_bash_set` tail (net `-1 B`); plain door opens (`!mts_open_plain`) add no extra door-tile LOS check, matching upstream VMS/Umoria (`muvo_apply_visible` catches the opener becoming visible). (4) Monster melee rounds (`core/monster_attack.s` right after `!map_has_atk0:`, past the `ATK_NONE` early exit) execute `inc zp_disturb` (including repelled melee rounds). | explicit maintainer direction 2026-11-19 (GitHub Issue #21); pinned VMS Moria `source/include/creature.inc:42-55, 697-757, 1191-1202` and pinned Umoria `src/monster.cpp:54-60, 477-540, 610-613`; C64 `test_monster_ai2.s` t16-t20, t23 and `test_monster_attack.s` t55 | MON-009 post-turn message-only door-burst disturbance; render-coupled `turn_scene_dirty` hostile-activity heuristic |
| MON-039 | Accepted | Project maintainer, 2026-11-20 ("address all your findings, including the 2 game deviations": the playtest audit found no ambient spawning) | Ambient monster generation follows pinned VMS Moria `moria.inc` (`randint(max_malloc_chance) = 1` -> `alloc_monster(floor_set, 1, max_sight, false)`, `max_malloc_chance = 160`, `max_sight = 20`): each consumed turn `turn_post_action` rolls `rng_range(CAT_MALLOC_CHANCE)` (`0..159`, mask-and-reject, unbiased) before `monster_ai_tick`; a `0` places one creature through `catalog_place_wanderer` / `catalog_place_far` (shared with the win creature, MON placement at generation): up to `32` `find_monster_floor` squares, the first with Chebyshev distance `> CAT_MAX_SIGHT` from the player; the creature is `pick_creature_type`'s (the level's VMS `alloc_monster` mix with its `mon_nasty` roll) or, in town, one of the `8` townspeople; `monster_spawn_one` then `monster_wake` (`MF_AWAKE`, `MX_SLEEP_CUR = 0`: VMS `slp = false`), and `zp_dirty_count` is raised. Deviations: Chebyshev distance (Moria8's monster metric) where VMS uses `max + min/2`; at most `32` placement tries where VMS loops until it finds a square; no spawn while `zp_mon_count >= MAX_MONSTERS - CAT_GEN_RESERVE` (`26`), keeping the rows level generation leaves to breeders and summons (VMS allows `max_malloc = 101`); the roll is per Moria8 consumed turn (`turn_post_action`), Umoria and VMS per game turn. Never written to saves (no new state). | pinned VMS `moria.inc:3633-3635`, `misc.inc:577-609`, `constants.inc:108-110`; pinned Umoria `game_run.cpp:2331-2333`; CX16 `harness_smoke.py monster_catalog` (`town_wanderer_*`, `wanderer_*`, `turn_wanderer*`: production `catalog_place_wanderer` and `turn_post_action`; `turn_wanderer` fails with the roll removed); C64 `catalog_spawn_product_smoke` / `_reu_smoke` (production `tramp_catalog_place_wanderer` through the `$F000` runtime) | `docs/FEATURE_MAP.md` row naming a `monster_spawn_wanderer` that never existed |
| MON-040 | Accepted | Project maintainer, 2026-11-20 (same direction) | Summoned creatures follow pinned VMS Moria `misc.inc` `summon_monster`: levels `1..min(dun_level + mon$summon_adj, max_mons_level)` (`mon$summon_adj = 2`), uniform over the catalog species of those levels, with no `mon_nasty` out-of-depth roll. `pick_summon_creature_type` (`core/monster_catalog.s`) sets `cat_level_adj = CAT_SUMMON_ADJ` for `cat_pick_id` (`pick_creature_type` sets `0`; `adc` with carry-out saturation to `CATALOG_MAX_MONS_LEVEL`); callers are the `MSF_SUMMON` spell (`monster_cast_summon`), the Summon Monster scroll and staff (`ep1_summon_many`, `ep1_summon_one`) and the summoning trap and chest (`chest_run_pending_summons`). The unit-test tier picker (`core/monster.s`, non-catalog) applies the same `+2` limit. Out of scope and unchanged: summon undead (`cat_undead` / `ep1_pick_undead_type`), polymorph (VMS `poly_monster` picks from all levels), Moria8 pits and nests, and the wizard summon | pinned VMS `misc.inc:612-645`, `constants.inc:120`, callers `creature.inc:991`, `scrolls.inc:152`, `staffs.inc:52`, `moria.inc:1889, 2661`; C64 `test_monster_magic3.s` t21-t22 (production `monster_pick_spell` -> `monster_cast_summon` and `ep1_summon_many`; both fail with `pick_creature_type`); CX16 `harness_smoke.py monster_catalog` `summon_cap` / `summon_adj` (200 production picks at DL16; fail with the adjustment removed) | summons picked from `1..dun_level` with the out-of-depth roll |
| MON-041 | Accepted | Project maintainer, 2026-11-20 ("a Moria8 vs VMS difference is usually an early accident: fix it") | Summons, breeding and clones follow pinned VMS Moria: (1) counts: Scroll of Summon Monster `randint(3)` (`scrolls.inc:147-153`), Scroll of Summon Undead `randint(3)` (`scrolls.inc:329-335`), Staff of Summoning `randint(4)` (`staffs.inc:46-52`); the summoning rune `2 + randint(3)` (`moria.inc:1885`) and the chest trap's `3` (`moria.inc:2655`) were already VMS. (2) Summon Undead (scroll and `MSF2_SUMMON_UNDEAD`) picks any undead of the catalog through one `pick_undead_creature_type` (`misc.inc:648-670` `summon_undead`; MON-033's `cat_undead[35]` pick). (3) A monster's summons land beside the player (`creature.inc:986-1001`: `summon_monster(char_row, char_col, ..)`; `find_adjacent_empty_player`), not beside the caster. (4) Every summon, clone (`spells.inc:1192`) and breeder's child (`creature.inc:1080`) is placed awake: `monster_spawn_awake` = `monster_spawn_one` + `monster_wake` (`slp = false`: `csleep := 0`, `misc.inc:529-534`). (5) In town, summons pick townspeople (`pick_creature_type` / `pick_summon_creature_type` return one of the 8 town rows: VMS `randint(m_level[0])`). | pinned VMS sources cited; C64 `test_monster_magic3.s` t23-t26, `test_monster_ai.s` t61 (clones awake); all fail at 312cd3c | scroll `1`, staff `2..4`, undead scroll `2` from the level's mix, summons beside the caster and asleep, clones asleep |
| MON-042 | Accepted | Project maintainer, 2026-11-20 (same direction) | Polymorph follows pinned VMS `spells.inc`: `poly_monster` (Wand of Polymorph `wands.inc:71`, Polymorph Other `magic.inc:72-73`) changes the first monster along the bolt when `randint(max_mons_level) > level` (`rng_range(40) >= cr_level`), else prints "The `<name>` is unaffected." (`combat_msg_monster_suffix`); `mass_poly` (Staff of Mass Polymorph, `staffs.inc:72`) changes every creature with `cdis < max_sight` except the win creatures (`cdefense` bit 31: Moria8 `cr_level > MONS_LEVEL_MAX`), seen or not, with no roll. The new creature is `randint(m_level[max_mons_level]) + m_level[0]`: any level `1..40` (`pick_any_creature_type`, `cat_level_adj = $ff`), placed awake on the same square, in town as well. One body (`core/monster_polymorph.s` `PolymorphResist`/`PolymorphReplace`) is emitted in the item and spell overlays. Adaptation: `cdis` is Chebyshev | pinned VMS `spells.inc:1113-1147, 1397-1421`; C64 `test_monster_magic3.s` t27-t28; CX16 `harness_smoke.py monster_catalog` `poly_any_level`; t27-t28 fail at 312cd3c | polymorph always succeeding (the Balrog silently refused), a depth-limited replacement placed asleep, Mass Polymorph on seen monsters only, none in town |
| MON-043 | Accepted | Project maintainer, 2026-11-23 ("make this act like VMS moria") | Monsters never flee at low HP: after confusion and spell/random-move checks, `monster_process_one` calls `monster_move_toward` unconditionally (matching pinned VMS Moria `mon_move` and Umoria `monsterMove`/`monsterDoMove`, where Turn Undead retreating in `monsterMoveUndead` is separate and out of scope). Removed `monster_check_flee`, `monster_move_away`, `mat_fleeing` (and its melee suppression in `monster_try_step`), and the spawn-time `HP / 4` flee threshold in `monster_spawn_one`. Kept the 12-byte monster record (`MONSTER_ENTRY_SIZE = 12`) and Save Format V2 (`$22`) intact by leaving bytes 10–11 as zeroed, unused `MX_RESERVED_0`/`MX_RESERVED_1` | explicit maintainer direction 2026-11-23; pinned VMS `source/include/creature.inc:1061-1135` (`mon_move`); pinned Umoria `src/monster.cpp:1101-1119, 1167-1232` (`monsterDoMove`, `monsterMove`); C64 `test_monster_ai.s` t17–t18 (fail pre-fix) and `test_monster_ai2.s` t6 through production `monster_ai_tick`; 7-port `make -j7 -O test` and `make playtest-gate` | commit `74700dc` (2026-02-15, `R3.4` low-HP fleeing) and MON-024's flee-threshold note |

## Conditional Verification Matrix

Select rows for the transitions changed and document omitted relevant rows.

| Change | Required cases |
| --- | --- |
| Spawn/sleep arithmetic | zero, ordinary, maximum source value; overflow and monotonicity |
| Wake eligibility | inside, at, and outside awareness boundary; visible/not visible; rest state if relevant |
| Wake transition | counter remains positive, reaches zero, underflows; group and explicit paths if affected |
| Spell/attack state | success, resistance/immunity if represented, empty slot, last slot |
| Visibility/detection | visible-only, detected-only, neither, LOS blocked, production targeting |
| Shared implementation | affected C64, C128, and Plus/4 production paths or explicit exemption |

Test-local copies prove harness behavior only. At least one regression test must
execute the changed production routine through its real dispatch/overlay path.

## Executable Enforcement

| Invariant | Current gate | Command/status |
| --- | --- | --- |
| Basic AI wake transitions | `platforms/commodore/c64/tests/test_monster_ai.s` | `TEST_FILTER='monster_ai' make test64` |
| Compact wake-pressure buckets and spawn-to-AI flow | `platforms/commodore/c64/tests/test_monster_ai.s` | deterministic distances 0-8/20 and production spawn cases at 1/6/8; C128/Plus4 have no dedicated ordinary-wake harness and rely on identical shared source plus product layout gates |
| Breath by element, damage divisor, resistance, acid armour, gas poison, no cap; Hold Person with Free Action, its timer and stacking; the Multi-Hued choice of spells (MON-025) | C64 `test_monster_magic.s` t28-t37 through production `monster_cast_breath`, `monster_cast_hold` and `monster_pick_spell` | `TEST_FILTER='monster_magic' make test64`; statistical bands for the element mix (60 breaths) and the breath share (40-60 of 60 picks); C128, Plus/4, Apple IIe, CX16, Atari and BBC compile the identical shared source |
| Fear attack save, duration, stacking and saturation (MON-012) | `platforms/commodore/c64/tests/test_monster_attack.s` t11, t14-t17 (production `mon_atk_effect_fear`, `player_saving_throw`) | `TEST_FILTER='monster_attack' make test64`; outcomes of the random save are asserted over 30 attempts |
| Orb of Draining doubles against evil creatures (`eff_ball_holy` sets `ball_harm = CF_EVIL`; `ball_target_damage` doubles each creature whose `cr_mflags` match, VMS `spells.inc` `fire_ball`, Umoria `HolyOrb` `CD_EVIL`); other balls do plain damage | C64 `test_orb_of_draining_prayer.s` t4 (evil: 50 - 2 x 20 = 10, `ball_harm` clear after; fails without the doubling), t5 (not evil: 30), t6 (`eff_ball` at evil: 30); static contract `orb_of_draining_holy_orb_contract` (`ped_s17` jumps to `eff_ball_holy`) | `TEST_FILTER='orb_of_draining' make test64`; other platforms compile the identical shared code |
| Turn Undead (prayer and Holy Word, `eff_turn_undead_core`): a visible undead is turned (`MX_CONFUSE = clvl`, woken) when `clvl + 1 > level` with no roll, else only on `randint(5) = 1` (VMS `spells.inc` `turn_undead`; Umoria `spells.cpp` `spellTurnUndead`) | C64 `test_turn_undead_prayer.s` t1, t4 (level = clvl turned, no roll; level = clvl + 1 resists a roll of 1), t5 (level 80 turned on `rng_range(5) = 0`, resists on 4); t4-t5 fail on the pre-2026-11-12 `rng_range(40) >= level`; C128 `test_turn_undead_prayer128.s` tests 4-5 likewise | `TEST_FILTER='turn_undead_prayer' make test64`; `turn_undead_prayer128` in `make test128`; other platforms compile the identical shared code |
| Confusion and poison attack durations: a new confusion lasts `randint(level) + 3` and an existing one gains 3 (VMS `creature.inc:404-417`; Umoria `monster.cpp:1563-1576`); poison adds `randint(level) + 5`, new or not (VMS `creature.inc:521-527`; Umoria `monster.cpp:1665-1669`); `randint(N)` is `1..N`, so Moria8 adds `rng_range(level) + 4` / `+ 6` | C64 `test_monster_attack.s` t31-t35 through production `mon_atk_effect_dispatch` (128 calls per case; both ends of each range asserted; t31, t33, t34 fail on the pre-2026-11-01 `+ 3` / `+ 5`) | `TEST_FILTER='monster_attack' make test64`; other platforms compile the identical shared code |
| Acid armour damage (MON-015): halving with integer division, to-AC drop and recalculation, worn-out piece, nothing worn, the last slot, random choice among worn pieces | C64 `test_monster_attack.s` t18-t22 through production `mon_atk_effect_acid` | `TEST_FILTER='monster_attack' make test64`; other platforms compile the identical shared code |
| Random movement rolls (MON-013) | `platforms/commodore/c64/tests/test_monster_ai.s` t59 through production `monster_ai_tick` | `TEST_FILTER='monster_ai' make test64`; statistical band (4-32 of 40) |
| Monster treasure drops (MON-014): kill staging through `eff_kill_monster`/`combat_note_kill`, carriers only, full queue, queue fulfilment with a stale chest latch, overlay-load failure, 4d3 count, reset with the monster table; the drop handoff runs before `turn_post_action` | C64 `test_chest_loot.s` t10-t16; static contracts `monster_drops_before_turn_contract`, `monster_drops_staged_on_kill_contract` | `TEST_FILTER='chest_loot|monster_drops' make test64`; melee and bash reach the same `combat_note_kill` (not separately runtime-tested); other platforms compile the identical shared code |
| C64 Detect Evil behavior | `platforms/commodore/c64/tests/test_detect_evil.s` | `TEST_FILTER='detect_evil' make test64`; does not prove timed Detect Monsters lifecycle |
| C128 detection dispatch/effect pieces | `platforms/commodore/c128/tests/test_detect_monsters128.s`, `test_detect_evil128.s` use test-local stubs/helpers | `TEST_FILTER='detect_monsters128|detect_evil128' make test128`; complete producer path `NOT IMPLEMENTED` |
| C64 detected-only targeting exclusion | `platforms/commodore/c64/tests/test_dispel_evil_prayer.s` | `TEST_FILTER='dispel_evil_prayer' make test64` |
| C128 detected-only targeting exclusion | `platforms/commodore/c128/tests/test_dispel_evil_prayer128.s` | `TEST_FILTER='dispel_evil_prayer128' make test128` |
| C64 renderer consumption | `platforms/commodore/c64/tests/test_render.s` | `TEST_FILTER='render' make test64`; seeded flags do not prove the producer |
| Plus/4 renderer consumption | `platforms/commodore/plus4/tests/test_renderplus4.s` | `TEST_FILTER='renderplus4' make testplus4` |
| Plus/4 production visibility-wrapper integration | `platforms/commodore/plus4/tests/test_visibility_renderplus4.s` | `TEST_FILTER='visibility_renderplus4' make testplus4` |
| C128 renderer consumption | `platforms/commodore/c128/tests/test_vdc_scroll_delta128.s` | `TEST_FILTER='vdc_scroll_delta128' make test128`; seeded cases do not prove the producer |
| C64 spell sleep dispatch | C64 sleep/sanctuary test files | `TEST_FILTER='sleep|sanctuary' make test64`; Sleep II exercises production feedback/resistance and pins the level-40 boundary; some other paths use test-local helpers |
| C128 spell sleep behavior | C128 sleep/sanctuary test files | `TEST_FILTER='sleep|sanctuary' make test128`; production-overlay coverage incomplete |
| Plus/4 shared sleep/wake/aggravation producer | `platforms/commodore/plus4/tests/test_visibility_renderplus4.s` | `TEST_FILTER='visibility_renderplus4' make testplus4` |
| Fresh-game invulnerability reset | `platforms/commodore/c128/tests/test_main_loop128.s` seeds `$FF` and calls production `game_new_start` | `TEST_FILTER='main_loop128' make test128`; C64, Plus/4, and Apple use the identical shared initializer, with runtime Apple combat confirmation still required |
| One-byte sleep arithmetic maximum boundary | `platforms/commodore/c64/tests/test_monster.s` | `TEST_FILTER='monster' make test64`; exhaustive byte-domain gate remains `NOT IMPLEMENTED` |
| Player-speed cadence fold (MON-026: haste, slow, each Ring of Speed, Boots of Speed/Slowness, stacked steps `-2..4`, every `2 - s` turns clamped to `mod 5` at `s = -4`, the double-move cap) | `platforms/commodore/c64/tests/test_monster_ai.s` t36-t40 (single steps), t69 (two rings: every 3rd turn across the turn's high byte), t70 (haste and two rings: every 4th), t71 (`+4` player speed via two rings + Boots of Speed + haste vs speed-0 monster: `s = -4` clamped to `mod 5`) exercise the production `monster_ai_tick` directly; t69-t70 fail on the MON-008 code | `TEST_FILTER='monster_ai' make test64`; C128/Plus4/Apple2 compile identical shared source and rely on product layout gates plus Apple2 runtime scenarios |
| One melee attack per monster action, no move after attacking (orthogonal and diagonal adjacency; VMS `make_move` ends the turn after `make_attack`) | `platforms/commodore/c64/tests/test_monster_ai.s` t57-t58 through production `monster_ai_tick` | `TEST_FILTER='monster_ai' make test64` |
| Adjacent monster within light is `MF_VISIBLE` even diagonally across a wall corner; blindness still hides it; distance 2 behind a wall stays hidden (MON-010) | `platforms/commodore/c64/tests/test_monster.s` t20-t22 through production `monster_update_visibility_all`; `test_effects.s` Test 35 through production `update_visibility` | `TEST_FILTER='monster|effects' make test64` |
| Monster spells and player saving throw (MON-011): wound dice, effect timers and stacking, resist path, heroism vs fear, spell bit dispatch incl. bits 6-7, save value/clamp, wis_adj thresholds, save extremes, paralysis con_adj | `platforms/commodore/c64/tests/test_monster_magic.s` t5, t7, t8, t15-t26 through production handlers and `monster_pick_spell`; `test_monster_ai.s` t15 | `TEST_FILTER='monster_magic|monster_ai' make test64` |
| Thrown items (the same VMS rules with Moria8 additions: STR damage, `1d1` for `0d0`, potions shatter; `docs/FEATURE_MAP.md` "Throwing Any Item"): item to-dam not `PL_TODMG`, to-hit by distance, a miss landing 9 in 10 | C64 `test_throw.s` t14-t16 through production `tw_roll_damage`, `throw_calc_tohit`, `tw_consume_item`, `tw_hit_used_up` | `TEST_FILTER='^throw$' make test64` |
| Fired missile range, to-hit by distance, damage multiplier and missed-shot landing (MON-018) | C64 `test_ranged.s` t11-t13, `test_throw.s` t12-t13 through production `rf_roll_damage`, `rf_calc_tohit`, `rf_fly`, `rf_shot_lands` | `TEST_FILTER='^(ranged|throw)$' make test64`; other platforms compile the identical shared code |
| A summon in a monster's own turn: the caster's record stays put and the summoned creature's record names the tile flagged `FLAG_OCCUPIED` (`monster_spawn_one` preserves `zp_mon_idx`, which `monster_write_back` uses after the cast) | C64 `test_monster_magic.s` t27 through production `monster_process_one` | `TEST_FILTER='monster_magic' make test64`; other platforms compile the identical shared code |
| Detected-only production free-look inspection | none | `NOT IMPLEMENTED` |
| Complete cross-platform timed Detect Monsters producer lifecycle | none | `NOT IMPLEMENTED` |
| Breeding chance, crowding stop and rest slowdown (MON-016) | `platforms/commodore/c64/tests/test_monster_ai.s` t60-t63 through production `monster_ai_tick` | `TEST_FILTER='monster_ai' make test64`; statistical bands over 60-250 trials with the seeded RNG |
| Fire breath takes VMS `fire_dam` (`moria.inc`; Umoria `damageFire`): `div 3` for the Resist Fire ring, `div 3` again for the Resist Heat timer, uncapped; frost the same through `cold_dam` with the Resist Cold ring and timer (MON-025) | C64 `test_monster_magic.s` t9, t10, t28-t29, t31-t32 through production `monster_cast_breath` | `TEST_FILTER='monster_magic' make test64`; other platforms compile the identical shared code |
| Protection from Evil repels evil attackers up to the player's level (MON-019): the level boundary (equal repelled, one above not), non-evil, no protection, timer not consumed, no damage or effect | C64 `test_monster_attack.s` t23-t26 through production `monster_attack_player` | `TEST_FILTER='monster_attack' make test64`; other platforms compile the identical shared code |
| Upstream attack types that deal no HP damage (12 Steal Money, 13 Steal Object, 19 Lose experience, 20 Aggravate, 21 Disenchant, 22-24 Eat food/light/charges; VMS `creature.inc` `make_attack` calls no `take_hit` for them, Umoria `executeAttackOnPlayer` no `playerTakesHit`) ship as `0d0` (`tools/parse_creatures.py` `NO_HP_ATTACK_TYPES`); a `0d0` hit deals 0 | C64 `test_monster_attack.s` t27-t30: the shipped `tier4.s` Banshee and Lich rows, then 12 production `monster_attack_player` rounds each (Banshee: no HP lost; Lich: only its 2d8) | `TEST_FILTER='monster_attack' make test64`; other platforms import the same tier files |
| Creatures act only within their alert radius or in view (MON-017) | `platforms/commodore/c64/tests/test_monster_ai.s` t64-t65 through production `monster_ai_tick` | `TEST_FILTER='monster_ai' make test64` |
| Attack-slot selection, no-spell casters, never-moving creatures and max HP in the shipped rows (MON-020 to MON-022, MON-024) | C64 `test_monster_attack.s` t36-t46 (tier4 data, production `monster_attack_player` and `monster_spawn_one`), `test_monster_tier3.s` t1-t4 (tier3 data) | `TEST_FILTER='monster_attack\|monster_tier3' make test64`; other platforms import the same tier files |
| Teleport To lands next to the caster; blocked neighbours leave the player in place (MON-023); a never-moving creature stays put (MON-022) | C64 `test_monster_ai.s` t66-t68 through production `monster_ai_tick` / `monster_pick_spell` | `TEST_FILTER='monster_ai' make test64`; other platforms compile the identical shared code |
| Lightning and acid resistance (MON-027): armour suffix roll (unenchanted, cursed, gloves never; rate and kinds on DL50; (Resist) +5 AC), worn flags from body, shield and weapon egos (tool egos none), lightning `div 3`, acid `div 3` / `div 4` on breath and touch, a resisting piece unharmed, gas unaffected | C64 `test_ego.s` t13-t19 (production `roll_ego_type`, `player_recalc_pflags_equipment`, `ego_get_suffix_ptr`), `test_monster_magic.s` t38-t42 (production `monster_cast_breath`, flags rebuilt by `player_recalc_equipment` from a Defender), `test_monster_attack.s` t47-t49 (production `mon_atk_effect_acid`) | `TEST_FILTER='^(ego|monster_magic|monster_attack)$' make test64`; other platforms compile the identical shared code; the 16-byte-slot suffix printer (Apple IIe, CX16, BBC Master) has no unit test |
| Fire, cold and lightning touches (MON-028): to-hit base, unresisted, lasting resistance, timer, lightning unaffected by fire and cold protection | C64 `test_monster_attack.s` t50-t53 through production `mon_atk_effect_dispatch` (the damage and each element's message) | `TEST_FILTER='^monster_attack$' make test64`; the C64 product enters the divisor through `tramp_element_divisor` (its `$F000` runtime): `scripted_element_divisor_smoke` runs it in a product image (fire resisted twice divided by 9, lightning by 1; X, `$01` and the I flag kept) |
| Lordly rings and the Amulet of Resist Acid (MON-029): flags from either ring hand and the amulet, the rings' AC, names | C64 `test_ego.s` t20 (production `player_recalc_pflags_equipment`, which ends in `player_calc_combat` for the AC), `test_item_desc.s` and C128 `test_item_desc128.s` (every item name) | `TEST_FILTER='^(ego|item_desc)$' make test64`; the tables and the flags routine are shared, placed per port (the C64 and Atari in their `$F000` runtimes); no other port runs them in a test |
| Crowns of the Magi (MON-030): the roll (only the Magi, INT 1-3, never on helms or unenchanted crowns), the head-slot flags, INT on wear and take-off and in the stats rebuild, the suffix, the `(+p1)` display, acid sparing it, the fixed items known after a load of an older save | C64 `test_ego.s` t21-t24 (production `roll_ego_type`, `player_recalc_pflags_equipment`, `equip_stat_index`, `player_adjust_equipment_stat`, `player_calc_stats`, `ego_get_suffix_ptr`), `test_item_desc.s` t12 (production `itemdesc_put_staged`), `test_monster_attack.s` t54 (production `mon_atk_effect_acid`), `test_save.s` t40 (production `load_read_known_items`) | `TEST_FILTER='^(ego|item_desc|monster_attack|save)$' make test64`; the C128 imports the core `player_adjust_equipment_stat`; the Apple IIe (`weapon_exchange`) and BBC Master (`item_actions`) harness scenarios wear and take off a Golden Crown of the Magi through their own copies (INT +2 and back, the fire, cold and acid flags) |
| Phase 5 4-slot melee loop, 19 `ADESC_*` verbs, and extended `ATK_*` effects (MON-032): slot 2/3 dispatch, 5-bit verb unpacking, `ATK_LOSE_STR` `-3` BTH & 50% unsustained roll, `ATK_LOSE_DEX..WIS` sustain guard & HP/combat recalc, `ATK_CORRODE`, `ATK_STEAL_GOLD/ITEM` vs `clvl` + DEX anti-theft + 50% blink, `ATK_LOSE_EXP` 24-bit drain + level drop, `ATK_DISENCHANT`, `ATK_EAT_FOOD/LIGHT/CHARGES` | C64 `test_monster_attack2.s` through production `monster_attack_player`, `mon_atk_verb_to_ptr2`, and `mon_atk_effect_ext` / `mae_cold_body` | `TEST_FILTER='monster_attack2' make test64`; all 7 ports + 5 cartridges compile the identical shared `core/monster_attack.s` and `core/monster_attack_effects.s` |
| Phase 5 `MSF2_*` monster spells & `cr_cdefense` vulnerabilities/immunities (MON-033, MON-034): `MSF2_BLINK`, `MSF2_TELE_SELF`, `MSF2_SUMMON_UNDEAD` (`cat_undead[35]`), `MSF2_SLOW` (`PFLAG_FREE_ACT` + save), `MSF2_DRAIN_MANA` (`6*r1` heal), elemental `2x` vuln & `/4` breath resist, `CD_LIGHT` `2d8`, `CD_STONE` `100`, `CD_NO_SLEEP` sleep/confuse immunity, Flame Tongue / Frost Brand `1.5x` | C64 `test_monster_magic3.s` through production `monster_can_cast`, `monster_pick_spell`, `eff_scale_elem_damage`, `eff_light_room`, `eff_wall_to_mud`, and `ego_apply_damage` | `TEST_FILTER='monster_magic3' make test64`; all 7 ports + 5 cartridges compile the identical shared modules |
| Phase 5 `CD_INVISIBLE` visibility, `CM2_PHASE`, `CM2_EATS_OTHER`, `CM2_PICKS_UP`, & 15-field `/` recall (MON-034, MON-035) | C64 `test_monster_ai2.s` and `test_score.s` through production `monster_update_visibility_all`, `monster_try_step`, and `ui_recall_display`, plus cross-port `make playtest-gate` | `TEST_FILTER='^(monster_ai2|score)$' make test64`; `make playtest-gate` |
| Monster theft VMS feedback, `AU:` status refresh, `subval >= 512` whole-bundle theft, and `±20` blink range (MON-036) | C64 `test_monster_attack2.s` t27-t32 through production `monster_attack_player` and `mon_atk_effect_dispatch` (all 5 VMS messages, Row 23 `AU:` refresh, `Arrow`/`Iron Spike` whole-slot vs `Ration` 1-unit stack rule, and `±20` `max_sight` range over 12,544-tile open map) | `TEST_FILTER='^monster_attack2$' make test64`; all 7 ports + 5 cartridges compile the identical shared `core/monster_attack_effects.s`; `make playtest-gate` |
| Monster stat & XP drain VMS messages (MON-037) | C64 `test_monster_attack2.s` t33 through production `mon_atk_effect_dispatch` and `mon_atk_hit` asserting all 6 rendered VMS messages (`STR`, `DEX`, `CON`, `INT`, `WIS`, `EXP`) on screen row 0 | `TEST_FILTER='^monster_attack2$' make test64`; all 7 ports + 5 cartridges compile the identical shared `core/monster_attack_effects.s` |
| Monster sighting (`muvo_apply_visible`), visible hostile-action (`mat_action_dirty` bit 1 + `MF_VISIBLE`, incl. local radius `<= zp_light_radius + 1` and silent `MSF2_BLINK`), door-burst mid-turn `inc zp_disturb`, melee disturbance, and non-disturbance of sleeping monsters (MON-005), unprovoked townies, detected-only behind walls, and unseen `CD_INVISIBLE` creatures (MON-038 / TRN-012 / TRN-014) | C64 `test_monster_ai2.s` t16-t20, t23 (24/24) and `test_monster_attack.s` t55 (55/55) through production `monster_update_visibility_all`, `monster_ai_tick`, and `monster_attack_player` | `TEST_FILTER='^(monster_ai2\|monster_attack)$' make test64`; all 7 ports + 5 cartridges compile the identical shared `core/monster.s`, `core/monster_ai.s`, and `core/monster_attack.s` |
| Ambient spawning (MON-039): `1 in 160` per consumed turn, one awake creature beyond `max_sight`, town townspeople, the `MAX_MONSTERS - 6` reserve, the C64 `$F000` trampoline | CX16 `harness_smoke.py monster_catalog`; C64 `catalog_spawn_product_smoke`, `catalog_spawn_product_reu_smoke` | `make testcx16`; `TEST_FILTER='catalog_spawn_product' make test64` |
| Summon level `dlvl + 2`, no out-of-depth roll (MON-040) | C64 `test_monster_magic3.s` t21-t22; CX16 `harness_smoke.py monster_catalog` | `TEST_FILTER='monster_magic3' make test64`; `make testcx16` |
| Summon counts, undead pick, beside the player, awake; clones and breeders awake (MON-041) | C64 `test_monster_magic3.s` t23-t26, `test_monster_ai.s` t61; CX16 `monster_catalog` `undead_pick_*` | `TEST_FILTER='monster_magic3\|monster_ai' make test64`; `make testcx16` |
| Polymorph roll, any-level awake replacement, Mass Polymorph reach (MON-042) | C64 `test_monster_magic3.s` t27-t28; CX16 `monster_catalog` `poly_any_level` | `TEST_FILTER='monster_magic3' make test64`; `make testcx16` |
| No low-HP monster fleeing; `MX_RESERVED_0/1` zeroed at spawn, ignored if nonzero in older saves; low-HP mobile and `CF_ATTACK_ONLY` monsters advance/attack normally (MON-043) | C64 `test_monster_ai.s` t16–t19 (`t17`–`t18` fail pre-fix) and `test_monster_ai2.s` t6 (`CM2_PHASE` outer-boundary walls) through production `monster_spawn_one` and `monster_ai_tick` | `TEST_FILTER='monster_ai\|monster_ai2\|monster_magic' make test64`; all 7 ports + 5 cartridges compile identical `core/monster.s` and `core/monster_ai.s`; `make -j7 -O test`; `make playtest-gate` |

## Change Record — Phase 5 Full 279-Species VMS Monster Parity (2026-11-16)

```text
Problem and success criteria:
  Deliver 100% VMS Moria 4.8 monster parity across all 7 ports and 5 cartridges:
  all 279/279 creatures playable (0 degraded, 0 omitted), 29 SoA fields per active
  species slot, all 4 melee attack slots, all 19 ADESC_* attack verbs, all 24 ATK_*
  melee effects, all 5 missing MSF2_* monster spells (completing all 18 VMS CSPELL
  flags), CD_FROST..CD_STONE vulnerabilities + /4 breath resistance + CD_NO_SLEEP
  immunity + CD_INVISIBLE visibility, CM2_PHASE / CM2_EATS_OTHER / CM2_PICKS_UP AI
  behaviors, and full 15-field '/' monster recall.
State being changed:
  - core/monster.s: +8 SoA arrays (cr_atk2_*, cr_atk3_*, cr_spell_flags2, cr_cdefense)
    and muvo_apply_visible CD_INVISIBLE ($80) gate.
  - core/monster_catalog.s & platforms/shared/catalog/*: 279/279 playable cat_available,
    cat_undead[35], catalog_fetch_ext -> cat_ext_record[8], catalog_recall_match_and_fill.
  - core/monster_attack.s & core/monster_attack_effects.s: 4-slot loop, 5-bit packed
    19-verb decoder, signed base_to_hit + 3*cr_level, clvl defence for theft, AC reduction
    on ATK_NORMAL/ATK_BLIND/ATK_LOSE_*, and all extended ATK_* handlers.
  - core/monster_ai.s: CM2_PHASE, CM2_EATS_OTHER, CM2_PICKS_UP, and mat_force_new_dirty.
  - core/monster_magic.s, core/spell_effects.s, core/ego_items.s, core/combat.s,
    core/eff_item_p1.s, core/player_magic_feedback.s: 5 MSF2_* spells, 2x vuln / /4
    breath resist, 1.5x elemental weapon ego, CD_LIGHT 2d8, CD_STONE 100, CD_NO_SLEEP.
  - core/recall_defs.s & core/ui_recall.s: 15-field '/' recall UI.
Search scope and terms:
  rg across core/, platforms/, and tools/ for cr_atk, mon_atk_, MSF_, CD_, CM_,
  catalog_fetch, ui_recall, eff_bolt, eff_light_room, eff_wall_to_mud, CD_NO_SLEEP.
Relevant readers/writers found and known exclusions:
  cat_fetch and catalog_recall_match_and_fill populate all 8 extended fields via
  port-owned catalog_fetch_ext; legacy C64 unit tests using 4 KB TestCreateOverlay
  or embedded 26-creature rosters gate optional extended blocks cleanly via
  MONSTER_MAGIC_PRODUCTION_EXTENDED / PLACE_SECRETS_EXTERNAL while dedicated
  test_monster_attack2.s, test_monster_ai2.s, test_monster_magic3.s, and all 7
  product builds compile the full production paths.
Initialization, reset and persistence points:
  cat_fetch initializes all 29 cr_* fields on level spawn, summon, polymorph, and
  load-game catalog_refetch_slots; town creatures initialize cr_atk2..cr_cdefense
  to 0; Save Format V2 (cat_slot_id_lo/hi[32] + recall[279]) required zero bump.
Affected production sequence through the changed transition:
  Level gen / summon -> pick_creature_type -> cat_fetch -> catalog_fetch_ext ->
  populates cr_atk2..cr_cdefense; AI turn -> monster_process_one -> monster_can_cast /
  monster_pick_spell (MSF + MSF2) or monster_try_step (CM2_PHASE/EATS_OTHER/PICKS_UP
  or 4-slot monster_attack_player); visibility -> muvo_apply_visible (CD_INVISIBLE);
  player combat/magic -> 1.5x/2x/div4/2d8/100/CD_NO_SLEEP; '/' -> ui_recall_display.
Contract decision or selected upstream oracle with source locations:
  Pinned VMS Moria 4.8 creature.inc, spells.inc, moria.inc, misc.inc, values.inc
  (MON-032 through MON-035 above).
Intentional Moria8 deviations:
  Wound spells remain consolidated into 3d8/8d8; breath/ball effects remain
  player/target-scoped without monster-on-monster collateral; stat/XP drain messages
  reuse compact Huffman strings where noted.
Input/intermediate widths, signedness, carry, range and overflow policy:
  Signed 16-bit to-hit intermediate (bth + 3*cr_level, -3..825) clamped [0, 255];
  24-bit gold/XP arithmetic in mae_add_sub24 floored at 0; 16-bit cr_xp compare in
  CM2_EATS_OTHER; signed 8-bit zp_eff_speed clamped at -128 in MSF2_SLOW; 16-bit
  caster HP clamped at $7FFF in MSF2_DRAIN_MANA.
RNG reduction and bias, if applicable:
  Uniform 1-pass reservoir sampling (mae_pick_slot: rng_range(count) == 0) over
  matching pack/armour slots; uniform bit-walk over cat_undead[35] and MSF+MSF2 choices.
Affected platforms, overlays, banks and owners:
  All 7 ports (C64, Plus/4, C128, Apple IIe, Commander X16, Atari 8-bit, BBC Master 128)
  and all 5 native cartridges; see each platform's memory contract for exact placement.
Required production-path tests:
  C64 test_monster_attack2.s, test_monster_ai2.s, test_monster_magic3.s, test_score.s,
  all 7 platform memory-contract and runtime suites, tools/report_memory_budgets.py,
  and make playtest-gate across every port and cartridge.
Known behavior explicitly out of scope:
  Raising MAX_MONSTERS above 32 on 198x66 maps and nearby aggravation haste (MON-006).
Unresolved uncertainty and risk:
  Tight (< 64 B) overlay/resident budgets on Apple IIe, C128, Atari 8-bit, Plus/4,
  and BBC Master are guarded fail-closed by link-time .asserts and contract checkers.
```

## Change Record — Monster Theft VMS Feedback, Stack Rule & Blink Range (2026-11-17)

```text
Problem and success criteria:
  Restore full VMS Moria 4.8 parity in shared mae_steal (ATK_STEAL_GOLD = 12 and
  ATK_STEAL_ITEM = 13) across all 7 ports and 5 cartridges: print all 5 VMS theft,
  dodge, and blink messages, refresh the gold status display after gold theft,
  apply VMS inven_destroy's subval >= 512 whole-bundle rule on missile/spike stacks,
  and bound thief blink distance to +-20 (widening +5 every 10 failed tries).
State being changed:
  - core/monster_attack_effects.s: generalized 5-bit mav_unpack for all 5 VMS theft
    messages, status_mark_dirty + status_draw trigger on mae_recalc_pend < 0,
    whole-slot inv_remove_item for ITEM_SLOT_IRON_SPIKE and ITEM_SLOT_ARROW..
    ITEM_SLOT_IRON_SHOT vs inv_consume_one otherwise, and mae_find_blink_tile
    implementing VMS teleport_away(monptr, max_sight=20).
Search scope and terms:
  rg across core/, platforms/, tools/, and upstream vms-moria/source/include/ for
  mae_steal, ATK_STEAL_GOLD, ATK_STEAL_ITEM, inv_consume_one, teleport_away,
  inven_destroy, missle_ctr, status_draw, and spell_effects_overlay.
Relevant readers/writers found and known exclusions:
  ATK_EAT_FOOD (case 22 in VMS creature.inc:625-640) is intentionally silent in VMS
  and remains unchanged. Test suites importing monster_attack.s without ui_status.s
  (test_monster_attack.s) stub status_mark_dirty/status_draw, while test_monster_attack2.s
  links production ui_status.s in Default.
Initialization, reset and persistence points:
  N/A for save format (no persistent struct or save-file layout changes); mae_recalc_pend,
  mae_dmg_lo, mae_idx, and frf_attempts are initialized on every mon_atk_effect_ext /
  mae_find_blink_tile entry.
Affected production sequence through the changed transition:
  monster_attack_player -> mon_atk_hit -> mon_atk_effect_dispatch -> mon_atk_effect_ext
  -> mae_cold_call -> mae_cold_body -> mae_steal -> mae_print_steal_msg / inv_remove_item
  or inv_consume_one / mae_find_blink_tile -> FLAG_OCCUPIED + MX_X/Y + clear MF_VISIBLE
  + inc zp_dirty_count -> status_mark_dirty + status_draw (on gold theft).
Contract decision or selected upstream oracle with source locations:
  Pinned VMS Moria 4.8 creature.inc:483-520, spells.inc:1202-1230, constants.inc:110
  (max_sight = 20), and misc.inc:1419-1479, 2526-2548 (MON-036 above).
Intentional Moria8 deviations:
  mae_find_blink_tile includes a 256-attempt safety cap (frf_attempts) so synthetic
  all-wall test maps terminate cleanly without hanging.
Input/intermediate widths, signedness, carry, range and overflow policy:
  dis starts at 20 and widens by +5 up to 125 (2*dis + 1 = 251 <= 255 for 8-bit
  rng_range), falling back to full-map df_roll_interior_xy once dis >= 126; 9-bit
  carry checks reject < 1 and >= MAP_COLS-1 / MAP_ROWS-1 without wraparound.
RNG reduction and bias, if applicable:
  rng_range(2*dis + 1) picks uniform integer offsets in [-dis, +dis] on each axis,
  rerolling out-of-bounds coordinates identically to VMS randint(2*dis + 1) - 1 - dis.
Affected platforms, overlays, banks and owners:
  All 7 ports and 5 cartridges via shared core/monster_attack_effects.s; ATK 12..13
  execute in HomeOverlay on C64/Plus4, RuntimeBanked on Atari8, cached OVL_ITEMS on
  C128/CX16, and HelpOverlay on Apple2/BBC Master.
Required production-path tests:
  C64 test_monster_attack2.s t27-t32, full make test across all 7 ports, and
  make playtest-gate across all 7 ports and 5 cartridges.
Known behavior explicitly out of scope:
  Monster-picked-up loot pouches (CM2_PICKS_UP) and ATK_EAT_FOOD feedback.
Unresolved uncertainty and risk:
  None; all segment budgets and cross-overlay call boundaries verified statically and
  at runtime.
```

## Change Record — VMS Monster Stat/XP Drain Messages (MON-037, 2026-11-18)

```text
Problem and success criteria:
  Replace generic HSTR_DF_CON_DRAIN ("You feel weakened.") across monster stat drains
  (ATK_LOSE_STR, ATK_LOSE_DEX..WIS) and monster XP drain (ATK_LOSE_EXP) with the six
  exact VMS Moria 4.8 creature.inc messages across all 7 ports and 5 cartridges.
State being changed:
  - core/monster_attack_effects.s: extended mav_unpack (code 0 -> '.', shared tail
    offsets 0, 7, 5, 21) and mae_bits/mae_tail (indices 5..10) for STR, INT, WIS, DEX,
    CON, and EXP drain messages; mae_lose_stat routes unsustained drain feedback through
    mae_cold_call (5..9), and mae_lose_exp calls mae_print_steal_msg (10); deduplicated
    mae_recalc_hp_combat into player_calc_combat + player_calc_hp.
Search scope and terms:
  rg across core/, platforms/, data/, and upstream vms-moria/source/include/creature.inc
  for HSTR_DF_CON_DRAIN, mae_lose_stat, mae_lose_exp, feel weakened, clumsy, wisdom is drained.
Relevant readers/writers found and known exclusions:
  Sustained hits retain HSTR_CHEST_UNAFFECTED; dart traps (core/trap_trigger_cold.s)
  use HSTR_CHEST_WEAKENED ("You feel weakened!") for both STR and CON darts (matching VMS
  moria.inc:1859, 1933).
Initialization, reset and persistence points:
  N/A (transient message output only; mat_atk_type is reloaded per melee blow).
Affected production sequence through the changed transition:
  monster_attack_player -> mon_atk_hit -> mon_atk_effect_dispatch -> mon_atk_effect_ext
  -> mae_lose_str / mae_lose_stat -> mae_recalc_hp_combat -> mae_cold_call -> mae_cold_body
  -> mae_print_steal_msg -> mav_unpack -> msg_print_ay (and mae_lose_exp -> mae_print_steal_msg).
Contract decision or selected upstream oracle with source locations:
  Pinned VMS Moria 4.8 creature.inc:398, 535, 548, 564, 577, 584 (MON-037 above).
Intentional Moria8 deviations:
  Sustained hits retain shared HSTR_CHEST_UNAFFECTED.
Input/intermediate widths, signedness, carry, range and overflow policy:
  5-bit codes 0..31 unpacked into hd_decode_buf (max length 33 + NUL = 34 B <= 40-col row).
RNG reduction and bias, if applicable:
  N/A (no RNG change).
Affected platforms, overlays, banks and owners:
  All 7 ports + 5 cartridges via shared core/monster_attack_effects.s; stat/XP drain
  messages execute with zero disk I/O in RuntimeBanked on C64/Plus4/Atari8, RuntimeBankedCode
  + Default on C128/CX16, and HelpOverlay on Apple2/BBC Master (C64 and Plus/4 mae_steal
  placed in HomeOverlay).
Required production-path tests:
  C64 test_monster_attack2.s t33, full 7-port make test, and 65-target make playtest-gate.
Known behavior explicitly out of scope:
  Per-stat sustained messages.
Unresolved uncertainty and risk:
  None.
```

## Change Record — Monster Sighting, Hostile-Action & Door-Burst Disturbance (MON-038, 2026-11-19)

```text
Problem and success criteria:
  Ensure visible hostile monster activity (including local-radius moves inside
  <= zp_light_radius + 1 where turn_scene_dirty remains 0, silent MSF2_BLINK /
  MSF2_TELE_SELF, and visible breeding), MF_VISIBLE 0 -> 1 sightings, monster
  melee rounds, and unconditional door bursts all raise zp_disturb ($69) mid-turn,
  while keeping sleeping monsters (MON-005), unprovoked wandering townies,
  detected-only monsters behind walls, and unseen CD_INVISIBLE creatures (TRN-012)
  quiet.
State being changed:
  - core/monster.s::muvo_apply_visible: executes inc zp_disturb alongside
    jsr player_search_mode_off on MF_VISIBLE 0 -> 1 transition.
  - core/monster_ai.s: sets mat_action_dirty bit 1 ($02) on hostile moves ($83)
    and spells/breeding/door-open/glyph-break ($03), keeping bit 1 clear ($81)
    on unprovoked townie wandering (!mpo_not_town bypass); !mpo_done executes
    inc zp_disturb when (mat_action_dirty & $02) != 0 && (zp_mon_flags & MF_VISIBLE) != 0;
    !mts_stuck and !mts_bash share !mts_bash_set executing inc zp_disturb alongside
    HSTR_MAT_DOOR_BURST (net -1 B).
  - core/monster_attack.s: executes inc zp_disturb right after !map_has_atk0:
    (past the ATK_NONE early return, including repelled melee rounds).
Search scope and terms:
  rg across core/ and platforms/ for muvo_apply_visible, mat_action_dirty,
  mts_stuck, mts_bash, mts_open_plain, mts_write_open, map_has_atk0,
  HSTR_MAT_DOOR_BURST, MF_VISIBLE, CD_INVISIBLE.
Relevant readers/writers found and known exclusions:
  Plain door opens (!mts_open_plain) add no extra door-tile LOS check, matching
  pinned VMS/Umoria (muvo_apply_visible catches the opener entering sight);
  sleeping monsters never reach active AI actions during auto-rest (MON-005);
  unseen CD_INVISIBLE creatures exit muvo_apply_visible before !muvo_can_see
  (TRN-012) and only disturb if they attack or become visible.
Initialization, reset and persistence points:
  zp_disturb ($69) is transient unsaved ZP state cleared in game_new_start,
  load_resume_reset_cold.s, cmd_autorest, and run_step (see TRN-014);
  mat_action_dirty is cleared per monster at the start of monster_process_one.
Affected production sequence through the changed transition:
  turn_post_action -> monster_ai_tick -> monster_process_one -> monster_try_step
  (door burst / hostile move / attack) or monster_pick_spell / breed -> !mpo_done
  (hostile bit 1 + MF_VISIBLE -> inc zp_disturb) -> main_loop
  monster_update_visibility_all -> muvo_apply_visible (0 -> 1 -> inc zp_disturb)
  -> auto_rest_should_stop / !run_active_post.
Contract decision or selected upstream oracle with source locations:
  MON-038 and TRN-014; pinned VMS Moria source/include/creature.inc:42-55,
  697-757, 1191-1202 and pinned Umoria src/monster.cpp:54-60, 477-540, 610-613.
Intentional Moria8 deviations:
  Unprovoked wandering townies leave mat_action_dirty bit 1 clear ($81) so
  resting in town is not interrupted by harmless townspeople moving in sight;
  provoked townies clear the bypass and disturb normally.
Input/intermediate widths, signedness, carry, range and overflow policy:
  8-bit bitmasks (mat_action_dirty bit 1 = $02, MF_VISIBLE = $08) and 8-bit
  non-zero latch zp_disturb incremented via 2-byte inc zp_disturb (preserving
  A/X/Y/C).
RNG reduction and bias, if applicable:
  N/A (no RNG changes).
Affected platforms, overlays, banks and owners:
  All 7 ports + 5 cartridges via shared core/monster.s, core/monster_ai.s, and
  core/monster_attack.s; all 12 product builds and all rebuilt test-variant PRGs
  verified within hard limits by tools/report_memory_budgets.py (0 overflows, 0
  stray artifacts; see TRN-014 in docs/TURN_RENDER_CONTRACT.md for the full
  7-port table, e.g. C64 Default $BF80/$C000, C128 128.play $CEBA/$D000 &
  128.bank $FEDA/$FF00, Apple IIe Default $7BD2/$7C00, Atari 8-bit Default
  $C0AC/$C100, BBC Master Default $7F77/$8000).
Required production-path tests:
  C64 test_monster_ai2.s t16-t20, t23 (24/24) and test_monster_attack.s t55
  (55/55), plus C64 monster (24/24), monster_ai (70/70), full C64 run_tests.sh
  (224/224 + cart), C128 make test128 (141/141 + legal 6/6 + cart PAL/NTSC
  23/23), Apple IIe (26/26), CX16 (27/27 + cart), Atari 8-bit (21/21 + 6/6
  cart), Plus/4 make testplus4 PASS (legal 6/6 + 47/47 + cart), BBC Master
  make testbbcmaster-runtime PASS (18/18), and make playtest-gate (65/65 PASS,
  0 failed, 0 targets skipped, exit 0; incl. plus4 5/5, plus4-cart 5/5, and
  JiffyDOS-enabled c64/c128 targets alongside all other ports and cartridges).
Known behavior explicitly out of scope:
  Shared monster distance Chebyshev-to-upstream conversion (tracked separately
  in docs/BACKLOG.md).
Unresolved uncertainty and risk:
  Zero product or test-suite defects remain (all 7 ports, all 5 cartridges,
  and 65/65 make playtest-gate passed); sole external timing caveat is
  test64-legal help hitting its 30s wall-clock cap on the final post-return
  bsave (memory(0xC000, 3840) after returning to gameplay) under sustained
  external host load 32.81-43.85 (title passed; not a product hang).
```

## Change Record — Remove Low-HP Monster Fleeing (MON-043, 2026-11-23)

```text
Problem and success criteria:
  Moria8 monsters fled when HP dropped below 1/4 of spawn HP (commit 74700dc, R3.4)
  and suppressed melee while fleeing (causing injured bosses like the 3,000-HP
  Balrog to run away below 750 HP and regenerate). Per maintainer direction
  (2026-11-23: "make this act like VMS moria"), remove low-HP monster fleeing
  across all 7 ports and 5 cartridges while keeping the 12-byte monster record
  and Save Format V2 ($22) unchanged.
State being changed:
  - core/monster.s: renamed MX_FLEE_LO/HI (bytes 10-11) to MX_RESERVED_0/1;
    removed HP/4 threshold calculation from monster_spawn_one and extended
    !mso_clear loop to zero bytes 5..11 (MX_FLAGS..MX_RESERVED_1).
  - core/monster_ai.s: removed mat_fleeing, monster_check_flee, monster_move_away,
    the flee branch in monster_process_one, the mat_fleeing clear in
    monster_move_toward, and the mat_fleeing melee suppression in
    monster_try_step.
  - core/game_loop.s: removed MX_FLEE_LO/HI clears in c128_test_force_dungeon_melee.
Search scope and terms:
  grep -rn -E "MX_FLEE|monster_check_flee|monster_move_away|mat_fleeing|force_flee|flee_thresh|flee"
  across core/, platforms/, docs/, tools/, playtest/.
Relevant readers/writers found and known exclusions:
  All product readers/writers (core/monster.s, core/monster_ai.s,
  core/game_loop.s) removed. Excluded: unrelated player AI bot fleeing notes in
  docs/AI_PLAYTEST_DESIGN.md, Turn Undead retreating (not implemented), and
  unused constants/comments in platforms/commodore/c64/tests/product_magic_missile_smoke.py
  and platforms/bbcmaster/harness_smoke.py (which write 0 to bytes 10-11).
Initialization, reset and persistence points:
  monster_spawn_one zeroes bytes 10-11 (MX_RESERVED_0/1) on spawn; Save Format
  V2 ($22) continues saving/loading the 384-byte monster_table (32 x 12 B)
  without format changes, and any nonzero value in bytes 10-11 of existing live
  saves is ignored (never read by production code).
Affected production sequence through the changed transition:
  monster_ai_tick -> monster_process_one -> (stun / confuse / cast / unprovoked
  town / CM_RANDOM_MOVE) -> monster_move_toward -> monster_try_step ->
  monster_attack_player (when target is player tile) or step toward player.
Contract decision or selected upstream oracle with source locations:
  MON-043 (Accepted, 2026-11-23), superseding 74700dc/R3.4 and MON-024's flee
  threshold note; pinned VMS Moria source/include/creature.inc:1061-1135
  (mon_move) and pinned Umoria src/monster.cpp:1101-1119, 1167-1232
  (monsterDoMove, monsterMove).
Intentional Moria8 deviations:
  None for low-HP fleeing; bytes 10-11 of the 12-byte monster slot remain
  reserved/unused to preserve Save Format V2 compatibility. (Chebyshev distance
  and Turn Undead behavior are unchanged and separate.)
Input/intermediate widths, signedness, carry, range and overflow policy:
  N/A (removed 16-bit HP/4 shift and 16-bit compare; no new arithmetic added;
  !mso_clear uses unsigned Y index 11..5 terminating at MX_HP_HI == 4).
RNG reduction and bias, if applicable:
  N/A (no RNG changes).
Affected platforms, overlays, banks and owners:
  All 7 shipping ports (C64, C128, Plus/4, Apple IIe, CX16, Atari 8-bit, BBC
  Master 128) and all 5 cartridges via shared core/monster.s, core/monster_ai.s,
  and core/game_loop.s (all resident segments shrink; no layout/overlay shifts
  violate hard boundary asserts).
Required production-path tests:
  C64 test_monster_ai.s t16-t19 (t17-t18 fail pre-fix via production
  monster_spawn_one and monster_ai_tick), test_monster_ai2.s t6 (4 outer map
  boundaries via monster_move_toward -> monster_try_step), test_monster_magic.s,
  C128 test_resist_heat_cold_prayer128.s, make build, make -j7 -O test, and
  make playtest-gate.
Known behavior explicitly out of scope:
  Turn Undead retreating (Umoria monsterMoveUndead, src/monster.cpp:1070);
  monster recall / awareness distance metric (MON-017).
Unresolved uncertainty and risk:
  None in product semantics or save compatibility; full-suite runtime gates
  require sufficiently low host load (< 10) to avoid external 30s timeout flakiness.
```



