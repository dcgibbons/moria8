#importonce
// special_rooms.s — Monster pits, treasure vaults, and nests
//
// At most one special room per dungeon level:
//   RT_PIT  (dlvl >= 5): 4-8 monsters of a single creature type
//   RT_VAULT (dlvl >= 8): Enhanced treasure, entrance sealed with secret door
//   RT_NEST (dlvl >= 3): 3-6 weaker mixed monsters + extra gold

#import "special_room_gen.s"

// ============================================================
// spawn_special_room_monsters — Spawn monsters for pit or nest
// Called from monster_spawn_level after normal spawns.
// Pit: 4-8 of same type; Nest: 3-6 mixed weaker types
// Clobbers: A, X, Y, zp_ptr0, zp_temp0-4, ms_spawn_x/y
// ============================================================
spawn_special_room_monsters:
    // --- Check for pit ---
    lda #RT_PIT
    jsr find_special_room
    bcc !ssm_no_pit+

    stx sr_room_idx
    jsr pick_creature_type
    sta sr_fixed_type           // All pit monsters same type
    lda #5
    jsr rng_range               // [0, 4]
    clc
    adc #4                      // [4, 8]
    sta sr_count
    lda #1                      // mode = pit (same type)
    sta sr_mode
    jmp !ssm_spawn_loop+

!ssm_no_pit:
    // --- Check for nest ---
    lda #RT_NEST
    jsr find_special_room
    bcc !ssm_done+

    stx sr_room_idx
    lda #4
    jsr rng_range               // [0, 3]
    clc
    adc #3                      // [3, 6]
    sta sr_count
    lda #0                      // mode = nest (mixed types, lower dlvl)
    sta sr_mode

!ssm_spawn_loop:
    lda sr_count
    beq !ssm_done+

    // Random floor position in room
    ldx sr_room_idx
    jsr random_floor_in_room    // A=x, Y=y
    sta ms_spawn_x
    sty ms_spawn_y

    // Verify: floor tile, not occupied, not player
    tya
    tax                         // X = y row
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy ms_spawn_x
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK | FLAG_OCCUPIED
    bne !ssm_skip+              // Not clean floor

    lda ms_spawn_x
    cmp zp_player_x
    bne !ssm_pos_ok+
    lda ms_spawn_y
    cmp zp_player_y
    beq !ssm_skip+              // Player is here
!ssm_pos_ok:

    // Pick creature type based on mode
    lda sr_mode
    bne !ssm_pit_type+

    // Nest mode: temporarily lower dlvl by 2 (floor 1)
    lda zp_player_dlvl
    pha                         // Save original dlvl
    sec
    sbc #2
    bcs !ssm_dlvl_floor+
    lda #1
!ssm_dlvl_floor:
    cmp #1
    bcs !ssm_dlvl_set+
    lda #1
!ssm_dlvl_set:
    sta zp_player_dlvl
    jsr pick_creature_type
    sta sr_fixed_type           // Reuse scratch for spawn type
    pla                         // Restore original dlvl
    sta zp_player_dlvl
    lda sr_fixed_type
    jmp !ssm_do_spawn+

!ssm_pit_type:
    lda sr_fixed_type

!ssm_do_spawn:
    jsr monster_spawn_one
    // Ignore failure (table could be full)

!ssm_skip:
    dec sr_count
    jmp !ssm_spawn_loop-

!ssm_done:
    rts

// ============================================================
// spawn_nest_gold — Scatter 2-4 gold piles in nest room
// Called from item_spawn_level after Phase 2 / before Phase 3.
// Clobbers: A, X, Y, zp_ptr0, zp_temp3, zp_temp4
// ============================================================
spawn_nest_gold:
    lda #RT_NEST
    jsr find_special_room
    bcc !sng_done+

    stx sr_room_idx

    // 2 + rng(3) gold piles = [2, 4]
    lda #3
    jsr rng_range               // [0, 2]
    clc
    adc #2                      // [2, 4]
    sta sr_count

!sng_loop:
    lda sr_count
    beq !sng_done+

    // Random floor position in nest room
    ldx sr_room_idx
    jsr random_floor_in_room    // A=x, Y=y
    sta fi_add_x
    sty fi_add_y

    // Gold type 0, qty = rng(dlvl*10) + 5 (same formula as Phase 1)
    lda #0
    sta fi_add_id
    jsr fi_add_clear_plain_meta

    // dlvl * 10 = dlvl*8 + dlvl*2
    lda zp_player_dlvl
    asl                         // *2
    sta sr_fixed_type           // Temp: dlvl*2
    lda zp_player_dlvl
    asl
    asl
    asl                         // *8
    clc
    adc sr_fixed_type           // *10
    bcc !sng_no_cap+
    lda #255
!sng_no_cap:
    jsr rng_range               // [0, dlvl*10-1]
    clc
    adc #5                      // [5, dlvl*10+4]
    bcc !sng_qty_ok+
    lda #255
!sng_qty_ok:
    sta fi_add_qty

    jsr floor_item_add
    // Ignore failure (table full)

    dec sr_count
    jmp !sng_loop-

!sng_done:
    rts
