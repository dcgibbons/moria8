#importonce
// special_room_gen.s - special-room generation helpers
//
// Shared by full special-room population and by generators that only need to
// assign room types and seal vault entrances.

// Vault seal scratch
vse_x:      .byte 0         // Current x for vertical wall scan
vse_y_iter: .byte 0         // Current y for vertical wall scan

// ============================================================
// assign_special_room - Decide if this level gets a special room
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
    bcs !asr_cap+               // Overflow -> cap
    cmp #60
    bcc !asr_thresh_ok+
!asr_cap:
    lda #60
!asr_thresh_ok:
    // A = threshold; sr_count = random roll
    // Want: roll < threshold (i.e., threshold > roll)
    cmp sr_count
    beq !asr_done+              // roll == threshold -> no special
    bcc !asr_done+              // threshold < roll -> no special

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
// find_special_room - Find room with given type
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
// vault_seal_entrance - Convert first door on vault perimeter to secret door
// Called after corridor carving / door placement in dungeon_generate.
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
    sta zp_temp0
    lda room_y,x
    sta zp_temp1
    lda room_w,x
    sta zp_temp2
    lda room_h,x
    sta zp_temp3

    // --- Scan top wall: y = ry-1, x from rx to rx+rw-1 ---
    lda zp_temp1
    sec
    sbc #1
    tay                         // Y = wall row
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldx zp_temp2                // Count = room width
    ldy zp_temp0                // Start at room_x
    jsr vse_scan_hwall
    bcs !vse_done+

    // --- Scan bottom wall: y = ry+rh ---
    lda zp_temp1
    clc
    adc zp_temp3
    tay
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldx zp_temp2
    ldy zp_temp0
    jsr vse_scan_hwall
    bcs !vse_done+

    // --- Scan left wall: x = rx-1, y from ry to ry+rh-1 ---
    lda zp_temp0
    sec
    sbc #1
    sta vse_x
    lda zp_temp1
    sta vse_y_iter
    ldx zp_temp3
    jsr vse_scan_vwall
    bcs !vse_done+

    // --- Scan right wall: x = rx+rw ---
    lda zp_temp0
    clc
    adc zp_temp2
    sta vse_x
    lda zp_temp1
    sta vse_y_iter
    ldx zp_temp3
    jsr vse_scan_vwall

!vse_done:
    rts

// Scan horizontal wall for door - zp_ptr0 = row base, Y = start col, X = count
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

// Scan vertical wall for door - vse_x = column, vse_y_iter = start row, X = count
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
