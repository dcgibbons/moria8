#importonce
// player_items.s — Equip, Remove, Eat, and equipment recalculation
//
// Phase 6.3: Player item interaction routines.
// item_wear: equip an item from carried inventory
// item_takeoff: remove an equipped item back to carried inventory
// item_eat: eat food from inventory
// player_recalc_equipment: recalculate AC/combat after equip changes

#import "ui_restore.s"
#import "input_ui_helpers.s"
#import "player_heal_feedback.s"
#import "player_item_select.s"

// ============================================================
// Constants
// ============================================================
.const FOOD_RATION_VALUE_LO = <1500
.const FOOD_RATION_VALUE_HI = >1500
.const FOOD_SLIME_VALUE_LO  = <500
.const FOOD_SLIME_VALUE_HI  = >500
.const FOOD_MAX_LO          = <4000
.const FOOD_MAX_HI          = >4000

.const ITEM_RATION     = 15    // Type ID for ration of food
.const ITEM_SLIME_MOLD = 16   // Type ID for slime mold

// ============================================================
// Scratch variables
// ============================================================
piw_slot:     .byte 0          // Source carried slot index
piw_equip:    .byte 0          // Target equipment slot index
piw_item_id:  .byte 0          // Item type ID being processed
piw_qty:      .byte 0          // Item qty being processed
piw_p1:       .byte 0          // Item p1 being processed
piw_to_hit:   .byte 0          // Item to-hit being processed
piw_to_dam:   .byte 0          // Item to-damage being processed
piw_to_ac:    .byte 0          // Item to-AC being processed
piw_flags:    .byte 0          // Item flags being processed
piw_ego:      .byte 0          // Item ego type being processed
piw_filter:   .byte $ff        // Active inventory filter for prompt/select helpers
piw_visible_count: .byte 0     // Number of cached visible slots
piw_visible_slots: .fill MAX_INV_SLOTS, 0  // Absolute carried/equipped slot indices
#if C64_PRODUCT_OVERLAY_RUNTIME || C128_PRODUCT_OVERLAY_RUNTIME || PLUS4_PRODUCT_OVERLAY_RUNTIME
piw_return_overlay: .byte 0    // Product overlay to restore after prompt-time modal UI
#endif

.const PIW_FILTER_PRAYER_BOOK = $fb
.const PIW_FILTER_MAGE_BOOK   = $fc
.const PIW_FILTER_RECHARGE    = $fa

// ============================================================
// Category -> equipment slot mapping table
// ============================================================
equip_slot_for_cat:
    .byte EQUIP_WEAPON     // ICAT_DIGGING (0) -> weapon slot 22
    .byte $ff              // ICAT_GOLD (1) -> invalid
    .byte EQUIP_WEAPON     // ICAT_WEAPON (2) -> slot 22
    .byte EQUIP_BODY       // ICAT_ARMOR (3) -> slot 23
    .byte EQUIP_SHIELD     // ICAT_SHIELD (4) -> slot 24
    .byte EQUIP_HEAD       // ICAT_HELM (5) -> slot 25
    .byte EQUIP_HANDS      // ICAT_GLOVES (6) -> slot 26
    .byte EQUIP_FEET       // ICAT_BOOTS (7) -> slot 27
    .byte EQUIP_LIGHT      // ICAT_LIGHT (8) -> slot 28
    .byte $ff              // ICAT_FOOD (9) -> invalid
    .byte $ff              // ICAT_POTION (10) -> invalid
    .byte $ff              // ICAT_SCROLL (11) -> invalid
    .byte EQUIP_RING       // ICAT_RING (12) -> slot 29
    .byte $ff              // ICAT_BOOK (13) -> not equippable
    .byte $ff              // ICAT_WAND (14) -> not equippable
    .byte $ff              // ICAT_STAFF (15) -> not equippable

// ============================================================
// Subroutines
// ============================================================

// show_inv_and_select — Show filtered inventory overlay and return the chosen
// key after restoring gameplay. Used by item-selection dialogs so `?` can
// select directly from the inventory list instead of forcing a second prompt.
// Input: A = filter value ($FF=all, $FE=wearable, $FD=identify-all, 0-15=exact ICAT match)
// Output: A = key pressed while the inventory overlay was visible
// Preserves: nothing
show_inv_and_select:
    sta piw_filter
