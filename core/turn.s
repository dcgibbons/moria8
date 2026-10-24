#importonce
#import "generation_busy_api.s"
// turn.s — Turn processing routines
//
// The main loop (main.s) dispatches player commands directly and calls
// turn_post_action after each action that consumes a turn. This module
// provides the post-action processing: effect timers, hunger, turn
// counter, HP regeneration, and status dirty flag.

#import "turn_render_state.s"
#import "eff_heal.s"
#import "turn_data.s"

// Hunger thresholds
.const FOOD_HUNGRY_AT   = 150   // Food counter below this = hungry
.const FOOD_WEAK_AT     = 50    // Below this = weak
.const FOOD_FAINT_AT    = 10    // Below this = faint

// player_update_hunger_state — classify hunger from the current food counter
// Output: zp_hunger_state updated to FULL / HUNGRY / WEAK / FAINT
// Preserves: nothing
player_update_hunger_state:
    lda zp_player_food_hi
    bne !full+              // Hi byte > 0 means plenty of food

    lda zp_player_food
    cmp #FOOD_FAINT_AT
    bcc !faint+
    cmp #FOOD_WEAK_AT
    bcc !weak+
    cmp #FOOD_HUNGRY_AT
    bcc !hungry+
!full:
    lda #HUNGER_FULL
    sta zp_hunger_state
    rts
!hungry:
    lda #HUNGER_HUNGRY
    sta zp_hunger_state
    rts
!weak:
    lda #HUNGER_WEAK
    sta zp_hunger_state
    rts
!faint:
    lda #HUNGER_FAINT
    sta zp_hunger_state
    rts

// turn_rest_disturbed — the player took damage or got hungrier. Set by the
// producers below; cleared when auto-rest starts (cmd_autorest), so while
// auto-rest runs a nonzero value means one of its own rest turns disturbed
// the player and it must stop (VMS Moria take_hit -> rest_off, hunger
// alerts; TRN-007). Platforms with a full play slot define it elsewhere.
#if !TURN_REST_DISTURBED_EXTERNAL
turn_rest_disturbed: .byte 0
#endif

// turn_maybe_play_hunger_alert — Alert only when hunger gets worse.
// Input: A = previous hunger state, zp_hunger_state = current state
turn_maybe_play_hunger_alert:
    cmp zp_hunger_state
    bcs !done+              // Same or improved state: no alert
    inc turn_rest_disturbed

    lda zp_hunger_state
    cmp #HUNGER_FAINT
    beq !faint+

    lda #SFX_HUNGER_WARN
    jmp hal_sound_play
!faint:
    lda #SFX_HUNGER_FAINT
    jmp hal_sound_play
!done:
    rts

// ============================================================
// Subroutines
// ============================================================

// turn_tick_effects — Decrement all active status effect timers
// When a timer reaches 0, prints expiration message.
// Preserves: nothing
turn_tick_effects:
    // Poison
    lda zp_eff_poison
    beq !no_poison+
    dec zp_eff_poison
    bne !poison_still+
    // Just expired — print message
    ldx #HSTR_EFF_POISON_END
    jsr huff_print_msg
    jmp !no_poison+
!poison_still:
    // Poison damage by VMS Moria con_adj (moria.inc; Umoria
    // playerUpdatePoisonedState): poison_damage[con_adj + 4] HP a turn, or
    // with bit 7 set, 1 HP on turns where turn mod (low bits) is 0 (TRN-010).
    lda player_data + PL_CON_CUR
    jsr player_con_hp_adj       // A = con_adj, -4..4
    clc
    adc #4
    tax
    lda poison_damage,x
    bpl !poison_hits+
    and #$7f
    tax
    lda zp_turn_lo
    sta zp_math_a
    lda zp_turn_hi
    sta zp_math_b
    jsr math_div_16x8           // A = turn mod X (Y preserved)
    bne !no_poison+
    lda #1
!poison_hits:
    tay
!poison_hit:
    jsr turn_apply_one_damage   // Clamped at 0; preserves Y
    dey
    bne !poison_hit-
    lda #DEATH_POISON
    sta zp_death_source
    jsr player_death_check
