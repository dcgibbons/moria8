#importonce
// scroll_effects_p3.s — Phase 3 scroll dispatch and effect handlers.
// Imported by each platform into the overlay that owns the spell-side
// handlers it calls (C64/Plus4: spell; Apple: spell + modal; C128: death +
// modal). SCROLL_P3_EXISTING_OWNER marks the overlay with the established
// eff_* handlers; SCROLL_P3_NEW_OWNER marks the overlay hosting the four new
// effects.

#if SCROLL_P3_EXISTING_OWNER || SCROLL_P3_NEW_OWNER
irs_dispatch_p3_overlay:
#if SCROLL_P3_EXISTING_OWNER
    // Wand of Stinking Cloud is a legacy ID (42), not a Phase 3 row. It still
    // uses the existing-owner path, but must bypass the 101-based scroll table.
    cmp #42
    beq irs_p3_run_existing
    cmp #ITEM_TYPE_WAND_SLOW
    bcc !irs_p3_scroll_tbl+
    // Wand/staff Phase 3 effects (114-121) ride the same inner-swap mechanism
    jmp irs_p3_run_existing
!irs_p3_scroll_tbl:
#endif
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
// the router left OVL_MODAL_MISC loaded, so swap out and back. On Apple IIe
// they live in OVL_SPELL and the router lives in OVL_DEATH; loading OVL.SPELL
// here would evict the chain's own continuation, so each spell-resident
// handler runs through tramp_spell_call_items (resident swap-call returning
// to OVL.ITEMS, matching !irs_re_done). Elsewhere the handlers are in the
// spell overlay, which the router already loaded.
#if APPLE2
.macro A2ReCall(handler) {
    lda #<handler
    ldy #>handler
    jmp irs_re_a2_call
}
.macro A2ReCallArg(handler, arg) {
    lda #arg
    sta a2_tsci_arg
    :A2ReCall(handler)
}
#endif
irs_p3_run_existing:
#if C128
    pha
    lda #OVL_DEATH
    jsr overlay_load
    bcc !irs_re_swap_ok+
    jmp !irs_re_fail+
!irs_re_swap_ok:
    pla
#endif
    cmp #ITEM_TYPE_SCR_RECHARGING
    beq !irs_re_recharge+
    cmp #ITEM_TYPE_SCR_RUNE_PROTECTION
    beq !irs_re_rune+
    cmp #ITEM_TYPE_SCR_GENOCIDE
    beq !irs_re_genocide+
    cmp #ITEM_TYPE_WAND_SLOW
    beq !irs_re_slow+
    cmp #ITEM_TYPE_WAND_STONE_MUD
    beq !irs_re_mud+
    cmp #ITEM_TYPE_WAND_TELEPORT_AWAY
    beq !irs_re_teleport+
    cmp #ITEM_TYPE_WAND_FIRE_BALL
    beq !irs_re_fire+
    cmp #ITEM_TYPE_WAND_COLD_BALL
    beq !irs_re_cold+
    cmp #ITEM_TYPE_STAFF_DISPEL_EVIL
    beq !irs_re_dispel+
    cmp #ITEM_TYPE_STAFF_SPEED
    beq !irs_re_speed+
    cmp #ITEM_TYPE_STAFF_REMOVE_CURSE
    beq !irs_re_remove_curse+
    cmp #42
    beq !irs_re_cloud+
    // Scroll of *Destruction* / Staff of Destruction
#if APPLE2
    :A2ReCall(eff_destroy_area)
#else
    jsr eff_destroy_area
    jmp !irs_re_done+
#endif
!irs_re_cloud:
    jsr eff_directional_monster
    bcc !irs_re_cloud_miss+
    jsr monster_get_ptr
    ldy #MX_CONFUSE
    lda #10
    sta (zp_ptr0),y
    ldx #HSTR_PIW_WAND_CLOUD
    jmp !irs_re_msg+
!irs_re_cloud_miss:
    ldx #HSTR_PIW_WAND_MISS
