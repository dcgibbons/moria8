// ranged_fire.s — Ranged combat (fire bows, crossbows, slings)
//
// SHIFT+F fires equipped ranged weapon at a target in a direction.
// Traces projectile path, checks for monster hit, rolls damage, consumes ammo.
// Reuses melee combat subroutines for to-hit and damage application.

// ============================================================
// Scratch variables
// ============================================================
rf_ammo_type:  .byte 0     // Matching ammo type (1=arrow, 2=bolt, 3=rock)
rf_ammo_slot:  .byte 0     // Inventory slot of ammo
rf_ammo_id:    .byte 0     // Item type ID of ammo
// Strings migrated to Huffman compression (HSTR_RF_* in huffman_data.s)

// ============================================================
// ranged_fire — Fire equipped ranged weapon
// Output: carry set = turn consumed, carry clear = no action
// Clobbers: everything
// ============================================================
ranged_fire:
    // 1. Check EQUIP_WEAPON is a ranged launcher
    ldx #EQUIP_WEAPON
    lda inv_item_id,x
    cmp #FI_EMPTY
    bne !rf_have_weapon+
    jmp rf_msg_no_weapon
!rf_have_weapon:
    tax                         // X = weapon type
    jsr item_get_missile
    bne !rf_is_ranged+
    jmp rf_msg_no_weapon
!rf_is_ranged:
    cmp #4
    bcc !rf_is_launcher+
    jmp rf_msg_no_weapon        // $80+ = ammo, not a launcher
!rf_is_launcher:

    // Valid launcher — save ammo type (1/2/3)
    sta rf_ammo_type

    // 2. Scan inventory (slots 0-21) for matching ammo
    ldx #0
!rf_ammo_scan:
    cpx #MAX_INV_SLOTS
    bcc !rf_ammo_cont+
    jmp rf_msg_no_ammo
!rf_ammo_cont:
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !rf_ammo_next+
    sta rf_ammo_id              // Save item type temporarily
    stx rf_ammo_slot            // Save loop counter
    tax                         // X = item type
    jsr item_get_missile        // A = missile value
    and #$7f                    // Strip high bit
    cmp rf_ammo_type
    beq !rf_ammo_found+
    ldx rf_ammo_slot            // Restore loop counter
!rf_ammo_next:
    inx
    jmp !rf_ammo_scan-

!rf_ammo_found:

    // 3. Get direction from player
    jsr get_direction_target
    bcs !rf_has_dir+
    clc
    rts                         // Cancelled
!rf_has_dir:

    jsr calc_direction_index
    bcs !rf_dir_ok+
    clc
    rts                         // Shouldn't happen
!rf_dir_ok:

    // 4. Trace projectile
    lda zp_player_x
    sta proj_cx
    lda zp_player_y
    sta proj_cy
    lda #20
    sta proj_steps

!rf_trace:
    dec proj_steps
    beq !rf_miss_dark_tramp+
    jsr trace_step
    bcs !rf_step_ok+
!rf_miss_dark_tramp:
    jmp rf_miss_darkness
!rf_step_ok:

    // Check for monster
    lda proj_cx
    ldy proj_cy
    jsr monster_find_at
    bcc !rf_trace-              // No monster, keep tracing

    // 5. Hit a monster! X = slot index
    stx cmb_slot
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    sta cmb_type

    // Calculate to-hit
    jsr combat_calc_tohit

    // Load monster AC
    ldx cmb_type
    lda cr_ac,x
    sta zp_combat_atk

    // Roll to-hit
    jsr combat_roll_tohit
    bcs !rf_tohit_success+
    jmp rf_miss_monster
!rf_tohit_success:

    // 6. Hit! Roll damage using ammo dice
    ldx rf_ammo_id
    lda it_dmg_dice,x
    pha
    lda it_dmg_sides,x
    tax                         // X = sides
    pla                         // A = dice count
    ldy #0                      // No bonus on dice
    jsr math_dice               // Result in zp_math_a

    // Add PL_TODMG (includes weapon enchant via player_recalc_equipment)
    lda player_data + PL_TODMG
    bmi !rf_neg_bonus+
    clc
    adc zp_math_a
    bcc !rf_dmg_ok+
    lda #255
    jmp !rf_dmg_ok+
!rf_neg_bonus:
    clc
    adc zp_math_a
    bpl !rf_dmg_ok+
    lda #0                      // Clamp to 0
!rf_dmg_ok:
    sta cmb_damage

    // Apply damage
    ldx cmb_slot
    lda cmb_damage
    jsr combat_apply_damage
    bcc !rf_hit_alive+

    // Monster killed — "YOU HAVE SLAIN THE <name>."
    ldx cmb_slot
    jsr combat_kill_message
    jmp rf_consume_ammo

!rf_hit_alive:
    // Wake the monster
    jsr monster_wake

    // Message: "THE <ammo> HITS THE <name>."
    jsr rf_msg_ammo_prefix          // "THE <ammo>"
    ldx #HSTR_RF_HITS
    jsr projectile_msg_suffix
    lda #SFX_HIT
    jsr sound_play
    jmp rf_consume_ammo

rf_miss_monster:
    // Message: "THE <ammo> MISSES THE <name>."
    jsr rf_msg_ammo_prefix
    ldx #HSTR_RF_MISSES
    jsr projectile_msg_suffix
    lda #SFX_MISS
    jsr sound_play
    jmp rf_consume_ammo

rf_miss_darkness:
    // Message: "THE <ammo> FLIES AWAY."
    jsr rf_msg_ammo_prefix
    ldx #HSTR_RF_FLIES
    jsr huff_append_combat
    jsr rf_print_msg

rf_consume_ammo:
    // 7. Consume 1 ammo
    ldx rf_ammo_slot
    dec inv_qty,x
    bne !rf_done+
    // Qty reached 0 — clear slot
    jsr inv_remove_item

!rf_done:
    sec                         // Turn consumed
    rts

rf_msg_no_weapon:
    ldx #HSTR_RF_NO_WEAPON
    jsr huff_print_msg
    clc
    rts

rf_msg_no_ammo:
    ldx #HSTR_RF_NO_AMMO
    jsr huff_print_msg
    clc
    rts

// rf_msg_ammo_prefix — Start building "THE <ammo>" in combat_msg_buf
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1
rf_msg_ammo_prefix:
    lda #0
    sta cmb_buf_idx
    lda #<(cmb_the_str + 1)         // Skip leading space: "THE " not " THE "
    ldy #>(cmb_the_str + 1)
    jsr combat_append_str
    lda #0
    sta fi_add_ego              // Ammo has no ego
    lda rf_ammo_id
    jsr item_append_name
    rts

// rf_print_msg — Null-terminate and print combat_msg_buf
// Clobbers: A, X
rf_print_msg:
    jmp cmb_term_and_print