!no_poison:

    // Blindness
    lda zp_eff_blind
    beq !no_blind+
    dec zp_eff_blind
    bne !no_blind+
    // Just expired — print message and trigger viewport redraw
    ldx #HSTR_EFF_BLIND_END
    jsr huff_print_msg
    lda #1
    sta vis_room_revealed       // Trigger full viewport redraw
!no_blind:

    // Confusion
    lda zp_eff_confuse
    beq !no_confuse+
    dec zp_eff_confuse
    bne !no_confuse+
    // Just expired — print message
    ldx #HSTR_EFF_CONFUSE_END
    jsr huff_print_msg
!no_confuse:

    // Paralysis
    lda zp_eff_paralyze
    beq !no_para+
    dec zp_eff_paralyze
    bne !no_para+
    // Just expired — print message
    ldx #HSTR_EFF_PARALYZE_END
    jsr huff_print_msg
!no_para:

    // Fear
    lda eff_fear_timer
    beq !no_fear+
    dec eff_fear_timer
    bne !no_fear+
    // Just expired — print message
    ldx #HSTR_EFF_FEAR_END
    jsr huff_print_msg
!no_fear:

    // Haste/slow
    lda zp_eff_speed
    beq !no_speed+
    // Signed decrement toward 0
    bpl !pos_speed+
    inc zp_eff_speed        // Negative, increment toward 0
    bne !no_speed+
    ldx #HSTR_EFF_SLOW_END
    bne !speed_msg+         // always taken
!pos_speed:
    dec zp_eff_speed        // Positive, decrement toward 0
    bne !no_speed+
    ldx #HSTR_EFF_HASTE_END
!speed_msg:
    jsr huff_print_msg
!no_speed:

    // Simple-dec effects: protect($55), invis($56), infra($57),
    // heat/fire resist($58), [skip bless($59)], [skip hero($5a)], regen($5b),
    // cold resist($5c)
    .assert "Simple-dec range", eff_resist_cold_timer - zp_eff_protect, 7
    ldy #zp_eff_protect
!tse_loop:
    cpy #zp_eff_bless
    beq !tse_next+
    cpy #zp_eff_hero
    beq !tse_next+
    lda $00,y
    beq !tse_next+
    sec
    sbc #1
    sta $00,y
!tse_next:
    iny
    cpy #eff_resist_cold_timer + 1
    bne !tse_loop-

    // Blessed / Prayer
    lda zp_eff_bless
    beq !no_bless+
    sec
    sbc #1
    sta zp_eff_bless
    bne !no_bless+
    lda #<turn_prayer_off_msg
    sta zp_ptr0
    lda #>turn_prayer_off_msg
    sta zp_ptr0_hi
    jsr msg_print
!no_bless:

    // Heroism: expiration removes the temporary +10 HP granted on activation.
    lda zp_eff_hero
    beq !no_hero+
    sec
    sbc #1
    sta zp_eff_hero
    bne !no_hero+

    lda player_data + PL_MHP_LO
    sec
    sbc #10
    sta player_data + PL_MHP_LO
    sta zp_player_mhp_lo
    lda player_data + PL_MHP_HI
    sbc #0
    sta player_data + PL_MHP_HI
    sta zp_player_mhp_hi

    // If current HP is now above max, clamp current HP down to max.
    lda #0
    jsr eff_heal                // HP += 0, capped at max HP, synced
!no_hero:

    // Word of recall
    lda zp_eff_word_recall
    beq !no_recall+
    dec zp_eff_word_recall
    bne !no_recall+

    // Word of recall expired — teleport between town and dungeon
    lda zp_player_dlvl
    beq !recall_to_dungeon+

    // In dungeon → go to town (dlvl 0)
    jsr turn_recall_clear_old_occupied
    lda #0
    sta zp_player_dlvl
    sta player_data + PL_DLEVEL
    lda #1
    sta level_entry_dir              // Ascending (town)
    jsr tramp_store_restock_all      // Restock stores on town re-entry (RP14-1)
    jmp !recall_generate+

!recall_to_dungeon:
    // In town → go to max depth reached
    lda player_data + PL_MAX_DLVL
    beq !no_recall+                  // Never been to dungeon — fizzle
    pha
    jsr turn_recall_clear_old_occupied
    pla
    sta zp_player_dlvl
    sta player_data + PL_DLEVEL
    lda #0
    sta level_entry_dir              // Descending (arrive at up stairs)

