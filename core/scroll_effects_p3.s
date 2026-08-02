#importonce
// scroll_effects_p3.s — Phase 3 scroll dispatch and effect handlers.
// Imported by each platform into the overlay that owns the spell-side
// handlers it calls (C64/Plus4: spell; Apple: spell + modal; C128: death +
// modal). SCROLL_P3_EXISTING_OWNER marks the overlay with the established
// eff_* handlers; SCROLL_P3_NEW_OWNER marks the overlay hosting the four new
// effects.

#if SCROLL_P3_EXISTING_OWNER || SCROLL_P3_NEW_OWNER
irs_dispatch_p3_overlay:
    sec
    sbc #ITEM_TYPE_SCR_TELEPORT_LEVEL
    tax
    lda irs_p3_table_lo,x
    sta zp_ptr1
    lda irs_p3_table_hi,x
    sta zp_ptr1_hi
    jmp (zp_ptr1)

irs_p3_table_lo:
#if SCROLL_P3_NEW_OWNER
    .byte <irs_p3_teleport_level, <irs_p3_magic_mapping, <irs_p3_object_detect
#else
    .byte <irs_p3_nop, <irs_p3_nop, <irs_p3_nop
#endif
#if SCROLL_P3_EXISTING_OWNER
    .byte <irs_p3_recharging, <irs_p3_rune, <irs_p3_genocide
#else
    .byte <irs_p3_nop, <irs_p3_nop, <irs_p3_nop
#endif
#if SCROLL_P3_NEW_OWNER
    .byte <irs_p3_mass_genocide
#else
    .byte <irs_p3_nop
#endif
#if SCROLL_P3_EXISTING_OWNER
    .byte <irs_p3_destruction
#else
    .byte <irs_p3_nop
#endif
irs_p3_table_hi:
#if SCROLL_P3_NEW_OWNER
    .byte >irs_p3_teleport_level, >irs_p3_magic_mapping, >irs_p3_object_detect
#else
    .byte >irs_p3_nop, >irs_p3_nop, >irs_p3_nop
#endif
#if SCROLL_P3_EXISTING_OWNER
    .byte >irs_p3_recharging, >irs_p3_rune, >irs_p3_genocide
#else
    .byte >irs_p3_nop, >irs_p3_nop, >irs_p3_nop
#endif
#if SCROLL_P3_NEW_OWNER
    .byte >irs_p3_mass_genocide
#else
    .byte >irs_p3_nop
#endif
#if SCROLL_P3_EXISTING_OWNER
    .byte >irs_p3_destruction
#else
    .byte >irs_p3_nop
#endif
irs_p3_nop:
    rts
#endif

#if SCROLL_P3_EXISTING_OWNER
irs_p3_destruction:
    lda #ITEM_TYPE_SCR_DESTRUCTION
    jmp irs_p3_run_existing

irs_p3_recharging:
    lda #ITEM_TYPE_SCR_RECHARGING
    jmp irs_p3_run_existing

irs_p3_rune:
    lda #ITEM_TYPE_SCR_RUNE_PROTECTION
    jmp irs_p3_run_existing

irs_p3_genocide:
    lda #ITEM_TYPE_SCR_GENOCIDE

// irs_p3_run_existing — Run an established spell-overlay/death-overlay
// handler for a Phase 3 scroll. On C128 those handlers live in OVL_DEATH and
// the router left OVL_MODAL_MISC loaded, so swap out and back. Elsewhere the
// handlers are in the spell overlay, which the router already loaded.
irs_p3_run_existing:
#if C128
    pha
    lda #OVL_DEATH
    jsr overlay_load
    bcs !irs_re_fail+
    pla
#endif
    cmp #ITEM_TYPE_SCR_RECHARGING
    beq !irs_re_recharge+
    cmp #ITEM_TYPE_SCR_RUNE_PROTECTION
    beq !irs_re_rune+
    cmp #ITEM_TYPE_SCR_GENOCIDE
    beq !irs_re_genocide+
    jsr eff_destroy_area
    jmp !irs_re_done+
