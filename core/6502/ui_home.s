#importonce
// ui_home.s — Player Home UI (deposit/retrieve items)
//
// Module ownership:
//   owner:
//     !HOME_OVERLAY_SEPARATE: RuntimeBanked on C64/C128 ($F000), or TownOverlay
//       for standalone unit-test harnesses that omit HOME_OVERLAY_SEPARATE.
//     HOME_OVERLAY_SEPARATE (all 7 6502 ports: C64, C128, Plus/4, Apple IIe,
//       CX16, Atari 8-bit, BBC Master): self-contained HomeOverlay (`ovl.home`)
//       with no calls or data reads into TownOverlay (store.s / ui_store.s).
//   lifetime:
//     !HOME_OVERLAY_SEPARATE: persistent in RuntimeBanked or transient in TownOverlay.
//     HOME_OVERLAY_SEPARATE: transient overlay; loaded on Home entry, released on exit.
//   callers:
//     !HOME_OVERLAY_SEPARATE: store_enter (`core/ui_store.s`) on #STORE_HOME.
//     HOME_OVERLAY_SEPARATE: port `tramp_store_enter` (via `game_loop.s:try_store_entry`)
//       dispatches #STORE_HOME directly into `OVL_HOME` (`home_enter`) and
//       restores the caller's bank/overlay on return.
//   .assert: protected by each port's RuntimeBanked/TownOverlay/HomeOverlay end .assert.
//
// No pricing — items are stored for free.

#import "input_ui_helpers.s"
#import "store_meta_macros.s"
#import "ui_weight_helpers.s"
#define UI_HOME_TEXT_MACROS_ONLY
#import "ui_home_text.s"
#undef UI_HOME_TEXT_MACROS_ONLY

// ============================================================
// PETSCII key constants (duplicated from ui_store.s — overlay segment not visible here)
// ============================================================
.const PETSCII_HM_A      = $41
.const PETSCII_HM_D      = $44
.const PETSCII_HM_Q      = $51
.const PETSCII_HM_R      = $52
.const PETSCII_HM_SPACE  = $20

// ============================================================
// Scratch variables
// ============================================================
hm_inv_slot:   .byte 0     // Player inventory slot for deposit
hm_store_slot: .byte 0     // Store slot for retrieve
hm_row:        .byte 0     // Current screen row
hm_save_x:     .byte 0     // Saved index register

home_put_white_col1:
    pha
    lda #COL_WHITE
    sta zp_text_color
    pla
home_put_col1_string:
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    stx zp_ptr0
    sty zp_ptr0_hi
    jmp hal_screen_put_string

hm_clear_and_title:
    txa
    pha
    tya
    pha
    lda #COL_BLACK
    sta zp_text_color
    jsr ui_help_clear_all
    pla
    tay
    pla
    tax
    lda #0
    jmp home_put_white_col1

home_put_letter:
    :StorePutLetterBody(hm_save_x)

#if HOME_OVERLAY_SEPARATE
.const HOME_GOLD_COL = 21

#if HAL_PLATFORM_INV_ADD_CARRIED_EXTERNAL
home_inv_add_carried:
{
    :InvAddCarriedBody()
}
#endif

// Self-contained Home screen renderer when HomeOverlay is separate from TownOverlay.
home_draw_screen:
    ldx #<hm_title_str
    ldy #>hm_title_str
    jsr hm_clear_and_title
.if (SCREEN_COLS >= 80) {
    lda #0
    ldx #55
} else {
    lda #1
    ldx #1
}
    jsr uwt_hm_draw_burden_header

    // Row 2: Separator
    lda #COL_DGREY
    sta zp_text_color
    lda #2
    jsr home_draw_separator_at_a

    // Rows 3-18: Item list (no prices; per-item weights on 80-col)
    .const HM_SHOW_ROW_WEIGHTS = (SCREEN_COLS >= 80) ? 1 : 0
#if ITEMDESC_STORE_SLOT_DUPLICATED
    :StoreDrawSlotListBody(hm_store_slot, hm_row, hm_save_x, home_put_letter, itemdesc_put_store_slot_home, HM_SHOW_ROW_WEIGHTS, home_put_slot_weight)
#else
    :StoreDrawSlotListBody(hm_store_slot, hm_row, hm_save_x, home_put_letter, itemdesc_put_store_slot, HM_SHOW_ROW_WEIGHTS, home_put_slot_weight)
#endif

    // Row 19: Home menu, then the gold to its right
    lda #STORE_MENU_ROW
    ldx #<hm_menu_str
    ldy #>hm_menu_str
    jsr home_put_white_col1

    lda #COL_YELLOW
    sta zp_text_color
    lda #STORE_MENU_ROW
    sta zp_cursor_row
    lda #HOME_GOLD_COL
    sta zp_cursor_col
    lda #<hm_gold_str
    sta zp_ptr0
    lda #>hm_gold_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    :StorePutGoldValueBody()

