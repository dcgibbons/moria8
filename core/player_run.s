#importonce
// player_run.s - UMoria CJS running algorithm with default options:
// cut known corners, examine potential corners, stop at open doors.

.const RUNF_OPEN        = %00000001
.const RUNF_BREAK_RIGHT = %00000010
.const RUNF_BREAK_LEFT  = %00000100

// Persistent state. zp_run_dir is UMoria's find_direction.
run_flags:    .byte 0
run_prev_dir: .byte 0
run_count:    .byte 0

// UMoria cycle[] and chome[], translated to Moria8 direction indices.
// Only the range reachable from run_home +/- 2 is retained.
run_cycle:
    .byte 7,3,5,0,4,2,6,1,7,3,5,0
run_home:
    .byte 3,7,5,9,4,2,6,8

// Scratch ownership while these routines execute:
// zp_temp0 scan/home index, zp_temp1 scan end/init bits,
// zp_temp2 dir_a, zp_temp3 dir_b, zp_temp4 check_dir.
// df_target_x/y are the tile-query base; df_dir_idx is the queried direction;
// df_found holds the current tile; disarm scratch holds initialization data.

// Set tile-query base to the player's current location.
run_base_player:
    lda zp_player_x
    sta df_target_x
    lda zp_player_y
    sta df_target_y
    rts

// Set tile-query base to the prospective first run step.
run_base_target:
    lda df_disarm_total
    sta df_target_x
    lda df_disarm_base
    sta df_target_y
    rts

// Record one initialization side. A is its short-wall bit, Y its break flag,
// and X the side direction. A deep wall records the next higher bit.
run_init_side:
    stx df_dir_idx
    sta df_disarm_chance
    sty df_disarm_trap_idx
    jsr run_base_player
    ldx df_dir_idx
    jsr run_wall
    bcs !ris_found+
    jsr run_base_target
    ldx df_dir_idx
    jsr run_wall
    bcc !ris_done+
    asl df_disarm_chance
!ris_found:
    lda df_disarm_chance
    ora zp_temp1
    sta zp_temp1
    lda run_flags
    ora df_disarm_trap_idx
    sta run_flags
!ris_done:
    rts

// Read the square in direction X from df_target_x/y.
// pm_live_occ_x/y retain its coordinates for monster checks.
run_get_tile:
    lda df_target_x
    clc
    adc dir_dx,x
    sta pm_live_occ_x
    cmp #MAP_COLS
    bcs !rgt_boundary+
    lda df_target_y
    clc
    adc dir_dy,x
    sta pm_live_occ_y
    cmp #MAP_ROWS
    bcs !rgt_boundary+
    tay
    ldx pm_live_occ_x
    jmp map_get_tile
!rgt_boundary:
    lda #TILE_WALL_H | FLAG_VISITED
    rts

// Carry set when the queried square has a terrain glyph the player can use
// for running. Remembered terrain remains displayed; otherwise use current
// light/room visibility for a newly-adjacent square not marked visited yet.
run_tile_displayed:
    lda df_found
    and #FLAG_VISITED
    bne !rtd_yes+
    ldx pm_live_occ_x
    ldy pm_live_occ_y
    jmp los_is_visible
!rtd_yes:
    sec
    rts

// Return A nonzero when live monster slot X is currently visible. Running
// evaluates the new leading edge before the normal post-move visibility pass.
run_monster_visible:
    txa
    tay
    ldx #4
!rmv_save:
    lda zp_temp0,x
    pha
    dex
    bpl !rmv_save-
    tya
    tax
#if RUN_MONSTER_VISIBILITY_EXTERNAL
    jsr run_monster_update_visibility_one
#else
    jsr monster_update_visibility_one
#endif
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_VISIBLE
    tay
    ldx #0
!rmv_restore:
    pla
    sta zp_temp0,x
    inx
    cpx #5
    bne !rmv_restore-
    tya
    rts

// Classify displayed terrain: A=0/carry set wall, A=1 open, A=$ff object.
run_terrain_class:
    lda df_found
    and #TILE_TYPE_MASK
    beq !rtc_open+
    cmp #TILE_DOOR_OPEN
    bcc !rtc_wall+
    cmp #TILE_MAGMA
    bcc !rtc_object+
    cmp #TILE_TRAP
    beq !rtc_object+
!rtc_wall:
    lda #0
    sec
    rts
!rtc_open:
    lda #1
    clc
    rts
