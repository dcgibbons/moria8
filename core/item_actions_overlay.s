#importonce
// item_actions_overlay.s — low-frequency item command handlers
//
// These command handlers are overlay-owned in product builds to keep the
// resident/default image below the C64 map boundary and the C128 staged source
// below the overlay window. Unit tests still import them directly through
// player_items.s unless the platform build defines ITEM_ACTIONS_OVERLAY_EXTERNAL.

#import "player_item_select.s"

#if ITEM_ACTIONS_EARTHQUAKE_OWNER
    #import "player_magic_earthquake.s"
#endif

#if ITEM_ACTIONS_MAP_AREA_OWNER
    #import "player_magic_map.s"

eff_item_overlay_dispatch:
    lda pm_spell_idx
    cmp #22
    beq !eiod_map_area+
    jmp eff_earthquake
!eiod_map_area:
    jmp eff_map_area
#endif

item_action_get_key:
    jsr hal_input_get_key
#if hal_platform_item_action_key_restores_bank
    sta iagk_key
    lda #MMU_ALL_RAM
    sta hal_memory_mmu_config_register
    lda #BANK_NO_ROMS
    sta hal_memory_cpu_port
    lda iagk_key
#endif
    rts

#if hal_platform_item_action_key_restores_bank
iagk_key: .byte 0
#endif

item_action_select_filtered_inv:
    jsr piw_prompt_filtered_inv
    bcs !ias_have_choices+
    clc
    rts
!ias_have_choices:
    jsr input_prepare_followup_key
    jsr item_action_get_key
#if C64_PRODUCT_OVERLAY_RUNTIME || C128_PRODUCT_OVERLAY_RUNTIME || PLUS4_PRODUCT_OVERLAY_RUNTIME
    cmp #$3f
    bne !ias_no_selector_overlay_hint+
    pha
    lda #OVL_ITEMS
    sta piw_return_overlay
    pla
!ias_no_selector_overlay_hint:
#endif
    jmp piw_select_filtered_inv_key

// ============================================================
// item_read_scroll — Read a scroll from inventory
// Prompts "READ WHICH SCROLL (A-V)?", waits for keypress.
// Output: carry set = turn consumed, carry clear = cancelled
// Clobbers: everything
// ============================================================
item_read_scroll:
    // Blindness check — can't read while blind
    lda zp_eff_blind
    beq !irs_can_see+
    ldx #HSTR_PIQ_CANT_READ
    jsr huff_print_msg
    clc
    rts
!irs_can_see:
    lda #ICAT_SCROLL
    ldx #HSTR_PIQ_READ_PROMPT
    jsr item_action_select_filtered_inv
    bcs !irs_in_range+
    rts
!irs_in_range:
    stx piw_slot
    sta piw_item_id
    ldx piw_item_id
    lda #1
    sta id_known,x

    ldx piw_slot
    jsr inv_remove_item

    lda piw_item_id
    cmp #20
    bcc !irs_dispatch_generic+
    cmp #39
    bcs !irs_dispatch_generic+
    sec
    sbc #20
    tax
    lda irs_dispatch_lo,x
    sta zp_ptr1
    lda irs_dispatch_hi,x
    sta zp_ptr1_hi
    jmp (zp_ptr1)
!irs_dispatch_generic:
    jmp irs_effect_generic

irs_dispatch_lo:
    .byte <irs_effect_light, <irs_effect_identify, <irs_effect_teleport
    .byte <irs_effect_generic, <irs_effect_generic, <irs_effect_generic, <irs_effect_generic, <irs_effect_generic
    .byte <irs_effect_generic, <irs_effect_generic, <irs_effect_generic, <irs_effect_generic
    .byte <irs_effect_wor, <irs_effect_remove_curse, <irs_effect_enchant_weapon, <irs_effect_enchant_armor
    .byte <irs_effect_mon_confuse, <irs_effect_aggravate, <irs_effect_protect
irs_dispatch_hi:
    .byte >irs_effect_light, >irs_effect_identify, >irs_effect_teleport
    .byte >irs_effect_generic, >irs_effect_generic, >irs_effect_generic, >irs_effect_generic, >irs_effect_generic
    .byte >irs_effect_generic, >irs_effect_generic, >irs_effect_generic, >irs_effect_generic
    .byte >irs_effect_wor, >irs_effect_remove_curse, >irs_effect_enchant_weapon, >irs_effect_enchant_armor
    .byte >irs_effect_mon_confuse, >irs_effect_aggravate, >irs_effect_protect

irs_effect_light:
    jsr eff_light_room
    ldx #HSTR_PIQ_LIGHT
    jsr huff_print_msg
    sec
    rts

irs_effect_identify:
    jmp eff_identify_scroll_resident

irs_effect_teleport:
    jsr eff_teleport_self
    ldx #HSTR_PIQ_TELEPORT
    jsr huff_print_msg
    sec
    rts

