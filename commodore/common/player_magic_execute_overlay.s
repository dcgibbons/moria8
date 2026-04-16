#importonce
// player_magic_execute_overlay.s — overlay-owned spell/prayer execution
//
// Low-frequency spell effect execution lives here to keep the resident C64
// image under MAP_BASE while preserving full 31-spell dispatch.

.const PMX_ICAT_WAND  = 14
.const PMX_ICAT_STAFF = 15

pmx_work_idx:    .byte 0
pmx_work_x:      .byte 0
pmx_work_y:      .byte 0
pmx_work_x2:     .byte 0
pmx_work_y2:     .byte 0
pmx_work_flag:   .byte 0
pmx_work_damage: .byte 0
pmx_target_slot: .byte 0
pmx_ball_prev_x: .byte 0
pmx_ball_prev_y: .byte 0
pmx_find_stairs_row: .byte 0
pmx_map_row: .byte 0

spell_execute_selected:
    lda pm_spell_type
    cmp #SPELL_MAGE
    beq !ses_mage+
    lda pm_spell_idx
    jmp priest_effect_dispatch
!ses_mage:
    lda pm_spell_idx
    jmp mage_effect_dispatch

mage_effect_dispatch:
    tax
    lda med_tbl_hi,x
    pha
    lda med_tbl_lo,x
    pha
    rts

med_tbl_lo:
    .byte <(med_s0-1),  <(eff_detect_monsters-1), <(eff_phase_door-1), <(eff_light_room-1)
    .byte <(med_s4-1),  <(med_s5-1), <(med_s6-1), <(med_s7-1)
    .byte <(med_s8-1),  <(eff_destroy_traps_doors-1), <(eff_sleep_monster_dir-1), <(eff_cure_poison-1)
    .byte <(eff_teleport_self-1), <(eff_remove_curse-1), <(med_s14-1), <(eff_wall_to_mud-1)
    .byte <(eff_create_food-1), <(med_s17-1), <(eff_sleep_adjacent-1), <(eff_polymorph_other-1)
    .byte <(eff_identify_prompt-1), <(eff_sleep_all-1), <(med_s22-1), <(eff_slow_monster_dir-1)
    .byte <(med_s24-1), <(med_s25-1), <(eff_teleport_other-1), <(eff_haste_self-1)
    .byte <(med_s28-1), <(eff_destroy_area-1), <(eff_genocide-1)
med_tbl_hi:
    .byte >(med_s0-1),  >(eff_detect_monsters-1), >(eff_phase_door-1), >(eff_light_room-1)
    .byte >(med_s4-1),  >(med_s5-1), >(med_s6-1), >(med_s7-1)
    .byte >(med_s8-1),  >(eff_destroy_traps_doors-1), >(eff_sleep_monster_dir-1), >(eff_cure_poison-1)
    .byte >(eff_teleport_self-1), >(eff_remove_curse-1), >(med_s14-1), >(eff_wall_to_mud-1)
    .byte >(eff_create_food-1), >(med_s17-1), >(eff_sleep_adjacent-1), >(eff_polymorph_other-1)
    .byte >(eff_identify_prompt-1), >(eff_sleep_all-1), >(med_s22-1), >(eff_slow_monster_dir-1)
    .byte >(med_s24-1), >(med_s25-1), >(eff_teleport_other-1), >(eff_haste_self-1)
    .byte >(med_s28-1), >(eff_destroy_area-1), >(eff_genocide-1)

med_s0:
    lda #2
    ldx #6
    ldy #1
    jmp eff_bolt
med_s4:
    lda #4
    ldx #4
    ldy #0
    jmp heal_dice
med_s5:
    jsr eff_find_doors
    jmp eff_find_traps
med_s6:
    lda #9
    jmp eff_ball
med_s7:
    jsr eff_directional_monster
    bcc !med_s7_done+
    jsr monster_get_ptr
    ldy #MX_CONFUSE
    lda #10
    sta (zp_ptr0),y
!med_s7_done:
    rts
