#importonce
// dungeon_feature_gen.s - generation-owned trap/secret-door state and helpers.

// Hidden traps are stored here; NOT in map tiles until triggered/found.
trap_count: .byte 0
trap_x:     .fill MAX_TRAPS, 0
trap_y:     .fill MAX_TRAPS, 0
trap_type:  .fill MAX_TRAPS, 0

// Shared feature scratch. Generation uses the target/found/dir fields; runtime
// trap, door, search, and disarm code reuses the same storage.
df_target_x: .byte 0
df_target_y: .byte 0
df_dir_idx:  .byte 0
df_found:    .byte 0
df_search_chance: .byte 0
df_death_source: .byte 0
df_death_hstr:   .byte 0
df_disarm_chance: .byte 0
df_disarm_trap_idx: .byte 0
df_disarm_total: .byte 0
df_disarm_base: .byte 0

// find_random_floor — Find a random empty walkable floor tile on the map.
// Output: carry set = found (df_target_x/y valid)
//         carry clear = failed after 200 tries
frf_attempts: .byte 0

find_random_floor:
    lda #200
    sta frf_attempts

!frf_loop:
    lda #MAP_COLS - 2
    jsr rng_range
    clc
    adc #1
    sta df_target_x

    lda #MAP_ROWS - 2
    jsr rng_range
    clc
    adc #1
    sta df_target_y

    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    :MapRead_ptr0_y()
    sta zp_temp0
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    bne !frf_next+
    lda zp_temp0
    and #(FLAG_OCCUPIED | FLAG_HAS_ITEM)
    bne !frf_next+
    sec
    rts
!frf_next:
    dec frf_attempts
    bne !frf_loop-

    clc
    rts
// Generation-only door scan scratch. This must not alias visible screen RAM:
// the generation busy screen stays visible while secrets are placed.
.const MAX_DOOR_SCAN = 32
.label door_scan_x = hal_layout_dungeon_door_scan_base
.label door_scan_y = door_scan_x + MAX_DOOR_SCAN
.label door_scan_count = door_scan_y + MAX_DOOR_SCAN
.assert "Door scan scratch stays inside platform scratch window", door_scan_count < hal_layout_dungeon_door_scan_limit, true

// place_secrets — Convert 1-3 random closed doors to secret doors.
place_secrets:
    lda zp_player_dlvl
    bne !ps_not_town+
    rts
!ps_not_town:
    lda #0
    sta door_scan_count

    ldx #1
!ps_row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    stx df_target_y

    ldy #1
!ps_col:
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_CLOSED
    bne !ps_next+

    lda door_scan_count
    cmp #MAX_DOOR_SCAN
    bcs !ps_next+

    tax
    lda df_target_y
    sta door_scan_y,x
    tya
    sta door_scan_x,x
    inc door_scan_count

!ps_next:
    iny
    cpy #MAP_COLS - 1
    bne !ps_col-

    ldx df_target_y
    inx
    cpx #MAP_ROWS - 1
    bne !ps_row-

    lda door_scan_count
    beq !ps_done+

    lda #3
    jsr rng_range
    clc
    adc #1
    sta df_found

    lda df_found
    cmp door_scan_count
    bcc !ps_convert+
    beq !ps_convert+
    lda door_scan_count
    sta df_found

!ps_convert:
    lda df_found
    beq !ps_done+

    lda door_scan_count
    jsr rng_range
    sta df_dir_idx

    tax
    lda door_scan_y,x
    sta df_target_y
    lda door_scan_x,x
    sta df_target_x

    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_SECRET
    :MapWrite_ptr0_y()

    dec door_scan_count
    ldx df_dir_idx
    ldy door_scan_count
    lda door_scan_x,y
    sta door_scan_x,x
    lda door_scan_y,y
    sta door_scan_y,x

    dec df_found
    jmp !ps_convert-

!ps_done:
    rts

.assert "MAX_TRAPS", MAX_TRAPS, 16
.assert "TRAP_TYPE_COUNT", TRAP_TYPE_COUNT, 6