!recall_generate:
    jsr tier_invalidate_state
    jsr level_change_generate_current

    // Drop transient generation/loading message state before recall arrival.
    jsr msg_clear
    ldx #HSTR_RECALL_ARRIVE
    jsr huff_print_msg
!no_recall:

    lda eff_invuln_timer
    beq !no_invuln+
    dec eff_invuln_timer
!no_invuln:

    // Detect monsters timer
    lda eff_detect_timer
    beq !no_detect+
    dec eff_detect_timer
    bne !no_detect+
    // Expired — clear detected monster render flags before any redraw path.
    lda #1
    sta muv_clear_detected
    sta vis_room_revealed
#if HAL_LAYOUT_VISIBILITY_FORCE_REDRAW
    sta vis_force_redraw_pending
#endif
    jsr monster_update_visibility_all
!no_detect:

    // Mana regen: spell-casting classes recover 1 MP per 2 turns
    // Extra regen (zp_eff_regen > 0): recover 1 MP every turn
    lda player_data + PL_SPELL_TYPE
    beq !no_mana_regen+              // Warriors (type 0) don't regen mana

    lda zp_player_mp
    cmp zp_player_mmp
    bcs !no_mana_regen+              // Already at max

    // Extra regen: skip turn check, always regen
    lda zp_eff_regen
    bne !do_mana_regen+

    // Normal rate: every 2 turns
    lda zp_turn_lo
    and #$01
    bne !no_mana_regen+

!do_mana_regen:
    inc zp_player_mp
    lda zp_player_mp
    sta player_data + PL_MANA
!no_mana_regen:

    rts

// turn_tick_hunger — Decrement food counter, update hunger state
// Preserves: nothing
turn_tick_hunger:
    lda zp_hunger_state
    pha

    // Decrement 16-bit food counter
    lda zp_player_food
    bne !no_borrow+
    lda zp_player_food_hi
    beq !starving+          // Already at 0
    dec zp_player_food_hi
!no_borrow:
    dec zp_player_food

    jsr player_update_hunger_state
    pla
    jmp turn_maybe_play_hunger_alert
!starving:
    // Food is 0 — player takes damage each turn
    jsr player_update_hunger_state
    pla
    jsr turn_maybe_play_hunger_alert

    // Starvation: 1 HP damage per turn, clamped at 0.
    jsr turn_apply_one_damage
    lda #DEATH_STARVE
    sta zp_death_source
    jmp player_death_check

// turn_apply_one_damage — Subtract 1 HP from the player, clamped at 0.
// Syncs HP back to player_data. Disturbs auto-rest (turn_rest_disturbed).
turn_apply_one_damage:
    inc turn_rest_disturbed
    lda zp_player_hp_lo
    sec
    sbc #1
    sta zp_player_hp_lo
    lda zp_player_hp_hi
    sbc #0
    sta zp_player_hp_hi
    bpl !sync+                  // Still >= 0 (0 stays 0)
    lda #0
    sta zp_player_hp_lo
    sta zp_player_hp_hi
!sync:
    jmp eff_heal_sync

// turn_tick_regen — HP regeneration each turn: VMS Moria regenhp
// (moria.inc), in Umoria's 16.16 fixed point (game_run.cpp
// playerRegenerateHitPoints):
//   HP.fraction += max HP x rate + REGEN_HPBASE
//   rate = regen_factor[hunger state] (0 when starving: food counter 0),
//          x2 while auto-resting (VMS rest > 0)
// Skipped while poisoned or at max HP; reaching max HP clears the fraction.
// turn_post_action runs it first, as VMS Moria regenerates from the turn's
// starting hunger and poison state, before the food and effect ticks.
// Max HP <= 42,410 keeps max HP x rate x 2 + carries in 24 bits (A <= 255).
// Preserves: nothing
turn_tick_regen:
    lda zp_eff_poison
    bne !ttr_done+
    lda zp_player_hp_lo
    cmp zp_player_mhp_lo
    lda zp_player_hp_hi
    sbc zp_player_mhp_hi
    bcs !ttr_done+              // HP >= max HP (unsigned)

    lda zp_player_food
    ora zp_player_food_hi
    beq !ttr_rate+              // Starving: rate 0, REGEN_HPBASE only
    ldx zp_hunger_state
    lda regen_factor,x
