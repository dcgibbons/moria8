// bash.s — Bash command (SHIFT+D)
//
// Bash doors open, stun monsters with shield attacks. Core umoria command.
// SHIFT+D + direction: bash doors (break open stuck/closed doors),
// monsters (shield bash + stun check), walls/empty (no effect).
// Reference: umoria playerBash() in player.cpp

// ============================================================
// Scratch variables
// ============================================================
bash_save_tile: .byte 0     // Saved tile byte at target
bash_dir_idx:   .byte 0     // Direction index 0-7

// Strings migrated to Huffman compression (HSTR_BASH_* in huffman_data.s)

// ============================================================
// bash_command — Entry point for bash command
// Output: carry set = turn consumed, carry clear = cancelled
// Clobbers: everything
// ============================================================
bash_command:
    // Fear check
    lda eff_fear_timer
    beq !bash_not_afraid+
    ldx #HSTR_PTM_AFRAID
    jsr huff_print_msg
    clc
    rts
!bash_not_afraid:

    // Get direction
    jsr get_direction_target
    bcs !bash_has_dir+
    clc
    rts                         // Cancelled
!bash_has_dir:

    // Save direction index for confusion redirection
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
!bash_find_dir:
    lda dir_dx,x
    cmp zp_temp0
    bne !bash_dir_next+
    lda dir_dy,x
    cmp zp_temp1
    beq !bash_dir_found+
!bash_dir_next:
    inx
    cpx #8
    bcc !bash_find_dir-
    clc
    rts                         // Shouldn't happen
!bash_dir_found:
    stx bash_dir_idx

    // Confusion check — randomize direction
    lda zp_eff_confuse
    beq !bash_not_confused+

    // Pick random direction 0-7
    lda #8
    jsr rng_range               // [0,7]
    sta bash_dir_idx
    tax

    // Recompute target from player position
    lda zp_player_x
    clc
    adc dir_dx,x
    sta df_target_x
    lda zp_player_y
    clc
    adc dir_dy,x
    sta df_target_y
!bash_not_confused:

    // Read map tile at target
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    lda (zp_ptr0),y
    sta bash_save_tile

    // Check for monster at target
    lda df_target_x
    ldy df_target_y
    jsr monster_find_at
    bcc !bash_no_monster+
    jmp bash_monster
!bash_no_monster:

    // Check tile type
    lda bash_save_tile
    and #TILE_TYPE_MASK

    cmp #TILE_DOOR_CLOSED
    beq bash_door

    // Wall types or secret door? "nothing happens"
    cmp #TILE_WALL_H
    beq !bash_wall+
    cmp #TILE_WALL_V
    beq !bash_wall+
    cmp #TILE_SECRET
    beq !bash_wall+
    cmp #TILE_CORNER_TL
    beq !bash_wall+
    cmp #TILE_CORNER_TR
    beq !bash_wall+
    cmp #TILE_CORNER_BL
    beq !bash_wall+
    cmp #TILE_CORNER_BR
    beq !bash_wall+
    cmp #TILE_RUBBLE
    beq !bash_wall+
    cmp #TILE_MAGMA
    beq !bash_wall+
    cmp #TILE_QUARTZ
    beq !bash_wall+

    // Empty space (floor, open door, stairs, etc.)
    ldx #HSTR_BASH_EMPTY
    jsr huff_print_msg
    sec                         // Turn consumed
    rts

!bash_wall:
    ldx #HSTR_BASH_NOTHING
    jsr huff_print_msg
    sec                         // Turn consumed
    rts

// ============================================================
// bash_door — Bash a closed door
// ============================================================
bash_door:
    // Print smash message
    ldx #HSTR_BASH_SMASH
    jsr huff_print_msg

    // Roll: rng_range(STR + 10), success if result >= 5
    lda zp_player_str
    clc
    adc #10
    jsr rng_range               // [0, STR+9]
    cmp #5
    bcs !bash_door_success+

    // Fail — door holds
    ldx #HSTR_BASH_HOLDS
    jsr huff_print_msg
    jsr bash_off_balance
    lda #SFX_BUMP
    jsr sound_play
    sec                         // Turn consumed
    rts

