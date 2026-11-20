# Turn And Render Contract

Load this document for turn consumption, visibility lifecycle, dirty/redraw
flags, auto-run/auto-rest, teleport/modal re-entry, or platform redraw paths.
Use `C128_MEMORY_CONTRACT.md` as well when physical VDC access, copy operations,
or banking changes.

## Authority

- Command/repeat lifecycle: `core/game_loop.s`
- Consumed-turn processing: `core/turn.s::turn_post_action`
- Shared redraw event storage: `core/turn_render_state.s`
- Terrain visibility: `core/dungeon_los.s`
- Monster visibility: monster visibility producer in shared monster code
- Physical rendering: platform-owned renderers

## Production Event Order

For a command that consumes a turn:

1. command mutates gameplay state
2. the command's staged monster drops are placed (`chest_fulfill_loot`,
   MON-014); a placed drop raises `zp_dirty_count`
3. `turn_post_action` clears the per-turn scene event
4. HP regeneration (from the turn's starting hunger, poison and rest state;
   TRN-009), then timed effects, hunger, light and pseudo-ID tick
5. monster AI runs
6. monster dirty result and pending `zp_dirty_count` promote scene dirtiness
7. turn counter advances and status becomes dirty
8. the main loop recomputes/consumes visibility and renders as required
9. repeat-command logic decides whether to continue on the next loop entry

Non-consuming commands do not pass through `turn_post_action`; their event
lifetime must therefore be traced separately.

## State And Event Inventory

