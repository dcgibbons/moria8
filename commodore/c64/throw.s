// throw.s — Throwing items at monsters
//
// SHIFT+T throws any inventory item at a target in a direction.
// Traces projectile path (like ranged_fire.s), checks for monster hit,
// rolls damage. Potions shatter on impact; other items land on floor.
// Reuses melee combat subroutines for to-hit and damage application.
// Reference: umoria player_throw.cpp

// ============================================================
// Scratch variables
// ============================================================
tw_slot:       .byte 0     // Inventory slot of thrown item
tw_item_id:    .byte 0     // Item type ID
tw_dir:        .byte 0     // Direction index 0-7
tw_cx:         .byte 0     // Current trace X
tw_cy:         .byte 0     // Current trace Y
tw_steps:      .byte 0     // Steps remaining (range)
tw_last_x:     .byte 0     // Last walkable position X (for floor drop)
tw_last_y:     .byte 0     // Last walkable position Y
tw_save_p1:    .byte 0     // Saved p1 before consumption
tw_save_flags: .byte 0     // Saved flags before consumption
tw_save_ego:   .byte 0     // Saved ego before consumption

// Strings migrated to Huffman compression (HSTR_TW_* in huffman_data.s)

// ============================================================
// throw_item — Throw an inventory item
// Output: carry set = turn consumed, carry clear = cancelled
// Clobbers: everything
// ============================================================
throw_item:
    // 1. Prompt for item
    ldx #HSTR_TW_PROMPT
    jsr huff_decode_string
    jsr msg_print

    jsr input_get_key

    // '?' shows inventory (all items) and re-prompts
    cmp #$3f
    bne !tw_not_inv+
    lda #$ff                    // Filter: show all items
    jsr show_inv_and_restore
    jmp throw_item
!tw_not_inv:

    // ESC ($03) or space ($20) → cancel
    cmp #$03
    beq !tw_cancel+
    cmp #$20
    beq !tw_cancel+

    // Convert PETSCII letter to slot index (A-V = $41-$56 → 0-21)
    sec
    sbc #$41
    bcc !tw_cancel+
    cmp #MAX_INV_SLOTS
    bcs !tw_cancel+

    // Check slot occupied
    tax
    lda inv_item_id,x
    cmp #FI_EMPTY
    bne !tw_slot_ok+

    // Empty slot
    ldx #HSTR_PIW_NOTHING
    jsr huff_decode_string
    jsr msg_print
    clc
    rts

!tw_cancel:
    ldx #HSTR_PIW_NEVERMIND
    jsr huff_decode_string
    jsr msg_print
    clc
    rts

!tw_slot_ok:
    stx tw_slot
    lda inv_item_id,x
    sta tw_item_id

    // 2. Get direction
    jsr get_direction_target
    bcs !tw_has_dir+
    clc
    rts                         // Cancelled
!tw_has_dir:

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
!tw_find_dir:
    lda dir_dx,x
    cmp zp_temp0
    bne !tw_dir_next+
    lda dir_dy,x
    cmp zp_temp1
    beq !tw_dir_found+
!tw_dir_next:
    inx
    cpx #8
    bcc !tw_find_dir-
    clc
    rts                         // Shouldn't happen
!tw_dir_found:
    stx tw_dir

    // 3. Calculate range: min(10, (STR + 20) * 10 / weight)
    lda zp_player_str
    clc
    adc #20                     // A = STR + 20
    ldx #10
    jsr math_multiply           // zp_math_a = lo, zp_math_b = hi

    // Load weight
    ldx tw_item_id
    lda it_weight,x
    beq !tw_max_range+          // Weight 0 → max range
    tax                         // X = divisor (weight)
    jsr math_div_16x8           // zp_math_a = quotient lo

    // Clamp to [1, 10]
    lda zp_math_a
    beq !tw_min_range+          // 0 → clamp to 1
    cmp #11
    bcc !tw_range_ok+
    lda #10                     // >10 → clamp to 10
    jmp !tw_range_ok+
!tw_min_range:
    lda #1
    jmp !tw_range_ok+
!tw_max_range:
    lda #10
!tw_range_ok:
    sta tw_steps

    // 4. Trace projectile
    lda zp_player_x
    sta tw_cx
    sta tw_last_x
    lda zp_player_y
    sta tw_cy
    sta tw_last_y

!tw_trace:
    dec tw_steps
    bmi !tw_miss_dark_tramp+

    // Step in direction
    ldx tw_dir
    lda tw_cx
    clc
    adc dir_dx,x
    sta tw_cx
    lda tw_cy
    clc
    adc dir_dy,x
    sta tw_cy

    // Bounds check
    lda tw_cx
    beq !tw_miss_dark_tramp+
    cmp #MAP_COLS - 1
    bcs !tw_miss_dark_tramp+
    lda tw_cy
    beq !tw_miss_dark_tramp+
    cmp #MAP_ROWS - 1
    bcc !tw_bounds_ok+