med_s8:
    lda #3
    ldx #8
    ldy #1
    jmp eff_bolt
med_s14:
    lda #4
    ldx #8
    ldy #1
    jmp eff_bolt
med_s17:
    lda #20
    jmp eff_recharge_item
med_s22:
    lda #6
    ldx #8
    ldy #1
    jmp eff_bolt
med_s24:
    lda #33
    jmp eff_ball
med_s25:
    lda #50
    jmp eff_recharge_item
med_s28:
    lda #49
    jmp eff_ball

priest_effect_dispatch:
    tax
    lda ped_tbl_hi,x
    pha
    lda ped_tbl_lo,x
    pha
    rts

ped_tbl_lo:
    .byte <(eff_detect_evil-1), <(ped_s1-1), <(ped_s2-1), <(eff_remove_fear-1)
    .byte <(eff_light_room-1), <(eff_find_traps-1), <(ped_s6-1), <(ped_s7-1)
    .byte <(ped_s8-1), <(eff_teleport_self-1), <(ped_s10-1), <(ped_s11-1)
    .byte <(eff_sleep_adjacent-1), <(eff_create_food-1), <(eff_remove_curse_all-1), <(eff_resist_heat_cold-1)
    .byte <(eff_cure_poison-1), <(ped_s17-1), <(ped_s18-1), <(eff_sense_invisible-1)
    .byte <(eff_protect_from_evil-1), <(eff_earthquake-1), <(eff_map_area-1), <(ped_s23-1)
    .byte <(eff_turn_undead-1), <(ped_s25-1), <(ped_s26-1), <(ped_s27-1)
    .byte <(ped_s28-1), <(eff_glyph_of_warding-1), <(eff_holy_word-1)
ped_tbl_hi:
    .byte >(eff_detect_evil-1), >(ped_s1-1), >(ped_s2-1), >(eff_remove_fear-1)
    .byte >(eff_light_room-1), >(eff_find_traps-1), >(ped_s6-1), >(ped_s7-1)
    .byte >(ped_s8-1), >(eff_teleport_self-1), >(ped_s10-1), >(ped_s11-1)
    .byte >(eff_sleep_adjacent-1), >(eff_create_food-1), >(eff_remove_curse_all-1), >(eff_resist_heat_cold-1)
    .byte >(eff_cure_poison-1), >(ped_s17-1), >(ped_s18-1), >(eff_sense_invisible-1)
    .byte >(eff_protect_from_evil-1), >(eff_earthquake-1), >(eff_map_area-1), >(ped_s23-1)
    .byte >(eff_turn_undead-1), >(ped_s25-1), >(ped_s26-1), >(ped_s27-1)
    .byte >(ped_s28-1), >(eff_glyph_of_warding-1), >(eff_holy_word-1)

ped_s1:
    lda #3
    ldx #3
    ldy #0
    jmp heal_dice
ped_s2:
    lda #12
    jsr rng_range
    clc
    adc #12
    clc
    adc zp_eff_bless
    bcc !ped_s2_store+
    lda #255
!ped_s2_store:
    sta zp_eff_bless
    rts
ped_s6:
    jsr eff_find_doors
    jmp eff_find_stairs
ped_s7:
    lda zp_eff_poison
    beq !ped_s7_done+
    lsr
    ora #1
    sta zp_eff_poison
!ped_s7_done:
    rts
ped_s8:
    jsr eff_directional_monster
    bcc !ped_s8_done+
    jsr monster_get_ptr
    ldy #MX_STUN
    lda #10
    sta (zp_ptr0),y
!ped_s8_done:
    rts
ped_s10:
    lda #4
    ldx #4
    ldy #0
    jmp heal_dice
ped_s11:
    lda #24
    jsr rng_range
    clc
    adc #24
    clc
    adc zp_eff_bless
    bcc !ped_s11_store+
    lda #255
!ped_s11_store:
    sta zp_eff_bless
    rts
ped_s17:
    lda #3
    ldx #6
    ldy zp_player_lvl
    jsr math_dice
    lda zp_math_a
    jmp eff_ball
