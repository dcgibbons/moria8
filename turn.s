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

    // Word of recall expired — teleport between town and dungeon
    // Clear FLAG_OCCUPIED at old position
    ldx zp_player_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_player_x
    lda (zp_ptr0),y
    and #~FLAG_OCCUPIED
    sta (zp_ptr0),y

    lda zp_player_dlvl
    beq !recall_to_dungeon+

    // In dungeon → go to town (dlvl 0)
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
    sta zp_player_dlvl
    sta player_data + PL_DLEVEL
    lda #0
    sta level_entry_dir              // Descending (arrive at up stairs)

!recall_generate:
    lda #$ff
    sta zp_run_dir                   // Stop running
    lda #0
    sta current_tier                 // Force first-entry tier lookup
    jsr tier_check_transition        // Load correct tier for new dlvl
    jsr level_generate
    jsr monster_spawn_level
    jsr item_spawn_level
    jsr update_visibility
    jsr screen_clear
    jsr viewport_update
    jsr render_viewport
    jsr status_draw

    lda #<recall_arrive_str
    sta zp_ptr0
    lda #>recall_arrive_str
    sta zp_ptr0_hi
    jsr msg_print
!no_recall:

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
    lda #DEATH_STARVE
    sta zp_death_source
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
    jsr turn_tick_light
    jsr monster_ai_tick

    // Increment turn counter
    inc zp_turn_lo
    bne !no_hi+
    inc zp_turn_hi
!no_hi:

    // Mark status bar as dirty so it redraws
    jsr status_mark_dirty

    rts

// turn_tick_light — Decrement light charges if torch/lantern equipped
// When charges reach 0, unequip and set light radius to 0.
// Warning at 10 charges.
// Preserves: nothing
turn_tick_light:
    ldx #EQUIP_LIGHT
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !ttl_done+              // No light equipped

    // Decrement charges
    lda inv_p1,x
    beq !ttl_done+              // Already 0 (shouldn't happen)
    sec
    sbc #1
    sta inv_p1,x

    // Check for warning at 10
    cmp #10
    bne !ttl_not_dim+
    // Print "YOUR LIGHT IS GROWING DIM."
    lda #<ttl_dim_str
    sta zp_ptr0
    lda #>ttl_dim_str
    sta zp_ptr0_hi
    jsr msg_print
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
    lda #<ttl_out_str
    sta zp_ptr0
    lda #>ttl_out_str
    sta zp_ptr0_hi
    jsr msg_print

!ttl_done:
    rts

// ============================================================
// Effect expiration strings
// ============================================================
eff_poison_end:   .text "YOU FEEL BETTER." ; .byte 0
eff_blind_end:    .text "YOU CAN SEE AGAIN." ; .byte 0
eff_confuse_end:  .text "YOU FEEL LESS CONFUSED." ; .byte 0
eff_paralyze_end: .text "YOU CAN MOVE AGAIN." ; .byte 0
ttl_dim_str:      .text "YOUR LIGHT IS GROWING DIM." ; .byte 0
ttl_out_str:      .text "YOUR LIGHT HAS GONE OUT." ; .byte 0
recall_arrive_str: .text "YOU FEEL YOURSELF YANKED AWAY!" ; .byte 0
