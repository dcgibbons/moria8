#importonce
// player_magic_utility.s — shared higher-end spell/prayer utility helpers
//
// Split out from the main execute overlay so focused runtime suites can cover
// map/dispel/glyph/heal utility behavior without importing the full dispatcher.

#if !PMX_MAP_AREA_EXTERNAL
    #import "player_magic_map.s"
#endif
#import "player_heal_feedback.s"

pmu_dispel_targets: .byte 0
pmu_dispel_type: .byte 0

eff_reveal_floorplan:
    ldx #0
!erf_row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #0
!erf_col:
    :MapRead_ptr0_y()
    sta zp_temp0
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    beq !erf_visit+
    cmp #TILE_DOOR_OPEN
    bcs !erf_visit+
    lda zp_temp0
    and #FLAG_LIT
    beq !erf_next+
!erf_visit:
    lda zp_temp0
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()
!erf_next:
    iny
    cpy #MAP_COLS
    bcc !erf_col-
    inx
    cpx #MAP_ROWS
    bcc !erf_row-
!erf_done:
    lda #1
    sta vis_room_revealed
    jmp eff_find_doors

pmu_create_food:
    lda zp_player_x
    ldy zp_player_y
    jsr floor_item_find_at
    bcc !ecf_free+
    jsr floor_item_remove
!ecf_free:
    lda zp_player_x
    sta fi_add_x
    lda zp_player_y
    sta fi_add_y
    lda #15
    sta fi_add_id
    jsr fi_add_clear_plain_meta
    lda #1
    sta fi_add_qty
    jsr floor_item_add
    bcc !ecf_fail+
    lda #1
    sta vis_room_revealed
    ldx #HSTR_PMU_CREATE_FOOD
    jsr huff_print_msg
    sec
    rts
!ecf_fail:
    clc
    rts

eff_dispel_flagged:
    lda #0
    sta pmu_dispel_targets
    lda #0
    sta pmx_work_idx
!edf_loop:
    ldx pmx_work_idx
    cpx #MAX_MONSTERS
    bcs !edf_done+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !edf_next+
    tax
    lda cr_mflags,x
    and pmx_work_flag
    beq !edf_next+
    ldy #MX_X
    lda (zp_ptr0),y
    tax
    ldy #MX_Y
    lda (zp_ptr0),y
    tay
    jsr los_is_visible
    bcc !edf_next+
    ldx pmx_work_idx
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    sta pmu_dispel_type
    sta cmb_type
    lda pmx_work_damage
    beq !edf_next+
    inc pmu_dispel_targets
    jsr rng_range
    clc
    adc #1
    sta zp_math_a
    lda #0
    sta zp_math_b
    ldx pmx_work_idx
    jsr combat_apply_damage_16
    bcs !edf_kill+
    lda pmu_dispel_type
    sta cmb_type
    jsr combat_msg_monster_shudders
    jmp !edf_next+
!edf_kill:
    jsr eff_kill_monster
    jsr combat_msg_monster_dissolves
!edf_next:
    inc pmx_work_idx
    jmp !edf_loop-
!edf_done:
    lda pmu_dispel_targets
    rts

eff_turn_undead:
    lda #0
    sta pmx_work_idx
!etud_loop:
    ldx pmx_work_idx
    cpx #MAX_MONSTERS
    bcs !etud_done+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !etud_next+
    tax
    lda cr_mflags,x
    and #CF_UNDEAD
    beq !etud_next+
    ldx pmx_work_idx
    jsr monster_get_ptr
    ldy #MX_CONFUSE
    lda zp_player_lvl
    sta (zp_ptr0),y
    ldy #MX_SLEEP_CUR
    lda #0
    sta (zp_ptr0),y
!etud_next:
    inc pmx_work_idx
    jmp !etud_loop-
!etud_done:
    rts

eff_destroy_area:
    lda #15
    ldx #8
    jsr eff_damage_adjacent
    jsr eff_destroy_traps_doors
    rts

eff_holy_word:
    jsr eff_remove_fear
    jsr eff_cure_poison
    lda zp_player_mhp_lo
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda zp_player_mhp_hi
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    ldx #HSTR_PIQ_VERY_GOOD
    jsr huff_print_msg
    jsr player_calc_stats
    jsr player_sync_to_zp
    lda #3
    sta eff_invuln_timer
    lda #CF_EVIL
    sta pmx_work_flag
    lda zp_player_lvl
    asl
    asl
    sta pmx_work_damage
    jmp eff_dispel_flagged

eff_glyph_of_warding:
    lda zp_player_x
    ldy zp_player_y
    jsr floor_item_find_at
    bcc !egow_free+
    ldx #HSTR_PMU_GLYPH_BLOCK
    jsr huff_print_msg
    rts
!egow_free:
    lda zp_player_x
    ldy zp_player_y
    jsr glyph_add_at
    bcc !egow_done+
    lda #1
    sta vis_room_revealed
    ldx #HSTR_PMU_GLYPH_OK
    jmp huff_print_msg
!egow_done:
    rts