ped_s18:
    lda #8
    ldx #4
    ldy #0
    jmp heal_dice
ped_s23:
    lda #16
    ldx #4
    ldy #0
    jmp heal_dice
ped_s25:
    lda #48
    jsr rng_range
    clc
    adc #48
    clc
    adc zp_eff_bless
    bcc !ped_s25_store+
    lda #255
!ped_s25_store:
    sta zp_eff_bless
    rts
ped_s26:
    lda #CF_UNDEAD
    sta pmx_work_flag
    lda zp_player_lvl
    asl
    clc
    adc zp_player_lvl
    sta pmx_work_damage
    jmp eff_dispel_flagged
ped_s27:
    lda #200
    jmp eff_heal
ped_s28:
    lda #CF_EVIL
    sta pmx_work_flag
    lda zp_player_lvl
    asl
    clc
    adc zp_player_lvl
    sta pmx_work_damage
    jmp eff_dispel_flagged

heal_dice:
    jsr math_dice
    lda zp_math_a
    jmp eff_heal

eff_sleep_monster_dir:
    jsr eff_directional_monster
    bcc !esmd_done+
    jsr monster_get_ptr
    ldy #MX_SLEEP_CUR
    lda #20
    sta (zp_ptr0),y
!esmd_done:
    rts

eff_slow_monster_dir:
    jsr eff_directional_monster
    bcc !eslow_done+
    jsr monster_get_ptr
    ldy #MX_SPEED_CNT
    lda #$ff
    sta (zp_ptr0),y
    ldy #MX_SLEEP_CUR
    lda #0
    sta (zp_ptr0),y
!eslow_done:
    rts

eff_remove_fear:
    lda #0
    sta eff_fear_timer
    rts

eff_detect_evil:
    jmp eff_detect_monsters

eff_remove_curse_all:
    ldx #0
!erca_loop:
    cpx #TOTAL_INV_SLOTS
    bcs !erca_done+
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !erca_next+
    lda inv_flags,x
    and #~IF_CURSED & $ff
    sta inv_flags,x
!erca_next:
    inx
    jmp !erca_loop-
!erca_done:
    rts

eff_find_stairs:
    lda #1
    sta pmx_find_stairs_row
!efs_row:
    lda pmx_find_stairs_row
    cmp #MAP_ROWS - 1
    bcs !efs_done+
    tax
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #1
!efs_col:
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_STAIRS_DN
    beq !efs_mark+
    cmp #TILE_STAIRS_UP
    bne !efs_next+
!efs_mark:
    :MapRead_ptr0_y()
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()
!efs_next:
    iny
    cpy #MAP_COLS - 1
    bcc !efs_col-
    inc pmx_find_stairs_row
    jmp !efs_row-
!efs_done:
    lda #1
    sta vis_room_revealed
    rts

eff_sleep_all:
    lda #0
    sta pmx_work_idx
!esa_all_loop:
    ldx pmx_work_idx
    cpx #MAX_MONSTERS
    bcs !esa_all_done+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !esa_all_next+
    ldy #MX_X
    lda (zp_ptr0),y
    sta pmx_work_x
    ldy #MX_Y
    lda (zp_ptr0),y
    sta pmx_work_y
    ldx pmx_work_x
    ldy pmx_work_y
    jsr los_is_visible
    bcc !esa_all_next+
    ldx pmx_work_idx
    jsr monster_get_ptr
    ldy #MX_SLEEP_CUR
    lda #25
    sta (zp_ptr0),y
!esa_all_next:
    inc pmx_work_idx
    jmp !esa_all_loop-
!esa_all_done:
    rts

eff_haste_self:
    lda #20
    jsr rng_range
    clc
    adc zp_player_lvl
    clc
    adc zp_eff_speed
    bcc !ehs_store+
    lda #$7f
!ehs_store:
    sta zp_eff_speed
    rts

eff_resist_heat_cold:
    lda #$03
    sta zp_eff_resist
    rts

