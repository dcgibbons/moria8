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
rf_dir:        .byte 0     // Direction index 0-7
rf_cx:         .byte 0     // Current trace X
rf_cy:         .byte 0     // Current trace Y
rf_steps:      .byte 0     // Steps remaining

// ============================================================
// Strings (reuse cmb_the_str, cmb_period, cmb_kill_str from combat.s)
// ============================================================
rf_no_weapon_str:  .text "NO RANGED WEAPON." ; .byte 0
rf_no_ammo_str:    .text "NO AMMO." ; .byte 0
rf_flies_str:      .text " FLIES AWAY." ; .byte 0
rf_misses_str:     .text " MISSES" ; .byte 0
rf_hits_str:       .text " HITS" ; .byte 0

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

    // Compute direction index from df_target_x/y
    lda df_target_x
    sec
    sbc zp_player_x
    sta zp_temp0                // dx
    lda df_target_y
    sec
    sbc zp_player_y
    sta zp_temp1                // dy

    ldx #0
!rf_find_dir:
    lda dir_dx,x
    cmp zp_temp0
    bne !rf_dir_next+
    lda dir_dy,x
    cmp zp_temp1
    beq !rf_dir_found+
!rf_dir_next:
    inx
    cpx #8
    bcc !rf_find_dir-
    clc
    rts                         // Shouldn't happen
!rf_dir_found:
    stx rf_dir

    // 4. Trace projectile
    lda zp_player_x
    sta rf_cx
    lda zp_player_y
    sta rf_cy
    lda #20
    sta rf_steps

!rf_trace:
    dec rf_steps
    beq !rf_miss_dark_tramp+

    // Step in direction
    ldx rf_dir
    lda rf_cx
    clc
    adc dir_dx,x
    sta rf_cx
    lda rf_cy
    clc
    adc dir_dy,x
    sta rf_cy

    // Bounds check
    lda rf_cx
    beq !rf_miss_dark_tramp+
    cmp #MAP_COLS - 1
    bcs !rf_miss_dark_tramp+
    lda rf_cy
    beq !rf_miss_dark_tramp+
    cmp #MAP_ROWS - 1
    bcc !rf_bounds_ok+
!rf_miss_dark_tramp:
    jmp rf_miss_darkness
!rf_bounds_ok:

    // Check walkability
    ldx rf_cy
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy rf_cx
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    lsr
    lsr
    lsr
    lsr
    tax
    lda walkable_table,x
    beq !rf_miss_dark_tramp-    // Blocked

    // Check for monster
    lda rf_cx
    ldy rf_cy
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
    jsr eff_kill_monster
    lda #<cmb_kill_str
    ldy #>cmb_kill_str
    jsr msg_build_action            // Reuse melee kill message builder
    jsr rf_print_msg
    lda #SFX_HIT
    jsr sound_play
    jmp rf_consume_ammo

!rf_hit_alive:
    // Wake the monster
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    ora #MF_AWAKE
    sta (zp_ptr0),y

    // Message: "THE <ammo> HITS THE <name>."
    jsr rf_msg_ammo_prefix          // "THE <ammo>"
    lda #<rf_hits_str
    ldy #>rf_hits_str
    jsr combat_append_str           // " HITS"
    lda #<cmb_the_str
    ldy #>cmb_the_str
    jsr combat_append_str           // " THE "
    jsr combat_append_monster_name
    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str
    jsr rf_print_msg
    lda #SFX_HIT
    jsr sound_play
    jmp rf_consume_ammo

rf_miss_monster:
    // Message: "THE <ammo> MISSES THE <name>."
    jsr rf_msg_ammo_prefix
    lda #<rf_misses_str
    ldy #>rf_misses_str
    jsr combat_append_str
    lda #<cmb_the_str
    ldy #>cmb_the_str
    jsr combat_append_str
    jsr combat_append_monster_name
    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str
    jsr rf_print_msg
    lda #SFX_MISS
    jsr sound_play
    jmp rf_consume_ammo

rf_miss_darkness:
    // Message: "THE <ammo> FLIES AWAY."
    jsr rf_msg_ammo_prefix
    lda #<rf_flies_str
    ldy #>rf_flies_str
    jsr combat_append_str
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
    lda #<rf_no_weapon_str
    sta zp_ptr0
    lda #>rf_no_weapon_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

rf_msg_no_ammo:
    lda #<rf_no_ammo_str
    sta zp_ptr0
    lda #>rf_no_ammo_str
    sta zp_ptr0_hi
    jsr msg_print
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