!ttr_rate:
    tax
    lda zp_player_mhp_lo
    sta zp_temp0
    lda zp_player_mhp_hi
    sta zp_temp1
    jsr math_mul_16x8           // mul_result = max HP x rate
    lda turn_resting
    beq !ttr_not_resting+
    asl mul_result_0
    rol mul_result_1
    rol mul_result_2
!ttr_not_resting:

    // fraction += mul_result + REGEN_HPBASE; whole HP go to eff_heal
    lda mul_result_0
    clc
    adc #<REGEN_HPBASE
    tax
    lda mul_result_1
    adc #>REGEN_HPBASE
    tay
    bcc !ttr_no_carry+
    inc mul_result_2
!ttr_no_carry:
    txa
    clc
    adc regen_frac_lo
    sta regen_frac_lo
    tya
    adc zp_regen_frac
    sta zp_regen_frac
    lda mul_result_2
    adc #0
    jsr eff_heal                // HP += A, capped at max HP, synced
    lda zp_player_hp_lo
    eor zp_player_mhp_lo
    bne !ttr_done+
    lda zp_player_hp_hi
    eor zp_player_mhp_hi
    bne !ttr_done+
    sta regen_frac_lo           // At max HP: no fraction carried
    sta zp_regen_frac
!ttr_done:
    rts

// Auto-rest doubles the regeneration rate. Unit tests without game_loop.s
// get a stand-in (test_main_loop.s binds the real flag).
#if (C64_UNIT_TEST || C128_UNIT_TEST) && !TURN_PRODUCTION_REST_STATE
turn_resting: .byte 0
#else
.label turn_resting = auto_rest_active
#endif

// turn_post_action — Run end-of-turn processing after a player action
// Called by the main loop after any action that consumes a turn.
// Runs regen, effect timers, hunger tick, monster AI, turn counter, status dirty.
// Preserves: nothing
turn_post_action:
    lda #0
    sta turn_scene_dirty

    jsr turn_tick_regen
    jsr turn_tick_effects
    jsr turn_tick_hunger
    jsr turn_tick_light
    jsr turn_tick_pseudo_id
    jsr monster_ai_tick
    ora zp_dirty_count              // pending non-local redraw request
    sta turn_scene_dirty
    lda #0
    sta zp_dirty_count

    // Increment turn counter
    inc zp_turn_lo
    bne !no_hi+
    inc zp_turn_hi
!no_hi:

    // Mark status bar as dirty so it redraws
    jmp status_mark_dirty

// turn_recall_clear_old_occupied — clear the current map tile occupied bit
// before an actual recall teleport transition.
// Safe to skip on recall fizzles, because the player remains on the same tile.
turn_recall_clear_old_occupied:
    ldx zp_player_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_player_x
    :MapRead_ptr0_y()
    and #~FLAG_OCCUPIED
    :MapWrite_ptr0_y()
    rts

// turn_tick_light — Decrement light charges if torch/lantern equipped
// Each charge represents LIGHT_TICKS_PER_CHARGE turns.
// When charges reach 0, unequip and set light radius to 0.
// Warning at 2 charges (~60 turns).
// Preserves: nothing
.const LIGHT_TICKS_PER_CHARGE = 30
turn_tick_light:
    ldx #EQUIP_LIGHT
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !ttl_done+              // No light equipped

    lda inv_p1,x
    beq !ttl_done+              // Already 0 (shouldn't happen)

    // Tick counter — only consume a charge every 30 turns
    lda light_tick_counter
    bne !ttl_tick+
    lda #LIGHT_TICKS_PER_CHARGE // Reset counter (fresh game or after charge decrement)
!ttl_tick:
    sec
    sbc #1
    sta light_tick_counter
    bne !ttl_done+              // Counter not yet zero, skip charge decrement

    // Decrement charges
    ldx #EQUIP_LIGHT
    lda inv_p1,x
    sec
    sbc #1
    sta inv_p1,x

    // Check for warning at 2 charges
    cmp #2
    bne !ttl_not_dim+
    // Print "YOUR LIGHT IS GROWING DIM."
    ldx #HSTR_TTL_DIM
    jsr huff_print_msg
    jmp !ttl_done+