!rtc_object:
    lda #$ff
    clc
    rts

// Carry set if the square in direction X is displayed as a wall ('#'/'%').
run_wall:
    jsr run_get_tile
    sta df_found
    jsr run_tile_displayed
    bcs run_terrain_class
    clc
    rts

// Carry set if the square in direction X displays as blank.
run_nothing:
    jsr run_get_tile
    sta df_found
    jsr run_tile_displayed
    bcs !rn_no+
    lda df_found
    and #FLAG_OCCUPIED
    beq !rn_yes+
    lda pm_live_occ_x
    ldy pm_live_occ_y
    jsr player_move_check_live_occupant
    bcc !rn_yes+
    jsr run_monster_visible
    bne !rn_no+
!rn_yes:
    sec
    rts
!rn_no:
    clc
    rts

// Classify the square in direction X. Carry set means an interesting visible
// object/monster. Otherwise A=1 means open and A=0 means closed.
run_classify:
    jsr run_get_tile
    sta df_found
    jsr run_tile_displayed
    bcc !rc_open+
    lda zp_player_dlvl
    bne !rc_not_store+
    lda pm_live_occ_x
    ldy pm_live_occ_y
    jsr check_store_door_at
    bcs !rc_stop+
!rc_not_store:
    lda df_found
    and #FLAG_HAS_ITEM
    bne !rc_stop+
    lda df_found
    and #FLAG_OCCUPIED
    beq !rc_feature+
    lda pm_live_occ_x
    ldy pm_live_occ_y
    jsr player_move_check_live_occupant
    bcc !rc_feature+
    jsr run_monster_visible
    bne !rc_stop+
!rc_feature:
    jsr run_terrain_class
    bmi !rc_stop+
    clc
    rts
!rc_open:
    jmp !rtc_open-
!rc_stop:
    sec
    rts

// Initialize UMoria's side-wall state before the first run step.
#if PLAYER_RUN_INITIALIZE_EXTERNAL
    :PlayerRunInitializeSegment()
run_initialize_impl:
#else
run_initialize:
#endif
    lda #1
    sta run_count
    lda #0
    sta run_flags
    sta zp_temp1               // short/deep side bits
    lda zp_run_dir
    sta run_prev_dir
    tax
    lda run_home,x
    sta zp_temp0

    lda zp_eff_blind
    beq !ri_target+
    lda #RUNF_OPEN             // Deterministic blind initialization.
    sta run_flags
    sec
    rts

!ri_target:
    ldx zp_run_dir
    lda zp_player_x
    clc
    adc dir_dx,x
    sta df_disarm_total
    lda zp_player_y
    clc
    adc dir_dy,x
    sta df_disarm_base

    // Left: beside player, then beside target.
    ldy zp_temp0
    iny
    ldx run_cycle,y
    lda #1
    ldy #RUNF_BREAK_LEFT
    jsr run_init_side

!ri_right:
    ldy zp_temp0
    dey
    ldx run_cycle,y
    lda #4
    ldy #RUNF_BREAK_RIGHT
    jsr run_init_side

!ri_finish:
    lda run_flags
    and #(RUNF_BREAK_LEFT | RUNF_BREAK_RIGHT)
    cmp #(RUNF_BREAK_LEFT | RUNF_BREAK_RIGHT)
    beq !ri_enclosed+
    inc run_flags              // OPEN is bit zero and is currently clear.
    sec
    rts

!ri_enclosed:
    lda zp_run_dir
    cmp #4
    bcc !ri_straight+
    lda zp_temp1
    and #10
    cmp #2                    // deep left only
    beq !ri_prev_right+
    cmp #8                    // deep right only
    beq !ri_prev_left+
    sec
    rts

!ri_straight:
    jsr run_base_target
    ldx zp_run_dir
    jsr run_wall              // Wall two squares ahead?
    bcc !ri_done+
    lda zp_temp1
    and #5
    cmp #1                    // short left only
    beq !ri_prev_far_right+
    cmp #4                    // short right only
    beq !ri_prev_far_left+
!ri_done:
    sec
    rts

!ri_prev_far_right:
    ldy zp_temp0
    dey
    dey
    bne !ri_store_prev+
!ri_prev_far_left:
    ldy zp_temp0
    iny
    iny
    bne !ri_store_prev+
!ri_prev_right:
    ldy zp_temp0
    dey
    bne !ri_store_prev+