!irs_re_recharge:
    // Upstream Recharging scroll: Recharge II strength (A=50)
    lda #50
    jsr eff_recharge_item
    jmp !irs_re_done+
!irs_re_rune:
    jsr eff_glyph_of_warding
    jmp !irs_re_done+
!irs_re_genocide:
    jsr eff_genocide
!irs_re_done:
#if C128
    pha
    lda #OVL_MODAL_MISC
    jsr overlay_load
    pla
    rts
!irs_re_fail:
    pla
#endif
    rts
#endif

#if SCROLL_P3_NEW_OWNER
// Teleport Level: dlvl += ±1 (upstream: -3 + 2*rng(2)), clamp >= 1, then
// the stairs level-change machinery (which ends the turn in main_loop).
irs_p3_teleport_level:
    lda #2
    jsr rng_range               // [0, 1]
    beq !irs_tl_up+
    inc zp_player_dlvl
    lda zp_player_dlvl
    cmp player_data + PL_MAX_DLVL
    bcc !irs_tl_not_deeper+
    sta player_data + PL_MAX_DLVL
!irs_tl_not_deeper:
    lda #0
    sta level_entry_dir         // 0 = descended
    jmp !irs_tl_go+
!irs_tl_up:
    dec zp_player_dlvl
    bne !irs_tl_up_ok+
    lda #1
    sta zp_player_dlvl
!irs_tl_up_ok:
    lda #1
    sta level_entry_dir         // 1 = ascended
!irs_tl_go:
    lda zp_player_dlvl
    sta player_data + PL_DLEVEL
    jmp level_change_generate_current

// Magic Mapping: reveal the whole level map (wizard reveal effect).
irs_p3_magic_mapping:
    jsr eff_reveal_floorplan
    lda #<irs_p3_map_msg
    ldy #>irs_p3_map_msg
    jmp pmx_print_inline

// Object Detection: reveal every floor item's tile.
irs_p3_object_detect:
    ldx #0
!irs_od_loop:
    lda fi_item_id,x
    cmp #FI_EMPTY
    beq !irs_od_next+
    stx irs_od_slot
    lda fi_y,x
    tay
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    lda fi_x,x
    tay
    :MapRead_ptr0_y()
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()
    ldx irs_od_slot
!irs_od_next:
    inx
    cpx #MAX_FLOOR_ITEMS
    bcc !irs_od_loop-
    lda #1
    sta vis_room_revealed
    lda #<irs_p3_od_msg
    ldy #>irs_p3_od_msg
    jmp pmx_print_inline

// Mass Genocide: remove every monster with clear LOS to the player.
irs_p3_mass_genocide:
    ldx #0
!irs_mg_loop:
    cpx #MAX_MONSTERS
    bcs !irs_mg_done+
    stx irs_mg_idx
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !irs_mg_next+
    ldy #MX_X
    lda (zp_ptr0),y
    sta zp_los_dx
    ldy #MX_Y
    lda (zp_ptr0),y
    sta zp_los_dy
    lda zp_player_x
    sta mm_los_cx
    lda zp_player_y
    sta mm_los_cy
    lda #20
    sta zp_los_step
    jsr mm_los_clear_to_target
    bcc !irs_mg_next+
    ldx irs_mg_idx
    jsr monster_remove
!irs_mg_next:
    ldx irs_mg_idx
    inx
    jmp !irs_mg_loop-
!irs_mg_done:
    lda #1
    sta vis_room_revealed
    lda #<irs_p3_mg_msg
    ldy #>irs_p3_mg_msg
    jmp pmx_print_inline

irs_od_slot: .byte 0
irs_mg_idx:  .byte 0
irs_p3_map_msg: .text "You feel your map grow clearer." ; .byte 0
irs_p3_od_msg:  .text "You sense treasure nearby." ; .byte 0
irs_p3_mg_msg:  .text "There is a bright flash of light." ; .byte 0
#endif
