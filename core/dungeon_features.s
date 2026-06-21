#importonce
// dungeon_features.s — Doors, traps, secret doors, search
//
// Phase 4.2: Explicit open/close door commands, stuck door mechanics,
// hidden trap placement and triggering, secret doors found by searching.

#import "input_ui_helpers.s"
#import "dungeon_feature_gen.s"
#import "dungeon_feature_actions.s"

// ============================================================
// Trap name Huffman indices (indexed by trap type 0-5)
// ============================================================
trap_name_huff_idx:
    .byte HSTR_DF_TRAP_0, HSTR_DF_TRAP_1, HSTR_DF_TRAP_2
    .byte HSTR_DF_TRAP_3, HSTR_DF_TRAP_4, HSTR_DF_TRAP_5

#if PLATFORM_DISARM_COMMAND_INLINE || !DISARM_HELPERS_EXTERNAL
trap_difficulty:
    .byte 5, 15, 10, 20, 20, 25
#endif

#if PLATFORM_DISARM_COMMAND_INLINE || !DISARM_COMMAND_EXTERNAL
trap_disarm_xp:
    .byte 1, 3, 2, 5, 6, 8

disarm_no_visible_str:
    .text "I do not see anything to disarm there." ; .byte 0
disarm_success_str:
    .text "You have disarmed the trap." ; .byte 0
disarm_fail_str:
    .text "You failed to disarm the trap." ; .byte 0
disarm_bad_fail_str:
    .text "You set the trap off!" ; .byte 0
#endif

// ============================================================
// trap_check_at_player — Check if player stepped on a trap
// Scans trap table for player's (x, y). If found: reveal trap on map and
// trigger it. Matching umoria, ordinary triggered floor traps remain live and
// can still be disarmed later.
// Called from main.s after successful move.
// ============================================================
trap_check_at_player:
    lda trap_count
    beq !tcp_done+          // No traps

    ldx #0
!tcp_loop:
    cpx trap_count
    bcs !tcp_done+

    lda trap_x,x
    cmp zp_player_x
    bne !tcp_next+
    lda trap_y,x
    cmp zp_player_y
    bne !tcp_next+

    // Found a trap at player position!
    // Save trap index
    stx df_dir_idx

    // Reveal trap on map: change tile to TILE_TRAP | flags
    ldy zp_player_y
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldy zp_player_x
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK     // Keep existing flags
    ora #TILE_TRAP          // Set tile type to trap
    ora #FLAG_VISITED       // Ensure visible
    :MapWrite_ptr0_y()

    // Trigger the trap effect
    ldx df_dir_idx
    jsr trap_trigger

    // Done (only one trap per tile)
    sec                     // Carry set = trap fired
    rts

!tcp_next:
    inx
    jmp !tcp_loop-

!tcp_done:
    clc                     // Carry clear = no trap
    rts

// trap_remove_at_index — Remove trap table entry X by swapping with the last.
trap_remove_at_index:
    dec trap_count
    ldy trap_count
    lda trap_x,y
    sta trap_x,x
    lda trap_y,y
    sta trap_y,x
    lda trap_type,y
    sta trap_type,x
    rts

// trap_find_target_visible — Find a visible target trap with matching table entry.
// Requires df_target_x/df_target_y from get_direction_target.
// Output: carry set = found, X/index stored in df_disarm_trap_idx.
trap_find_target_visible:
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_TRAP
    bne !not_found+

    ldx #0
!scan:
    cpx trap_count
    bcs !not_found+
    lda trap_x,x
    cmp df_target_x
    bne !next+
    lda trap_y,x
    cmp df_target_y
    bne !next+
    stx df_disarm_trap_idx
    sec
    rts
!next:
    inx
    jmp !scan-
!not_found:
    clc
    rts

#if PLATFORM_DISARM_COMMAND_INLINE || !DISARM_COMMAND_EXTERNAL
// disarm_command — Direct visible floor-trap disarm command.
// Output: carry set = turn consumed, carry clear = no turn.
disarm_command:
    jsr get_direction_target
    bcc !no_turn+
    jsr trap_find_target_visible
    bcs !has_trap+
    lda #<disarm_no_visible_str
    sta zp_ptr0
    lda #>disarm_no_visible_str
    sta zp_ptr0_hi
    jsr msg_print
!no_turn:
    clc
    rts

!has_trap:
    jsr player_disarm_get_effective_chance
    sta df_disarm_total
    ldx df_disarm_trap_idx
    lda trap_type,x
    tax
    lda df_disarm_total
    jsr disarm_calc_success_threshold
    sta df_disarm_chance
    lda #100
    jsr rng_range
    cmp df_disarm_chance
    bcc !success+

    lda df_disarm_total
    jsr disarm_roll_bad_fail
    bcs !bad_fail+
    lda #<disarm_fail_str
    sta zp_ptr0
    lda #>disarm_fail_str
    sta zp_ptr0_hi
    jsr msg_print
    sec
    rts

!success:
    lda #<disarm_success_str
    sta zp_ptr0
    lda #>disarm_success_str
    sta zp_ptr0_hi
    jsr msg_print
    jsr disarm_award_trap_xp
    jsr disarm_restore_target_floor
    ldx df_disarm_trap_idx
    jsr trap_remove_at_index
    jsr disarm_move_player_to_target
    sec
    rts

!bad_fail:
    lda #<disarm_bad_fail_str
    sta zp_ptr0
    lda #>disarm_bad_fail_str
    sta zp_ptr0_hi
    jsr msg_print
    jsr disarm_move_player_to_target
    ldx df_disarm_trap_idx
    jsr trap_trigger
    sec
    rts

disarm_restore_target_floor:
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_FLOOR
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()
    rts

disarm_move_player_to_target:
    lda df_target_x
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda df_target_y
    sta zp_player_y
    sta player_data + PL_MAP_Y
    rts

disarm_award_trap_xp:
    ldx df_disarm_trap_idx
    lda trap_type,x
    tax
    lda player_data + PL_XP_0
    clc
    adc trap_disarm_xp,x
    sta player_data + PL_XP_0
    bcc !done+
    inc player_data + PL_XP_1
    bne !done+
    inc player_data + PL_XP_2
!done:
    rts

#endif

#if !DISARM_HELPERS_EXTERNAL
#import "disarm_helpers.s"
#endif

// ============================================================
// trap_trigger — Execute a trap's effect
// Input: X = trap table index (trap_type[X] has the type)
// ============================================================
trap_trigger:
    jsr player_search_mode_off
    lda trap_type,x

    cmp #TRAP_OPEN_PIT
    bne !not_pit+
    jmp trap_do_pit
!not_pit:
    cmp #TRAP_ARROW
    bne !not_arrow+
    jmp trap_do_arrow
!not_arrow:
    cmp #TRAP_POISON_GAS
    bne !not_gas+
    jmp trap_do_gas
!not_gas:
    cmp #TRAP_TELEPORT
    bne !not_tele+
    jmp trap_do_teleport
!not_tele:
    cmp #TRAP_POISON_DART
    bne !not_dart+
    jmp trap_do_dart
!not_dart:
    // Must be TRAP_ROCKFALL
    jmp trap_do_rockfall

// --- Trap effect handlers ---

// Open pit: 1d4 damage
trap_do_pit:
    ldx #HSTR_DF_YOU_FELL
    jsr huff_print_msg
    lda #DEATH_TRAP_PIT
    sta df_death_source
    lda #HSTR_DF_TRAP_0
    sta df_death_hstr
    lda #1              // 1 die
    ldx #4              // d4
    ldy #0              // +0
    jsr trap_apply_damage
    rts

// Arrow trap: 1d8 damage
trap_do_arrow:
    ldx #HSTR_DF_ARROW_HITS
    jsr huff_print_msg
    lda #DEATH_TRAP_ARROW
    sta df_death_source
    lda #HSTR_DF_TRAP_1
    sta df_death_hstr
    lda #1
    ldx #8
    ldy #0
    jsr trap_apply_damage
    rts

// Poison gas: set poison timer to 10 + 1d10
trap_do_gas:
    ldx #HSTR_DF_POISON_GAS
    jsr huff_print_msg
    // Set poison timer: 10 + rng_range(10) + 1 = 11..20
    lda #10
    jsr rng_range           // [0, 9]
    clc
    adc #11                 // [11, 20]
    sta zp_eff_poison
    // Print "YOU FEEL POISONED."
    ldx #HSTR_DF_POISONED
    jsr huff_print_msg
    rts

// Teleport: move player to random floor tile
trap_do_teleport:
    ldx #HSTR_DF_TELEPORTED
    jsr huff_print_msg
    jsr trap_teleport
    rts

