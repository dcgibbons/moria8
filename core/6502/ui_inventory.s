#importonce
// ui_inventory.s — Inventory display screen
//
// Full-screen inventory view.
// CMD_INVENTORY shows carried items (slots 0-21).

#import "ui_weight_helpers.s"

.const UINV_TITLE_COL = hal_layout_inventory_title_col
.const UINV_FOOTER_COL = hal_layout_inventory_footer_col
.const UINV_SELECT_COL = hal_layout_inventory_select_col
.const UINV_IDENTIFY_COL = hal_layout_inventory_identify_col

// ============================================================
// Subroutines
// ============================================================

// ui_inv_display — Show carried inventory (slots 0-21) with dismiss footer.
// Preserves: nothing
ui_inv_display:
    lda #UINV_FOOTER_COL
    ldx #<press_key_str
    ldy #>press_key_str
    bne ui_inv_display_common

// ui_inv_select_display — Show carried inventory with direct-selection footer.
// Used by prompt-time `?` overlays that should allow an item letter directly
// from the inventory screen.
// Preserves: nothing
ui_inv_select_display:
    lda piw_filter
    cmp #$fd
    beq !uinv_identify_select+
    lda #UINV_SELECT_COL
    ldx #<uinv_select_str
    ldy #>uinv_select_str
    bne ui_inv_display_common
!uinv_identify_select:
    lda #UINV_IDENTIFY_COL
    ldx #<uinv_identify_footer_str
    ldy #>uinv_identify_footer_str
    bne ui_inv_display_common

ui_inv_display_common:
    sta uinv_footer_col
    stx uinv_footer_lo
    sty uinv_footer_hi
    lda #COL_WHITE
    sta zp_text_color
    jsr ui_help_clear_all

    // Title
    lda #0
    sta zp_cursor_row
    lda #UINV_TITLE_COL
    sta zp_cursor_col
    lda #<uinv_title_str
    ldy #>uinv_title_str
    jsr screen_put_string_ay

.if (SCREEN_COLS >= 80 && SCREEN_ROWS < 25) {
    lda #0
    ldx #55
    jsr uwt_shared_draw_burden_header

    // Count matching items; 24-row screens omit the row-1 separator when all 22 rows are used.
    lda #0
    sta uinv_slot
    sta uinv_visible
!uinv_cnt_loop:
    ldx uinv_slot
    cpx #MAX_INV_SLOTS
    bcs !uinv_cnt_done+
    jsr piw_inv_slot_matches_filter
    bcc !uinv_cnt_next+
    inc uinv_visible
!uinv_cnt_next:
    inc uinv_slot
    bne !uinv_cnt_loop-
!uinv_cnt_done:
    lda uinv_visible
    cmp #MAX_INV_SLOTS
    bcc !uinv_draw_sep+
    lda #1
    bne !uinv_row_set+
!uinv_draw_sep:
    lda #1
    sta zp_cursor_row
    lda #UINV_TITLE_COL
    sta zp_cursor_col
    lda #<uinv_sep_str
    ldy #>uinv_sep_str
    jsr screen_put_string_ay
    lda #2
!uinv_row_set:
    sta uinv_row
} else {
.if (SCREEN_COLS >= 80) {
    lda #0
    ldx #55
    jsr uwt_shared_draw_burden_header

    // Separator
    lda #1
    sta zp_cursor_row
    lda #UINV_TITLE_COL
    sta zp_cursor_col
    lda #<uinv_sep_str
    ldy #>uinv_sep_str
    jsr screen_put_string_ay
} else {
    lda #1
    ldx #9
    jsr uwt_inv_draw_burden_header
}
    lda #2                      // Start at row 2
    sta uinv_row
}

    lda #COL_LGREY
    sta zp_text_color

    // Iterate carried slots 0-21
    lda #0
    sta uinv_slot
    sta uinv_any                // Track if any items shown
    sta uinv_visible            // Visible ordinal for filtered relabeling
!uinv_loop:
    lda uinv_slot
    cmp #MAX_INV_SLOTS
    bcs !uinv_loop_done+

    ldx uinv_slot
    jsr piw_inv_slot_matches_filter
    bcc !uinv_next+
