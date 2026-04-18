#importonce
#import "generation_busy_api.s"
// turn.s — Turn processing routines
//
// The main loop (main.s) dispatches player commands directly and calls
// turn_post_action after each action that consumes a turn. This module
// provides the post-action processing: effect timers, hunger, turn
// counter, HP regeneration, and status dirty flag.

#import "turn_render_state.s"

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

// turn_maybe_play_hunger_alert — Alert only when hunger gets worse.
// Input: A = previous hunger state, zp_hunger_state = current state
turn_maybe_play_hunger_alert:
    cmp zp_hunger_state
    bcs !done+              // Same or improved state: no alert

    lda zp_hunger_state
    cmp #HUNGER_FAINT
    beq !faint+

    lda #SFX_HUNGER_WARN
    jsr sound_play
    rts
!faint:
    lda #SFX_HUNGER_FAINT
    jsr sound_play
    rts
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
    // Poison tick: 1 HP damage per turn (only while timer > 0), clamped at 0.
    jsr turn_apply_one_damage
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
    jmp !no_speed+
!pos_speed:
    dec zp_eff_speed        // Positive, decrement toward 0
!no_speed:

    // Simple-dec effects: protect($55), invis($56), infra($57),
    // [skip resist($58)], [skip bless($59)], hero($5a), regen($5b)
    .assert "Simple-dec range", zp_eff_regen - zp_eff_protect, 6
    ldy #zp_eff_protect
!tse_loop:
    cpy #zp_eff_resist
    beq !tse_next+
    cpy #zp_eff_bless
    beq !tse_next+
    lda $00,y
    beq !tse_next+
    sec
    sbc #1
    sta $00,y
!tse_next:
    iny
    cpy #zp_eff_regen + 1
    bne !tse_loop-

    // Blessed / Prayer
    lda zp_eff_bless
    beq !no_bless+
    sec
    sbc #1
    sta zp_eff_bless
    bne !no_bless+
    ldx #HSTR_PMX_PRAYER_OFF
    jsr huff_print_msg
!no_bless:

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

    ldx #HSTR_RECALL_ARRIVE
    jsr huff_print_msg
!no_recall:

    // Detect monsters timer
    lda eff_detect_timer
    beq !no_detect+
    sec
    sbc #1
    sta eff_detect_timer
    and #$7f
    bne !no_detect+
    lda #0
    sta eff_detect_timer
    // Expired — trigger redraw to hide detected monsters
    lda #1
    sta vis_room_revealed
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
    jsr turn_maybe_play_hunger_alert
    rts
!starving:
    // Food is 0 — player takes damage each turn
    jsr player_update_hunger_state
    pla
    jsr turn_maybe_play_hunger_alert

    // Starvation: 1 HP damage per turn, clamped at 0.
    jsr turn_apply_one_damage
    lda #DEATH_STARVE
    sta zp_death_source
    jsr player_death_check
    rts

// turn_apply_one_damage — Subtract 1 HP from the player, clamped at 0.
// Syncs HP back to player_data.
turn_apply_one_damage:
    lda zp_player_hp_lo
    sec
    sbc #1
    sta zp_player_hp_lo
    lda zp_player_hp_hi
    sbc #0
    sta zp_player_hp_hi

    lda zp_player_hp_hi
    bmi !dead+
    ora zp_player_hp_lo
    bne !sync+
!dead:
    lda #0
    sta zp_player_hp_lo
    sta zp_player_hp_hi
!sync:
    lda zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda zp_player_hp_hi
    sta player_data + PL_HP_HI
    rts

// turn_tick_regen — HP regeneration each turn
// Decrements zp_regen_counter. When it expires, heal 1 HP (capped at max).
// Poison suppresses regeneration. zp_eff_regen active = double tick rate.
// Preserves: nothing
turn_tick_regen:
    // Skip if poisoned (poison suppresses regen)
    lda zp_eff_poison
    bne !ttr_done+

    // Skip if at max HP (16-bit compare)
    lda zp_player_hp_hi
    cmp zp_player_mhp_hi
    bcc !ttr_not_max+           // HP hi < MHP hi → not at max
    bne !ttr_done+              // HP hi > MHP hi → over max (shouldn't happen)
    lda zp_player_hp_lo
    cmp zp_player_mhp_lo
    bcs !ttr_done+              // HP lo >= MHP lo → at or over max
!ttr_not_max:

    // Decrement counter (by 2 if zp_eff_regen active, else by 1)
    lda zp_regen_counter
    ldx zp_eff_regen
    beq !ttr_dec1+
    // Extra regen: subtract 2
    sec
    sbc #2
    jmp !ttr_check+
!ttr_dec1:
    sec
    sbc #1
!ttr_check:
    beq !ttr_heal+              // Counter hit 0 → heal
    bpl !ttr_store+             // Counter still positive → store and done