| State/event | Class | Producer | Consumer/reset contract |
| --- | --- | --- | --- |
| `turn_scene_dirty` | pure render-dirtiness turn result that may be aggregated into command lifetime | monster AI/pending dirty tiles; forced-full-redraw command tail; search-mode OR of two consumed turns; earthquake | cleared at each `turn_post_action`, explicitly overwritten/aggregated by command helpers, then consumed by viewport render decisions only (decoupled from auto-rest and auto-run stop checks per TRN-014) |
| `zp_disturb` (`$69`, aliased `turn_rest_disturbed`) | shared repeat-command disturbance latch (unsaved ZP safe zone `$69`, preserved by `zp_save_buf`/`LegalSnapshot`) | `inc zp_disturb` on `MF_VISIBLE` `0 -> 1` sighting (`muvo_apply_visible`), visible hostile monster activity (`!mpo_done` when `(mat_action_dirty & $02) && (zp_mon_flags & MF_VISIBLE)`), monster door burst (`!mts_stuck`/`!mts_bash` shared `!mts_bash_set` tail), monster melee (`monster_attack_player` past `!map_has_atk0`), poison/starvation HP loss (`turn_apply_one_damage`), worsening hunger (`turn_maybe_play_hunger_alert`), player displacement (`eff_teleport_apply_target`, Word of Recall arrival), silent dangerous transitions (`ITR3_BLIND`/`ITR3_TIMID` `0 -> 1` onset, `zp_eff_hero` expiry, `eff_invuln_timer` expiry), and secret/trap discovery (`!ds_found_common`, fresh `chest_search_reveal`) | cleared on new game (`game_new_start`), load resume (`load_resume_reset_cold.s`), auto-rest entry (`cmd_autorest`), and at the top of each `run_step`; consumed with `zp_msg_flags` by `auto_rest_should_stop` and `!run_active_post` so stale prior-turn events are discarded and current-turn disturbances stop repetition (TRN-014) |
| `PLF_RESTING` (`$20` in `player_data + PL_FLAGS`) | active auto-rest UI state flag (mutually exclusive with `PLF_SEARCHING`, not bit 7) | set by `cmd_autorest` when starting auto-rest | read by `status_state` / Row 21 draw (`core/ui_status.s`) to render `"Rest*"` in `COL_YELLOW`; cleared with immediate `status_draw` in consolidated `!auto_rest_stop` on stop or cancel, and cleared on new game and load resume (TRN-014) |
| `turn_action_redraw_pending` (`zp_dirty_count`) | pending action-owned redraw latch | map/monster mutation helpers | folded into `turn_scene_dirty`, then cleared by `turn_post_action` |
| `vis_room_revealed` | visibility/full-viewport signal | LOS, room lighting, blindness changes | consumed by viewport redraw path |
| `disk_prompt_redraw_pending` | persistent full-screen redraw request | `asset_load_ask_for_disk` (a failed required load's "Insert program disk" screen) | tested and cleared (`lsr`) at the top of each `main_loop` pass, after the level-up recalc and before the command is read, by `ui_view_redraw_gameplay_view`: the prompt can come after the pass's render (level-up recalc, a command that took no turn) |
| `MF_VISIBLE` | current ordinary monster sight (`CD_INVISIBLE` `$80` gated by `PFLAG_SEE_INVIS \| zp_eff_see_inv \| zp_eff_invis`) | production visibility update (`muvo_apply_visible`) | renderer, search-mode & `zp_disturb` sighting/hostile-action disturbance (TRN-014), and ordinary targeting authority |
| `MF_DETECTED` | magical detection knowledge | timed Detect Monsters or immediate Detect Evil until its post-redraw clear | renderer, free-look, and monster dirty tracking; not ordinary targeting and does not disturb auto-rest/auto-run on its own |
| `mat_force_new_dirty` | per-move destination redraw override | `monster_try_step` when an unseen/phasing mover breaks a glyph, eats a `MF_VISIBLE \| MF_DETECTED` monster (`CM2_EATS_OTHER`), or picks up a floor item (`CM2_PICKS_UP`) | consumed and cleared by `mat_mark_move_dirty` / `mat_mark_tile_dirty_if_nonlocal` on the destination tile |

Do not combine events merely because both trigger drawing. Their reset boundary
and persistence class must match. A stale pulse cannot control a new command,
and clearing a pulse cannot erase an unconsumed persistent redraw request.

## Settled Visibility Rules

- Gameplay state, remembered terrain, current terrain visibility, monster
  visibility, detection, infravision and physical screen state are distinct.
- LOS and door/wall occlusion are decided by shared gameplay visibility, not by
  platform renderers.
- Renderers consume `MF_VISIBLE | MF_DETECTED`; ordinary spell targeting uses
  `MF_VISIBLE`, not detected-only state, as defined authoritatively by MON-001.
- Single-tile, dirty-region, scroll-delta and full redraw paths must converge on
  the same glyph and attribute result.
- Opening/closing doors, teleport, lit-room entry, blindness transitions and
  monster movement must invalidate the affected scene immediately.

## Repeated Commands

Auto-run and auto-rest are command lifecycles. A change must define whether the
first action occurs before re-entry, which prior-turn events are ignored, which
current-turn events stop repetition, and when pending redraws are consumed.

Required lifecycle cases when repeat logic changes:

- entry with a stale prior-turn event still set
- at least one successful continuation
- a stop event generated by the repeated turn
- user cancellation with pending redraw work
- horizontal and vertical movement where applicable

## Platform Contract

C64 and Plus/4 use their 40-column renderers. C128 uses the 80-column VDC and
may use block-copy/scroll-delta paths. Optimizations may differ, but final state
must agree. C128 horizontal and vertical movement, copied interiors and stale
dynamic-tile clearing require distinct production-path coverage.

## Conditional Verification Matrix

| Change | Required cases |
| --- | --- |
| Event lifetime | clean entry, stale entry, two producers before consumption, reset boundary |
| Visibility producer | blocked/open LOS, range boundary, blindness/light state, movement |
| Renderer consumer | visible-only, detected-only, neither; local and full redraw convergence |
| Repeat commands | first iteration, continuation, new stop event, cancellation |
| Re-entry | teleport and modal return before movement |
| Shared behavior | production producer through each affected platform renderer |

Tests that seed final flags prove renderer consumption only. They do not prove
the production visibility producer.

## Decision Ledger

Accepted rows dated 2026-07-09 record explicit maintainer decisions from the
work16 behavior review; this ledger is their durable approval provenance.

| ID | Status | Owner/date | Scope and selected rule | Evidence/enforcement | Supersedes |
| --- | --- | --- | --- | --- | --- |
| TRN-001 | Accepted | Project maintainer, 2026-07-09 | Renderers and inspection consume detected-only knowledge; targeting policy is owned solely by MON-001 | maintainer decision; renderer tests; free-look implementation evidence; inspection test `NOT IMPLEMENTED` | none |
| TRN-002 | Accepted | Project maintainer, 2026-07-09 | Searching consumes two turns and aggregates scene dirtiness from both | `core/game_loop_helpers.s::turn_post_action_searchable_or_die`; implementation review and partial main-loop tests | none |
| TRN-003 | Superseded in part | Project maintainer, 2026-07-09 | Auto-rest discards stale entry dirtiness, consumes at least one rest turn, and stops only for recovery, input, messages, or scene dirtiness produced during its own turns | `cmd_autorest`, `auto_rest_should_stop`; C64/C128 main-loop coverage | none; stop set superseded by TRN-007 and TRN-014 |
| TRN-004 | Superseded | Project maintainer, 2026-07-12 | Auto-run follows pinned VMS Moria `area_affect`/`pick_dir`: inspect the three newly adjacent squares, stop once before empty/open doorways and visible objects/monsters, stop at corridor choices, and follow unambiguous blocked-direction corners. | explicit maintainer direction; pinned VMS `area_affect`/`pick_dir`; C64 run fixtures and cross-platform runtime gates | ad hoc lighting and previous-tile doorway heuristics |
| TRN-005 | Superseded | Project maintainer, 2026-07-15 | Auto-run retains VMS leading-edge object and doorway checks, but applies UMoria's open-area rule at room edges: a blocked run inside a room stops and must not invoke enclosed-corridor corner following. Corridor corners remain eligible for an unambiguous turn. | reported room-perimeter loop; UMoria `player_run.cpp` open-area model; C64 room-edge and corridor-corner fixtures | TRN-004 blocked-direction corner scope |
| TRN-007 | Superseded | Project maintainer, 2026-10-21 | Auto-rest also stops when its own rest turn damages the player or worsens hunger. `turn_rest_disturbed` is an auto-rest-scoped latch, not a per-turn event: set only by `turn_apply_one_damage` (poison, starvation) and by `turn_maybe_play_hunger_alert` on a worse hunger state, cleared on auto-rest entry (`cmd_autorest`, stale handling as TRN-003), and read only by `auto_rest_should_stop`, so a nonzero value always means auto-rest's own turns disturbed the player. Apple IIe keeps the byte in resident RAM (`TURN_REST_DISTURBED_EXTERNAL`). Other damage already prints a message. | explicit maintainer direction 2026-10-21 to fix playtest finding F-M2-1 (a CTRL+R rest from 8/21 HP starved to death); pinned VMS Moria `take_hit` calls `rest_off`, and the hunger alerts interrupt resting; C64 `test_main_loop.s` t45-t46, `test_turn.s` t30-t33 | TRN-003 stop set; superseded by TRN-014 |
| TRN-006 | Accepted | Project maintainer, 2026-07-15 | Auto-run uses UMoria's complete CJS state machine and default options: cut known corners, examine potential corners, and stop for visible open-door objects. Doorless openings are ordinary open topology, not stop objects. Running tracks open-area and left/right wall breaks, scans the three or five newly adjacent squares after each successful move, stops for visible objects or monsters, follows unambiguous corridor turns, and stops when open-area topology changes. Moria8 initializes all runner state deterministically rather than retaining UMoria's process-static values. | explicit maintainer direction; upstream `umoria/src/player_run.cpp` and default configuration; production C64 runner fixtures; C64/C128 command-loop tests | TRN-004 and TRN-005 hybrid behavior |
| TRN-008 | Accepted | Project maintainer, 2026-10-22 | On platforms defining `HAL_PLATFORM_LEVELUP_MAGIC_USES_TRAMPOLINE` (all seven), a level-up applies level, HP, combat bonuses, sound and "Welcome to level N." at once, but the mana recalculation and new-spell check run at the top of the next `main_loop` pass, followed by `status_draw`. `levelup_magic_pending` is a flag (1 = owed), set by `combat_apply_levelup`, tested and cleared by `lsr` in `main_loop`, and cleared on new game and load. Reason: the magic trampolines load an overlay over the window, which stranded level-ups made by overlay code (thrown/fired missile, bash, spell) and hung wizard level-up. Effect: the new maximum mana and any "new spells" message appear after the monsters' turn of the levelling action rather than with the level-up message. | maintainer choice 2026-10-22 ("defer magic recalc") for playtest finding §14.10 item 3 in `docs/AI_PLAYTEST_DESIGN.md`; C64 static contracts `levelup_magic_deferred_contract`, `levelup_magic_main_loop_contract`; `make playtest-smoke` (C64 product build: throw via the `?` list, then wizard level-up and one more turn; fails on the pre-change build) | immediate in-command magic recalc |
| TRN-009 | Accepted | Project maintainer, 2026-10-22 | HP regeneration follows pinned VMS Moria `regenhp` (`moria.inc`, constants `player$regen_*` in `constants.inc`) in Umoria's 16.16 fixed point (`game_run.cpp` `playerRegenerateHitPoints`, `config.cpp` `PLAYER_REGEN_*`; identical at the pinned revision): each consumed turn, unless poisoned or at max HP, HP.fraction += max HP x rate + 1442, where rate is 197 full or hungry, 98 weak, 33 faint, 0 starving (food counter 0, Moria8's starvation-damage condition), doubled while auto-resting (`auto_rest_active`, VMS `rest > 0`; the base is not doubled); reaching max HP clears the fraction. `turn_tick_regen` runs first in `turn_post_action`, so the rate uses the turn's starting hunger, poison and rest state as upstream does. The fraction is `zp_regen_frac` (high byte, ZP `$42`, saved with the game) plus resident `regen_frac_lo` (cleared on new game and load, not saved). Whole HP are added through `eff_heal` (`core/eff_heal.s`). Deviations: the low fraction byte is not saved (a load loses under 1/256 HP); `zp_eff_regen` no longer affects HP regeneration (VMS x1.5; no Moria8 item or spell sets that timer); Umoria's search-mode doubling is not applied (VMS doubles only for rest). Old saves reuse `$42` (the former countdown) as the fraction high byte: under 1 HP once. Max HP must stay at or below 42,410 (24-bit product; at most 255 whole HP per turn). | explicit maintainer direction 2026-10-22 ("fix the overflow ... the formula would be ideal") after `docs/AI_PLAYTEST_DESIGN.md` §14.5; pinned VMS/Umoria sources; C64 `test_effects.s` 1-5, 32-38 (hand-computed from the upstream constants), `test_turn.s` t1 (order) and t2, `test_main_loop.s` t47 (real auto-rest flag) | CON-indexed `regen_rate` countdown (1 HP per 8-50 turns), which read past its 16-entry table for CON 18/01 and above |
| TRN-010 | Accepted | Project maintainer, 2026-10-22 | Poison damage follows pinned VMS Moria (`moria.inc` poisoned tick; Umoria `playerUpdatePoisonedState` identical): each turn the poison timer stays above 0, the player takes damage by `con_adj` (`player_con_hp_adj`, VMS `con_adj`): -4: 4 HP; -3 and -2: 3; -1: 2; 0 (CON 7-16): 1; 1-3 (CON 17 to 18/75 and 18/76-18/98): 1 HP on turns where `turn mod 2 = 0`; 4 (18/99+): 1 HP when `turn mod 3 = 0`, using the 16-bit turn counter before `turn_post_action` advances it. The expiry turn does no damage. Table `poison_damage` lives in `core/turn_data.s` (Apple IIe: resident main RAM, imported before the play slot). | explicit maintainer direction 2026-10-22 ("yes align the poison") after the M4 baseline found poison deaths (`docs/AI_PLAYTEST_DESIGN.md` §15); pinned VMS/Umoria sources; C64 `test_effects.s` 39-46 (production `turn_tick_effects` and `player_con_hp_adj`; mutation-checked), `test_turn.s` t9 | 1 HP every poisoned turn at any CON |
| TRN-011 | Accepted | Project maintainer, 2026-10-22 | The last paralyzed turn follows pinned VMS Moria (`moria.inc`: the turn's counter update runs `paralysis := paralysis - 1`, then "Accept a command?" when `paralysis < 1`, then creatures move) and Umoria `playDungeon` (`playerUpdateParalysis`, then `executeInputCommands`, then `updateMonsters`): when the main loop finds `zp_eff_paralyze` = 1, it clears it, prints the paralysis-end message and reads a command; the command's own `turn_post_action` then runs the timers and the monsters. Paralysis above 1 still spends whole turns (`turn_post_action`, which counts it down). Before, the expiring turn ran `turn_post_action`, so monsters acted between expiry and the player's first command, and a paralyzing attacker (White Mushroom patch) could re-paralyze the player forever. | explicit maintainer direction 2026-10-22 ("yes") after the M4 baseline (`docs/AI_PLAYTEST_DESIGN.md` §15.2: 8 of 32 deaths); pinned VMS/Umoria sources; C64 `test_main_loop.s` t48 (real main-loop paralysis dispatch; fails on the old order) | expiring paralysis as a monster turn |
| TRN-012 | Accepted | Project maintainer, 2026-11-16 (Phase 5 `CD_INVISIBLE` & `CM2_*` redraw rules) | (1) `muvo_apply_visible` (`core/monster.s`) clears `MF_VISIBLE` on `CD_INVISIBLE ($80)` creatures unless `(player_pflags & PFLAG_SEE_INVIS) \| zp_eff_see_inv \| zp_eff_invis` is nonzero; a creature newly gaining `MF_VISIBLE` turns off search mode (`player_search_mode_off`), whereas an unseen `CD_INVISIBLE` mover neither sets `MF_VISIBLE` nor triggers search-off until it attacks or becomes visible (`MF_DETECTED` continues to render under Detect Monsters per TRN-001). (2) `CM2_PHASE ($20)` creatures traverse interior walls/veins/rubble/doors without mutating tile or `door_state` bytes; when a visible or detected phasing creature steps into or out of a non-local viewport wall/door tile, `mat_mark_move_dirty` (`scene_render_mat_tile`) redraws both the vacated wall/door glyph and the newly occupied tile immediately. (3) When an unseen mover (`MF_VISIBLE == 0 && MF_DETECTED == 0`) mutates its destination tile by breaking a glyph, eating a `MF_VISIBLE \| MF_DETECTED` creature (`CM2_EATS_OTHER $40`), or removing a floor item (`CM2_PICKS_UP $80`), `monster_try_step` sets `mat_force_new_dirty` so `mat_mark_tile_dirty_if_nonlocal` still redraws the destination tile to erase the stale glyph, monster, or item glyph. | pinned VMS `creature.inc` (`update_mon`, `make_move`); C64 `test_monster_ai2.s` through production `monster_update_visibility_all` and `monster_ai_tick`; `make playtest-gate` | unconditional `MF_VISIBLE` in LOS; non-local redraw gated solely on mover `MF_VISIBLE \| MF_DETECTED` |
| TRN-013 | Accepted | Project maintainer, 2026-11-18 (Bugs A & B: overcast mana/faint/CON parity & Umoria-style CON max-HP sync) | (1) `player_calc_hp` (`core/player.s`) always writes both `player_data + PL_MHP_LO/HI` and `zp_player_mhp_lo/hi` and clamps `zp_player_hp_lo/hi` + `player_data + PL_HP_LO/HI` when `HP > MHP`, and every `CON` mutation site (`pm_consume_mana`, `mae_lose_stat`, `mae_lose_exp`, `trap_do_dart`, `ee_op_drain`, `ee_op_restore`, `eff_holy_word`, `player_adjust_equipment_stat` / Apple2 & BBC Master `player_adjust_equipment_stat_apply`) updates `zp_player_str,y` and calls `player_calc_hp` when `CON` changes so status-bar Row 22/23 (`status_draw` diffing `zp_player_con` and `zp_player_mhp_lo/hi`) never stays stale. (2) `pm_consume_mana` (`core/player_magic.s`) prints `"You faint from the effort!"` (`SPELL_MAGE`) vs `"You faint from fatigue!"` (`SPELL_PRIEST`) and, on the `1/3` CON-drain roll, prints `"You have damaged your health!"` before `-MORE-` acknowledgement. (3) `magic_recalc_mana` (`core/player_magic_tail.s`) uses `zp_temp1` rather than `pm_cost_tmp` so an in-cast `magic_recalc_mana` cannot overwrite the active spell's mana cost. | explicit maintainer bug report 2026-11-18 (Bugs A & B); pinned VMS `magic.inc:106-120`, `prayer.inc:99-113`, Umoria `player_stats.cpp:275-277`; C64 `test_overcast_ordering.s`, `test_player.s`, `test_ego.s`, C128 `test_prayer_prayer128.s` | `player_calc_hp` leaving `zp_player_mhp` stale; silent overcast CON drain; `magic_recalc_mana` clobbering `pm_cost_tmp` |
| TRN-014 | Accepted | Project maintainer, 2026-11-19 (GitHub Issue #21: complete auto-rest disturbance model) | (1) Unified disturbance latch `zp_disturb = $69` (repurposing unused `zp_dirty_lo` in the unsaved `$60-$8F` safe zone, preserved by `zp_save_buf`/`LegalSnapshot`, aliased as `turn_rest_disturbed`), retiring resident `turn_rest_disturbed` and `TURN_REST_DISTURBED_EXTERNAL`. (2) `turn_scene_dirty` is decoupled from both auto-rest and auto-run and becomes pure render dirtiness: `cmd_autorest` and `run_step` clear `zp_disturb` on entry/step to discard stale prior-turn events, while `auto_rest_should_stop` (after recovery check) and `!run_active_post` stop on `zp_msg_flags \| zp_disturb` (auto-rest also stops on full HP & MP recovery and cancel input; auto-run keeps TRN-006 CJS topology/object/monster rules). (3) Every dangerous or attention-worthy event runs `inc zp_disturb` (`2 B`, preserves A/X/Y/C): `MF_VISIBLE` `0 -> 1` sighting (`muvo_apply_visible`), visible hostile monster actions at any distance including moves inside `<= zp_light_radius + 1`, spells, silent `MSF2_BLINK`/`MSF2_TELE_SELF`, door opens, glyph breaks, and visible breeding (`!mpo_done` checking `(mat_action_dirty & $02) && (zp_mon_flags & MF_VISIBLE)` per MON-038), monster door bursts (`!mts_stuck`/`!mts_bash`), monster melee (`monster_attack_player` past `ATK_NONE`), poison/starvation HP loss (`turn_apply_one_damage`), worsening hunger (`turn_maybe_play_hunger_alert`), player displacement (`eff_teleport_apply_target`, Word of Recall arrival), silent dangerous transitions (cursed `ITR3_BLIND`/`ITR3_TIMID` onset `0 -> 1`, `zp_eff_hero` expiry MHP `-10` clamp, `eff_invuln_timer` expiry), and secret/trap discovery (`!ds_found_common` and fresh `chest_search_reveal`). Sleeping monsters (MON-005), unprovoked townies (`mat_action_dirty = $81`), detected-only monsters behind walls (`MF_DETECTED` without `MF_VISIBLE`), unseen `CD_INVISIBLE` creatures (TRN-012), and benign silent buff timers (`protect`, `invis`, `infra`, `resist`, `resist_cold`, `see_inv`, `eff_detect_timer`) stay quiet. (4) Auto-rest sets `PLF_RESTING ($20)` in `player_data + PL_FLAGS` (`cmd_autorest`), rendering `"Rest*"` in `COL_YELLOW` on Row 21 mutually exclusively with `"Search*"` (`core/ui_status.s`); consolidated `!auto_rest_stop` clears `auto_rest_active` and `PLF_RESTING` and calls `status_draw` immediately on stop or cancel, and new game (`game_new_start`) and load resume (`load_resume_reset_cold.s`) clear both `zp_disturb` and `PLF_RESTING`. | explicit maintainer direction 2026-11-19 (all 4 policy choices approved for GitHub Issue #21); pinned VMS `creature.inc:42-55, 697-757, 1191-1202` and Umoria `src/monster.cpp:54-60, 477-540, 610-613`; C64 `test_main_loop.s` t27/t34-t35/t37/t45-t46/t57-t59, `test_turn.s` t30-t39, `test_monster_ai2.s` t16-t23, `test_monster_attack.s` t55, `test_chest_disarm.s` t7, `test_ui_views.s` t25; C128 `test_main_loop128.s` t30/t39-t41 | TRN-003 and TRN-007 stop sets; resident `turn_rest_disturbed` / `TURN_REST_DISTURBED_EXTERNAL`; `turn_scene_dirty` coupling in auto-rest and auto-run |

## Executable Enforcement

| Invariant | Current gate | Command/status |
| --- | --- | --- |
| Dirty-latch promotion and monster dirty result | `platforms/commodore/c64/tests/test_turn.s` | `TEST_FILTER='turn' make test64` |
| Haste/slow timer decay toward zero and expiry messages at zero crossing | `platforms/commodore/c64/tests/test_turn.s` t27-t29 exercise production `turn_tick_effects` | `TEST_FILTER='turn' make test64` |
| C64 command/search/repeat lifecycle | `platforms/commodore/c64/tests/test_main_loop.s` | `TEST_FILTER='main_loop' make test64`; search tests do not prove asymmetric dirty-first/clean-second aggregation |
| C128 command/search/run redraw lifecycle | `platforms/commodore/c128/tests/test_main_loop128.s` | `TEST_FILTER='main_loop128' make test128`; search tests do not prove asymmetric dirty-first/clean-second aggregation |
| C128 physical scroll-delta rendering | `platforms/commodore/c128/tests/test_vdc_scroll_delta128.s` | `TEST_FILTER='vdc_scroll_delta128' make test128` |
| Plus/4 production visibility/render path | `platforms/commodore/plus4/tests/test_visibility_renderplus4.s` | `TEST_FILTER='visibility_renderplus4' make testplus4` |
| C64 modal return keeps physical color RAM visible | Wizard-item product smoke generates chest ID 128 and inspects `$01` plus physical `$D800-$DBE7` after redraw | `TEST_FILTER='wizard_item_product_smoke' make test64` |
| Chest-loot placement requests same-command scene redraw | Focused chest-loot latch test plus C64/Plus4 product smokes through real Open dispatch | `TEST_FILTER='chest_loot|chest_open_product_smoke' make test64`; `TEST_FILTER='chest_open_product_plus4' make testplus4` |
| Auto-rest & auto-run unified `zp_disturb` (`$69`) stop policy, render-only `turn_scene_dirty` decoupling, stale-entry discard, `PLF_RESTING` / Row 21 `"Rest*"` lifecycle, and silent dangerous transitions (TRN-014) | C64 `test_main_loop.s` t27, t34-t35, t37, t45-t46, t57-t59 (59/59); `test_turn.s` t30-t39 (39/39); `test_monster_ai2.s` t16-t23 (24/24); `test_monster_attack.s` t55 (55/55); `test_chest_disarm.s` t7 (8/8); `test_ui_views.s` t25 (25/25); C128 `test_main_loop128.s` t30, t39-t41 (41/41) through production `cmd_autorest`, `auto_rest_should_stop`, `run_step`, `turn_tick_effects`, `muvo_apply_visible`, `monster_ai_tick`, `monster_attack_player`, `eff_teleport_apply_target`, `chest_search_reveal`, `game_new_start`, `load_resume_game`, `status_draw` | `TEST_FILTER='^(main_loop\|turn\|monster_ai2\|monster_attack\|chest_disarm\|ui_views)$' make test64`; `TEST_FILTER='^main_loop128$' make test128-fast`; all 7 ports + 5 cartridges compile the identical shared producers and consumers |
| Deferred level-up magic recalc (TRN-008): flag set by `combat_apply_levelup`, run and cleared at the top of `main_loop` with `status_draw`; no stranded overlay code | C64 static contracts `levelup_magic_deferred_contract`, `levelup_magic_main_loop_contract`; playtest smoke on the C64 product build: throw through the `?` list, then wizard level-up and one more turn (fails on the pre-change build) | `TEST_FILTER='levelup_magic' make test64`; `make playtest-smoke`. No runtime test asserts the mana value after the deferred recalc |
| HP regeneration formula, rate selection, cap and fraction clear (TRN-009); regen runs first; resting rate follows the real auto-rest flag | C64 `test_effects.s` 1-5, 32-38 exercise production `turn_tick_regen` with hand-computed upstream values; `test_turn.s` t1 asserts the `turn_post_action` order; `test_main_loop.s` t47 records `turn_resting` through real `cmd_autorest`/`cmd_rest` dispatch | `TEST_FILTER='effects|turn|main_loop' make test64`; other platforms compile the identical shared routine. No runtime test covers save/load of the fraction |
| Poison damage by `con_adj` and turn parity (TRN-010) | C64 `test_effects.s` 39-46 run production `turn_tick_effects` with hand-derived VMS values, including the 16-bit turn counter | `TEST_FILTER='effects' make test64`; other platforms compile the identical shared routine |
| The last paralyzed turn reads a command before monsters act (TRN-011) | C64 `test_main_loop.s` t48 through the real `main_loop` paralysis branch | `TEST_FILTER='main_loop' make test64`; other platforms compile the identical shared loop |
| SHIFT+X weapon exchange (`cmd_exchange`, status-only tail): a swap consumes one turn (two in search mode, TRN-002), a refusal none | C64 `test_main_loop.s` t51-t53 and C128 `test_main_loop128.s` tests 35-37 (real key map and dispatch, stub trampoline); product smokes on all 7 ports check the turn counter | `TEST_FILTER='main_loop' make test64`; `TEST_FILTER='main_loop128\|exchange_product_smoke128' make test128` |
| A disk prompt since the last pass rebuilds the gameplay view before the next command, and the request is cleared | C64 `test_main_loop.s` t54 and C128 `test_main_loop128.s` test 38 through the real `main_loop` (both fail without the redraw) | `TEST_FILTER='main_loop' make test64`; `TEST_FILTER='main_loop128' make test128-fast`; other platforms compile the identical shared loop and prompt |
| `CD_INVISIBLE` visibility/search-off gate, `CM2_PHASE` wall/door non-mutation & non-local wall redraw, and `mat_force_new_dirty` redraw on unseen eat/pickup/glyph-break (TRN-012) | C64 `test_monster_ai2.s` through production `monster_update_visibility_all` and `monster_ai_tick` | `TEST_FILTER='monster_ai2' make test64`; all 7 ports compile the identical shared visibility/dirty producers |
| Overcast arcane/divine faint messages, overcast CON-drain feedback before `-MORE-`, `magic_recalc_mana` non-clobber of `pm_cost_tmp`, and `player_calc_hp` ZP `zp_player_mhp` sync & `HP <= MHP` clamp across CON mutations (TRN-013) | C64 `test_overcast_ordering.s`, `test_player.s` t7, `test_ego.s` t22, and C128 `test_prayer_prayer128.s` t3 | `TEST_FILTER='^(overcast_ordering\|player\|ego)$' make test64`; `TEST_FILTER='^prayer_prayer128$' make test128-fast` |
| Search two-turn dirty aggregation with dirty/clean and clean/dirty orderings | none | `NOT IMPLEMENTED` |
| Detected-only production free-look inspection | none | `NOT IMPLEMENTED` |

## License/source modal repair verification (2026-11-11)

`make -j7 -O test` passed. The production title/Help/legal paths execute on all
seven renderers; Commodore fixtures cover exact-width lines, split CRLF and
EOF at the page boundary. The PAL/NTSC cartridge Help path, both with normal
and simulated Ultimate detection, checks dirty bits from entry and the modal
before caller redraw consumes them, plus sound expiry during input. Normal
Help return reaches gameplay before movement without consuming turns or RNG.
Entry and exit use the same live-sound and dirty-OR policy. C64/Plus4
snapshot after media prompting so a message reset cannot be rolled back by
viewer entry; production tests seed stale message flags across that prompt.
Injected refill errors reach the error screen without consuming cache bytes
or hiding the error at a page prompt. Optional Apple/Atari/BBC overlay loads
can be cancelled from the cold title before normal title/Help entry.
These complete the applicable event-lifetime, modal re-entry and shared-render
rows. Visibility producers/consumers, repeat and teleport rules are N/A: this
repair changes the document renderer and its return, not those implementations.
See `docs/LEGAL_VIEWER.md` for payload ownership and the complete change record.


Pass 3 cancellation verification (2026-11-11): `make -j7 -O test` passed.
On Apple/Atari/BBC, a failed optional legal load returns C=1 on Escape. Help
then exits through the existing gameplay redraw instead of loading HELP from
the absent program disk; Title draws a resident menu instead of loading TITLE.
One caller snapshot survives repeated failures and successful retry; a
write observer checks restored core ZP at the cancel boundary, preserving the
sound/dirty exceptions. These complete the affected retry, modal-re-entry and
shared-render rows. Other ports retain the existing compiled Help path.

## Phase 5 `CD_INVISIBLE` Visibility & `CM2_*` Non-Local Redraw Verification (2026-11-16)

```text
Problem and success criteria:
  Keep terrain/monster glyph state converged across local and non-local redraws
  when Phase 5 introduces invisible monsters (CD_INVISIBLE $80), wall/door-phasing
  monsters (CM2_PHASE $20), monster-eating monsters (CM2_EATS_OTHER $40), and
  item-pickup monsters (CM2_PICKS_UP $80).
State being changed:
  - core/monster.s::muvo_apply_visible: gates MF_VISIBLE and search-off disturbance
    on !(cr_cdefense & CD_INVISIBLE) || PFLAG_SEE_INVIS || zp_eff_see_inv || zp_eff_invis.
  - core/monster_ai.s: adds mat_force_new_dirty (cleared at start of monster_process_one
    and after mat_mark_tile_dirty_if_nonlocal), raised when monster_try_step breaks a
    glyph, eats a visible/detected monster, or removes a floor item; preserves old
    wall/door terrain bytes across CM2_PHASE moves while letting mat_mark_move_dirty
    restore vacated non-local wall/door glyphs via scene_render_mat_tile.
  - core/monster_attack_effects.s (mae_steal) & core/monster_magic.s (MSF2_BLINK,
    MSF2_TELE_SELF, MSF2_SUMMON_UNDEAD) & core/spell_effects.s (CD_LIGHT, CD_STONE):
    increment zp_dirty_count on monster teleport/spawn/kill mutations.
Search scope and terms:
  rg across core/ and platforms/ for MF_VISIBLE, MF_DETECTED, mat_mark_move_dirty,
  mat_mark_tile_dirty_if_nonlocal, scene_render_mat_tile, zp_dirty_count, vis_room_revealed.
Relevant readers/writers found and known exclusions:
  All 7 platform renderers consume MF_VISIBLE | MF_DETECTED and FLAG_OCCUPIED /
  FLAG_HAS_ITEM identically through shared scene_render_mat_tile and viewport
  redraw paths; mat_mark_move_dirty preserves mat_force_new_dirty across the
  old-tile check via pha/pla so only the destination tile receives the override.
Initialization, reset and persistence points:
  mat_force_new_dirty is cleared per-monster in monster_process_one and at exit of
  mat_mark_tile_dirty_if_nonlocal (transient scratch, not saved).
Affected production sequence through the changed transition:
  turn_post_action -> monster_ai_tick -> monster_process_one -> monster_try_step
  -> mat_mark_move_dirty -> mat_mark_tile_dirty_if_nonlocal -> scene_render_mat_tile
  -> mat_scene_dirty promoted into turn_scene_dirty -> main_loop monster_update_visibility_all
  and local/full viewport render.
Contract decision or selected upstream oracle with source locations:
  TRN-001, MON-001, MON-034, MON-035, and TRN-012 above; pinned VMS creature.inc
  update_mon and make_move.
Intentional Moria8 deviations:
  None to visibility or redraw convergence.
Input/intermediate widths, signedness, carry, range and overflow policy:
  8-bit flag masks ($80 CD_INVISIBLE, $08 MF_VISIBLE, $10 MF_DETECTED) and boolean/count
  scratch mat_force_new_dirty.
RNG reduction and bias, if applicable:
  N/A for visibility and dirty-tile tracking.
Affected platforms, overlays, banks and owners:
  Shared core/monster.s (Default resident on all 7 ports) and core/monster_ai.s.
Required production-path tests:
  C64 test_monster_ai2.s (invisible sight, see-invis equipment/timers, Detect Monsters
  MF_DETECTED, CM2_PHASE wall preservation & redraw, CM2_EATS_OTHER & CM2_PICKS_UP
  mat_force_new_dirty) plus 7-port + 5-cartridge make playtest-gate.
Known behavior explicitly out of scope:
  Detected-only free-look unit test (TRN-001).
Unresolved uncertainty and risk:
  None.
```

## Overcast Mana/Faint/CON Parity & CON Max-HP Sync Verification (TRN-013, 2026-11-18)

```text
Problem and success criteria:
  (A) Prevent magic_recalc_mana from overwriting pm_cost_tmp with class_spell_min_level;
  (B) Emit separate VMS arcane/divine faint messages ("You faint from the effort!" /
  "You faint from fatigue!") plus "You have damaged your health!" on the 1/3 overcast CON
  drain before -MORE- acknowledgement, and recompute max HP + zp_player_mhp_lo/hi (clamping
  HP <= MHP) on every CON change across all 7 ports.
State being changed:
  - core/player_magic_tail.s::magic_recalc_mana: uses zp_temp1 instead of pm_cost_tmp.
  - core/player_magic.s::pm_consume_mana: selects HSTR_PM_FAINT_EFFORT vs HSTR_PM_NO_MANA
    from PL_SPELL_TYPE, prints HSTR_PM_HEALTH_DAMAGED on the 1/3 CON roll, decrements
    PL_CON_CUR & zp_player_con, calls player_calc_hp, and acknowledges via msg_show_more.
  - core/player.s::player_calc_hp: syncs zp_player_mhp_lo/hi and clamps zp_player_hp_lo/hi
    and PL_HP_LO/HI when HP > MHP.
  - core/player_adjust_equipment_stat.s, platforms/apple2/main.s, platforms/bbcmaster/main.s,
    core/trap_trigger_cold.s, core/eff_item_extended.s, core/player_magic_utility.s: sync
    zp_player_str,y and invoke player_calc_hp whenever CON changes.
Search scope and terms:
  rg across core/, platforms/, playtest/, and upstream vms-moria/umoria for pm_cost_tmp,
  pm_consume_mana, player_calc_hp, PL_CON_CUR, zp_player_con, player_adjust_equipment_stat.
Relevant readers/writers found and known exclusions:
  Potion of Gain Constitution (core/eff_gain_stat.s) already maintains VMS +1 MHP across
  both PL_MHP and zp_player_mhp + eff_heal_full; playtest/moria_playtest/magic.py infrastructure
  findings are reported separately under AGENTS.md Rule 5 without unrequested edits.
Initialization, reset and persistence points:
  player_sync_to_zp / player_sync_from_zp sync PL_HP_LO..PL_MAX_MANA and ZP mirrors on
  chargen, save, and load; load_resume_game runs player_calc_hp to converge both copies.
Affected production sequence through the changed transition:
  player_cast_spell / player_pray -> tramp_spell_execute_selected -> pm_finish_success_common
  -> pm_consume_mana -> huff_print_msg -> player_calc_hp -> msg_show_more -> main_loop status_draw.
Contract decision or selected upstream oracle with source locations:
  Pinned VMS magic.inc:106-120, prayer.inc:99-113; pinned Umoria mage_spells.cpp:251-264,
  player_pray.cpp:256-269, player_stats.cpp:24-60, 275-277 (TRN-013 above).
Intentional Moria8 deviations:
  Overcast CON drain uses 1-point decrement down to min 3 (preserving standalone C128
  spell-unit harness linkage).
Input/intermediate widths, signedness, carry, range and overflow policy:
  16-bit unsigned MHP/HP comparison (cpx zp_player_hp_lo / sbc zp_player_hp_hi) clamps
  HP > MHP across 0..65535.
RNG reduction and bias, if applicable:
  Unchanged (rng_range(5 * missing_mp) + 1 paralysis; rng_range(3) == 1 1/3 CON drain).
Affected platforms, overlays, banks and owners:
  All 7 ports + 5 cartridges; core/player.s shrinks net -44 B via 6-byte vital/stat loops,
  keeping Apple IIe Default ($7BBB < $7C00), Atari Default ($C0E2 < $C100), C64 Default,
  C128 128.bank/128.huff, Plus/4 Plus4HuffIndex (16 B tail intact), and BBC Master ANDY
  within all hard boundaries.
Required production-path tests:
  C64 test_overcast_ordering.s, test_player.s, test_ego.s, C128 test_prayer_prayer128.s,
  full 7-port make test, and 65-target make playtest-gate.
Known behavior explicitly out of scope:
  Playtest bot book-tracking fix in playtest/moria_playtest/magic.py (reported per Rule 5).
Unresolved uncertainty and risk:
  None.
```

## Complete Auto-Rest & Auto-Run Disturbance Model Verification (TRN-014, 2026-11-19)

```text
Problem and success criteria:
  Resolve GitHub Issue #21 across all 7 ports and 5 cartridges by replacing the
  partial render-coupled rest/run stop checks with a unified ZP disturbance latch
  (zp_disturb = $69) decoupled from pure render-dirtiness turn_scene_dirty, wiring
  every dangerous or attention-worthy producer (sighting, visible hostile activity
  at any distance including <= zp_light_radius + 1, melee, door burst, damage,
  worsening hunger, displacement, silent dangerous status transitions, and
  secret/trap discovery) while keeping sleeping monsters (MON-005), unprovoked
  townies, detected-only monsters behind walls, unseen CD_INVISIBLE creatures
  (TRN-012), and benign silent buff timers quiet, and rendering "Rest*" on Row 21
  via PLF_RESTING.
State being changed:
  - core/zeropage.s: repurposes dormant $69 (zp_dirty_lo) as zp_disturb (aliased
    turn_rest_disturbed) in the unsaved $60-$8F safe zone.
  - core/turn.s & platforms/{apple2,bbcmaster,cx16}/main.s: removes resident
    turn_rest_disturbed and TURN_REST_DISTURBED_EXTERNAL (shifting CX16
    levelup_magic_pending to $0699); updates damage/hunger alerts and adds
    wrap-safe inc zp_disturb on ITR3_BLIND 0 -> 1 onset, ITR3_TIMID 0 -> 1 onset,
    zp_eff_hero expiry, eff_invuln_timer expiry, and Word of Recall arrival
    (fizzle stays quiet).
  - core/monster.s::muvo_apply_visible: adds inc zp_disturb beside
    player_search_mode_off on MF_VISIBLE 0 -> 1 sighting.
  - core/monster_ai.s: tags mat_action_dirty bit 1 ($02) for hostile actions
    ($03 spells/breeding/door-open/glyph-break, $83 hostile moves; $81 kept for
    unprovoked townies); !mpo_done runs inc zp_disturb when (mat_action_dirty & $02)
    && (zp_mon_flags & MF_VISIBLE); door bursts (!mts_stuck, !mts_bash) share
    !mts_bash_set running inc zp_disturb alongside HSTR_MAT_DOOR_BURST (net -1 B).
  - core/monster_attack.s: adds inc zp_disturb right after !map_has_atk0 (past
    ATK_NONE early exit).
  - core/spell_effects.s::eff_teleport_apply_target: adds inc zp_disturb beside
    player_search_mode_off.
  - core/dungeon_features.s (!ds_found_common) & core/chest_search.s
    (chest_search_reveal): adds inc zp_disturb on secret door, floor trap, and
    fresh chest trap discovery (already-found chest repeat stays quiet).
  - core/game_loop.s & core/load_resume_reset_cold.s: decouples turn_scene_dirty
    from auto-rest and auto-run; cmd_autorest sets PLF_RESTING & clears
    zp_disturb (and branches via bcs !toggle_done- to call status_draw if
    already at full vitals so clearing PLF_SEARCHING immediately erases
    "Search*", saving 3 B); auto_rest_should_stop checks recovery then
    zp_msg_flags | zp_disturb; consolidated !auto_rest_stop clears
    auto_rest_active + PLF_RESTING and calls status_draw; run_step clears
    zp_disturb on entry and !run_active_post checks zp_msg_flags | zp_disturb;
    game_new_start and load_resume_reset_cold.s clear zp_disturb and PLF_RESTING.
  - core/ui_status.s: adds status_resting_str ("Rest*", +6 B) in StatusTextSegment,
    extends status_state to (PLF_SEARCHING | PLF_RESTING) with bit-7 .assert, and
    draws "Rest*" in COL_YELLOW mutually exclusively with "Search*" on Row 21.
  - platforms/bbcmaster/harness_smoke.py: clears PLF_RESTING in player_data +
    PL_FLAGS alongside direct AUTO_REST_ACTIVE_ADDR = 0 reset in dungeon_descend,
    and (per user-approved Rule-5 fix) preserves live $FE34 HAZEL bit 3 ($08)
    via enter_shadow()/leave_shadow() across all 5 LYNNE shadow-RAM helpers.
  - platforms/commodore/plus4/tests/hot_gameplay_zero_disk_smoke.py (per
    user-approved Rule-5 fix): lowers arrow-trap fixture hp/mhp from 200/200 to
    50/50 (expected 42..49) so 4-turn VMS regen (< 1 HP) cannot heal 1d8 rolls
    of 1-2 back to max HP.
Search scope and terms:
  rg across core/ and platforms/ for turn_rest_disturbed, TURN_REST_DISTURBED_EXTERNAL,
  turn_scene_dirty, zp_dirty_lo, auto_rest_active, auto_rest_should_stop, run_step,
  PLF_RESTING, mat_action_dirty, muvo_apply_visible, HSTR_MAT_DOOR_BURST,
  eff_teleport_apply_target, ds_found_common, chest_search_reveal.
Relevant readers/writers found and known exclusions:
  turn_scene_dirty remains solely for viewport redraw scheduling; benign silent
  buff timers in !tse_loop (protect, invis, infra, resist, resist_cold, see_inv)
  and eff_detect_timer remain quiet; plain door opens (!mts_open_plain) add no
  extra door-tile LOS check because muvo_apply_visible catches the opener entering
  sight.
Initialization, reset and persistence points:
  zp_disturb ($69) sits in the unsaved $60-$8F safe zone (preserved across KERNAL
  I/O and legal viewer snapshots by zp_save_buf/LegalSnapshot) and is cleared in
  game_new_start, load_resume_reset_cold.s, cmd_autorest, and run_step.
  PLF_RESTING ($20) in player_data + PL_FLAGS is set in cmd_autorest and cleared
  in !auto_rest_stop, game_new_start, and load_resume_reset_cold.s (zero save
  format change).
Affected production sequence through the changed transition:
  cmd_autorest -> set auto_rest_active + PLF_RESTING, clear zp_disturb ->
  turn_post_action -> turn_tick_effects / monster_ai_tick -> inc zp_disturb ->
  main_loop monster_update_visibility_all (muvo_apply_visible -> inc zp_disturb)
  -> status_draw -> auto_rest_should_stop -> !auto_rest_stop (clear PLF_RESTING
  + status_draw); analogously run_step -> clear zp_disturb -> turn_post_action
  -> !run_active_post (zp_msg_flags | zp_disturb).
Contract decision or selected upstream oracle with source locations:
  TRN-014 and MON-038; pinned VMS Moria source/include/creature.inc:42-55,
  697-757, 1191-1202 and pinned Umoria src/monster.cpp:54-60, 477-540, 610-613.
Intentional Moria8 deviations:
  Unified single-byte zp_disturb latch instead of separate rest/run/search stop
  flags; benign silent buff expiries remain quiet; Row 21 shows compact "Rest*"
  (6 B) rather than full-word "Resting".
Input/intermediate widths, signedness, carry, range and overflow policy:
  inc zp_disturb is an 8-bit non-zero latch tested via ora zp_msg_flags; at most
  a handful of disturbance producers fire within a single turn before the next
  repeat consumer clears it (never approaches 256 increments in one turn).
  PLF_RESTING ($20) is assert-guarded not bit 7 so status_state bit 7 stays
  reserved for zp_eff_poison.
RNG reduction and bias, if applicable:
  N/A (no RNG changes).
Affected platforms, overlays, banks and owners:
  All 7 ports + 5 cartridges pass make build, check-hal-boundaries, make disk,
  check_overlay_calls.py (12 targets, 0 violations), check128-payloads, all
  static memory contracts, and tools/report_memory_budgets.py (0 overflows
  across all 12 product builds and all freshly rebuilt test-variant PRGs;
  0 stray artifacts in core/, platforms/, docs/):
    - C64 disk/cart: Default $BF80/$C000 (128 B) / $B585 (2,683 B);
      64.bank $FFC9/$FFFA (49 B); ovl.storage $EFE4/$F000 (28 B).
    - Plus/4 disk/cart: Default $C6F2/$C800 (270 B) / $C102 (1,790 B);
      4.bank $FBA7/$FC00 (89 B) / $FAF3 (269 B); ovl.storage $EFEE (18 B) / $EFF1 (15 B).
    - C128 disk/cart: Default $AE66/$AF00 (154 B) / $AC31 (719 B);
      128.play $CEBA/$D000 (326 B); 128.bank $FEDA/$FF00 (38 B);
      128.runtime $19F3/$1A00 (13 B); ovl.home (45 B).
    - Apple IIe disk: Default $7BD2/$7C00 (46 B); A2PlaySlot $9F4E/$A000 (178 B);
      ovl.storage $B917/$BA00 (233 B).
    - CX16 disk/cart: Default $930D/$9B00 (2,035 B) / $92F1 (2,063 B);
      OVL.STORAGE $AC6B/$C000 (5,013 B).
    - Atari 8-bit disk/cart: Default $C0AC/$C100 (84 B) / $BD65 (923 B);
      ATARI.BNK $FF8F/$FFFA (107 B) / $FEAD (333 B);
      OVL.STO $EE39/$F000 (455 B) / $EE35 (459 B).
    - BBC Master 128: Default $7F77/$8000 (137 B); BeebPlaySlot $A348/$A400 (184 B);
      ovl.storage $B705/$C000 (2,299 B).
    - Tightest rebuilt test-variant PRGs: c128 titleart 24 B free ($AEE8/$AF00),
      c128 skipovl2 57 B free ($AEC7/$AF00), c64 moria_ego_damage_smoke 1,507 B
      init-tail / ~44 B est. resident ($C81D/$CE00).
Required production-path tests:
  Unit & contract suites: C64 test_main_loop.s t27/t34-t35/t37/t45-t46/t57-t59
  (59/59), test_turn.s t30-t39 (39/39), test_monster_ai2.s t16-t23 (24/24),
  test_monster_attack.s t55 (55/55), test_chest_disarm.s t7 (8/8),
  test_ui_views.s t25 (25/25); C128 test_main_loop128.s t30/t39-t41 (41/41),
  monster128, status_coherence128.
  Full cross-port runtime & playtest gates (all 5 ROM env vars present; 0
  product defects): test-prebuild PASS; C128 make test128 PASS (141/141 +
  c128-legal 6/6 + c128-cartridge PAL 23/23 & NTSC 23/23); Apple IIe 26/26
  PASS; CX16 27/27 + cartridge PASS; Atari 8-bit 21/21 (16 a800xl + 5 a130xe)
  + 6/6 cartridge PASS; C64 run_tests.sh 224/224 PASS + test64-cartridge PAL
  28+10 & NTSC 28+10 PASS + test64-legal title PASS; Plus/4 make testplus4 PASS
  (plus4-legal 6/6 + run_testsplus4.sh 47/47, incl. hot_gameplay_zero_disk_product_plus4
  hp=50->48) + testplus4-cartridge PAL 20+11 & NTSC 20+11 PASS; BBC Master
  make testbbcmaster-runtime PASS (18/18, incl. boot_title 9/9 and
  dungeon_descend Ctrl+R/PLF_RESTING); make playtest-gate 65/65 PASS, 0 failed,
  0 targets skipped (exit 0; incl. plus4 5/5 [39-step tour + 4 characters],
  plus4-cart 5/5 [39-step tour + 4 characters], and JiffyDOS-enabled c64/c128
  targets alongside c64-cart, c64-noreu, c128-cart, apple2, atari8,
  atari8-cart, bbcmaster, cx16, and cx16-cart).
Known behavior explicitly out of scope:
  Numeric repeat prefixes (0-9 / ^num) and VMS rest-for-N-turns prompt.
Unresolved uncertainty and risk:
  Zero product or test-suite defects remain (all 7 ports, all 5 cartridges,
  and 65/65 make playtest-gate passed); the sole external timing caveat is
  test64-legal help hitting its 30s wall-clock cap on the very last post-return
  bsave (memory(0xC000, 3840) after key("Q") returned to gameplay $AD22) under
  sustained external host load 32.81-43.85 (title passed; not a product hang).
```