!bash_door_success:
    // Open the door: change tile type to TILE_DOOR_OPEN, keep flags
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    lda bash_save_tile
    and #TILE_FLAG_MASK         // Keep flags
    ora #TILE_DOOR_OPEN         // Set to open door
    sta (zp_ptr0),y

    // Print success message
    ldx #HSTR_BASH_CRASH
    jsr huff_print_msg

    lda #SFX_HIT
    jsr sound_play
    sec                         // Turn consumed
    rts

// ============================================================
// bash_monster — Bash a monster with shield
// Input: X = monster slot from monster_find_at
// ============================================================
bash_monster:
    // Save slot and load creature type (same pattern as combat.s:46-58)
    stx cmb_slot
    jsr monster_get_ptr         // zp_ptr0 = entry
    ldy #MX_TYPE
    lda (zp_ptr0),y
    sta cmb_type

    // Wake monster and mark provoked
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    ora #MF_AWAKE | MF_PROVOKED
    sta (zp_ptr0),y

    // --- Calculate to-hit ---
    // Base: STR + 5
    lda zp_player_str
    clc
    adc #5
    sta zp_combat_tohit

    // Add shield weight / 2
    ldy #EQUIP_SHIELD
    lda inv_item_id,y
    cmp #FI_EMPTY
    beq !bash_no_shield+
    tax                         // X = shield item type
    lda it_weight,x
    lsr                         // weight / 2
    clc
    adc zp_combat_tohit
    bcc !bash_tohit_ok+
    lda #255                    // Cap at 255
    jmp !bash_tohit_ok+
!bash_no_shield:
!bash_tohit_ok:
    sta zp_combat_tohit

    // Load monster AC
    ldx cmb_type
    lda cr_ac,x
    sta zp_combat_atk

    // Roll to-hit
    jsr combat_roll_tohit
    bcs !bash_hit+

    // Miss
    lda #<cmb_miss_str
    ldy #>cmb_miss_str
    jsr msg_build_action
    jsr cmb_print_buf
    lda #SFX_MISS
    jsr sound_play
    jmp bash_monster_done

!bash_hit:
    // --- Calculate damage: 1d4 + str_damage_bonus[STR-3] + 3 ---
    lda #1                      // 1 die
    ldx #4                      // 4 sides
    ldy #0                      // No bonus
    jsr math_dice               // Result in zp_math_a

    // Add STR damage bonus
    ldx zp_player_str
    dex
    dex
    dex                         // X = STR - 3
    lda str_damage_bonus,x
    bmi !bash_str_neg+
    clc
    adc zp_math_a
    jmp !bash_add_flat+
!bash_str_neg:
    clc
    adc zp_math_a
    bpl !bash_add_flat+
    lda #0                      // Clamp to 0
!bash_add_flat:
    // Add +3 flat bonus
    clc
    adc #3
    bcc !bash_dmg_ok+
    lda #255                    // Clamp at 255
!bash_dmg_ok:
    sta cmb_damage

    // Apply damage
    ldx cmb_slot
    lda cmb_damage
    jsr combat_apply_damage
    bcc !bash_hit_alive+

    // Monster killed
    ldx cmb_slot
    jsr monster_remove

    lda #<cmb_kill_str
    ldy #>cmb_kill_str
    jsr msg_build_action
    jsr cmb_print_buf

    jsr combat_award_xp
    jsr combat_check_levelup

    lda #SFX_HIT
    jsr sound_play
    jmp bash_monster_done

!bash_hit_alive:
    // Hit but alive
    lda #<cmb_hit_str
    ldy #>cmb_hit_str
    jsr msg_build_action
    jsr cmb_print_buf

    lda #SFX_HIT
    jsr sound_play

    // Check for stun
    jsr bash_stun_check

bash_monster_done:
    // Always check off-balance after bash attempt
    jsr bash_off_balance
    sec                         // Turn consumed
    rts