!ttr_heal:

    // Counter expired (or went negative) → heal 1 HP
    // 16-bit increment: zp_player_hp += 1
    inc zp_player_hp_lo
    bne !ttr_no_carry+
    inc zp_player_hp_hi
!ttr_no_carry:
    // Cap at max HP
    lda zp_player_hp_hi
    cmp zp_player_mhp_hi
    bcc !ttr_cap_ok+            // HP hi < MHP hi → under max
    bne !ttr_clamp+             // HP hi > MHP hi → over max
    lda zp_player_hp_lo
    cmp zp_player_mhp_lo
    bcc !ttr_cap_ok+            // HP lo < MHP lo → under max
    beq !ttr_cap_ok+            // Equal → exactly at max
!ttr_clamp:
    // Clamp to max
    lda zp_player_mhp_lo
    sta zp_player_hp_lo
    lda zp_player_mhp_hi
    sta zp_player_hp_hi
!ttr_cap_ok:
    // Sync to player_data
    lda zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda zp_player_hp_hi
    sta player_data + PL_HP_HI

    // Reset counter from regen_rate table
    lda player_data + PL_CON_CUR
    sec
    sbc #3                      // Index = CON - 3
    tax
    lda regen_rate,x
    sta zp_regen_counter
    rts

!ttr_store:
    sta zp_regen_counter
!ttr_done:
    rts

// turn_post_action — Run end-of-turn processing after a player action
// Called by the main loop after any action that consumes a turn.
// Runs effect timers, hunger tick, regen, monster AI, turn counter, status dirty.
// Preserves: nothing
turn_post_action:
    lda #0
    sta turn_scene_dirty

    jsr turn_tick_effects
    jsr turn_tick_hunger
    jsr turn_tick_regen
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

    // Periodic store restock every 256 turns (when lo byte wraps to 0)
    lda zp_turn_lo
    bne !no_restock+
    jsr tramp_store_restock_all
!no_restock:

    // Mark status bar as dirty so it redraws
    jsr status_mark_dirty

    rts

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

// turn_tick_pseudo_id — Pseudo-identify equipped items over time
// Each turn, decrements zp_pseudo_id_timer. When it reaches 0, scans
// equipment for the first unidentified item without IF_TRIED.
// Sets IF_TRIED, prints quality message, and resets timer.
// Preserves: nothing
turn_tick_pseudo_id:
    lda zp_pseudo_id_timer
    beq !pid_done+              // Timer 0 = inactive
    dec zp_pseudo_id_timer
    bne !pid_done+              // Not expired yet

    // Timer expired — scan equipment slots
    ldx #EQUIP_WEAPON
!pid_scan:
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !pid_next+
    lda inv_flags,x
    and #IF_IDENTIFIED
    bne !pid_next+              // Already fully identified
    lda inv_flags,x
    and #IF_TRIED
    bne !pid_next+              // Already pseudo-ID'd

    // Found unID'd item — set IF_TRIED
    lda inv_flags,x
    ora #IF_TRIED
    sta inv_flags,x

    // Get quality index
    stx pid_save_x
    jsr pid_get_quality         // A = quality index 0-4
    sta pid_save_q

    // Print "Sense: <quality>" via Huffman (sequential HSTR_PID_TERRIBLE+q)
    lda pid_save_q
    clc
    adc #HSTR_PID_TERRIBLE
    tax
    jsr huff_print_msg
    jmp !pid_reset+

!pid_next:
    inx
    cpx #EQUIP_RING + 1
    bcc !pid_scan-
    // No unID'd items found — still reset timer
!pid_reset:
    lda player_data + PL_RESERVED
    sta zp_pseudo_id_timer
!pid_done:
    rts

pid_save_x: .byte 0
pid_save_q: .byte 0

// pid_get_quality — Determine quality level from item enchantment
// Input: X = inventory slot index
// Output: A = quality index (0=TERRIBLE, 1=BAD, 2=AVERAGE, 3=GOOD, 4=EXCELLENT)
// Preserves: X
pid_get_quality:
    lda inv_flags,x
    and #IF_CURSED
    bne !pgq_bad+
    lda inv_p1,x
    bmi !pgq_neg+
    // Positive or zero
    beq !pgq_avg+
    cmp #3
    bcs !pgq_exc+
    lda #3                      // GOOD (p1 = 1 or 2)
    rts
!pgq_exc:
    lda #4                      // EXCELLENT (p1 >= 3)
    rts
!pgq_neg:
    cmp #$FF
    beq !pgq_bad+
    lda #0                      // TERRIBLE (p1 <= -2)
    rts
!pgq_bad:
    lda #1                      // BAD (p1 = -1 or cursed)
    rts
!pgq_avg:
    lda #2                      // AVERAGE (p1 = 0)
    rts

// Pseudo-ID strings migrated to Huffman (HSTR_PID_* in huffman_data.s)
