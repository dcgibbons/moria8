// turn.s — Turn processing routines
//
// The main loop (main.s) dispatches player commands directly and calls
// turn_post_action after each action that consumes a turn. This module
// provides the post-action processing: effect timers, hunger, turn
// counter, HP regeneration, and status dirty flag.

// Hunger thresholds
.const FOOD_HUNGRY_AT   = 150   // Food counter below this = hungry
.const FOOD_WEAK_AT     = 50    // Below this = weak
.const FOOD_FAINT_AT    = 10    // Below this = faint

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
    lda #<eff_poison_end
    sta zp_ptr0
    lda #>eff_poison_end
    sta zp_ptr0_hi
    jsr msg_print
    jmp !no_poison+
!poison_still:
    // Poison tick: 1 HP damage per turn (only while timer > 0)
    lda zp_player_hp_lo
    sec
    sbc #1
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    bcs !poison_no_borrow+
    dec zp_player_hp_hi
    lda zp_player_hp_hi
    sta player_data + PL_HP_HI
!poison_no_borrow:
    jsr player_death_check
!no_poison:

    // Blindness
    lda zp_eff_blind
    beq !no_blind+
    dec zp_eff_blind
    bne !no_blind+
    // Just expired — print message and trigger viewport redraw
    lda #<eff_blind_end
    sta zp_ptr0
    lda #>eff_blind_end
    sta zp_ptr0_hi
    jsr msg_print
    lda #1
    sta vis_room_revealed       // Trigger full viewport redraw
!no_blind:

    // Confusion
    lda zp_eff_confuse
    beq !no_confuse+
    dec zp_eff_confuse
    bne !no_confuse+
    // Just expired — print message
    lda #<eff_confuse_end
    sta zp_ptr0
    lda #>eff_confuse_end
    sta zp_ptr0_hi
    jsr msg_print
!no_confuse:

    // Paralysis
    lda zp_eff_paralyze
    beq !no_para+
    dec zp_eff_paralyze
    bne !no_para+
    // Just expired — print message
    lda #<eff_paralyze_end
    sta zp_ptr0
    lda #>eff_paralyze_end
    sta zp_ptr0_hi
    jsr msg_print
!no_para:

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

    // Protection
    lda zp_eff_protect
    beq !no_prot+
    dec zp_eff_protect
!no_prot:

    // Invisibility
    lda zp_eff_invis
    beq !no_invis+
    dec zp_eff_invis
!no_invis:

    // Infravision
    lda zp_eff_infra
    beq !no_infra+
    dec zp_eff_infra
!no_infra:

    // Bless
    lda zp_eff_bless
    beq !no_bless+
    dec zp_eff_bless
!no_bless:

    // Heroism
    lda zp_eff_hero
    beq !no_hero+
    dec zp_eff_hero
!no_hero:

    // Extra regeneration
    lda zp_eff_regen
    beq !no_regen+
    dec zp_eff_regen
!no_regen:

    // Word of recall
    lda zp_eff_word_recall
    beq !no_recall+
    dec zp_eff_word_recall
    bne !no_recall+
    // TODO: teleport to town / back to dungeon (Phase 7)
!no_recall:

    rts

// turn_tick_hunger — Decrement food counter, update hunger state
// Preserves: nothing
turn_tick_hunger:
    // Decrement 16-bit food counter
    lda zp_player_food
    bne !no_borrow+
    lda zp_player_food_hi
    beq !starving+          // Already at 0
    dec zp_player_food_hi
!no_borrow:
    dec zp_player_food

    // Update hunger state based on food counter
    // Compare 16-bit food counter to thresholds
    lda zp_player_food_hi
    bne !full+              // Hi byte > 0 means plenty of food

    // Hi byte is 0, check lo byte against thresholds
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
!starving:
    // Food is 0 — player takes damage each turn
    lda #HUNGER_FAINT
    sta zp_hunger_state

    // Starvation: 1 HP damage per turn
    lda zp_player_hp_lo
    sec
    sbc #1
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    bcs !starve_no_borrow+
    dec zp_player_hp_hi
    lda zp_player_hp_hi
    sta player_data + PL_HP_HI
!starve_no_borrow:
    jsr player_death_check
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
    jsr turn_tick_effects
    jsr turn_tick_hunger
    jsr turn_tick_regen
    jsr monster_ai_tick

    // Increment turn counter
    inc zp_turn_lo
    bne !no_hi+
    inc zp_turn_hi
!no_hi:

    // Mark status bar as dirty so it redraws
    jsr status_mark_dirty

    rts

// ============================================================
// Effect expiration strings
// ============================================================
eff_poison_end:   .text "YOU FEEL BETTER." ; .byte 0
eff_blind_end:    .text "YOU CAN SEE AGAIN." ; .byte 0
eff_confuse_end:  .text "YOU FEEL LESS CONFUSED." ; .byte 0
eff_paralyze_end: .text "YOU CAN MOVE AGAIN." ; .byte 0
