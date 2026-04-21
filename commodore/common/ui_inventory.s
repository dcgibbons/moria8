#importonce
// ui_inventory.s — Inventory display screen
//
// Full-screen inventory view.
// CMD_INVENTORY shows carried items (slots 0-21).

#if C128
.const UINV_TITLE_COL = (SCREEN_COLS - 9) / 2
.const UINV_FOOTER_COL = (SCREEN_COLS - 13) / 2
.const UINV_SELECT_COL = (SCREEN_COLS - 11) / 2
.const UINV_IDENTIFY_COL = (SCREEN_COLS - 26) / 2
#else
.const UINV_TITLE_COL = 15
.const UINV_FOOTER_COL = 12
.const UINV_SELECT_COL = 14
.const UINV_IDENTIFY_COL = 7
#endif

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
    jsr piw_build_visible_inv_cache
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
    sta zp_ptr0
    lda #>uinv_title_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // Separator
    lda #1
    sta zp_cursor_row
    lda #UINV_TITLE_COL
    sta zp_cursor_col
    lda #<uinv_sep_str
    sta zp_ptr0
    lda #>uinv_sep_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #COL_LGREY
    sta zp_text_color

    // Iterate carried slots 0-21
    lda #0
    sta uinv_slot
    lda #2                      // Start at row 2
    sta uinv_row
    lda #0
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

    // Unfiltered inventory keeps absolute slot letters; filtered views are
    // relabeled contiguously so prompt/parser/overlay stay aligned.
    lda piw_filter
    cmp #$ff
    bne !uinv_filtered_letter+
    lda uinv_slot
    clc
    adc #$01                    // Screen code 'A'
    jsr screen_put_char
    jmp !uinv_letter_done+
!uinv_filtered_letter:
    lda uinv_visible
    clc
    adc #$01                    // Screen code 'A'
    jsr screen_put_char
    inc uinv_visible
!uinv_letter_done:

    // ") "
    lda #$29                    // Screen code ')'
    jsr screen_put_char
    lda #$20                    // Space
    jsr screen_put_char

    // Item name with ego prefix/suffix (R14)
    ldx uinv_slot
    jsr put_inv_name_with_ego

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
    sta zp_ptr0
    lda #>uinv_nothing_str
    sta zp_ptr0_hi
    jsr screen_put_string

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
    clc
    adc #$60                    // 1 -> 'a', 7 -> 'g'
    sta uinv_identify_footer_last
!uinv_footer_ready:
    lda #24
    sta zp_cursor_row
    lda uinv_footer_col
    sta zp_cursor_col
    lda uinv_footer_lo
    sta zp_ptr0
    lda uinv_footer_hi
    sta zp_ptr0_hi
    jsr screen_put_string

    rts

// ============================================================
// Scratch
// ============================================================
uinv_slot:    .byte 0
uinv_row:     .byte 0
uinv_any:     .byte 0
uinv_visible: .byte 0
uinv_footer_col: .byte 0
uinv_footer_lo:  .byte 0
uinv_footer_hi:  .byte 0

// ============================================================
// String data (screen codes via inherited encoding)
// ============================================================
uinv_title_str:   .text "Inventory" ; .byte 0
uinv_sep_str:     .text "---------" ; .byte 0
uinv_nothing_str: .text "Nothing." ; .byte 0
uinv_select_str:  .text "Select item" ; .byte 0
uinv_identify_footer_str:  .text "Identify which item (a-"
uinv_identify_footer_last: .text "a"
                          .text ")?" ; .byte 0
