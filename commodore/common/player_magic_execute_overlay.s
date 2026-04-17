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
pmx_find_stairs_row: .byte 0
pmx_map_row: .byte 0

#import "player_magic_ball.s"

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
    .byte <(med_s0-1),  <(med_s1-1), <(eff_phase_door-1), <(med_s3-1)
    .byte <(med_s4-1),  <(med_s5-1), <(med_s6-1), <(med_s7-1)
    .byte <(med_s8-1),  <(eff_destroy_traps_doors-1), <(eff_sleep_monster_dir-1), <(eff_cure_poison-1)
    .byte <(eff_teleport_self-1), <(med_s13-1), <(med_s14-1), <(eff_wall_to_mud-1)
    .byte <(med_s16-1), <(med_s17-1), <(med_s18-1), <(eff_polymorph_other-1)
    .byte <(eff_identify_prompt-1), <(eff_sleep_all-1), <(med_s22-1), <(eff_slow_monster_dir-1)
    .byte <(med_s24-1), <(med_s25-1), <(eff_teleport_other-1), <(med_s27-1)
    .byte <(med_s28-1), <(eff_destroy_area-1), <(eff_genocide-1)
med_tbl_hi:
    .byte >(med_s0-1),  >(med_s1-1), >(eff_phase_door-1), >(med_s3-1)
    .byte >(med_s4-1),  >(med_s5-1), >(med_s6-1), >(med_s7-1)
    .byte >(med_s8-1),  >(eff_destroy_traps_doors-1), >(eff_sleep_monster_dir-1), >(eff_cure_poison-1)
    .byte >(eff_teleport_self-1), >(med_s13-1), >(med_s14-1), >(eff_wall_to_mud-1)
    .byte >(med_s16-1), >(med_s17-1), >(med_s18-1), >(eff_polymorph_other-1)
    .byte >(eff_identify_prompt-1), >(eff_sleep_all-1), >(med_s22-1), >(eff_slow_monster_dir-1)
    .byte >(med_s24-1), >(med_s25-1), >(eff_teleport_other-1), >(med_s27-1)
    .byte >(med_s28-1), >(eff_destroy_area-1), >(eff_genocide-1)

med_s0:
    lda #2
    ldx #6
    ldy #1
    jmp eff_bolt
med_s1:
    jmp pmx_detect_monsters_msg
med_s3:
    jmp pmx_light_room_msg
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
med_s13:
    jsr eff_remove_curse
    ldx #HSTR_PIQ_CLEANSED
    jsr huff_print_msg
    rts
med_s14:
    lda #4
    ldx #8
    ldy #1
    jmp eff_bolt
med_s16:
    jsr eff_create_food
    bcs !med_s16_done+
    lda #<pmx_msg_object_under
    ldy #>pmx_msg_object_under
    jsr pmx_print_inline
!med_s16_done:
    rts
med_s17:
    lda #20
    jmp eff_recharge_item
med_s18:
    jmp pmx_sleep_adjacent_msg
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
med_s27:
    jmp eff_haste_self
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
    .byte <(ped_s0-1), <(ped_s1-1), <(ped_s2-1), <(eff_remove_fear-1)
    .byte <(ped_s4-1), <(eff_find_traps-1), <(ped_s6-1), <(ped_s7-1)
    .byte <(ped_s8-1), <(eff_teleport_self-1), <(ped_s10-1), <(ped_s11-1)
    .byte <(ped_s12-1), <(ped_s13-1), <(ped_s14-1), <(ped_s15-1)
    .byte <(eff_cure_poison-1), <(ped_s17-1), <(ped_s18-1), <(ped_s19-1)
    .byte <(ped_s20-1), <(eff_earthquake-1), <(eff_map_area-1), <(ped_s23-1)
    .byte <(eff_turn_undead-1), <(ped_s25-1), <(ped_s26-1), <(ped_s27-1)
    .byte <(ped_s28-1), <(ped_s29-1), <(ped_s30-1)