home_put_slot_weight:
.if (SCREEN_COLS >= 80) {
    lda hm_row
    sta zp_cursor_row
    ldy hm_store_slot
    :AuxReadY(si_qty)
    sta iw_qty
    :AuxReadY(si_meta_hi)
    sta iw_mc_2
    :AuxReadY(si_item_id)
    jsr inven_mul_ego_a
    jmp uwt_hm_put_col69
}

home_draw_separator_at_a:
    sta zp_cursor_row
    :StoreDrawSeparatorBody()

home_clear_msg_area:
    :StoreClearMsgAreaBody()

home_find_empty_slot:
    :StoreFindEmptySlotBody(hm_save_x)

#if ITEMDESC_STORE_SLOT_DUPLICATED
#import "itemdesc_store_slot_macro.s"
itemdesc_put_store_slot_home:
    :ItemdescPutStoreSlotBody()
#endif
#endif

// ============================================================
// home_enter — Main home mode loop
// Input: zp_store_idx = STORE_HOME (7)
// Clobbers: everything
// ============================================================
home_enter:
#if HOME_OVERLAY_SEPARATE
    jsr home_draw_screen
#else
    jsr store_draw_screen       // Reuses overlay's draw (skips prices for home)
    lda #1
    ldx #1
    jsr uwt_hm_draw_burden_header

    // Overwrite the store menu with the home menu (the gold stays beside it)
    lda #COL_WHITE
    sta zp_text_color
    lda #STORE_MENU_ROW
    ldx #<hm_menu_str
    ldy #>hm_menu_str
    jsr home_put_col1_string
#endif

!he_loop:
    jsr hal_input_get_key

    // D = deposit
    cmp #PETSCII_HM_D
    bne !he_not_dep+
    jsr home_deposit
    jmp home_enter              // Refresh screen
!he_not_dep:

    // R = retrieve
    cmp #PETSCII_HM_R
    bne !he_not_ret+
    jsr home_retrieve
    jmp home_enter              // Refresh screen
!he_not_ret:

    // Q, ESC, or space = exit
    jsr hm_is_cancel_key
    beq !he_exit+

    // Unknown key — ignore
    jmp !he_loop-

!he_exit:
    lda #COL_BLACK
    sta zp_text_color
    jmp ui_help_clear_all

// ============================================================
// home_retrieve — Take an item from home
// ============================================================
home_retrieve:
    // Prompt on row 20
#if HOME_OVERLAY_SEPARATE
    jsr home_clear_msg_area
#else
    jsr store_clear_msg_area
#endif
    lda #20
    ldx #<hm_retrieve_str
    ldy #>hm_retrieve_str
    jsr home_put_white_col1

    lda #STORE_MAX_ITEMS
    jsr hm_prompt_slot_key
    bcs !hr_valid_slot+
    rts

!hr_valid_slot:
    // Compute absolute slot = store_base_idx[zp_store_idx] + key_offset
    ldx zp_store_idx
    clc
    adc store_base_idx,x
    sta hm_store_slot

    // Check if slot occupied
    tax
    :AuxReadX(si_item_id)
    cmp #FI_EMPTY
    bne !hr_slot_occupied+
    rts                         // Empty slot
!hr_slot_occupied:

    // Copy item from store to inventory: a full pack still takes one that
    // stacks (VMS inven_check_num, Umoria inventoryCanCarryItemCount)
    sta fi_add_id               // A = item_id, X = hm_store_slot
    :AuxReadX(si_qty)
    sta fi_add_qty
    :AuxReadX(si_p1)
    sta fi_add_p1
    :AuxReadX(si_to_hit)
    sta fi_add_to_hit
    :AuxReadX(si_to_dam)
    sta fi_add_to_dam
    :AuxReadX(si_to_ac)
    sta fi_add_to_ac
    :LoadStoreFlagsX()
    sta fi_add_flags
    :LoadStoreMetaHiX()
    sta fi_add_ego
#if HOME_OVERLAY_SEPARATE && HAL_PLATFORM_INV_ADD_CARRIED_EXTERNAL
    jsr home_inv_add_carried        // the weight limit, then a slot
#else
    jsr inv_add_carried             // the weight limit, then a slot
#endif
    bcs !hr_has_room+

    // Inventory full, or too heavy (X = the refusal)
    cpx #HSTR_UIS_TOO_HEAVY
    bne !hr_full+
    jsr huff_decode_string          // "You can't carry that much weight."
    ldx zp_ptr0
    ldy zp_ptr0_hi
    bne !hr_refusal+                // always: the buffer is not in page zero
!hr_full:
    ldx #<hm_inv_full_str
    ldy #>hm_inv_full_str
!hr_refusal:
    jmp hm_show_red_row22_wait

!hr_has_room:
    // Clear store slot
    ldx hm_store_slot
    lda #FI_EMPTY
    :AuxWriteX(si_item_id)
    lda #0
    :AuxWriteX(si_qty)
    :AuxWriteX(si_p1)
    :AuxWriteX(si_to_hit)
    :AuxWriteX(si_to_dam)
    :AuxWriteX(si_to_ac)
    :AuxWriteX(si_meta)
    :AuxWriteX(si_meta_hi)

    // Success message
    ldx #<hm_retrieved_str
    ldy #>hm_retrieved_str
    jmp hm_show_ok_row22_sfx