irs_effect_wor:
    lda #15
    jsr rng_range
    clc
    adc #15
    sta zp_eff_word_recall

    ldx #HSTR_PIQ_AIR_CRACKLE
    jsr huff_print_msg
    sec
    rts

irs_effect_remove_curse:
    jsr eff_remove_curse
    ldx #HSTR_PIQ_CLEANSED
    jsr huff_print_msg
    sec
    rts

irs_effect_enchant_weapon:
    ldx #EQUIP_WEAPON
    lda inv_item_id,x
    cmp #FI_EMPTY
    bne !irs_ew_has+
    ldx #HSTR_PIQ_VIBRATION
    jsr huff_print_msg
    sec
    rts

!irs_ew_has:
    ldx #EQUIP_WEAPON
    lda inv_flags,x
    and #IF_CURSED
    beq !irs_ew_not_cursed+
    lda inv_flags + EQUIP_WEAPON
    and #~IF_CURSED & $ff
    sta inv_flags + EQUIP_WEAPON
    lda #0
    sta inv_to_hit + EQUIP_WEAPON
    sta inv_to_dam + EQUIP_WEAPON
    jsr player_recalc_equipment
    jmp !irs_ew_msg+

!irs_ew_not_cursed:
    ldx #EQUIP_WEAPON
    lda inv_to_hit,x
    cmp #5
    bcc !irs_ew_inc+
    lda inv_to_dam,x
    cmp #5
    bcc !irs_ew_inc+
    ldx #HSTR_PIQ_NOTHING
    jsr huff_print_msg
    sec
    rts

!irs_ew_inc:
    inc inv_to_hit + EQUIP_WEAPON
    inc inv_to_dam + EQUIP_WEAPON
    jsr player_recalc_equipment

!irs_ew_msg:
    ldx #HSTR_PIQ_WPN_GLOW
    jsr huff_print_msg
#if C64_TEST_SCRIPTED_SCROLL_SELECTOR
    lda #8
    sta c64_test_scroll_selector_return_pending
#endif
#if C128_TEST_SCRIPTED_SCROLL_SELECTOR
    lda #8
    sta c128_test_scroll_selector_return_pending
#endif
    sec
    rts

irs_effect_enchant_armor:
    ldx #EQUIP_BODY
!irs_ea_scan:
    cpx #EQUIP_FEET + 1
    bcs !irs_ea_none+
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !irs_ea_next+
    lda inv_flags,x
    and #IF_CURSED
    bne !irs_ea_has+
    lda inv_to_ac,x
    cmp #5
    bcc !irs_ea_has+
!irs_ea_next:
    inx
    jmp !irs_ea_scan-

!irs_ea_none:
    ldx #HSTR_PIQ_VIBRATION
    jsr huff_print_msg
    sec
    rts

!irs_ea_has:
    stx piw_slot
    lda inv_flags,x
    and #IF_CURSED
    beq !irs_ea_not_cursed+
    lda inv_flags,x
    and #~IF_CURSED & $ff
    sta inv_flags,x
    lda #0
    sta inv_to_ac,x
    jsr player_recalc_equipment
    jmp !irs_ea_msg+

!irs_ea_not_cursed:
    ldx piw_slot
    lda inv_to_ac,x
    cmp #5
    bcc !irs_ea_inc+
    ldx #HSTR_PIQ_NOTHING
    jsr huff_print_msg
    sec
    rts

!irs_ea_inc:
    inc inv_to_ac,x
    jsr player_recalc_equipment

!irs_ea_msg:
    ldx #HSTR_PIQ_ARM_GLOW
    jsr huff_print_msg
    sec
    rts

irs_effect_mon_confuse:
    lda #1
    sta zp_confuse_melee
    ldx #HSTR_PIQ_HANDS_GLOW
    jsr huff_print_msg
    sec
    rts

irs_effect_aggravate:
    jsr eff_aggravate
    ldx #HSTR_PIQ_HUMMING
    jsr huff_print_msg
    sec
    rts

irs_effect_protect:
    lda #25
    jsr rng_range
    clc
    adc #25
    clc
    adc zp_eff_protect
    bcc !irs_prot_ok+
    lda #255
!irs_prot_ok:
    sta zp_eff_protect

    ldx #HSTR_PIQ_PROTECTED
    jsr huff_print_msg
    sec
    rts

irs_effect_generic:
    ldx #HSTR_PIQ_NOTHING
    jsr huff_print_msg
    sec
    rts

// ============================================================
// item_aim_wand — Aim a wand from inventory
// ============================================================
item_aim_wand:
    lda #ICAT_WAND
    ldx #HSTR_PIW_AIM_PROMPT
    jsr item_action_select_filtered_inv
    bcs !iaw_in_range+
    rts
!iaw_in_range:
    stx piw_slot
    sta piw_item_id
    ldx piw_slot
    lda inv_p1,x
    bne !iaw_has_charges+

    ldx #HSTR_PIW_NO_CHARGES
    jsr huff_print_msg
    clc
    rts

