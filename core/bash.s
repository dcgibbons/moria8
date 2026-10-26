#importonce
#import "df_target_dir.s"
#import "df_target_row.s"
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
    jsr df_target_from_dir
!bash_not_confused:

    // Read map tile at target
    jsr df_target_row_ptr
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
    jsr bash_off_balance_door
    lda #SFX_BUMP
    jsr hal_sound_play
    sec                         // Turn consumed
    rts

!bd_success:
    // Open the door: change tile type to TILE_DOOR_OPEN, keep flags
    jsr df_target_row_ptr
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
// bash_monster — Bash a monster: VMS bash (moria.inc:3384) is py_attack with
// a stand-in weapon: the shield's damage dice (none without one), weight =
// STR, bth = (STR + body weight) / 6, +0 to-hit, to-dam body weight/75 + 1.
// 150 stands in for the unassigned body weight, as in bash_door, so bth =
// STR/6 + 25 and to-dam = 3. Blows are attack_blows with weight = STR, so
// adj_weight is 10: the DEX blows / 1.5, at least one. A creature hit and
// left alive is stunned for randint(2) + 1 turns; then off-balance if
// randint(140) > DEX: paralysed randint(3) turns.
// Deltas: to-hit, the 1-in-20 rolls and criticals use Moria8's melee forms
// (Umoria class level adjustment, the player's melee to-hit in the critical).
// Input: X = monster slot from monster_find_at
// ============================================================
.const BASH_TODAM = 3           // body weight 150 / 75 + 1
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

    // Blows: DEX < 19 (18 or less) one, < 118 two, 18/100 three
    lda zp_player_dex
    ldx #1
    cmp #19
    bcc !bash_blows+
    inx
    cmp #118
    bcc !bash_blows+
    inx
!bash_blows:
    stx bash_blows
    lda #0
    sta bash_hit_alive

    // To-hit: STR/6 + 25 + level * class melee BTH per level
    lda zp_player_str
    sta zp_math_a
    lda #0
    sta zp_math_b
    ldx #6
    jsr math_div_16x8           // zp_math_a = STR / 6
    lda zp_math_a
    clc
    adc #25
    sta zp_combat_tohit
    lda player_data + PL_CLASS
    ldx #CLASS_LVL_SIZE
    jsr math_multiply           // A = class * 5 (melee BTH per level first)
    tax
    lda class_level_adj,x
    ldx zp_player_lvl
    jsr math_multiply           // zp_math_a = level * BTH per level (<= 160)
    lda zp_math_a
    clc
    adc zp_combat_tohit
    bcc !bash_tohit_ok+
    lda #255
!bash_tohit_ok:
    sta zp_combat_tohit

!bash_blow:
    ldx cmb_type
    lda cr_ac,x
    sta zp_combat_atk
    jsr combat_roll_tohit
    bcs !bash_hit+

    // Miss
    lda #<cmb_miss_str
    ldy #>cmb_miss_str
    jsr msg_build_action
    jsr cmb_print_buf
    lda #SFX_MISS
    jsr hal_sound_play
    jmp !bash_next_blow+

!bash_hit:
    // Damage: the shield's dice (0 without one), a critical for weight STR,
    // then + BASH_TODAM
    lda #0
    sta zp_math_a
    ldx inv_item_id + EQUIP_SHIELD
    cpx #FI_EMPTY
    beq !bash_have_dice+
    lda it_dmg_packed,x
    beq !bash_have_dice+
    pha
    and #$0f
    tax                         // X = sides
    pla
    lsr
    lsr
    lsr
    lsr                         // A = dice count
    ldy #0
    jsr math_dice               // zp_math_a = roll
!bash_have_dice:
    lda zp_math_a
    sta cmb_damage
    lda zp_player_str
    jsr combat_critical_blow_weight
    lda cmb_damage
    clc
    adc #BASH_TODAM
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
    jmp bash_monster_done       // VMS py_attack: a kill ends the blows, no stun

!bash_hit_alive:
    // Hit but alive
    lda #<cmb_hit_str
    ldy #>cmb_hit_str
    jsr msg_build_action
    jsr cmb_print_buf
    lda #SFX_HIT
    jsr hal_sound_play
    inc bash_hit_alive

!bash_next_blow:
    dec bash_blows
    beq !bash_blows_done+
    jmp !bash_blow-
!bash_blows_done:
    lda bash_hit_alive
    beq bash_monster_done

    // Stunned for randint(2) + 1 turns (VMS sets the count)
    lda #2
    jsr rng_range               // [0,1]
    clc
    adc #2                      // [2,3]
    pha
    ldx cmb_slot
    jsr monster_get_ptr
    pla
    ldy #MX_STUN
    sta (zp_ptr0),y

    // Print "<name> appears stunned!"
    lda #0
    sta cmb_buf_idx
    jsr combat_append_monster_name
    ldx #HSTR_BASH_STUNNED
    jsr huff_append_combat
    jsr cmb_term_and_print

bash_monster_done:
    // Always check off-balance after bash attempt
    jsr bash_off_balance
    sec                         // Turn consumed
    rts

bash_blows:     .byte 0
bash_hit_alive: .byte 0

// ============================================================
// bash_off_balance — After a creature bash (VMS bash): off-balance when
// randint(140) > DEX, paralysed randint(3) turns.
// bash_off_balance_door — After a door bash (Umoria playerBashClosedDoor):
// randint(150) > DEX, paralysed 1 + randint(2) turns.
// ============================================================
bash_off_balance_door:
    lda #150
    ldx #2
    ldy #2
    bne !bob_roll+              // always taken
bash_off_balance:
    lda #140
    ldx #3
    ldy #1
!bob_roll:
    stx bob_turns
    sty bob_base
    jsr rng_range               // randint(N) - 1
    cmp zp_player_dex
    bcc !bash_balanced+         // randint(N) <= DEX: safe

    lda bob_turns
    jsr rng_range
    clc
    adc bob_base
    sta zp_eff_paralyze

    ldx #HSTR_BASH_OFFBAL
    jsr huff_print_msg

!bash_balanced:
    rts
bob_turns: .byte 0
bob_base:  .byte 0