#if C64_PRODUCT_OVERLAY_RUNTIME || C128_PRODUCT_OVERLAY_RUNTIME || PLUS4_PRODUCT_OVERLAY_RUNTIME
    lda #OVL_NONE
    sta piw_return_overlay
    // Only restore an overlay when the immediate return target is inside the
    // overlay window. Resident prompts can run while an overlay is current on
    // the outer stack, but they must not reload that overlay before returning.
    tsx
    lda $0102,x
    cmp #$e0
    bcc !sias_return_resident+
    cmp #$f0
    bcs !sias_return_resident+
    lda current_overlay
    cmp #OVL_ITEMS
    bne !sias_return_resident+
    sta piw_return_overlay
!sias_return_resident:
#endif
    jsr input_prepare_selectable_overlay_key
    jsr tramp_ui_inv_select_display
#if C64_TEST_SCRIPTED_BOOK_OVERLAY || C128_TEST_SCRIPTED_BOOK_OVERLAY
    jmp test_assert_book_overlay
#endif
    jsr input_get_followup_key
    pha
    jsr ui_view_restore_modal_overlay
#if C64_PRODUCT_OVERLAY_RUNTIME || C128_PRODUCT_OVERLAY_RUNTIME || PLUS4_PRODUCT_OVERLAY_RUNTIME
    // Prompt-time inventory can be opened from OVL.ITEMS command handlers.
    // Reload the caller overlay before returning to code in the $E000 window.
    lda piw_return_overlay
    cmp #OVL_ITEMS
    bne !sias_no_items_reload+
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !sias_no_items_reload+
#if C128_PRODUCT_OVERLAY_RUNTIME
    jsr hal_platform_runtime_resync
    lda #MMU_ALL_RAM
    sta hal_memory_mmu_config_register
#endif
    sei
#if C64_PRODUCT_IRQ_VECTOR_RUNTIME
    jsr hal_irq_install_runtime
#endif
#if !PLUS4
    lda #BANK_NO_KERNAL
    sta hal_memory_cpu_port
#endif
!sias_no_items_reload:
#endif
    pla
    rts

// show_equip_and_select — Show equipment overlay and return the chosen key
// after restoring gameplay. Used by item_takeoff when player presses '?'.
// Preserves: nothing
show_equip_and_select:
    jsr input_prepare_selectable_overlay_key
    jsr tramp_ui_equip_select_display
    jsr input_get_followup_key
    pha
    jsr ui_view_restore_modal_overlay
    pla
    rts

// piw_inv_slot_matches_filter — check whether a carried slot is visible
// Input: X = carried slot index, piw_filter = active filter
// Output: carry set if slot is occupied and visible under this filter
// Preserves: X
piw_inv_slot_matches_filter:
    txa
    pha

    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !piw_inv_fail+
    sta piw_item_id

    ldy piw_filter
    cpy #$ff
    beq !piw_inv_match+
    cpy #$fd
    beq !piw_inv_match+
    tax
    lda it_category,x
    cpy #PIW_FILTER_RECHARGE
    beq !piw_inv_recharge+
    cpy #$fe
    beq !piw_inv_wearable+
    cmp piw_filter
    beq !piw_inv_match+
    cpy #PIW_FILTER_MAGE_BOOK
    beq !piw_inv_mage_book+
    cpy #PIW_FILTER_PRAYER_BOOK
    bne !piw_inv_fail+
    lda piw_item_id
    cmp #48
    beq !piw_inv_match+
    sec
    sbc #58
    cmp #3
    bcs !piw_inv_fail+
    bcc !piw_inv_match+

!piw_inv_recharge:
    cmp #ICAT_WAND
    beq !piw_inv_match+
    cmp #ICAT_STAFF
    beq !piw_inv_match+
    bne !piw_inv_fail+

!piw_inv_wearable:
    tax
    lda piw_item_id
    cmp #ITEM_FLASK_OIL
    beq !piw_inv_fail+
    lda equip_slot_for_cat,x
    cmp #$ff
    beq !piw_inv_fail+
    bne !piw_inv_match+

!piw_inv_mage_book:
    lda piw_item_id
    cmp #47
    beq !piw_inv_match+
    sec
    sbc #55
    cmp #3
    bcs !piw_inv_fail+

!piw_inv_match:
    sec
    pla
    tax
    rts

!piw_inv_fail:
    clc
    pla
    tax
    rts

// piw_count_filtered_inv / piw_build_visible_inv_cache — count/cache visible
// carried slots for a filter.
// Input: A = filter value
// Output: A = visible count
// Clobbers: X, Y
piw_count_filtered_inv:
piw_build_visible_inv_cache:
    sta piw_filter
    ldy #0
    ldx #0
!piw_count_inv_loop:
    tya
    pha
    jsr piw_inv_slot_matches_filter
    pla
    tay
    bcc !piw_count_inv_next+
    txa
    sta piw_visible_slots,y
    iny
