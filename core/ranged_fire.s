#importonce
// ranged_fire.s — Ranged combat (fire bows, crossbows, slings)
//
// SHIFT+F fires equipped ranged weapon at a target in a direction.
// Traces projectile path, checks for monster hit, rolls damage, consumes ammo.
// Reuses melee combat subroutines for to-hit and damage application.
//
// Pinned VMS Moria moria.inc throw_object/facts/drop_throw: the launcher sets
// the range, the full missile skill less one per square flown, the player's,
// ammunition's and launcher's to-hit, a critical hit by the ammunition's
// weight, and a shot that misses lands at the last open square 9 times in 10
// (one that hits is used up). Damage follows Umoria weaponMissileFacts, by its
// stated fix ("multiply damage bonuses instead of adding ... this makes them
// much more useful"): (dice + ammunition to-dam + launcher to-dam) x the
// launcher's multiplier (maintainer, 2026-10-26).


// ============================================================
// Scratch variables
// ============================================================
rf_ammo_type:  .byte 0     // Matching ammo type (1=arrow, 2=bolt, 3=rock)
rf_ammo_slot:  .byte 0     // Inventory slot of ammo
rf_ammo_id:    .byte 0     // Item type ID of ammo
rf_launcher:   .byte 0     // Launcher index into rf_range_tbl/rf_mult_tbl
rf_dist:       .byte 0     // Squares flown

// Per launcher, Short Bow, Light Crossbow, Sling (IT_MISSILE_BASE + 0..2),
// then Long Bow, Composite Bow, Heavy Crossbow (IT_MISSILE2_BASE + 0..2):
// range (VMS facts: 25, 25, 20, 30, 35, 35) and damage multiplier (Umoria:
// x2, x3, x2, x3, x4, x4).
rf_range_tbl:  .byte 25, 25, 20, 30, 35, 35
rf_mult_tbl:   .byte 2, 3, 2, 3, 4, 4
.assert "Launcher tables cover the six launchers", rf_mult_tbl - rf_range_tbl, 3 + IT_MISSILE2_END - IT_MISSILE2_BASE
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

    // Valid launcher — save ammo type (1/2/3) and the launcher index
    sta rf_ammo_type
    lda inv_item_id + EQUIP_WEAPON
    sec
    sbc #IT_MISSILE_BASE
    cmp #IT_MISSILE2_BASE - IT_MISSILE_BASE
    bcc !rf_index+
    sbc #IT_MISSILE2_BASE - IT_MISSILE_BASE - 3   // carry set: index 3-5
!rf_index:
    sta rf_launcher

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
    ldx rf_ammo_slot
    jsr tw_save_slot            // The shot may land: keep its fields

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

    // 4. Trace projectile, at most the launcher's range in squares
rf_fly:
    lda zp_player_x
    sta proj_cx
    sta tw_last_x
    lda zp_player_y
    sta proj_cy
    sta tw_last_y
    lda #0
    sta rf_dist
    ldx rf_launcher
    lda rf_range_tbl,x
    sta proj_steps
    inc proj_steps

!rf_trace:
    dec proj_steps
    beq !rf_miss_dark_tramp+
    jsr trace_step
    bcs !rf_step_ok+
!rf_miss_dark_tramp:
    jmp rf_miss_darkness
!rf_step_ok:
    inc rf_dist
    lda proj_cx
    sta tw_last_x
    lda proj_cy
    sta tw_last_y

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

    jsr rf_calc_tohit

    // Load monster AC
    ldx cmb_type
    lda cr_ac,x
    sta zp_combat_atk

    // Roll to-hit
    jsr combat_roll_tohit
    bcs !rf_tohit_success+
    jmp rf_miss_monster
!rf_tohit_success:

    // 6. Hit! Roll damage
    jsr rf_roll_damage

    // Critical hit by the ammunition's weight (VMS critical_blow)
    ldx tw_item_id
    lda it_weight,x
    jsr combat_critical_blow_weight

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
    jsr hal_sound_play
    jmp rf_consume_ammo

rf_miss_monster:
    // Message: "THE <ammo> MISSES THE <name>."
    jsr rf_msg_ammo_prefix
    ldx #HSTR_RF_MISSES
    jsr projectile_msg_suffix
    lda #SFX_MISS
    jsr hal_sound_play
    jmp rf_shot_lands

rf_miss_darkness:
    // Message: "THE <ammo> FLIES AWAY."
    jsr rf_msg_ammo_prefix
    ldx #HSTR_RF_FLIES
    jsr huff_append_combat
    jsr rf_print_msg

rf_shot_lands:
    // 7. A shot that missed lands at the last open square when
    // randint(10) > 1 (VMS drop_throw), else it is lost
    ldx rf_ammo_slot
    jsr inv_consume_one
    lda #10
    jsr rng_range               // [0,9]
    beq !rf_done+
    jsr tw_drop_saved
    jmp !rf_done+

rf_consume_ammo:
    // 7. A shot that hit is used up
    ldx rf_ammo_slot
    jsr inv_consume_one

!rf_done:
    sec                         // Turn consumed
    rts

// rf_calc_tohit — The shot's hit chance for the squares flown (rf_dist)
// Output: zp_combat_tohit
// Clobbers: A, X, Y, zp_math_a/b, zp_temp0
rf_calc_tohit:
    // To-hit: the full missile skill with the player's, ammunition's and
    // launcher's to-hit (VMS tpth), less one per square flown (tbth - cur_dis)
    lda player_data + PL_TOHIT
    clc
    adc tw_save_to_hit
    clc
    adc inv_to_hit + EQUIP_WEAPON
    sta cmb_total_tohit
    lda #4                      // BTH_BOW offset in class_properties
    ldx #1                      // BOW level adj offset
    jsr combat_calc_tohit_common
    lda zp_combat_tohit
    sec
    sbc rf_dist
    bcs !rf_dist_ok+
    lda #0
!rf_dist_ok:
    sta zp_combat_tohit
    rts

// rf_roll_damage — The shot's damage before a critical hit: the ammunition's
// dice, then Umoria's launcher multiplier
// Output: cmb_damage
// Clobbers: A, X, Y, zp_math_a/b, zp_temp0
rf_roll_damage:
    ldx tw_item_id
    lda it_dmg_packed,x
    pha
    and #$0f
    tax                         // X = sides
    pla
    lsr
    lsr
    lsr
    lsr                         // A = dice count
    ldy #0                      // No bonus on dice
    jsr math_dice               // Result in zp_math_a

    // Add the ammunition's and launcher's to-dam (signed; enchantments stay
    // well inside a signed byte), floor at 0, then multiply by the launcher
    lda tw_save_to_dam
    clc
    adc inv_to_dam + EQUIP_WEAPON
    clc
    adc zp_math_a
    bpl !rf_dmg_pos+
    lda #0
!rf_dmg_pos:
    sta zp_temp0
    ldx rf_launcher
    lda rf_mult_tbl,x
    tax
    lda zp_temp0
    jsr math_multiply           // zp_math_a = lo, zp_math_b = hi
    lda zp_math_b
    beq !rf_dmg_lo+
    lda #255
    bne !rf_dmg_ok+
!rf_dmg_lo:
    lda zp_math_a
!rf_dmg_ok:
    sta cmb_damage
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
    jmp item_append_name              // tail call

// rf_print_msg — Null-terminate and print combat_msg_buf
// Clobbers: A, X
rf_print_msg:
    jmp cmb_term_and_print