!ri_prev_left:
    ldy zp_temp0
    iny
!ri_store_prev:
    lda run_cycle,y
    sta run_prev_dir
    sec
    rts

#if PLAYER_RUN_INITIALIZE_EXTERNAL
    :PlayerRunRestoreResidentSegment()
#endif

// Carry set after the internal 102-step safety cap.
run_continue:
    inc run_count
    lda run_count
    cmp #102
    rts

// Evaluate newly adjacent squares after a successful run step.
// Carry set means stop; carry clear means continue.
run_area_affect:
    lda zp_eff_blind
    beq !ra_setup+
    clc
    rts
!ra_setup:
    ldx run_prev_dir
    lda run_home,x
    sta df_disarm_total        // home index
    sta zp_temp0               // scan index
    sta zp_temp1               // scan end
    cpx #4
    bcc !ra_cardinal+
    dec zp_temp0
    inc zp_temp1
!ra_cardinal:
    dec zp_temp0
    inc zp_temp1
    lda #$ff
    sta zp_temp2               // dir_a
    sta zp_temp3               // dir_b
    jsr run_base_player

!ra_scan:
    ldy zp_temp0
    lda run_cycle,y
    sta df_dir_idx
    tax
    jsr run_classify
    bcs !ra_scan_stop+
!ra_classified:
    tax                         // X=0 closed, X=1 open
    lda run_flags
    and #RUNF_OPEN
    beq !ra_corridor+

    lda zp_temp0
    cmp df_disarm_total
    beq !ra_next+
    bcc !ra_right_side+
    lda #RUNF_BREAK_LEFT
    bne !ra_side_mask+
!ra_right_side:
    lda #RUNF_BREAK_RIGHT
!ra_side_mask:
    sta zp_temp4
    cpx #0
    beq !ra_side_closed+
    and run_flags
    bne !ra_scan_stop+
    beq !ra_next+
!ra_side_closed:
    eor #(RUNF_BREAK_LEFT | RUNF_BREAK_RIGHT)
    and run_flags
    bne !ra_scan_stop+
    lda run_flags
    ora zp_temp4
    sta run_flags
    bne !ra_next+

!ra_corridor:
    cpx #0
    beq !ra_next+
    lda zp_temp2
    bpl !ra_second+
    lda df_dir_idx
    sta zp_temp2
    jmp !ra_next+
!ra_second:
    lda zp_temp3
    bpl !ra_scan_stop+
    ldy zp_temp0
    dey
    lda run_cycle,y
    cmp zp_temp2
    bne !ra_scan_stop+
    lda df_dir_idx
    cmp #4
    bcc !ra_new_straight+
    sta zp_temp3
    dey
    lda run_cycle,y
    sta zp_temp4
    jmp !ra_next+
!ra_new_straight:
    lda zp_temp2
    sta zp_temp3
    lda df_dir_idx
    sta zp_temp2
    ldy zp_temp0
    iny
    lda run_cycle,y
    sta zp_temp4
    jmp !ra_next+

!ra_scan_stop:
    jmp !ra_stop+

!ra_next:
    inc zp_temp0
    lda zp_temp1
    cmp zp_temp0
    bcc !ra_scan_done+
    jmp !ra_scan-
!ra_scan_done:

    lda run_flags
    and #RUNF_OPEN
    bne !ra_continue+
    lda zp_temp3
    bpl !ra_corner+
    lda zp_temp2
    bmi !ra_continue+
    sta zp_run_dir
    sta run_prev_dir
    clc
    rts

!ra_corner:
    jsr run_base_player
    ldx zp_temp2
    lda df_target_x
    clc
    adc dir_dx,x
    sta df_target_x
    lda df_target_y
    clc
    adc dir_dy,x
    sta df_target_y
    jsr run_wall
    bcc !ra_potential+
    ldx zp_temp4
    jsr run_wall
    bcc !ra_potential+
    lda zp_temp3              // Known corner: cut diagonally.
    sta zp_run_dir
    sta run_prev_dir
    bne !ra_continue+

!ra_potential:
    ldx zp_temp2
    jsr run_nothing
    bcc !ra_stop+
    ldx zp_temp3
    jsr run_nothing
    bcc !ra_stop+
    lda zp_temp2
    sta zp_run_dir
    lda zp_temp3
    sta run_prev_dir
!ra_continue:
    clc
    rts
!ra_stop:
    sec
    rts

player_run_end:
