// tunnel.s — Tunnel command (+ key)
//
// Dig through walls, magma, quartz, and rubble. Core umoria command.
// + direction: tunnel into adjacent tile. STR + weapon bonus vs wall
// resistance determines success. Treasure veins drop gold when opened.
// Reference: umoria playerTunnel() in player.cpp

// ============================================================
// Scratch variables
// ============================================================
tun_save_tile:  .byte 0     // Saved tile byte at target
tun_dir_idx:    .byte 0     // Direction index 0-7
tun_dig_ability: .byte 0    // Calculated digging ability

// ============================================================
// player_tunnel — Entry point for tunnel command
// Output: carry set = turn consumed, carry clear = cancelled
// Clobbers: everything
// ============================================================
player_tunnel:
    // Fear check
    lda eff_fear_timer
    beq !tun_not_afraid+
    ldx #HSTR_PTM_AFRAID
    jsr huff_decode_string
    jsr msg_print
    clc
    rts
!tun_not_afraid:

    // Get direction
    jsr get_direction_target
    bcs !tun_has_dir+
    clc
    rts                         // Cancelled
!tun_has_dir:

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
!tun_find_dir:
    lda dir_dx,x
    cmp zp_temp0
    bne !tun_dir_next+
    lda dir_dy,x
    cmp zp_temp1
    beq !tun_dir_found+
!tun_dir_next:
    inx
    cpx #8
    bcc !tun_find_dir-
    clc
    rts                         // Shouldn't happen
!tun_dir_found:
    stx tun_dir_idx

    // Confusion check — 75% chance of random direction (umoria)
    lda zp_eff_confuse
    beq !tun_not_confused+

    lda #4
    jsr rng_range               // [0,3]
    beq !tun_not_confused+      // 25% chance: keep intended direction

    // Pick random direction 0-7
    lda #8
    jsr rng_range
    sta tun_dir_idx
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
!tun_not_confused:

    // Read map tile at target
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    lda (zp_ptr0),y
    sta tun_save_tile

    // Check for monster at target → attack instead
    lda df_target_x
    ldy df_target_y
    jsr monster_find_at
    bcc !tun_no_monster+
    // Monster present — redirect to melee attack
    lda df_target_x
    ldy df_target_y
    jmp player_attack_monster
!tun_no_monster:

    // Re-setup map pointer (monster_find_at clobbers zp_ptr0)
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi

    // Boundary check: edge tiles are permanent rock
    lda df_target_x
    beq !tun_permanent+
    cmp #MAP_COLS - 1
    beq !tun_permanent+
    lda df_target_y
    beq !tun_permanent+
    cmp #MAP_ROWS - 1
    beq !tun_permanent+

    // Check tile type
    lda tun_save_tile
    and #TILE_TYPE_MASK

    // Granite walls (types 1-6: $10-$60)
    cmp #TILE_WALL_H
    beq !tun_granite+
    cmp #TILE_WALL_V
    beq !tun_granite+
    cmp #TILE_CORNER_TL
    beq !tun_granite+
    cmp #TILE_CORNER_TR
    beq !tun_granite+
    cmp #TILE_CORNER_BL
    beq !tun_granite+
    cmp #TILE_CORNER_BR
    beq !tun_granite+

    // Magma
    cmp #TILE_MAGMA
    beq !tun_magma+

    // Quartz
    cmp #TILE_QUARTZ
    beq !tun_quartz+

    // Rubble — always succeeds
    cmp #TILE_RUBBLE
    beq !tun_rubble+

    // Secret doors — treat as granite
    cmp #TILE_SECRET
    beq !tun_granite+

    // Closed doors — also accept (treat as granite difficulty)
    cmp #TILE_DOOR_CLOSED
    beq !tun_granite+

    // Everything else (floor, open door, stairs, trap) — nothing to tunnel
    ldx #HSTR_TUN_NOTHING
    jsr huff_decode_string
    jsr msg_print
    clc                         // No turn consumed
    rts

!tun_permanent:
    ldx #HSTR_TUN_PERMANENT
    jsr huff_decode_string
    jsr msg_print
    clc                         // No turn consumed
    rts

// ============================================================
// Tunnel attempt by wall type
// Each sets resistance, then falls through to dig check
// ============================================================

!tun_granite:
    // Resistance: rng(20) + 8 → 8-27
    lda #20
    jsr rng_range
    clc
    adc #8
    sta zp_temp0                // resistance
    ldx #HSTR_TUN_DIG_GRANITE   // fail message
    jmp !tun_dig_check+

!tun_magma:
    // Resistance: rng(12) + 3 → 3-14
    lda #12
    jsr rng_range
    clc
    adc #3
    sta zp_temp0                // resistance
    ldx #HSTR_TUN_DIG_MAGMA     // fail message
    jmp !tun_dig_check+

!tun_quartz:
    // Resistance: rng(10) + 2 → 2-11
    lda #10
    jsr rng_range
    clc
    adc #2
    sta zp_temp0                // resistance
    ldx #HSTR_TUN_DIG_QUARTZ    // fail message
    jmp !tun_dig_check+

// ============================================================
// Rubble — always succeeds, no resistance check
// ============================================================
!tun_rubble:
    // Replace with floor
    ldy df_target_x
    lda #TILE_FLOOR | FLAG_VISITED | FLAG_LIT
    sta (zp_ptr0),y

    ldx #HSTR_TUN_RUBBLE
    jsr huff_decode_string
    jsr msg_print

    lda #1
    sta vis_room_revealed       // Trigger viewport redraw
    sec                         // Turn consumed
    rts

// ============================================================
// tun_dig_check — Compare digging ability vs resistance
// Input: zp_temp0 = resistance, X = fail message HSTR ID
// zp_ptr0/Y still point to target tile
// ============================================================
!tun_dig_check:
    stx zp_temp1                // Save fail message ID

    // Calculate digging ability (banked at $F000)
    // Accounts for digging tools or weapon TODMG bonus
    jsr tramp_dig_ability

    // Success check: digging_ability > resistance
    lda tun_dig_ability
    cmp zp_temp0                // carry set if ability >= resistance
    bcc !tun_fail+
    // Also need strictly greater: if equal, 50% chance
    bne !tun_success+
    jsr rng_byte
    and #1
    beq !tun_fail+

!tun_success:
    // Replace tile with floor
    ldy df_target_x
    lda #TILE_FLOOR | FLAG_VISITED | FLAG_LIT
    sta (zp_ptr0),y

    // Check for treasure in vein
    lda tun_save_tile
    and #FLAG_HAS_ITEM
    beq !tun_no_treasure+

    // Spawn gold from treasure vein
    jsr tunnel_spawn_gold

    ldx #HSTR_TUN_FOUND
    jsr huff_decode_string
    jsr msg_print
    lda #SFX_PICKUP
    jsr sound_play
    jmp !tun_success_done+

!tun_no_treasure:
    ldx #HSTR_TUN_FINISHED
    jsr huff_decode_string
    jsr msg_print

!tun_success_done:
    lda #1
    sta vis_room_revealed       // Trigger viewport redraw
    sec                         // Turn consumed
    rts

!tun_fail:
    // Print wall-type-specific "You dig in the..." message
    ldx zp_temp1                // Fail message HSTR ID
    jsr huff_decode_string
    jsr msg_print
    sec                         // Turn consumed (digging takes effort)
    rts

// tunnel_spawn_gold is in item.s (shared with spell_effects.s)
