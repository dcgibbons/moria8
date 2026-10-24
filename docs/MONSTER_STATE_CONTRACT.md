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
| `MX_HP_LO`, `MX_HP_HI` | Current 16-bit HP | combat, monster magic, flee logic |
| `MX_FLAGS.MF_AWAKE` | Monster may proceed into active AI | `monster_process_one` |
| `MX_SLEEP_CUR` | Remaining compact sleep counter | `monster_wake_check` |
| `MX_SPEED_CNT` | Movement scheduling state | monster AI tick |
| `MX_STUN` | Turns unable to act | `monster_process_one` |
| `MX_CONFUSE` | Live confusion timer used by AI | combat and `monster_process_one` |
| `MX_FLEE_LO`, `MX_FLEE_HI` | 16-bit flee HP threshold | movement/flee logic |
| `MF_PROVOKED` | Player hostility; permits town-creature retaliation | combat, bash, AI |
| `MF_VISIBLE` | Current ordinary sight and renderer authority | visibility, targeting |
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
| MON-006 | Accepted in part | Project maintainer, 2026-07-09 | Explicit/group wakes clear `MX_SLEEP_CUR`; Sleep I/II/III use monster-level resistance; aggravation wakes globally | shared helpers and C64/C128/Plus4 focused gates; no-sleep immunity and upstream nearby aggravation haste remain open | none |
| MON-007 | Accepted | Project maintainer, 2026-07-10 | Compact ordinary wake pressure uses distance steps `{8,8,4,3,2,2,1...}` scaled from VMS Moria's `floor(75/d)`; an eligible zero sleep counter wakes before rest/stealth gates | explicit maintainer direction to address staff review; C64 deterministic wake regressions | none |
| MON-008 | Accepted | Project maintainer, 2026-08-05 | Player haste/slow (`zp_eff_speed`) and Ring of Speed (`PFLAG_SPEED`) fold into the per-tick monster cadence: haste or ring steps a monster one cadence slower, an active slow timer one faster, clamped to the existing 0-2 cadence (floor = act every other turn, cap = double move); haste+ring stacking yields no extra effect; the fold is computed per-tick and never mutates stored monster speed state (`cr_speed`, `MX_SPEED_CNT`) | explicit maintainer direction 2026-08-05; oracle Umoria `playerChangeSpeed` (`player.cpp:367-377`) and `monsterMovementRate` (`monster.cpp:74-92`) with documented floor/cap deviations (Umoria -1 = every 3rd turn; Moria8 floor = every 2nd); C64 `test_monster_ai.s` t36-t40, `test_turn.s` t27-t29 | none |
| MON-009 | Accepted | Project maintainer, 2026-09-10 | Monster door-state engine (`!mts_door_block` in `core/monster_ai.s`): door-capable monsters (`cr_aaf` bit 7) pick locks (success unlocks without opening; turn spent either way) and burst stuck doors (open + 50% break); non-capable monsters bash with the |s|-adjusted terms. All three rolls share `mts_state_roll`, the exact Umoria `monsterOpenDoor` formula, translated from one-based `randomNumber(N) < T` to zero-based `rng_range_word(N) < T-1`: `rng_range_word((hp+1)*A) < 40*(hp-B)-1`, with pick A=50+p/B=10+p, burst/bash A=50+|s| or 80+|s|, B=10+|s| or 20+|s|; hp is clamped to 254 and hp <= B never succeeds (equality explicitly clears carry). The burst message "You hear a door burst open!" is printed unconditionally, matching upstream, which has no visibility/distance gate | pinned Umoria `monster.cpp::monsterOpenDoor`; C64 `test_monster_ai.s` t47-t55 including the hp == B boundary set (red-green verified 2026-09-10); multi-platform build asserts | none |
| MON-010 | Accepted | Project maintainer, 2026-10-21 | Any monster within one step (including diagonally across a wall corner) is in line of sight for `MF_VISIBLE`, subject to the existing light/infravision range and blindness gates; line-of-sight tracing applies only at distance 2 and beyond. A monster that can attack the player is therefore never drawn as bare floor | explicit maintainer direction 2026-10-21; pinned Umoria `dungeon_los.cpp::los` adjacency return and VMS Moria `los`; AI playtest finding F-M2-3; C64 `test_monster.s` t20-t22 and `test_effects.s` Test 35 | PR #46 corner-hidden expectation in `test_effects.s` Test 35 |
| MON-011 | Accepted | Project maintainer, 2026-10-21 | Monster wound, blind, confuse and fear spells follow pinned VMS Moria `creature.inc` `cast_spell` (spells 8, 9, 11, 12, 13; Umoria `monster.cpp` identical): Cause Light Wounds 3d8 (`MSF_WOUND_LIGHT`, bit 0) and Cause Serious Wounds 8d8 (`MSF_WOUND_SERIOUS`, bit 6, formerly the unused monster heal) print "casts a spell."; blind 12+randint(3) or +6, confuse and fear randint(5)+3 or +2, saturating at 255; fear (`MSF_FEAR`, bit 7) is now cast and Heroism blocks it. Each is preceded by a player saving throw (`core/player_save.s`): `rng_range(100) < race save + class save + adjustment` (VMS `player_saves`), adjustment wis_adj + level for spells and con_adj for the paralysis touch, using Moria8's existing race/class save values. Deviations: saved spells print Umoria's "You resist the effects of the spell."; failed blind/confuse/fear keep Moria8's effect messages because the status line has no effect indicators. Breath elements are out of scope (`docs/BACKLOG.md`) | explicit maintainer direction 2026-10-21 (`docs/AI_PLAYTEST_DESIGN.md` §14.6-14.7); pinned VMS `creature.inc`, `misc.inc` (`player_saves`, `wis_adj`, `con_adj`); pinned Umoria `monster.cpp`; C64 `test_monster_magic.s` t5, t7, t8, t15-t26 (mutation-checked), `test_monster_ai.s` t15 | generic 2d8+level bolt without save; 1d10+10 blind and 1d5+5 confuse without save; monster self-heal spell; paralysis save of class save + level |
| MON-012 | Accepted | Project maintainer, 2026-10-23 | The monster fear attack (`ATK_FEAR`, `mon_atk_effect_fear`) follows pinned VMS Moria `creature.inc` (fear attack 4; Umoria `monster.cpp` case 4 identical apart from the save formula): after the hit's damage, the player gets `player_saves(wis_adj)` (`player_wis_save_adj`, `player_saving_throw`); if not saved, a player who is not afraid becomes afraid for 3 + randint(level) turns ("frightens you" message), and an afraid player gains 3 more turns (no message), saturating at 255. Heroism still blocks it (VMS clears fear each turn while heroic). Deviations: a resisted fear prints nothing (VMS "You resist the effects!"), as Moria8's paralysis touch already does; Moria8's own race/class save values (MON-011). | maintainer direction 2026-10-23 ("make recommended fixes as discovered", M4 goal) after the M4 baseline's Poltergeist deaths (`docs/AI_PLAYTEST_DESIGN.md` §15.2); pinned VMS/Umoria sources; C64 `test_monster_attack.s` t11, t14-t17 | no save; timer rng_range(level) + 3, replaced only when larger |
| MON-013 | Accepted | Project maintainer, 2026-10-23 | Monster random movement follows pinned Umoria `monsterMove` (VMS `creature.inc` uses the same CMOVE bits): after confusion and spell casting, a creature with `CM_75_RANDOM` (`$20`) moves randomly when `randomNumber(100) < 75`, else with `CM_40_RANDOM` (`$10`) when `< 40`, else with `CM_20_RANDOM` (`$08`) when `< 20`; otherwise it moves normally. The bits are kept in place in `cr_speed` bits 3-5 (speed code bits 0-1; `tools/parse_creatures.py` stores `speed | (cmove & $38)`, regenerated from the pinned Umoria revision: 53 shipped creatures carry at least one bit, e.g. Poltergeist `$3A`). `rng_range(100)` draws 0-99, so the thresholds are 74/39/19. A random move is `monster_move_random` (one of 8 directions; Umoria tries up to five of 9 including staying put), which attacks the player if it steps onto them. Town creatures keep their own wandering. | maintainer direction 2026-10-23 ("make recommended fixes as discovered", M4 goal): the M4 runs found the Poltergeist (88% random upstream) chasing and hitting the bot 50-70 times; `docs/AI_PLAYTEST_DESIGN.md` §15.4; C64 `test_monster_ai.s` t59 (22 of 40 trials step toward the player with `CM_75_RANDOM`, 40 of 40 with the roll removed) | creatures always moved toward the player |
| MON-014 | Accepted | Project maintainer, 2026-10-23 | Killed monsters drop treasure as in pinned VMS Moria `moria.inc` `monster_death`/`summon_object` (Umoria `monsterDeath` uses the same CMOVE bits 24-30): the creature's flags select object (bit 24), gold (25) or 50/50 mixed (both) drops, rolled as 60% one (26), 90% one (27), randint(2) (28), 2d2 (29) and 4d3 (30; Umoria 4d2), each placed in the 5x5 box around the kill with the chest-contents generator (`chest_generate_loot`, `docs/CHEST_DESIGN.md`: object or gold at the current depth, 10 placement attempts on a free floor or open-door tile). The flags are `cr_treasure` (`core/monster_death.s`), a tier SoA field after `cr_spell_flags` generated by `tools/parse_creatures.py` from the pinned Umoria list (67 of 120 shipped creatures carry treasure, e.g. Creeping Copper Coins `$12`, Orc `$0b`, Balrog `$7f`; town rows fixed). Only kills by the player stage a drop: melee, bash and `eff_kill_monster` (spells, missiles, earthquake, dispel) all reach `combat_note_kill`, which stages the flags at the position `monster_remove` left in `mfa_x`/`mfa_y`; genocide, polymorph and destruction remove without drops, as upstream `delete_monster`. Deviations: drops are placed when the command ends (`chest_fulfill_loot` at the top of `turn_post_action_searchable_or_die`), still before monsters act, rather than at the moment of the kill; at most 4 kills per command are staged (`MD_QUEUE_MAX`); occupied tiles are skipped and an object or gold amount follows the chest rules; the win flag (bit 31) stays with `combat_note_kill`. The queue is cleared with the monster table (new level) and on load. | maintainer direction 2026-10-23 ("why don't monsters drop stuff and can we fix that?" ... "yes proceed", option (a): a per-creature treasure byte) during the M4 goal; pinned VMS/Umoria sources; C64 `test_chest_loot.s` t10-t16 (production `chest_fulfill_loot`, `chest_generate_loot`, `eff_kill_monster`; t11 and t14 mutation-checked) | monsters dropped nothing (creature treasure bits were discarded by the generator) |
| MON-015 | Accepted | Project maintainer, 2026-10-24 | The monster acid attack (`ATK_ACID`, `mon_atk_effect_acid` in `core/monster_acid.s`) follows pinned VMS Moria `creature.inc` acid attack 6 -> `moria.inc` `acid_dam`/`minus_ac` (Umoria identical): after the attack's effect message, one worn armour piece is chosen with `rng_range(count)` among the occupied body, shield, head and hands slots (`EQUIP_BODY`-`EQUIP_HANDS`); if its base AC + to-AC is above 0 the game prints "Your <item description> is damaged!" (the description as the wear message gives it, before the change), lowers its to-AC by 1, recalculates equipment and halves the damage (`dam div 2`). Otherwise, or with nothing worn, the full damage lands. Deviations: VMS's cloak slot does not exist in Moria8; no Moria8 armour carries acid resistance and the player has no acid resistance, so VMS's "resists damage!" and divide-by-3/4 branches do not exist; acid damage to pack items (VMS `inven_damage`, "There is an acrid smell coming from your pack!") is not implemented. The C128 main image and the Apple IIe and BBC Master resident images carry the routine (`MON_ATK_ACID_EXTERNAL`) | maintainer direction 2026-10-24 ("Full VMS": rules and the named-item message) after M4's Green Naga deaths (`docs/AI_PLAYTEST_DESIGN.md` §15.4); pinned VMS `moria.inc` `acid_dam`, `minus_ac`; C64 `test_monster_attack.s` t18-t22 (production `mon_atk_effect_acid`; halving and random choice mutation-checked) | acid dealt full damage and left armour untouched |

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
| Fear attack save, duration, stacking and saturation (MON-012) | `platforms/commodore/c64/tests/test_monster_attack.s` t11, t14-t17 (production `mon_atk_effect_fear`, `player_saving_throw`) | `TEST_FILTER='monster_attack' make test64`; outcomes of the random save are asserted over 30 attempts |
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
| Player-speed cadence fold (haste, slow, Ring of Speed, cadence clamps) | `platforms/commodore/c64/tests/test_monster_ai.s` t36-t40 exercise the production `monster_ai_tick` directly | `TEST_FILTER='monster_ai' make test64`; C128/Plus4/Apple2 compile identical shared source and rely on product layout gates plus Apple2 runtime scenarios |
| One melee attack per monster action, no move after attacking (orthogonal and diagonal adjacency; VMS `make_move` ends the turn after `make_attack`) | `platforms/commodore/c64/tests/test_monster_ai.s` t57-t58 through production `monster_ai_tick` | `TEST_FILTER='monster_ai' make test64` |
| Adjacent monster within light is `MF_VISIBLE` even diagonally across a wall corner; blindness still hides it; distance 2 behind a wall stays hidden (MON-010) | `platforms/commodore/c64/tests/test_monster.s` t20-t22 through production `monster_update_visibility_all`; `test_effects.s` Test 35 through production `update_visibility` | `TEST_FILTER='monster|effects' make test64` |
| Monster spells and player saving throw (MON-011): wound dice, effect timers and stacking, resist path, heroism vs fear, spell bit dispatch incl. bits 6-7, save value/clamp, wis_adj thresholds, save extremes, paralysis con_adj | `platforms/commodore/c64/tests/test_monster_magic.s` t5, t7, t8, t15-t26 through production handlers and `monster_pick_spell`; `test_monster_ai.s` t15 | `TEST_FILTER='monster_magic|monster_ai' make test64` |
| Detected-only production free-look inspection | none | `NOT IMPLEMENTED` |
| Complete cross-platform timed Detect Monsters producer lifecycle | none | `NOT IMPLEMENTED` |
