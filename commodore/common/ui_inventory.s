#importonce
// ui_inventory.s — Inventory display screen
//
// Full-screen inventory view.
// CMD_INVENTORY shows carried items (slots 0-21).

#if C128
.const UINV_TITLE_COL = (SCREEN_COLS - 9) / 2
.const UINV_FOOTER_COL = (SCREEN_COLS - 13) / 2
#else
.const UINV_TITLE_COL = 15
.const UINV_FOOTER_COL = 12
#endif

// ============================================================
// Subroutines
// ============================================================

// ui_inv_display — Show carried inventory (slots 0-21)
// Lists occupied slots as A) ITEM_NAME, B) ITEM_NAME, etc.
// Preserves: nothing
ui_inv_display:
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
    lda uinv_filter
    sta piw_filter

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
    lda uinv_filter
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
    lda #24
    sta zp_cursor_row
    lda #UINV_FOOTER_COL
    sta zp_cursor_col
    lda #<press_key_str
    sta zp_ptr0
    lda #>press_key_str
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
uinv_filter:  .byte $ff       // $FF=all, $FE=wearable, 0-15=exact ICAT match

// ============================================================
// String data (screen codes via inherited encoding)
// ============================================================
uinv_title_str:   .text "Inventory" ; .byte 0
uinv_sep_str:     .text "---------" ; .byte 0
uinv_nothing_str: .text "Nothing." ; .byte 0