ped_tbl_hi:
    .byte >(ped_s0-1), >(ped_s1-1), >(ped_s2-1), >(eff_remove_fear-1)
    .byte >(ped_s4-1), >(eff_find_traps-1), >(ped_s6-1), >(ped_s7-1)
    .byte >(ped_s8-1), >(eff_teleport_self-1), >(ped_s10-1), >(ped_s11-1)
    .byte >(ped_s12-1), >(ped_s13-1), >(ped_s14-1), >(ped_s15-1)
    .byte >(eff_cure_poison-1), >(ped_s17-1), >(ped_s18-1), >(ped_s19-1)
    .byte >(ped_s20-1), >(eff_earthquake-1), >(eff_map_area-1), >(ped_s23-1)
    .byte >(eff_turn_undead-1), >(ped_s25-1), >(ped_s26-1), >(ped_s27-1)
    .byte >(ped_s28-1), >(ped_s29-1), >(ped_s30-1)

ped_s0:
    jmp eff_detect_evil
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
    jmp pmx_add_bless_msg
ped_s4:
    jmp pmx_light_room_msg
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
    jmp pmx_add_bless_msg
ped_s12:
    jmp pmx_sleep_adjacent_msg
ped_s13:
    jsr eff_create_food
    bcs !ped_s13_done+
    lda #<pmx_msg_object_under
    ldy #>pmx_msg_object_under
    jsr pmx_print_inline
!ped_s13_done:
    rts
ped_s14:
    jsr eff_remove_curse_all
    ldx #HSTR_PIQ_CLEANSED
    jsr huff_print_msg
    rts
ped_s15:
    jmp eff_resist_heat_cold
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
ped_s19:
    jmp eff_sense_invisible
ped_s20:
    jmp eff_protect_from_evil
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
    jmp pmx_add_bless_msg
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
    jmp pmx_heal_and_report
ped_s28:
    lda #CF_EVIL
    sta pmx_work_flag
    lda zp_player_lvl
    asl
    clc
    adc zp_player_lvl
    sta pmx_work_damage
    jmp eff_dispel_flagged
ped_s29:
    jmp eff_glyph_of_warding
ped_s30:
    jmp eff_holy_word

heal_dice:
    jsr math_dice
    lda zp_math_a
    jmp pmx_heal_and_report

pmx_light_room_msg:
    jsr eff_light_room
    ldx #HSTR_PIQ_LIGHT
    jmp huff_print_msg

#import "player_magic_detect.s"
#import "player_magic_feedback.s"
#import "player_magic_utility.s"

eff_sleep_monster_dir:
    jsr eff_directional_monster
    bcc !esmd_done+
    lda #20
    jsr monster_apply_sleep
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
    lda eff_fear_timer
    beq !erf_done+
    lda #0
    sta eff_fear_timer
    ldx #HSTR_EFF_FEAR_END
    jsr huff_print_msg
!erf_done:
    rts

eff_detect_evil:
    jmp pmx_detect_evil_msg

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
    lda #25
    jsr monster_apply_sleep
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
    jmp pmx_add_speed_msg

eff_resist_heat_cold:
    jmp pmx_set_resist_heat_cold_msg

eff_sense_invisible:
    jmp pmx_set_see_invisible_msg

eff_protect_from_evil:
    lda #25
    jsr rng_range
    clc
    adc #25
    jmp pmx_add_protect_msg

eff_create_food:
    lda zp_player_x
    ldy zp_player_y
    jsr floor_item_find_at
    bcc !ecf_free+
    clc
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
    sec
    rts

eff_recharge_item:
    sta pmx_work_damage
    ldx #0
!eri_scan:
    cpx #MAX_INV_SLOTS
    bcs !eri_none+
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
    lda #<pmx_msg_bright_flash
    ldy #>pmx_msg_bright_flash
    jsr pmx_print_inline
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
!eri_none:
    lda #<pmx_msg_no_recharge
    ldy #>pmx_msg_no_recharge
    jsr pmx_print_inline
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
    lda #1
    sta vis_room_revealed
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

pmx_msg_bright_flash:
    .text "There is a bright flash of light." ; .byte 0
pmx_msg_no_recharge:
    .text "You have nothing to recharge." ; .byte 0