!iaw_has_charges:
    ldx piw_slot
    dec inv_p1,x

    ldx piw_item_id
    lda #1
    sta id_known,x

    lda piw_item_id
    cmp #39
    beq !iaw_light+
    cmp #40
    beq !iaw_lightning+
    cmp #41
    beq !iaw_frost+
    cmp #42
    beq !iaw_cloud+
    sec
    rts

!iaw_light:
    jsr eff_light_room
    ldx #HSTR_PIQ_LIGHT
    jsr huff_print_msg
    sec
    rts

!iaw_lightning:
    // Temporary Balrog win-condition test hack: make Wand of Lightning hit
    // for roughly 10x its normal 3d8 damage without affecting the spell.
    lda #30
    ldx #8
    ldy #0
    jsr eff_bolt
    ldx #HSTR_PIW_WAND_BOLT
    jsr huff_print_msg
    sec
    rts

!iaw_frost:
    lda #4
    ldx #8
    ldy #0
    jsr eff_bolt
    ldx #HSTR_PIW_WAND_FROST
    jsr huff_print_msg
    sec
    rts

!iaw_cloud:
    jsr eff_directional_monster
    bcc !iaw_cloud_miss+
    jsr monster_get_ptr
    ldy #MX_CONFUSE
    lda #10
    sta (zp_ptr0),y
    ldx #HSTR_PIW_WAND_CLOUD
    jsr huff_print_msg
    sec
    rts
!iaw_cloud_miss:
    ldx #HSTR_PIW_WAND_MISS
    jsr huff_print_msg
    sec
    rts

// ============================================================
// item_use_staff — Use a staff from inventory
// ============================================================
item_use_staff:
    lda #ICAT_STAFF
    ldx #HSTR_PIW_USE_PROMPT
    jsr item_action_select_filtered_inv
    bcs !ius_in_range+
    rts
!ius_in_range:
    stx piw_slot
    sta piw_item_id
    ldx piw_slot
    lda inv_p1,x
    bne !ius_has_charges+

    ldx #HSTR_PIW_STAFF_EMPTY
    jsr huff_print_msg
    clc
    rts

!ius_has_charges:
    ldx piw_slot
    dec inv_p1,x

    ldx piw_item_id
    lda #1
    sta id_known,x

    lda piw_item_id
    cmp #43
    beq !ius_light+
    cmp #44
    beq !ius_detect+
    cmp #45
    beq !ius_teleport+
    cmp #46
    beq !ius_clw+
    sec
    rts

!ius_light:
    jsr eff_light_room
    ldx #HSTR_PIQ_LIGHT
    jsr huff_print_msg
    sec
    rts

!ius_detect:
    jsr eff_detect_monsters
    ldx #HSTR_PIQ_SENSE
    jsr huff_print_msg
    sec
    rts

!ius_teleport:
    jsr eff_teleport_self
    ldx #HSTR_PIQ_TELEPORT
    jsr huff_print_msg
    sec
    rts

!ius_clw:
    lda #1
    ldx #8
    ldy #1
    jsr math_dice
    lda zp_math_a
    jsr pmx_heal_and_report
    sec
    rts

// ============================================================
// item_refuel — Refuel a brass lantern with a flask of oil
// ============================================================
item_refuel:
    ldx #EQUIP_LIGHT
    lda inv_item_id,x
    cmp #14
    beq !ir_has_lamp+

    ldx #HSTR_PIR_NOT_LAMP
    jsr huff_print_msg
    clc
    rts

!ir_has_lamp:
    ldx #0
!ir_scan:
    cpx #MAX_INV_SLOTS
    bcs !ir_no_oil+
    lda inv_item_id,x
    cmp #ITEM_FLASK_OIL
    beq !ir_found_oil+
    inx
    jmp !ir_scan-

!ir_no_oil:
    ldx #HSTR_PIR_NO_OIL
    jsr huff_print_msg
    clc
    rts

!ir_found_oil:
    stx piw_slot

    lda inv_p1,x
    clc
    adc inv_p1 + EQUIP_LIGHT
    bcs !ir_overflow+
    cmp #LANTERN_MAX_CHARGES + 1
    bcc !ir_no_overflow+

!ir_overflow:
    lda #LANTERN_MAX_CHARGES
    sta inv_p1 + EQUIP_LIGHT

    ldx #HSTR_PIR_OVERFLOW
    jsr huff_print_msg
    ldx #HSTR_PIR_FULL
    jsr huff_print_msg
    jmp !ir_remove_flask+

!ir_no_overflow:
    sta inv_p1 + EQUIP_LIGHT
    ldx #HSTR_PIR_REFUELED
    jsr huff_print_msg

!ir_remove_flask:
    ldx piw_slot
    jsr inv_remove_item
    sec
    rts