!piw_count_inv_next:
    inx
    cpx #MAX_INV_SLOTS
    bcc !piw_count_inv_loop-
    sty piw_visible_count
    tya
    rts

// piw_prompt_filtered_inv — print a filtered inventory prompt or "nothing there"
// Input: A = filter value, X = Huffman prompt string id
// Output: carry set if the prompt was printed, carry clear if no visible items
piw_prompt_filtered_inv:
    stx piw_qty
    jsr piw_build_visible_inv_cache
    bne !piw_prompt_inv_have_choices+
    ldx #HSTR_PIW_NOTHING
    jsr huff_print_msg
    clc
    rts
!piw_prompt_inv_have_choices:
    ldx piw_qty
    jsr piw_print_prompt_with_count
    sec
    rts

// piw_pick_filtered_inv_key — map a filtered prompt letter to a carried slot
// Input: A = PETSCII key, piw_filter = active filter
// Output: carry set on success, X = carried slot, A = item type ID
//         carry clear if key is outside the visible filtered range
piw_pick_filtered_inv_key:
    jsr input_normalize_inventory_letter_key
    sec
    sbc #$41
    bcc !piw_pick_inv_fail+
    tay
    cpy piw_visible_count
    bcs !piw_pick_inv_fail+
    lda piw_visible_slots,y
    tax
    lda inv_item_id,x
    sec
    rts

!piw_pick_inv_fail:
    clc
    rts

// piw_build_visible_equip_cache — cache non-empty equipment slots
// piw_count_visible_equip / piw_build_visible_equip_cache — count/cache
// non-empty equipment slots for takeoff prompt mapping.
// Output: A = non-empty equipment count
// Clobbers: X, Y
piw_count_visible_equip:
piw_build_visible_equip_cache:
    ldy #0
    ldx #EQUIP_WEAPON
!piw_count_eq_loop:
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !piw_count_eq_next+
    txa
    sta piw_visible_slots,y
    iny
!piw_count_eq_next:
    inx
    cpx #EQUIP_RING + 1
    bcc !piw_count_eq_loop-
    sty piw_visible_count
    tya
    rts

// piw_pick_visible_equip_key — map a contiguous equipment letter to a slot
// Input: A = PETSCII key
// Output: carry set on success, X = absolute equipment slot, A = item type ID
//         carry clear if key is outside the visible equipped-item range
piw_pick_visible_equip_key:
    jsr input_normalize_inventory_letter_key
    sec
    sbc #$41
    bcc !piw_pick_eq_fail+
    tay
    cpy piw_visible_count
    bcs !piw_pick_eq_fail+
    lda piw_visible_slots,y
    tax
    lda inv_item_id,x
    sec
    rts

!piw_pick_eq_fail:
    clc
    rts

// piw_print_prompt_with_count — decode, patch, and print a visible range prompt
// Input: A = visible count (> 0), X = Huffman prompt string id
// Output: message printed via the message-line path
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
!piw_prompt_patch_loop:
    lda hd_decode_buf,y
    beq !piw_prompt_print+
    cmp #$28                    // '('
    bne !piw_prompt_not_open+
    lda #$01                    // C64 screen code 'a'
    sta hd_decode_buf + 1,y
    jmp !piw_prompt_next+
!piw_prompt_not_open:
    cmp #$2d                    // '-'
    bne !piw_prompt_next+
    lda piw_qty
    clc
    adc #$00                    // 1 -> screen code 'a', 2 -> 'b'
    sta hd_decode_buf + 1,y
!piw_prompt_next:
    iny
    cpy #41
    bcc !piw_prompt_patch_loop-

!piw_prompt_print:
#if hal_huffman_print_uses_cached_msg
    plp
#endif
    jmp msg_print_current_ptr

// Wear/takeoff/eat/quaff command bodies live separately so C128 can
// place the callable code outside the I/O hole.
#if !PLAYER_ITEM_COMMANDS_EXTERNAL
    #import "player_item_commands.s"
#endif

// ============================================================
// Low-frequency item actions — resident in tests, overlay-owned in product
// builds to keep the main image below the C64/C128 layout ceilings.
// ============================================================
#if !ITEM_ACTIONS_OVERLAY_EXTERNAL
    #import "item_actions_overlay.s"
#endif

// Strings migrated to Huffman compression (HSTR_PIW_*, HSTR_PIQ_* in huffman_data.s)

// ============================================================
// item_gain_spell — Study a spell book to learn qualifying spells
// Books are not consumed.
// Output: carry set = turn consumed, carry clear = cancelled
// Clobbers: everything
// ============================================================
