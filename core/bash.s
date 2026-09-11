#importonce
// bash.s — Bash command (CTRL+B)
//
// Bash doors open, stun monsters with shield attacks. Core umoria command.
// CTRL+B + direction: bash doors (break open stuck/closed doors),
// monsters (shield bash + stun check). Tunnelable terrain hands off to
// the digging path so the dig intent reaches player_tunnel.
// Reference: umoria playerBash() in player.cpp


// ============================================================
// Scratch variables
// ============================================================
bash_save_tile: .byte 0     // Saved tile byte at target

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

    // Confusion check — randomize direction
    lda zp_eff_confuse
    beq !bash_not_confused+

    // Pick random direction 0-7
    lda #8
    jsr rng_range               // [0,7]
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
    :MapRead_ptr0_y()
    sta bash_save_tile

    // Check for monster at target
    lda df_target_x
    ldy df_target_y
    jsr monster_find_at
    bcc !bash_no_monster+
    jmp bash_monster
!bash_no_monster:

    // Chest at the (post-confusion) target? Dispatch to the chest overlay via
    // the resident chest_dispatch; never returns here (docs/CHEST_DESIGN.md).
    jsr chest_find_at_df_target
    bcc !bash_no_chest+
    lda #<chest_bash_command
    ldy #>chest_bash_command
    jmp chest_dispatch
!bash_no_chest:

    // Check tile type
    lda bash_save_tile
    and #TILE_TYPE_MASK

    cmp #TILE_DOOR_CLOSED
    beq bash_door

    // Tunnelable terrain? Hand off to the digging path so Shift+D on a
    // vein/wall/rubble reaches the tunnel logic instead of bash's wall miss.
    cmp #TILE_WALL_H
    beq !bash_tunnel+
    cmp #TILE_WALL_V
    beq !bash_tunnel+
    cmp #TILE_SECRET
    beq !bash_tunnel+
    cmp #TILE_CORNER_TL
    beq !bash_tunnel+
    cmp #TILE_CORNER_TR
    beq !bash_tunnel+
    cmp #TILE_CORNER_BL
    beq !bash_tunnel+
    cmp #TILE_CORNER_BR
    beq !bash_tunnel+
    cmp #TILE_RUBBLE
    beq !bash_tunnel+
    cmp #TILE_MAGMA
    beq !bash_tunnel+
    cmp #TILE_QUARTZ
    beq !bash_tunnel+

    // Empty space (floor, open door, stairs, etc.)
    ldx #HSTR_BASH_EMPTY
    jsr huff_print_msg
    sec                         // Turn consumed
    rts

!bash_tunnel:
    jmp player_tunnel_resolved_target

// ============================================================
// bash_door — Bash a closed door
// Umoria playerBashClosedDoor: chance = STR + weight/2; success iff
// rng(chance * (20 + |s|)) < 10 * (chance - |s|), where s = signed door
// state (locked/stuck magnitude). Moria8 proxy: PL_WEIGHT is aesthetic and
// never assigned, so a fixed 75 stands in for a typical body weight/2
// (maintainer-approved deviation 2026-09-04). Success opens the door (50%
// break) and steps into the doorway; failure prints "holds firm" and rolls
// the DEX off-balance check.
// ============================================================
bash_door:
    // Print smash message
    ldx #HSTR_BASH_SMASH
    jsr huff_print_msg

    lda zp_player_str
    clc
    adc #75
    sta bash_chance

    // |door state| — bit 7 set = stuck/jammed, magnitude in bits 0-6
    lda df_target_x
    ldy df_target_y
    jsr door_state_get
    bpl !bd_abs+
    and #$7f
!bd_abs:
    sta bash_abs_state

    // chance - |s| <= 0 → hopeless; the door holds
    lda bash_chance
    sec
    sbc bash_abs_state
    bcc !bd_holds+
    beq !bd_holds+

    // spread = chance * (20 + |s|)
    lda bash_abs_state
    clc
    adc #20
    tax
    lda bash_chance
    jsr math_multiply           // zp_math_a/b = spread
    lda zp_math_a
    sta zp_temp0
    lda zp_math_b
    sta zp_temp1
    jsr rng_range_word          // zp_temp2/3 = roll [0, spread-1]

    // threshold = 10 * (chance - |s|)
    lda bash_chance
    sec
    sbc bash_abs_state
    ldx #10
    jsr math_multiply           // zp_math_a/b = threshold

    // success iff roll < threshold (16-bit)
    lda zp_temp3
    cmp zp_math_b
    bcc !bd_success+
    bne !bd_holds+
    lda zp_temp2
    cmp zp_math_a
    bcc !bd_success+

!bd_holds:
    ldx #HSTR_BASH_HOLDS
    jsr huff_print_msg
    jsr bash_off_balance
    lda #SFX_BUMP
    jsr hal_sound_play
    sec                         // Turn consumed
    rts

!bd_success:
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
    :MapWrite_ptr0_y()

    // 50% break (Umoria: misc_use = 1 - randomNumber(2) — any nonzero state
    // on an open door is broken)
    lda #2
    jsr rng_range
    bne !bd_unbroken+
    // A broken result needs a state entry. Existing locked/stuck entries can
    // be updated even when full; an untracked plain door cannot add one.
    lda bash_abs_state
    bne !bd_broken+
    ldx door_state_count
    cpx #MAX_DOOR_STATES
    bcs !bd_unbroken+            // Full table: open, but keep it closable
!bd_broken:
    lda #1
    bne !bd_set_state+           // always
!bd_unbroken:
    lda #0
!bd_set_state:
    jsr door_state_set_at

    // Print success message
    ldx #HSTR_BASH_CRASH
    jsr huff_print_msg

    // Step into the doorway (Umoria playerMove on bash success)
    lda df_target_x
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda df_target_y
    sta zp_player_y
    sta player_data + PL_MAP_Y
    lda #1
    sta player_move_relocated

    // Umoria routes successful door bashes through playerMove, including its
    // passive search after relocation. Preserve that movement side effect.
    jsr player_move_maybe_passive_search

    lda #SFX_HIT
    jsr hal_sound_play
    sec                         // Turn consumed
    rts

bash_chance:     .byte 0
bash_abs_state:  .byte 0

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
    jsr hal_sound_play
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
#if HAL_PLATFORM_BASH_LEVELUP_RESTORE_ITEMS
    jsr tramp_combat_check_levelup_items
#else
    jsr combat_check_levelup
#endif
    jsr combat_note_kill
    jsr combat_print_winner_message

    lda #SFX_HIT
    jsr hal_sound_play
    jmp bash_monster_done

!bash_hit_alive:
    // Hit but alive
    lda #<cmb_hit_str
    ldy #>cmb_hit_str
    jsr msg_build_action
    jsr cmb_print_buf

    lda #SFX_HIT
    jsr hal_sound_play

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
