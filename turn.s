// turn.s — Game turn sequencer
//
// The game's heartbeat. Each call to turn_execute runs one full game turn:
//   1. Player action (get input, execute command)
//   2. Monster AI (for each active monster, check speed, run AI)
//   3. Status effect timer tick (decrement timers, apply effects)
//   4. Regeneration tick (HP/mana recovery based on CON/level)
//   5. Hunger tick (decrement food counter)
//   6. Increment turn counter
//
// Phase 1 implements the skeleton: steps 1, 3, 5, 6.
// Monster AI (step 2) is added in Phase 5.
// Regeneration (step 4) is added in Phase 5.

// Turn phases (stored in zp_turn_phase)
.const TURN_PLAYER   = 0
.const TURN_MONSTERS = 1
.const TURN_EFFECTS  = 2
.const TURN_REGEN    = 3
.const TURN_HUNGER   = 4

// Hunger thresholds (constants defined in tables.s)
.const FOOD_HUNGRY_AT   = 150   // Food counter below this = hungry
.const FOOD_WEAK_AT     = 50    // Below this = weak
.const FOOD_FAINT_AT    = 10    // Below this = faint

// ============================================================
// Subroutines
// ============================================================

// turn_execute — Run one full game turn
// Preserves: nothing
turn_execute:
    // --- Phase 0: Player action ---
    lda #TURN_PLAYER
    sta zp_turn_phase

    jsr input_get_command   // Get player's command
    // TODO: dispatch command to appropriate handler (Phase 3+)
    // For now, just accept the input and continue

    // --- Phase 1: Monster AI ---
    lda #TURN_MONSTERS
    sta zp_turn_phase
    // TODO: Phase 5 — iterate active monster table, run AI
    // jsr monsters_take_turns

    // --- Phase 2: Status effects ---
    lda #TURN_EFFECTS
    sta zp_turn_phase
    jsr turn_tick_effects

    // --- Phase 3: Regeneration ---
    lda #TURN_REGEN
    sta zp_turn_phase
    // TODO: Phase 5 — HP/mana regeneration
    // jsr turn_tick_regen

    // --- Phase 4: Hunger ---
    lda #TURN_HUNGER
    sta zp_turn_phase
    jsr turn_tick_hunger

    // --- Increment turn counter ---
    inc zp_turn_lo
    bne !done+
    inc zp_turn_hi
!done:
    rts

// turn_tick_effects — Decrement all active status effect timers
// Any timer that reaches 0 triggers removal of that effect.
// Preserves: nothing
turn_tick_effects:
    // Poison
    lda zp_eff_poison
    beq !no_poison+
    dec zp_eff_poison
    // TODO: apply poison damage (Phase 5)
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