!irs_re_msg:
    jsr huff_print_msg
    jmp !irs_re_done+
!irs_re_recharge:
    // Upstream Recharging scroll: Recharge II strength (A=50)
#if APPLE2
    :A2ReCallArg(eff_recharge_item, 50)
#else
    lda #50
    jsr eff_recharge_item
    jmp !irs_re_done+
#endif
!irs_re_rune:
#if APPLE2
    :A2ReCall(eff_glyph_of_warding)
#else
    jsr eff_glyph_of_warding
    jmp !irs_re_done+
#endif
!irs_re_genocide:
#if APPLE2
    :A2ReCall(eff_genocide)
#else
    jsr eff_genocide
    jmp !irs_re_done+
#endif
!irs_re_slow:
#if APPLE2
    :A2ReCall(eff_slow_monster_dir)
#else
    jsr eff_slow_monster_dir
    jmp !irs_re_done+
#endif
!irs_re_mud:
    jsr eff_wall_to_mud
    jmp !irs_re_done+
!irs_re_teleport:
#if APPLE2
    :A2ReCall(eff_teleport_other)
#else
    jsr eff_teleport_other
    jmp !irs_re_done+
#endif
!irs_re_fire:
    // Fire Ball spell damage (49)
#if APPLE2
    :A2ReCallArg(eff_ball, 49)
#else
    lda #49
    jsr eff_ball
    jmp !irs_re_done+
#endif
!irs_re_cold:
    // Frost Ball spell damage (33)
#if APPLE2
    :A2ReCallArg(eff_ball, 33)
#else
    lda #33
    jsr eff_ball
    jmp !irs_re_done+
#endif
!irs_re_dispel:
#if APPLE2
    :A2ReCall(ped_s28)
#else
    jsr ped_s28
    jmp !irs_re_done+
#endif
!irs_re_speed:
#if APPLE2
    :A2ReCall(eff_haste_self)
#else
    jsr eff_haste_self
#endif
    jmp !irs_re_done+
!irs_re_remove_curse:
#if APPLE2
    :A2ReCall(eff_remove_curse)
#else
    jsr eff_remove_curse
#endif
!irs_re_done:
#if C128
    lda #OVL_ITEMS
    jsr overlay_load
    rts
!irs_re_fail:
    pla
    rts
#elif APPLE2
    lda #OVL_ITEMS
    jsr overlay_load
    rts
#else
    rts
#endif
#endif

#if APPLE2 && SCROLL_P3_EXISTING_OWNER
// irs_re_a2_call — Stage an OVL.SPELL handler and run it through the resident
// swap-call trampoline. A/Y = handler address. Runs in the death overlay;
// the swap to OVL.SPELL happens only inside resident code so this chain's
// continuation is never evicted.
irs_re_a2_call:
    sta tsci_target+1
    sty tsci_target+2
    jmp tramp_spell_call_items
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
    jmp scroll_teleport_level_exec

// Magic Mapping: reveal the whole level map (wizard reveal effect).
irs_p3_magic_mapping:
#if APPLE2
    // eff_reveal_floorplan lives in OVL.SPELL; the message string is in this
    // overlay. Print first (msg_print is resident), then run the effect
    // through the swap-call trampoline, which restores OVL.ITEMS on exit.
    lda #<irs_p3_map_msg
    sta zp_ptr0
    ldy #>irs_p3_map_msg
    sty zp_ptr0_hi
    jsr msg_print
    :A2ReCall(eff_reveal_floorplan)
#else
    jsr eff_reveal_floorplan
    lda #<irs_p3_map_msg
    ldy #>irs_p3_map_msg
    jmp irs_p3_report
#endif

// Object Detection: reveal every floor item's tile.
irs_p3_object_detect:
    ldx #0