// ============================================================
// home_deposit — Store an item from inventory into home
// ============================================================
home_deposit:
    // Draw inventory list
    ldx #<hm_deposit_title
    ldy #>hm_deposit_title
    jsr hm_clear_and_title
.if (SCREEN_COLS >= 80) {
    lda #0
    ldx #55
    jsr uwt_hm_draw_burden_header
}

    // List inventory items (row 1 is unused, so start at row 1 to keep slot 21 above row 23 prompt)
    lda #1
    sta hm_row
    lda #0
    sta hm_save_x              // Slot counter

!hd_inv_loop:
    lda hm_save_x
    cmp #MAX_INV_SLOTS
    bcs !hd_inv_done+

    // Check if slot occupied
    tax
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !hd_inv_next+

    lda hm_row
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col

    lda #COL_LGREY
    sta zp_text_color

    // Letter
    jsr home_put_letter
    lda #$20                    // Space
    jsr hal_screen_put_char

    // Item description with ego/status/stat suffixes
    ldx hm_save_x
    jsr itemdesc_put_inv_slot
.if (SCREEN_COLS >= 80) {
    lda hm_row
    sta zp_cursor_row
    ldx hm_save_x
    lda inv_qty,x
    jsr inven_mul_slot_x
    jsr uwt_hm_put_col69
}

    inc hm_row

!hd_inv_next:
    inc hm_save_x
    jmp !hd_inv_loop-

!hd_inv_done:
    // Prompt
    lda #23
    ldx #<hm_which_str
    ldy #>hm_which_str
    jsr home_put_white_col1

    lda #MAX_INV_SLOTS
    jsr hm_prompt_slot_key
    bcs !hd_valid_slot+
    rts

!hd_valid_slot:
    sta hm_inv_slot

    // Check slot occupied
    tax
    lda inv_item_id,x
    cmp #FI_EMPTY
    bne !hd_slot_occupied+
    jmp !hd_cancel+
!hd_slot_occupied:

    // Find empty home slot
#if HOME_OVERLAY_SEPARATE
    jsr home_find_empty_slot
#else
    jsr store_find_empty_slot
#endif
    bcs !hd_has_slot+

    // Home full
    ldx #<hm_home_full_str
    ldy #>hm_home_full_str
hm_show_red_row22_wait:
    lda #COL_RED
    sta zp_text_color
    lda #22
    jsr home_put_col1_string
    jmp hal_input_get_key           // Wait, tail call

!hd_has_slot:
    // X = empty absolute slot
    stx hm_store_slot
    // Transfer item from inventory to home
    ldx hm_inv_slot
    lda inv_item_id,x
    ldy hm_store_slot
    :AuxWriteY(si_item_id)
    lda inv_qty,x
    :AuxWriteY(si_qty)
    lda inv_p1,x
    :AuxWriteY(si_p1)
    lda inv_to_hit,x
    :AuxWriteY(si_to_hit)
    lda inv_to_dam,x
    :AuxWriteY(si_to_dam)
    lda inv_to_ac,x
    :AuxWriteY(si_to_ac)
    :StoreStoreMetaYFromInvX()

    // Remove from inventory
    ldx hm_inv_slot
    jsr inv_remove_item

    // Success message
    ldx #<hm_deposited_str
    ldy #>hm_deposited_str
hm_show_ok_row22_sfx:
    lda #COL_LGREEN
    sta zp_text_color
    lda #22
    jsr home_put_col1_string

    lda #SFX_PICKUP
    jmp hal_sound_play
!hd_cancel:
    rts

hm_prompt_slot_key:
    sta zp_temp4
    jsr input_prepare_followup_key
    jsr hal_input_get_key
    jsr hm_is_cancel_key
    beq !hpsk_cancel+
    sec
    sbc #PETSCII_HM_A
    bcc !hpsk_cancel+
    cmp zp_temp4
    bcs !hpsk_cancel+
    sec
    rts
!hpsk_cancel:
    clc
    rts

hm_is_cancel_key:
    cmp #PETSCII_HM_Q
    beq !hik_yes+
    jsr input_is_modal_escape_key
    beq !hik_yes+
    cmp #PETSCII_HM_SPACE
!hik_yes:
    rts

uwt_hm_draw_burden_header:
    :UiWeightDrawBurdenHeaderBody(uwt_hm_put_tenths, uwt_hm_burden_str, uwt_hm_lb_str)
uwt_hm_put_tenths:
    :UiWeightPutTenthsBody()
uwt_hm_put_tenths_from_buf:
    :UiWeightPutTenthsFromBufBody()
uwt_hm_put_col69:
.if (SCREEN_COLS >= 80) {
    :UiWeightPutCol69Body(uwt_hm_put_tenths_from_buf, uwt_hm_lb_str)
}
uwt_hm_burden_str: .text "Burden: " ; .byte 0
uwt_hm_lb_str:     .text " lb" ; .byte 0