!tw_miss_dark_tramp:
    jmp tw_miss_darkness
!tw_bounds_ok:

    // Check walkability
    ldx tw_cy
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy tw_cx
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    lsr
    lsr
    lsr
    lsr
    tax
    lda walkable_table,x
    beq !tw_miss_dark_tramp-    // Blocked

    // Update last walkable position
    lda tw_cx
    sta tw_last_x
    lda tw_cy
    sta tw_last_y

    // Check for monster
    lda tw_cx
    ldy tw_cy
    jsr monster_find_at
    bcc !tw_trace-              // No monster, keep tracing

    // 5. Hit a monster! X = slot index
    stx cmb_slot
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    sta cmb_type

    // Calculate BOW-based to-hit (75% of BOW BTH)
    jsr throw_calc_tohit

    // Load monster AC
    ldx cmb_type
    lda cr_ac,x
    sta zp_combat_atk

    // Roll to-hit
    jsr combat_roll_tohit
    bcs !tw_hit+
    jmp tw_miss_monster
!tw_hit:

    // 6. Hit! Roll damage using item's dice
    ldx tw_item_id
    lda it_dmg_dice,x
    bne !tw_has_dice+
    // No dice (0d0) — use 1d1 minimum
    lda #1
    ldx #1
    jmp !tw_roll_dice+
!tw_has_dice:
    pha
    lda it_dmg_sides,x
    tax                         // X = sides
    pla                         // A = dice count
!tw_roll_dice:
    ldy #0                      // No bonus on dice
    jsr math_dice               // Result in zp_math_a

    // Add STR damage bonus from str_damage_bonus[STR-3]
    ldx zp_player_str
    dex
    dex
    dex                         // X = STR - 3
    lda str_damage_bonus,x
    bmi !tw_str_neg+
    clc
    adc zp_math_a
    jmp !tw_add_todmg+
!tw_str_neg:
    clc
    adc zp_math_a
    bpl !tw_add_todmg+
    lda #0                      // Clamp to 0
!tw_add_todmg:

    // Add PL_TODMG
    sta zp_temp0
    lda player_data + PL_TODMG
    bmi !tw_todmg_neg+
    clc
    adc zp_temp0
    bcc !tw_dmg_ok+
    lda #255
    jmp !tw_dmg_ok+
!tw_todmg_neg:
    clc
    adc zp_temp0
    bpl !tw_dmg_ok+
    lda #0                      // Clamp to 0
!tw_dmg_ok:
    sta cmb_damage

    // Apply damage
    ldx cmb_slot
    lda cmb_damage
    jsr combat_apply_damage
    bcc !tw_hit_alive+

    // Monster killed — "YOU HAVE SLAIN THE <name>."
    ldx cmb_slot
    jsr eff_kill_monster
    lda #<cmb_kill_str
    ldy #>cmb_kill_str
    jsr msg_build_action
    jsr cmb_print_buf
    lda #SFX_HIT
    jsr sound_play
    jmp tw_consume_item

!tw_hit_alive:
    // Wake the monster
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    ora #MF_AWAKE
    sta (zp_ptr0),y

    // Message: "THE <item> HITS THE <name>."
    jsr tw_msg_item_prefix          // "THE <item>"
    ldx #HSTR_RF_HITS
    jsr huff_append_combat          // " HITS"
    lda #<cmb_the_str
    ldy #>cmb_the_str
    jsr combat_append_str           // " THE "
    jsr combat_append_monster_name
    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str
    jsr cmb_term_and_print
    lda #SFX_HIT
    jsr sound_play
    jmp tw_consume_item

tw_miss_monster:
    // Message: "THE <item> MISSES THE <name>."
    jsr tw_msg_item_prefix
    ldx #HSTR_RF_MISSES
    jsr huff_append_combat
    lda #<cmb_the_str
    ldy #>cmb_the_str
    jsr combat_append_str
    jsr combat_append_monster_name
    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str
    jsr cmb_term_and_print
    lda #SFX_MISS
    jsr sound_play
    jmp tw_consume_item

tw_miss_darkness:
    // Message: "THE <item> FLIES AWAY." or "THE <item> SHATTERS!"
    jsr tw_msg_item_prefix

    // Check if potion → shatter message
    ldx tw_item_id
    lda it_category,x
    cmp #ICAT_POTION
    bne !tw_flies+
    ldx #HSTR_TW_SHATTERS
    jsr huff_append_combat
    jsr cmb_term_and_print
    jmp tw_consume_item
!tw_flies:
    ldx #HSTR_RF_FLIES
    jsr huff_append_combat
    jsr cmb_term_and_print