!uinv_show:
    // Print letter and item name
    lda uinv_row
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col

    // Carried pack letters follow the current visible order.
    lda uinv_visible
    clc
    adc #$01                    // Screen code 'A'
    jsr hal_screen_put_char
    inc uinv_visible

    // ") "
    lda #$29                    // Screen code ')'
    jsr hal_screen_put_char
    lda #$20                    // Space
    jsr hal_screen_put_char

    // Item description with ego/status/stat suffixes
    ldx uinv_slot
    jsr itemdesc_put_inv_slot

.if (SCREEN_COLS >= 80) {
    lda uinv_row
    sta zp_cursor_row
    ldx uinv_slot
    lda inv_qty,x
    jsr inven_mul_slot_x
    jsr uwt_shared_put_col69
}

    inc uinv_row
    lda #1
    sta uinv_any

!uinv_next:
    inc uinv_slot
    jmp !uinv_loop-

!uinv_loop_done:
    // If no items, show "YOU HAVE NOTHING."
    lda uinv_any
    bne !uinv_footer+

    lda #2
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<uinv_nothing_str
    ldy #>uinv_nothing_str
    jsr screen_put_string_ay

!uinv_footer:
    lda #COL_WHITE
    sta zp_text_color
    lda piw_filter
    cmp #$fd
    bne !uinv_footer_ready+
    lda uinv_visible
    bne !uinv_footer_have_count+
    lda #1
!uinv_footer_have_count:
    // Screen-code mixed lowercase letters are 1-based: 1 -> 'a', 7 -> 'g'.
    sta uinv_identify_footer_last
!uinv_footer_ready:
    lda #(SCREEN_ROWS - 1)
    sta zp_cursor_row
    lda uinv_footer_col
    sta zp_cursor_col
    lda uinv_footer_lo
    sta zp_ptr0
    lda uinv_footer_hi
    sta zp_ptr0_hi
    jmp hal_screen_put_string              // tail call


uwt_shared_draw_burden_header:
.if (SCREEN_COLS >= 80) {
    :UiWeightDrawBurdenHeaderBody(uwt_shared_put_tenths, uwt_inv_burden_str, uwt_inv_lb_str)
}
uwt_shared_put_tenths:
.if (SCREEN_COLS >= 80) {
    :UiWeightPutTenthsBody()
}
uwt_shared_put_tenths_from_buf:
.if (SCREEN_COLS >= 80) {
    :UiWeightPutTenthsFromBufBody()
}
uwt_shared_put_col69:
.if (SCREEN_COLS >= 80) {
    :UiWeightPutCol69Body(uwt_shared_put_tenths_from_buf, uwt_inv_lb_str)
}
uwt_inv_draw_burden_header:
.if (SCREEN_COLS < 80) {
    :UiWeightDrawBurdenHeaderBody(uwt_inv_put_tenths, uwt_inv_burden_str, uwt_inv_lb_str)
}
uwt_inv_put_tenths:
.if (SCREEN_COLS < 80) {
    :UiWeightPutTenthsBody()
}
uwt_inv_put_tenths_from_buf:
.if (SCREEN_COLS < 80) {
    :UiWeightPutTenthsFromBufBody()
}

// ============================================================
// Scratch
// ============================================================
#if UI_INVENTORY_SCRATCH_RESIDENT
    :UiInventoryScratchSegment()
#endif
uinv_slot:    .byte 0
uinv_row:     .byte 0
uinv_any:     .byte 0
uinv_visible: .byte 0
uinv_footer_col: .byte 0
uinv_footer_lo:  .byte 0
uinv_footer_hi:  .byte 0
#if UI_INVENTORY_SCRATCH_RESIDENT
    :UiInventoryCodeSegment()
#endif

// ============================================================
// String data (screen codes via inherited encoding)
// ============================================================
#if !UI_INVENTORY_HEADER_STRINGS_EXTERNAL
uinv_title_str:   .text "Inventory" ; .byte 0
uinv_sep_str:
.if (SCREEN_COLS >= 80) {
    .text "---------" ; .byte 0
}
#endif
uwt_inv_burden_str: .text "Burden: " ; .byte 0
uwt_inv_lb_str:     .text " lb" ; .byte 0
uinv_nothing_str: .text "Nothing." ; .byte 0
uinv_select_str:  .text "Select item" ; .byte 0
uinv_identify_footer_str:  .text "Identify which item (a-"
uinv_identify_footer_last: .text "a"
                          .text ")?" ; .byte 0