!irs_od_loop:
    lda fi_item_id,x
    cmp #FI_EMPTY
    beq !irs_od_next+
    stx irs_od_slot
    // Mark the tile visited+lit so the item renders on the map even in the
    // dark (upstream field_mark semantics). Guard the row index: floor-item
    // arrays can hold stale data off-dungeon, and an out-of-range row would
    // read map_row_* out of bounds and scribble an arbitrary address.
    lda fi_y,x
    cmp #MAP_ROWS
    bcs !irs_od_next+
    tay
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    lda fi_x,x
    cmp #MAP_COLS
    bcs !irs_od_next+
    tay
    :MapRead_ptr0_y()
    ora #(FLAG_VISITED | FLAG_LIT)
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
    jmp irs_p3_report

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
    jmp irs_p3_report

// irs_p3_report — Shared message + exit tail for the new Phase 3 effects.
// On Apple IIe the death overlay owns the handlers; on C128 the modal-misc
// overlay owns them, so the items overlay must be restored before returning
// to the read-scroll flow.
irs_p3_report:
#if APPLE2
    // pmx_print_inline lives in OVL.SPELL on this platform, which is not
    // loaded here (the router runs from OVL.DEATH). Inline its body:
    // msg_print is resident and the message string is in this overlay.
    // Do NOT load OVL.ITEMS here — that would evict this overlay before the
    // rts fetches, executing items-overlay bytes at this address. The
    // resident router (irs_p3_swap_exec) restores OVL.ITEMS after we return.
    sta zp_ptr0
    sty zp_ptr0_hi
    jsr msg_print
    rts
#else
    jsr pmx_print_inline
#if C128
    lda #OVL_ITEMS
    jsr overlay_load
#endif
    rts
#endif

irs_od_slot: .byte 0
irs_mg_idx:  .byte 0
irs_p3_map_msg: .text "You feel your map grow clearer." ; .byte 0
irs_p3_od_msg:  .text "You sense treasure nearby." ; .byte 0
irs_p3_mg_msg:  .text "There is a bright flash of light." ; .byte 0
#endif


#if C128
// iq_dispatch_p3_overlay — C128 Phase 3 potion dispatch + handlers.
// Reached from the banked quaff dispatch with the modal-misc overlay loaded
// and A = potion type ID. Lives in the modal overlay because both the C128
// banked payload and the items overlay are full.
iq_dispatch_p3_overlay:
    cmp #ITEM_TYPE_POT_HEALING
    beq !iqp3_healing+
    cmp #ITEM_TYPE_POT_RESTORATION
    beq !iqp3_restoration+
    cmp #ITEM_TYPE_POT_RESIST_HEAT
    beq !iqp3_resist_heat+
    cmp #ITEM_TYPE_POT_RESIST_COLD
    beq !iqp3_resist_cold+
    cmp #ITEM_TYPE_POT_CURE_CRITICAL
    beq !iqp3_cure_critical+
    cmp #ITEM_TYPE_POT_NEUTRALIZE
    beq !iqp3_neutralize+
    rts

!iqp3_healing:
    lda #200
    jsr pmx_heal_and_report
    rts

!iqp3_cure_critical:
    lda #6
    ldx #7
    ldy #0
    jsr math_dice
    lda zp_math_a
    jsr pmx_heal_and_report
    rts

!iqp3_restoration:
    jsr player_calc_stats
    ldx #HSTR_PIQ_RESTORED
    jsr huff_print_msg
    rts

!iqp3_resist_heat:
    lda #10
    jsr rng_range
    clc
    adc #10
    clc
    adc zp_eff_resist
    bcc !iqp3_rh_store+
    lda #255
!iqp3_rh_store:
    sta zp_eff_resist
    rts

!iqp3_resist_cold:
    lda #10
    jsr rng_range
    clc
    adc #10
    clc
    adc eff_resist_cold_timer
    bcc !iqp3_rc_store+
    lda #255
!iqp3_rc_store:
    sta eff_resist_cold_timer
    rts

!iqp3_neutralize:
    jsr eff_cure_poison
    ldx #HSTR_EFF_POISON_END
    jsr huff_print_msg
    rts
#endif