!ttl_not_dim:
    // Check for depletion at 0
    cmp #0
    bne !ttl_done+

    // Light expired
    lda #0
    sta zp_light_radius

    // Clear equip slot
    ldx #EQUIP_LIGHT
    jsr inv_remove_item

    // Print "YOUR LIGHT HAS GONE OUT."
    ldx #HSTR_TTL_OUT
    jsr huff_print_msg

!ttl_done:
    rts

// Strings migrated to Huffman compression (HSTR_EFF_*, HSTR_TTL_*, HSTR_RECALL_* in huffman_data.s)
light_tick_counter: .byte 0
eff_fear_timer:   .byte 0

// ============================================================
// Pseudo-identification system
// ============================================================

// turn_tick_pseudo_id — Auto-sense magical gear over time.
// Matches umoria's cadence: every 16 turns, if not confused, roll a
// level-based outer chance (10 + 750 / (5 + level)). On success, scan carried
// items first (1/50 per eligible item) and then equipment (1/10 per eligible
// item), reporting the result with umoria-style useful wording.
// Preserves: nothing
turn_tick_pseudo_id:
    lda zp_turn_lo
    and #$0f
    cmp #$0f
    beq !pid_turn_ok+
    jmp !pid_done+
!pid_turn_ok:
    lda zp_eff_confuse
    beq !pid_clear_ok+
    jmp !pid_done+
!pid_clear_ok:
    lda #<750
    sta zp_math_a
    lda #>750
    sta zp_math_b
    lda #5
    clc
    adc zp_player_lvl
    tax
    jsr math_div_16x8
    lda zp_math_a
    clc
    adc #10
    jsr rng_range
    beq !pid_outer_ok+
    jmp !pid_done+
!pid_outer_ok:

    ldx #0
!pid_scan_pack:
    cpx #MAX_INV_SLOTS
    bcs !pid_scan_equip+
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !pid_next_pack+
    jsr pid_item_enchanted
    bcc !pid_next_pack+
    stx pid_slot
    lda #50
    jsr rng_range
    pha
    ldx pid_slot
    pla
    bne !pid_next_pack+
    lda inv_flags,x
    ora #IF_SENSED
    sta inv_flags,x
    jsr pid_print_sense_msg
    jmp !pid_done+
!pid_next_pack:
    inx
    bne !pid_scan_pack-

!pid_scan_equip:
    ldx #EQUIP_WEAPON
!pid_scan_gear:
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !pid_next+
    jsr pid_item_enchanted
    bcc !pid_next+
    stx pid_slot
    lda #10
    jsr rng_range
    pha
    ldx pid_slot
    pla
    bne !pid_next+
    lda inv_flags,x
    ora #IF_SENSED
    sta inv_flags,x
    jsr pid_print_sense_msg
    jmp !pid_done+

!pid_next:
    inx
    cpx #EQUIP_END
    bcc !pid_scan_gear-
!pid_done:
    rts

turn_prayer_off_msg:
    .text "The prayer has expired."
    .byte 0

// pid_item_enchanted — Return carry set for unsensed positive magical gear
// Input: X = inventory slot index
// Output: carry set = eligible for auto-sense
// Preserves: X
pid_item_enchanted:
    lda inv_flags,x
    and #IF_IDENTIFIED | IF_SENSED | IF_CURSED
    bne !pid_no+
    lda inv_item_id,x
    cmp #13
    beq !pid_no+               // Wooden torch fuel is not pseudo-ID-worthy
    cmp #14
    beq !pid_no+               // Brass lantern fuel is not pseudo-ID-worthy
    lda inv_ego,x
    bne !pid_yes+
    lda inv_to_hit,x
    bne !pid_check_positive_stat+
    lda inv_to_dam,x
    bne !pid_check_positive_stat+
    lda inv_to_ac,x
    bne !pid_check_positive_stat+
    lda inv_p1,x
    beq !pid_no+
    bmi !pid_no+
    bpl !pid_yes+
!pid_check_positive_stat:
    bmi !pid_no+
!pid_yes:
    sec
    rts
!pid_no:
    clc
    rts

// pid_print_sense_msg — Print compact Moria8 auto-sense wording.
// Input: X = inventory slot index
// Preserves: nothing
pid_print_sense_msg:
    ldx #HSTR_PID_CARRY
    jmp huff_print_msg

pid_slot: .byte 0