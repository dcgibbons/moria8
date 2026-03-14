#importonce
// special_rooms.s — Monster pits, treasure vaults, and nests
//
// At most one special room per dungeon level:
//   RT_PIT  (dlvl >= 5): 4-8 monsters of a single creature type
//   RT_VAULT (dlvl >= 8): Enhanced treasure, entrance sealed with secret door
//   RT_NEST (dlvl >= 3): 3-6 weaker mixed monsters + extra gold

// ============================================================
// Static scratch (safe across subroutine calls)
// ============================================================
sr_room_idx:    .byte 0     // Room index for special room operations
sr_count:       .byte 0     // Spawn loop counter
sr_mode:        .byte 0     // 0=nest (mixed), 1=pit (same type)
sr_fixed_type:  .byte 0     // Creature type for pit (all same) / temp

// Vault seal scratch
vse_rx:     .byte 0
vse_ry:     .byte 0
vse_rw:     .byte 0
vse_rh:     .byte 0
vse_x:      .byte 0         // Current x for vertical wall scan
vse_y_iter: .byte 0         // Current y for vertical wall scan

// ============================================================
// assign_special_room — Decide if this level gets a special room
// Called after shuffle_rooms in dungeon_generate.
// Clears all room_type entries, then may set one to RT_PIT/VAULT/NEST.
// Clobbers: A, X, Y, zp_temp3, zp_temp4
// ============================================================
assign_special_room:
    // Clear all room_type to RT_NORMAL
    ldx room_count
    beq !asr_done+
    dex
    lda #RT_NORMAL
!asr_clear:
    sta room_type,x
    dex
    bpl !asr_clear-

    // Need dlvl >= 3 and at least 2 rooms
    lda zp_player_dlvl
    cmp #3
    bcc !asr_done+
    lda room_count
    cmp #2
    bcc !asr_done+

    // Roll probability: rng(100) < min(dlvl*3, 60)
    lda #100
    jsr rng_range               // A = [0, 99]
    sta sr_count                // Temp: random roll

    // Compute threshold = min(dlvl*3, 60)
    lda zp_player_dlvl
    sta sr_fixed_type           // Temp: dlvl
    asl                         // dlvl*2
    clc
    adc sr_fixed_type           // dlvl*3
    bcs !asr_cap+               // Overflow → cap
    cmp #60
    bcc !asr_thresh_ok+
!asr_cap:
    lda #60
!asr_thresh_ok:
    // A = threshold; sr_count = random roll
    // Want: roll < threshold (i.e., threshold > roll)
    cmp sr_count
    beq !asr_done+              // roll == threshold → no special
    bcc !asr_done+              // threshold < roll → no special

    // Pick a room: rng(room_count-1) + 1 (skip room 0 = stairs-up)
    lda room_count
    sec
    sbc #1
    jsr rng_range               // [0, room_count-2]
    clc
    adc #1                      // [1, room_count-1]
    sta sr_room_idx             // Save before rng_range clobbers registers

    // Pick type based on dlvl eligibility
    lda zp_player_dlvl
    cmp #8
    bcs !asr_all_three+
    cmp #5
    bcs !asr_pit_or_nest+

    // dlvl 3-4: nest only
    lda #RT_NEST
    jmp !asr_store+

!asr_pit_or_nest:
    // dlvl 5-7: pit or nest (50/50)
    lda #2
    jsr rng_range               // [0, 1]
    beq !asr_is_nest+
    lda #RT_PIT
    jmp !asr_store+
!asr_is_nest:
    lda #RT_NEST
    jmp !asr_store+

!asr_all_three:
    // dlvl 8+: pit, vault, or nest (equal probability)
    lda #3
    jsr rng_range               // [0, 2]
    clc
    adc #1                      // [1, 3] = RT_PIT, RT_VAULT, RT_NEST
    // Fall through to store

!asr_store:
    ldx sr_room_idx
    sta room_type,x
!asr_done:
    rts

// ============================================================
// find_special_room — Find room with given type
// Input:  A = room type to find (RT_PIT, RT_VAULT, RT_NEST)
// Output: X = room index, carry set = found
//         carry clear = not found
// Clobbers: X
// ============================================================
find_special_room:
    ldx room_count
    beq !fsr_fail+
    dex
!fsr_loop:
    cmp room_type,x
    beq !fsr_found+
    dex
    bpl !fsr_loop-
!fsr_fail:
    clc
    rts
!fsr_found:
    sec
    rts

// ============================================================
// vault_seal_entrance — Convert first door on vault perimeter to secret door
// Called after add_corridor_doors in dungeon_generate.
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
vault_seal_entrance:
    lda #RT_VAULT
    jsr find_special_room
    bcs !vse_go+
    rts
!vse_go:
    // Save room geometry to scratch
    lda room_x,x
    sta vse_rx
    lda room_y,x
    sta vse_ry
    lda room_w,x
    sta vse_rw
    lda room_h,x
    sta vse_rh

    // --- Scan top wall: y = ry-1, x from rx to rx+rw-1 ---
    lda vse_ry
    sec
    sbc #1
    tay                         // Y = wall row
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldx vse_rw                  // Count = room width
    ldy vse_rx                  // Start at room_x
    jsr vse_scan_hwall
    bcs !vse_done+

    // --- Scan bottom wall: y = ry+rh ---
    lda vse_ry
    clc
    adc vse_rh
    tay
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldx vse_rw
    ldy vse_rx
    jsr vse_scan_hwall
    bcs !vse_done+

    // --- Scan left wall: x = rx-1, y from ry to ry+rh-1 ---
    lda vse_rx
    sec
    sbc #1
    sta vse_x
    lda vse_ry
    sta vse_y_iter
    ldx vse_rh
    jsr vse_scan_vwall
    bcs !vse_done+

    // --- Scan right wall: x = rx+rw ---
    lda vse_rx
    clc
    adc vse_rw
    sta vse_x
    lda vse_ry
    sta vse_y_iter
    ldx vse_rh
    jsr vse_scan_vwall

!vse_done:
    rts

// Scan horizontal wall for door — zp_ptr0 = row base, Y = start col, X = count
// Returns carry set if found and sealed
vse_scan_hwall:
!vsh_loop:
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    beq !vsh_seal+
    cmp #TILE_DOOR_CLOSED
    beq !vsh_seal+
    iny
    dex
    bne !vsh_loop-
    clc
    rts
!vsh_seal:
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_SECRET
    :MapWrite_ptr0_y()
    sec
    rts

// Scan vertical wall for door — vse_x = column, vse_y_iter = start row, X = count
// Returns carry set if found and sealed
vse_scan_vwall:
!vsv_loop:
    ldy vse_y_iter
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldy vse_x
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    beq !vsv_seal+
    cmp #TILE_DOOR_CLOSED
    beq !vsv_seal+
    inc vse_y_iter
    dex
    bne !vsv_loop-
    clc
    rts
!vsv_seal:
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_SECRET
    :MapWrite_ptr0_y()
    sec
    rts

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
    sta fi_add_p1
    sta fi_add_flags

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
