#importonce
// player_item_prompt.s — shared carried/equipped inventory prompt helpers.

#import "input_ui_helpers.s"

// Scratch variables shared with item/equipment command bodies.
piw_slot:     .byte 0
piw_equip:    .byte 0
piw_item_id:  .byte 0
piw_qty:      .byte 0
piw_p1:       .byte 0
piw_to_hit:   .byte 0
piw_to_dam:   .byte 0
piw_to_ac:    .byte 0
piw_flags:    .byte 0
piw_ego:      .byte 0
piw_filter:   .byte $ff
piw_visible_count: .byte 0
piw_visible_slots: .fill MAX_INV_SLOTS, 0
#if PLATFORM_PRODUCT_OVERLAY_RUNTIME
piw_return_overlay: .byte 0
#endif

.const PIW_FILTER_PRAYER_BOOK = $fb
.const PIW_FILTER_MAGE_BOOK   = $fc
.const PIW_FILTER_RECHARGE    = $fa

equip_slot_for_cat:
    .byte EQUIP_WEAPON
    .byte $ff
    .byte EQUIP_WEAPON
    .byte EQUIP_BODY
    .byte EQUIP_SHIELD
    .byte EQUIP_HEAD
    .byte EQUIP_HANDS
    .byte EQUIP_FEET
    .byte EQUIP_LIGHT
    .byte $ff
    .byte $ff
    .byte $ff
    .byte EQUIP_RING
    .byte $ff
    .byte $ff
    .byte $ff

show_inv_and_select:
    sta piw_filter
    jsr input_prepare_selectable_overlay_key
    jsr tramp_ui_inv_select_display
#if C64_TEST_SCRIPTED_BOOK_OVERLAY || C128_TEST_SCRIPTED_BOOK_OVERLAY
    jmp test_assert_book_overlay
#endif
    jsr input_get_followup_key
    tay
#if HAL_PLATFORM_NO_MODAL_RESTORE
    tya
    rts
#else
#if PLATFORM_PRODUCT_OVERLAY_RUNTIME
    lda piw_return_overlay
    bne !sias_have_return_overlay+
    tsx
    lda $0102,x
    cmp #$e0
    bcc !sias_check_outer_return+
    cmp #$f0
    bcc !sias_return_overlay+
!sias_check_outer_return:
    lda $0104,x
    cmp #$e0
    bcc !sias_return_resident+
    cmp #$f0
    bcs !sias_return_resident+
!sias_return_overlay:
    lda current_overlay
    cmp #OVL_ITEMS
    beq !sias_store_return_overlay+
    cmp #OVL_SPELL
    bne !sias_return_resident+
!sias_store_return_overlay:
    sta piw_return_overlay
!sias_return_resident:
!sias_have_return_overlay:
#endif
    tya
    pha
    jsr ui_view_restore_modal_overlay
#if PLATFORM_PRODUCT_OVERLAY_RUNTIME
    ldx piw_return_overlay
    lda #OVL_NONE
    sta piw_return_overlay
    txa
    beq !sias_no_overlay_reload+
    jsr overlay_load
    bcc !sias_overlay_loaded+
    brk
!sias_overlay_loaded:
#if PLATFORM_PRODUCT_OVERLAY_RELOAD_RESYNC
    jsr hal_platform_runtime_resync
    lda #MMU_ALL_RAM
    sta hal_memory_mmu_config_register
#endif
    sei
#if PLATFORM_PRODUCT_IRQ_VECTOR_RUNTIME
    jsr hal_irq_install_runtime
#endif
#if PLUS4_PRODUCT_OVERLAY_RUNTIME
    jsr plus4_install_ram_irq_vectors
    jsr plus4_bank_ram
#else
    lda #BANK_NO_KERNAL
    sta hal_memory_cpu_port
#endif
!sias_no_items_reload:
!sias_no_overlay_reload:
#endif
    pla
    rts
#endif

show_equip_and_select:
    jsr input_prepare_selectable_overlay_key
    jsr tramp_ui_equip_select_display
    jsr input_get_followup_key
#if HAL_PLATFORM_NO_MODAL_RESTORE
    rts