tw_consume_item:
    // Save item properties before consumption (inv_remove_item clears them)
    ldx tw_slot
    lda inv_p1,x
    sta tw_save_p1
    lda inv_flags,x
    sta tw_save_flags
    lda inv_ego,x
    sta tw_save_ego

    // Consume 1 from inventory
    dec inv_qty,x
    bne !tw_qty_ok+
    // Qty reached 0 — clear slot
    jsr inv_remove_item
!tw_qty_ok:

    // Place on floor? Potions always shatter (no floor item)
    ldx tw_item_id
    lda it_category,x
    cmp #ICAT_POTION
    beq !tw_done+

    // Place 1 copy on floor at last walkable position
    lda tw_last_x
    sta fi_add_x
    lda tw_last_y
    sta fi_add_y
    lda tw_item_id
    sta fi_add_id
    lda #1
    sta fi_add_qty
    lda tw_save_p1
    sta fi_add_p1
    lda tw_save_flags
    sta fi_add_flags
    lda tw_save_ego
    sta fi_add_ego
    jsr floor_item_add
    // Ignore failure (table full)

!tw_done:
    sec                         // Turn consumed
    rts

// ============================================================
// throw_calc_tohit — BOW-based to-hit at 75%
// Like combat_calc_tohit but uses BTH_BOW (offset 4) instead of BTH (offset 3)
// Then applies 75% multiplier (*3/4)
// Output: zp_combat_tohit
// Clobbers: A, X, Y, zp_math_a/b, zp_temp0
// ============================================================
throw_calc_tohit:
    // Get class BTH_BOW (class_properties offset 4)
    lda player_data + PL_CLASS
    ldx #CLASS_PROP_SIZE
    jsr math_multiply           // A = class * 10
    clc
    adc #4                      // Offset to BTH_BOW field
    tax
    lda class_properties,x
    sta zp_combat_tohit

    // Add race BTH (race_properties offset 7, signed byte)
    lda player_data + PL_RACE
    ldx #RACE_PROP_SIZE
    jsr math_multiply           // A = race * RACE_PROP_SIZE
    clc
    adc #7                      // Offset to BTH field
    tax
    lda race_properties,x
    bmi !tct_race_neg+
    clc
    adc zp_combat_tohit
    bcc !tct_race_done+
    lda #255
    jmp !tct_race_done+
!tct_race_neg:
    eor #$ff
    clc
    adc #1
    sta zp_temp0
    lda zp_combat_tohit
    sec
    sbc zp_temp0
    bcs !tct_race_done+
    lda #0
!tct_race_done:
    sta zp_combat_tohit

    // Add PL_TOHIT * 3
    lda player_data + PL_TOHIT
    bmi !tct_neg_tohit+
    sta zp_temp0
    asl                         // *2
    clc
    adc zp_temp0                // *3
    clc
    adc zp_combat_tohit
    bcc !tct_tohit_ok+
    lda #255
    jmp !tct_tohit_ok+
!tct_neg_tohit:
    eor #$ff
    clc
    adc #1
    sta zp_temp0
    asl
    clc
    adc zp_temp0                // *3 (positive value)
    sta zp_temp0
    lda zp_combat_tohit
    sec
    sbc zp_temp0
    bcs !tct_tohit_ok+
    lda #0
!tct_tohit_ok:
    sta zp_combat_tohit

    // Add player_level * class_bth_bow_per_level (class_level_adj offset 1)
    lda player_data + PL_CLASS
    ldx #CLASS_LVL_SIZE
    jsr math_multiply           // A = class * 5
    clc
    adc #1                      // Offset to BOW per-level
    tax
    lda class_level_adj,x       // BOW per level
    ldx zp_player_lvl
    jsr math_multiply           // zp_math_a = level * bow_per_level
    lda zp_math_a
    clc
    adc zp_combat_tohit
    bcc !tct_lvl_done+
    lda #255
!tct_lvl_done:
    sta zp_combat_tohit

    // Apply 75%: tohit = tohit * 3 / 4
    lda zp_combat_tohit
    sta zp_temp0
    asl                         // *2
    bcs !tct_cap_75+            // Overflow on *2
    clc
    adc zp_temp0                // *3
    bcc !tct_div4+
!tct_cap_75:
    lda #255                    // Cap intermediate at 255
!tct_div4:
    lsr                         // /2
    lsr                         // /4 → 75%
    sta zp_combat_tohit
    rts

// ============================================================
// tw_msg_item_prefix — Start building "THE <item>" in combat_msg_buf
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1
// ============================================================
tw_msg_item_prefix:
    lda #0
    sta cmb_buf_idx
    lda #<(cmb_the_str + 1)         // Skip leading space: "THE " not " THE "
    ldy #>(cmb_the_str + 1)
    jsr combat_append_str
    lda #0
    sta fi_add_ego                  // Don't append ego suffix for thrown item name
    lda tw_item_id
    jsr item_append_name
    rts