// ============================================================
// bash_stun_check — Check if bash stuns the monster
// Uses cmb_slot, cmb_type (must still be valid)
// ============================================================
bash_stun_check:
    // bash_power = 25 + rng_range(100) + rng_range(100) — range 25-225
    lda #100
    jsr rng_range               // [0,99]
    sta zp_temp0
    lda #100
    jsr rng_range               // [0,99]
    clc
    adc zp_temp0
    clc
    adc #25                     // bash_power in A (may wrap but 25+99+99=223 fits)
    sta zp_temp0                // zp_temp0 = bash_power

    // mon_hp_q = monster HP / 4 (16-bit → 8-bit after shift)
    ldx cmb_slot
    jsr monster_get_ptr
    ldy #MX_HP_HI
    lda (zp_ptr0),y
    sta zp_temp1                // HP hi
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    sta zp_temp2                // HP lo

    // Divide 16-bit HP by 4 (shift right twice)
    lsr zp_temp1
    ror zp_temp2
    lsr zp_temp1
    ror zp_temp2

    // If HP hi byte still nonzero after /4 → skip stun (massive monster)
    lda zp_temp1
    bne !bash_ignores+
    // zp_temp2 = mon_hp_q (8-bit)

    // avg_max_q = cr_hd_num[type] * (cr_hd_sides[type]+1) / 8
    ldx cmb_type
    lda cr_hd_sides,x
    clc
    adc #1                      // sides + 1
    tax                         // X = sides+1
    ldx cmb_type
    lda cr_hd_num,x             // A = hd_num
    ldx cmb_type
    // Need: A = hd_num, X = sides+1
    pha                         // Save hd_num
    lda cr_hd_sides,x
    clc
    adc #1
    tax                         // X = sides+1
    pla                         // A = hd_num
    jsr math_multiply           // zp_math_a = lo, zp_math_b = hi

    // Divide by 8 (shift right 3 times on 16-bit result)
    lda zp_math_b
    sta zp_temp3                // hi
    lda zp_math_a               // lo
    lsr zp_temp3
    ror
    lsr zp_temp3
    ror
    lsr zp_temp3
    ror
    // A = avg_max_q (low byte; zp_temp3 should be 0 for reasonable creatures)

    // mon_tough = mon_hp_q + avg_max_q (clamp at 255)
    clc
    adc zp_temp2                // mon_hp_q + avg_max_q
    bcc !bash_tough_ok+
    lda #255
!bash_tough_ok:
    sta zp_temp2                // zp_temp2 = mon_tough

    // If bash_power > mon_tough → stun
    lda zp_temp0                // bash_power
    cmp zp_temp2                // compare with mon_tough
    bcc !bash_ignores+          // bash_power < mon_tough → no stun
    beq !bash_ignores+          // bash_power == mon_tough → no stun

    // Stun! stun_add = rng_range(3) + 2, cap total at 24
    lda #3
    jsr rng_range               // [0,2]
    clc
    adc #2                      // [2,4]

    // Add to existing stun timer
    ldx cmb_slot
    jsr monster_get_ptr
    ldy #MX_STUN
    clc
    adc (zp_ptr0),y
    cmp #25
    bcc !bash_stun_ok+
    lda #24                     // Cap at 24
!bash_stun_ok:
    sta (zp_ptr0),y

    // Print "<name> appears stunned!"
    lda #0
    sta cmb_buf_idx
    jsr combat_append_monster_name
    ldx #HSTR_BASH_STUNNED
    jsr huff_append_combat
    jsr cmb_term_and_print
    rts

!bash_ignores:
    // Print "<name> ignores your bash!"
    lda #0
    sta cmb_buf_idx
    jsr combat_append_monster_name
    ldx #HSTR_BASH_IGNORES
    jsr huff_append_combat
    jsr cmb_term_and_print
    rts

// ============================================================
// bash_off_balance — Check if player loses balance after bash
// ============================================================
bash_off_balance:
    lda #150
    jsr rng_range               // [0,149]
    cmp zp_player_dex
    bcc !bash_balanced+         // roll < DEX → safe
    beq !bash_balanced+         // roll == DEX → safe

    // Off balance — paralyze 1-2 turns
    lda #2
    jsr rng_range               // [0,1]
    clc
    adc #1                      // [1,2]
    sta zp_eff_paralyze

    ldx #HSTR_BASH_OFFBAL
    jsr huff_print_msg

!bash_balanced:
    rts