eff_sense_invisible:
    lda #1
    sta zp_eff_see_inv
    lda #1
    sta zp_eff_invis
    rts

eff_protect_from_evil:
    lda #25
    jsr rng_range
    clc
    adc #25
    clc
    adc zp_eff_protect
    bcc !epfe_store+
    lda #255
!epfe_store:
    sta zp_eff_protect
    rts

eff_map_area:
    lda #1
    sta pmx_map_row
!emap_row:
    lda pmx_map_row
    cmp #MAP_ROWS - 1
    bcs !emap_done+
    tax
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #1
!emap_col:
    :MapRead_ptr0_y()
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()
    iny
    cpy #MAP_COLS - 1
    bcc !emap_col-
    inc pmx_map_row
    jmp !emap_row-
!emap_done:
    lda #1
    sta vis_room_revealed
    rts

eff_ball:
    sta pmx_work_damage
    jsr get_direction_target
    bcs !eball_have_dir+
    rts
!eball_have_dir:
    jsr calc_direction_index
    bcs !eball_trace_init+
    rts
!eball_trace_init:
    lda zp_player_x
    sta proj_cx
    sta pmx_ball_prev_x
    lda zp_player_y
    sta proj_cy
    sta pmx_ball_prev_y
    lda #20
    sta proj_steps
!eball_trace:
    dec proj_steps
    beq !eball_explode_prev+
    lda proj_cx
    sta pmx_ball_prev_x
    lda proj_cy
    sta pmx_ball_prev_y
    jsr trace_step
    bcc !eball_explode_prev+
    lda proj_cx
    ldy proj_cy
    jsr monster_find_at
    bcs !eball_target_here+
    jmp !eball_trace-
!eball_target_here:
    lda proj_cx
    sta pmx_work_x
    lda proj_cy
    sta pmx_work_y
    jmp !eball_apply+
!eball_explode_prev:
    lda pmx_ball_prev_x
    sta pmx_work_x
    lda pmx_ball_prev_y
    sta pmx_work_y
!eball_apply:
    lda #0
    sta pmx_work_idx
!eball_loop:
    ldx pmx_work_idx
    cpx #MAX_MONSTERS
    bcs !eball_done+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !eball_next+
    ldy #MX_X
    lda (zp_ptr0),y
    sta pmx_work_x2
    sec
    sbc pmx_work_x
    bcs !eball_dx_pos+
    eor #$ff
    clc
    adc #1
!eball_dx_pos:
    cmp #2
    bcs !eball_next+
    ldy #MX_Y
    lda (zp_ptr0),y
    sta pmx_work_y2
    sec
    sbc pmx_work_y
    bcs !eball_dy_pos+
    eor #$ff
    clc
    adc #1
!eball_dy_pos:
    cmp #2
    bcs !eball_next+
    ldx pmx_work_idx
    lda pmx_work_damage
    sta zp_math_a
    lda #0
    sta zp_math_b
    jsr combat_apply_damage_16
    bcc !eball_next+
    jsr eff_kill_monster
!eball_next:
    inc pmx_work_idx
    jmp !eball_loop-
!eball_done:
    rts

eff_create_food:
    lda zp_player_x
    ldy zp_player_y
    jsr floor_item_find_at
    bcc !ecf_free+
    rts
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
    lda #1
    sta vis_room_revealed
    rts

eff_recharge_item:
    sta pmx_work_damage
    ldx #0
!eri_scan:
    cpx #MAX_INV_SLOTS
    bcs !eri_done+
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !eri_next+
    tay
    lda it_category,y
    cmp #PMX_ICAT_WAND
    beq !eri_found+
    cmp #PMX_ICAT_STAFF
    beq !eri_found+
!eri_next:
    inx
    jmp !eri_scan-
