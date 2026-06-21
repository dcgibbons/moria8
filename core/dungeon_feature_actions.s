#importonce
// dungeon_feature_actions.s — Direction prompts plus door/search runtime
// actions shared by platform loops.

#import "input_ui_helpers.s"
#import "dungeon_feature_gen.s"
#import "player_search.s"

// get_direction_target — Prompt for direction and compute target.
// Output: df_target_x/df_target_y = adjacent tile coordinates
//         carry set = valid direction entered
//         carry clear = invalid key
get_direction_target:
    ldx #HSTR_DF_DIRECTION
    jsr huff_print_msg

    lda zp_player_x
    pha
    lda zp_player_y
    pha
    jsr input_prepare_followup_key
    jsr hal_input_get_key
    jsr petscii_to_command
    sta df_dir_idx
    pla
    sta zp_player_y
    pla
    sta zp_player_x

    lda df_dir_idx
    cmp #CMD_MOVE_N
    bcc !gdt_invalid+
    cmp #CMD_MOVE_SE + 1
    bcs !gdt_invalid+

    sec
    sbc #CMD_MOVE_N
    tax

    lda zp_player_x
    clc
    adc dir_dx,x
    sta df_target_x

    lda zp_player_y
    clc
    adc dir_dy,x
    sta df_target_y

    sec
    rts

!gdt_invalid:
    clc
    rts

// door_try_open — Attempt to open a door at (df_target_x, df_target_y).
// Output: carry set = door opened/stuck attempt consumed a turn,
//         carry clear = no turn consumed.
door_try_open:
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    :MapRead_ptr0_y()
    sta df_dir_idx

    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_CLOSED
    beq !dto_closed+
    cmp #TILE_DOOR_OPEN
    beq !dto_already_open+
    cmp #TILE_SECRET
    beq !dto_no_door+

!dto_no_door:
    ldx #HSTR_DF_NO_DOOR
    jsr huff_print_msg
    clc
    rts

!dto_already_open:
    ldx #HSTR_DF_ALREADY_OPEN
    jsr huff_print_msg
    clc
    rts

!dto_closed:
    lda #4
    jsr rng_range
    cmp #0
    bne !dto_open_it+

    lda zp_player_str
    cmp #16
    bcs !dto_open_it+

    ldx #HSTR_DF_DOOR_STUCK
    jsr huff_print_msg
    lda #SFX_BUMP
    jsr hal_sound_play
    sec
    rts

!dto_open_it:
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    lda df_dir_idx
    and #TILE_FLAG_MASK
    ora #TILE_DOOR_OPEN
    :MapWrite_ptr0_y()

    ldx #HSTR_DF_DOOR_OPENED
    jsr huff_print_msg
    sec
    rts

// door_try_close — Attempt to close a door at (df_target_x, df_target_y).
// Output: carry set = door closed, carry clear = no turn consumed.
door_try_close:
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    :MapRead_ptr0_y()
    sta df_dir_idx

    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    beq !dtc_open+
    cmp #TILE_DOOR_CLOSED
    beq !dtc_already_closed+

    ldx #HSTR_DF_NO_DOOR
    jsr huff_print_msg
    clc
    rts

!dtc_already_closed:
    ldx #HSTR_DF_ALREADY_CLOSED
    jsr huff_print_msg
    clc
    rts

!dtc_open:
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    lda df_dir_idx
    and #TILE_FLAG_MASK
    ora #TILE_DOOR_CLOSED
    :MapWrite_ptr0_y()

    ldx #HSTR_DF_DOOR_CLOSED
    jsr huff_print_msg
    sec
    rts

// search_scan_effective_silent — Shared search scan using live player chance.
// Output: carry set = something found, carry clear = nothing found.
search_scan_effective_silent:
    jsr player_search_get_effective_chance
    // Fall through into search_scan_adjacent_silent.

// search_scan_adjacent_silent — Search adjacent tiles without printing a
// "nothing found" message. Found-object messages still print.
// Input: A = per-tile search chance in percent
// Output: carry set = something found, carry clear = nothing found
search_scan_adjacent_silent:
    sta df_search_chance
    lda #0
    sta df_found
    sta df_dir_idx

!ds_loop:
    ldx df_dir_idx

    lda zp_player_x
    clc
    adc dir_dx,x
    sta df_target_x

    lda zp_player_y
    clc
    adc dir_dy,x
    sta df_target_y

    lda df_target_x
    beq !ds_skip+
    cmp #MAP_COLS - 1
    bcs !ds_skip+
    lda df_target_y
    beq !ds_skip+
    cmp #MAP_ROWS - 1
    bcc !ds_bounds_ok+
!ds_skip:
    jmp !ds_next+
!ds_bounds_ok:

    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK

    cmp #TILE_SECRET
    bne !ds_check_trap+

    lda df_search_chance
    beq !ds_check_trap+
    lda #100
    jsr rng_range
    cmp df_search_chance
    bcs !ds_check_trap+

!ds_secret_found:
    ldy df_target_x
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_DOOR_CLOSED
    :MapWrite_ptr0_y()

    ldx #HSTR_DF_FOUND_SECRET
    jsr huff_print_msg
    lda #1
    sta df_found
    jmp !ds_next+

!ds_check_trap:
    ldx #0
!ds_trap_scan:
    cpx trap_count
    bcs !ds_next+

    lda trap_x,x
    cmp df_target_x
    bne !ds_trap_next+
    lda trap_y,x
    cmp df_target_y
    bne !ds_trap_next+

    ldy df_target_x
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_TRAP
    beq !ds_trap_next+

    txa
    pha

    lda df_search_chance
    beq !ds_trap_not_found+
    lda #100
    jsr rng_range
    cmp df_search_chance
    bcs !ds_trap_not_found+

!ds_trap_found:
    pla
    tax

    ldy trap_y,x
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldy trap_x,x
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_TRAP
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()

    ldx #HSTR_DF_FOUND_TRAP
    jsr huff_print_msg
    lda #1
    sta df_found
    jmp !ds_next+

!ds_trap_not_found:
    pla

!ds_trap_next:
    inx
    jmp !ds_trap_scan-

!ds_next:
    inc df_dir_idx
    lda df_dir_idx
    cmp #8
    beq !ds_done+
    jmp !ds_loop-

!ds_done:
    lda df_found
    beq !ds_none+
    sec
    rts
!ds_none:
    clc
    rts

// do_search — Search adjacent tiles for secrets and traps.
// Always consumes a turn; if nothing was found, prints the standard message.
do_search:
    jsr search_scan_effective_silent
    bcs !ds_exit+
    ldx #HSTR_DF_FOUND_NOTHING
    jsr huff_print_msg
!ds_exit:
    rts