// Poison dart: 1d4 damage + 50% chance CON decrement
trap_do_dart:
    ldx #HSTR_DF_DART_HITS
    jsr huff_print_msg
    lda #DEATH_TRAP_DART
    sta df_death_source
    lda #HSTR_DF_TRAP_4
    sta df_death_hstr
    lda #1
    ldx #4
    ldy #0
    jsr trap_apply_damage
    // 50% chance to lose 1 CON
    jsr rng_byte
    and #1
    beq !no_con_drain+
    // Decrement CON
    lda player_data + PL_CON_CUR
    cmp #4                  // Don't go below 3
    bcc !no_con_drain+
    jsr decrement_stat
    sta player_data + PL_CON_CUR
    sta zp_player_con
    ldx #HSTR_DF_CON_DRAIN
    jsr huff_print_msg
!no_con_drain:
    rts

// Rockfall: 2d8 damage
trap_do_rockfall:
    ldx #HSTR_DF_ROCKFALL
    jsr huff_print_msg
    lda #DEATH_TRAP_ROCKFALL
    sta df_death_source
    lda #HSTR_DF_DEATH_ROCKFALL
    sta df_death_hstr
    lda #2              // 2 dice
    ldx #8              // d8
    ldy #0              // +0
    jsr trap_apply_damage
    rts

// ============================================================
// trap_apply_damage — Roll damage and subtract from player HP
// Input: A = dice count, X = dice sides, Y = bonus
// Prints "YOU TAKE N DAMAGE." message.
// ============================================================
trap_apply_damage:
    jsr math_dice           // Result in zp_math_a (lo), zp_math_b (hi)

    // Save damage amount
    lda zp_math_a
    sta df_target_x         // Reuse scratch for damage value

    // Subtract from player HP (16-bit)
    lda zp_player_hp_lo
    sec
    sbc zp_math_a
    sta zp_player_hp_lo
    lda zp_player_hp_hi
    sbc zp_math_b
    sta zp_player_hp_hi

    // Clamp lethal trap damage before syncing the player struct.
    lda zp_player_hp_hi
    bmi !trap_lethal+
    ora zp_player_hp_lo
    bne !trap_sync+

!trap_lethal:
    lda #0
    sta zp_player_hp_lo
    sta zp_player_hp_hi
    lda df_death_source
    sta zp_death_source
    jsr trap_resolve_death_name

!trap_sync:
    // Sync to player struct
    lda zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda zp_player_hp_hi
    sta player_data + PL_HP_HI

    // Print "YOU TAKE N DAMAGE."
    ldx #HSTR_DF_DAMAGE_PRE
    jsr huff_print_msg

    // Print damage number and " DAMAGE." inline on same row
    // msg_print left cursor at end of "YOU TAKE "
    // Set message color for inline text
    lda zp_text_color
    pha
    lda #COL_MSG_TEXT
    sta zp_text_color

    lda df_target_x
    jsr screen_put_decimal

    ldx #HSTR_DF_DAMAGE_POST
    jsr huff_decode_string
    jsr hal_screen_put_string

    pla
    sta zp_text_color

    // Play hit sound for surviving hits; lethal trap damage uses the
    // standard death path so the death sound is not overwritten.
    lda zp_player_hp_hi
    ora zp_player_hp_lo
    beq !trap_death+

    lda #SFX_HIT
    jsr hal_sound_play

    rts

!trap_death:
    jmp player_death_check

// ============================================================
// trap_resolve_death_name — Resolve lethal trap cause text
// ============================================================
// Copies the existing trap name string into creature_name_buf so the death
// overlay can display it after tier/overlay memory has been replaced.
trap_resolve_death_name:
    ldx df_death_hstr
    jsr huff_decode_string
    ldy #0
!trdn_copy:
    lda hd_decode_buf,y
    sta creature_name_buf,y
    beq !trdn_done+
    iny
    cpy #31
    bne !trdn_copy-
    lda #0
    sta creature_name_buf,y
!trdn_done:
    rts

// ============================================================
// trap_teleport — Move player to a random floor tile
// ============================================================
trap_teleport:
    jsr player_search_mode_off
    // Find a random floor tile using simple scan
    lda #100                // Max attempts
    sta df_found
!tt_loop:
    // Random x in [1, MAP_COLS-2]
    lda #MAP_COLS - 2
    jsr rng_range
    clc
    adc #1
    sta df_target_x

    // Random y in [1, MAP_ROWS-2]
    lda #MAP_ROWS - 2
    jsr rng_range
    clc
    adc #1
    sta df_target_y

    // Check if floor
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    beq !tt_found+

    dec df_found
    bne !tt_loop-
    rts                     // Give up, stay in place

!tt_found:
    // Move player to new position
    lda df_target_x
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda df_target_y
    sta zp_player_y
    sta player_data + PL_MAP_Y
    rts

// ============================================================
// Compile-time validation
// ============================================================