!eri_found:
    stx pmx_target_slot
    lda inv_p1,x
    sta pmx_work_flag
    lda pmx_work_damage
    lsr
    lsr
    lsr
    clc
    adc #2
    sta zp_temp0
    lda pmx_work_flag
    cmp zp_temp0
    bcc !eri_recharge+
    lda #4
    jsr rng_range
    bne !eri_recharge+
    ldx pmx_target_slot
    jsr inv_remove_item
    jmp !eri_done+
!eri_recharge:
    lda pmx_work_damage
    lsr
    lsr
    lsr
    clc
    adc #1
    jsr rng_range
    clc
    adc #2
    ldx pmx_target_slot
    clc
    adc inv_p1,x
    sta inv_p1,x
!eri_done:
    rts

eff_polymorph_other:
    jsr eff_directional_monster
    bcc !epo_done+
    stx pmx_work_idx
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    sta ms_spawn_x
    ldy #MX_Y
    lda (zp_ptr0),y
    sta ms_spawn_y
    ldx pmx_work_idx
    jsr monster_remove
    jsr pick_creature_type
    jsr monster_spawn_one
!epo_done:
    rts

eff_teleport_other:
    jsr eff_directional_monster
    bcc !eto_done+
    stx pmx_work_idx
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    sta pmx_work_x
    ldy #MX_Y
    lda (zp_ptr0),y
    sta pmx_work_y
    jsr find_random_floor
    bcc !eto_done+
    ldx pmx_work_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy pmx_work_x
    :MapRead_ptr0_y()
    and #~FLAG_OCCUPIED & $ff
    :MapWrite_ptr0_y()
    ldx pmx_work_idx
    jsr monster_get_ptr
    ldy #MX_X
    lda df_target_x
    sta (zp_ptr0),y
    ldy #MX_Y
    lda df_target_y
    sta (zp_ptr0),y
    ldy #MX_SLEEP_CUR
    lda #0
    sta (zp_ptr0),y
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    :MapRead_ptr0_y()
    ora #FLAG_OCCUPIED
    :MapWrite_ptr0_y()
    lda #1
    sta vis_room_revealed
!eto_done:
    rts

eff_dispel_flagged:
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
    lda pmx_work_damage
    beq !edf_next+
    jsr rng_range
    clc
    adc #1
    sta zp_math_a
    lda #0
    sta zp_math_b
    ldx pmx_work_idx
    jsr combat_apply_damage_16
    bcc !edf_next+
    jsr eff_kill_monster
!edf_next:
    inc pmx_work_idx
    jmp !edf_loop-
!edf_done:
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

eff_earthquake:
    lda #4
    ldx #8
    jmp eff_damage_adjacent

eff_destroy_area:
    lda #15
    ldx #8
    jsr eff_damage_adjacent
    jsr eff_destroy_traps_doors
    rts

eff_genocide:
    jsr eff_directional_monster
    bcc !egeno_done+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    tax
    lda cr_display,x
    sta pmx_work_flag
    ldx #0
!egeno_loop:
    cpx #MAX_MONSTERS
    bcs !egeno_done+
    stx pmx_work_idx
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !egeno_next+
    tax
    lda cr_display,x
    cmp pmx_work_flag
    bne !egeno_next+
    ldx pmx_work_idx
    jsr monster_remove
!egeno_next:
    ldx pmx_work_idx
    inx
    jmp !egeno_loop-
!egeno_done:
    lda #1
    sta vis_room_revealed
    rts

eff_holy_word:
    jsr eff_remove_fear
    jsr eff_cure_poison
    lda #0
    sta zp_eff_blind
    sta zp_eff_confuse
    lda zp_player_mhp_lo
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda zp_player_mhp_hi
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda #CF_EVIL
    sta pmx_work_flag
    lda zp_player_lvl
    asl
    asl
    sta pmx_work_damage
    jsr eff_dispel_flagged
    rts

eff_glyph_of_warding:
    lda zp_player_x
    ldy zp_player_y
    jsr floor_item_find_at
    bcs !egow_done+
    lda zp_player_x
    ldy zp_player_y
    jsr glyph_add_at
    bcc !egow_done+
    lda #1
    sta vis_room_revealed
!egow_done:
    rts
