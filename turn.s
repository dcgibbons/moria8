// turn.s — Turn processing routines
//
// The main loop (main.s) dispatches player commands directly and calls
// turn_post_action after each action that consumes a turn. This module
// provides the post-action processing: effect timers, hunger, turn
// counter, and status dirty flag.
//
// Monster AI (Phase 5) will be called from turn_post_action.
// Regeneration (Phase 5) will be added to turn_post_action.

// Hunger thresholds
.const FOOD_HUNGRY_AT   = 150   // Food counter below this = hungry
.const FOOD_WEAK_AT     = 50    // Below this = weak
.const FOOD_FAINT_AT    = 10    // Below this = faint

// ============================================================
// Subroutines
// ============================================================

// turn_tick_effects — Decrement all active status effect timers
// Any timer that reaches 0 triggers removal of that effect.
// Preserves: nothing
turn_tick_effects:
    // Poison
    lda zp_eff_poison
    beq !no_poison+
    dec zp_eff_poison

    // Poison tick: 1 HP damage per turn
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
    // TODO: if just expired, redraw screen (Phase 5)
!no_blind:

    // Confusion
    lda zp_eff_confuse
    beq !no_confuse+
    dec zp_eff_confuse
!no_confuse:

    // Paralysis
    lda zp_eff_paralyze
    beq !no_para+
    dec zp_eff_paralyze
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
    // TODO: starvation damage (Phase 5)
    rts

// turn_post_action — Run end-of-turn processing after a player action
// Called by the main loop after any action that consumes a turn.
// Runs effect timers, hunger tick, increments turn counter, marks status dirty.
// Preserves: nothing
turn_post_action:
    jsr turn_tick_effects
    jsr turn_tick_hunger
    jsr monster_ai_tick

    // Increment turn counter
    inc zp_turn_lo
    bne !no_hi+
    inc zp_turn_hi
!no_hi:

    // Mark status bar as dirty so it redraws
    jsr status_mark_dirty

    rts