#else
    pha
    jsr ui_view_restore_modal_overlay
    pla
    rts
#endif

piw_inv_slot_matches_filter:
    txa
    pha
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !fail+
    sta piw_item_id
    ldy piw_filter
    cpy #$ff
    beq !match+
    cpy #$fd
    beq !match+
    tax
#if HAL_PLATFORM_ITEM_CATALOG_BANKED
    jsr item_load_category_x
#else
    lda it_category,x
#endif
    cpy #PIW_FILTER_RECHARGE
    beq !recharge+
    cpy #$fe
    beq !wearable+
    cmp piw_filter
    beq !match+
    cpy #PIW_FILTER_MAGE_BOOK
    beq !mage_book+
    cpy #PIW_FILTER_PRAYER_BOOK
    bne !fail+
    lda piw_item_id
    cmp #48
    beq !match+
    sec
    sbc #58
    cmp #3
    bcs !fail+
    bcc !match+
!recharge:
    cmp #ICAT_WAND
    beq !match+
    cmp #ICAT_STAFF
    beq !match+
    bne !fail+
!wearable:
    tax
    lda piw_item_id
    cmp #ITEM_FLASK_OIL
    beq !fail+
    lda equip_slot_for_cat,x
    cmp #$ff
    beq !fail+
    bne !match+
!mage_book:
    lda piw_item_id
    cmp #47
    beq !match+
    sec
    sbc #55
    cmp #3
    bcs !fail+
!match:
    sec
    pla
    tax
    rts
!fail:
    clc
    pla
    tax
    rts

piw_count_filtered_inv:
piw_build_visible_inv_cache:
    sta piw_filter
    ldy #0
    ldx #0
!loop:
    tya
    pha
    jsr piw_inv_slot_matches_filter
    pla
    tay
    bcc !next+
    txa
    sta piw_visible_slots,y
    iny
!next:
    inx
    cpx #MAX_INV_SLOTS
    bcc !loop-
    sty piw_visible_count
    tya
    rts

piw_prompt_filtered_inv:
    stx piw_qty
    jsr piw_build_visible_inv_cache
    bne !have_choices+
    ldx #HSTR_PIW_NOTHING
    jsr huff_print_msg
    clc
    rts
!have_choices:
    ldx piw_qty
    jsr piw_print_prompt_with_count
    sec
    rts

piw_pick_filtered_inv_key:
    jsr input_normalize_inventory_letter_key
    sec
    sbc #$41
    bcc !fail+
    tay
    cpy piw_visible_count
    bcs !fail+
    lda piw_visible_slots,y
    tax
    lda inv_item_id,x
    sec
    rts
!fail:
    clc
    rts

piw_count_visible_equip:
piw_build_visible_equip_cache:
    ldy #0
    ldx #EQUIP_WEAPON
!loop:
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !next+
    txa
    sta piw_visible_slots,y
    iny
!next:
    inx
    cpx #VISIBLE_EQUIP_END
    bcc !loop-
    sty piw_visible_count
    tya
    rts

piw_pick_visible_equip_key:
    jsr input_normalize_inventory_letter_key
    sec
    sbc #$41
    bcc !fail+
    tay
    cpy piw_visible_count
    bcs !fail+
    lda piw_visible_slots,y
    tax
    lda inv_item_id,x
    sec
    rts
!fail:
    clc
    rts

piw_print_prompt_with_count:
    sta piw_p1
#if hal_huffman_print_uses_cached_msg
    php
    sei
#endif
    jsr huff_decode_string
    lda piw_p1
    sta piw_qty
    ldy #0
!patch_loop:
    lda hd_decode_buf,y
    beq !piw_prompt_print+
    cmp #$28
    bne !not_open+
    lda #$01
    sta hd_decode_buf + 1,y
    jmp !next+
!not_open:
    cmp #$2d
    bne !next+
    lda piw_qty
    clc
    adc #$00
    sta hd_decode_buf + 1,y
!next:
    iny
    cpy #41
    bcc !patch_loop-
!piw_prompt_print:
#if hal_huffman_print_uses_cached_msg
    plp
#endif
    jmp msg_print_current_ptr
