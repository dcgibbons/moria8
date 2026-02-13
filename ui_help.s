// ui_help.s — Help screen (command reference)
//
// Displays all available key bindings on a full screen.
// Called via '?' key (CMD_HELP).
//
// Layout (40 columns, 25 rows):
//   Row 0:  COMMAND REFERENCE
//   Rows 2-22: Two-column key listing
//   Row 24: PRESS ANY KEY

// ============================================================
// Constants
// ============================================================
.const HELP_LINE_COUNT = 22

// ============================================================
// Subroutines
// ============================================================

// ui_help_clear_all — Clear all 25 rows using screen_clear_row
// Uses indirect addressing per row (via screen_row_lo/hi tables).
// Input: zp_text_color must be set to desired clear color
// Clobbers: A, X, Y, zp_screen_lo/hi, zp_color_lo/hi
ui_help_clear_all:
    lda #0
    sta help_line_idx
!hca_loop:
    lda help_line_idx
    jsr screen_clear_row
    inc help_line_idx
    lda help_line_idx
    cmp #SCREEN_ROWS
    bcc !hca_loop-
    rts

// ui_help_display — Show help screen
// Preserves: nothing
ui_help_display:
    // Clear entire screen row by row
    lda #COL_WHITE
    sta zp_text_color
    jsr ui_help_clear_all

    // Title
    lda #0
    sta zp_cursor_row
    lda #11
    sta zp_cursor_col
    lda #<help_title_str
    sta zp_ptr0
    lda #>help_title_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // Draw help lines
    lda #COL_LGREY
    sta zp_text_color

    lda #0
    sta help_line_idx

!help_loop:
    ldx help_line_idx
    cpx #HELP_LINE_COUNT
    bcs !help_done+

    // Load string pointer from table
    lda help_line_ptrs_lo,x
    sta zp_ptr0
    lda help_line_ptrs_hi,x
    sta zp_ptr0_hi

    // Row = line_idx + 2
    txa
    clc
    adc #2
    sta zp_cursor_row
    lda #0
    sta zp_cursor_col
    jsr screen_put_string

    inc help_line_idx
    jmp !help_loop-

!help_done:
    // Footer
    lda #COL_WHITE
    sta zp_text_color
    lda #24
    sta zp_cursor_row
    lda #12
    sta zp_cursor_col
    lda #<help_footer_str
    sta zp_ptr0
    lda #>help_footer_str
    sta zp_ptr0_hi
    jsr screen_put_string

    rts

// ============================================================
// Scratch
// ============================================================
help_line_idx: .byte 0

// ============================================================
// String data
// ============================================================
help_title_str:
    .text "COMMAND REFERENCE" ; .byte 0

help_footer_str:
    .text "PRESS ANY KEY" ; .byte 0

// Help lines — two-column layout
// Left column: movement/nav, Right column: actions
help_l0:  .text "MOVEMENT         ACTIONS" ; .byte 0
help_l1:  .text "H LEFT  L RIGHT  O OPEN DOOR" ; .byte 0
help_l2:  .text "K UP    J DOWN   C CLOSE DOOR" ; .byte 0
help_l3:  .text "Y NW    U NE     S SEARCH" ; .byte 0
help_l4:  .text "B SW    N SE     . REST" ; .byte 0
help_l5:  .text "CURSORS ALSO WORK" ; .byte 0
help_l6:  .text "                 > GO DOWN STAIRS" ; .byte 0
help_l7:  .text "RUNNING          < GO UP STAIRS" ; .byte 0
help_l8:  .text "SHIFT+DIRECTION" ; .byte 0
help_l9:  .text "                 INFORMATION" ; .byte 0
help_l10: .text "COMMANDS         SHIFT+C CHARACTER" ; .byte 0
help_l11: .text "G GET ITEM       X LOOK" ; .byte 0
help_l12: .text "D DROP ITEM      ? THIS HELP" ; .byte 0
help_l13: .text "I INVENTORY      COMBAT" ; .byte 0
help_l14: .text "E EQUIPMENT      WALK INTO MONSTER" ; .byte 0
help_l15: .text "W WEAR/WIELD     SHIFT+E EAT FOOD" ; .byte 0
help_l16: .text "T TAKE OFF       OTHER" ; .byte 0
help_l17: .text "Q QUAFF POTION   SHIFT+S SAVE" ; .byte 0
help_l18: .text "R READ SCROLL    SHIFT+Q QUIT" ; .byte 0
help_l19: .text "A AIM WAND       P PRAY" ; .byte 0
help_l20: .text "Z USE STAFF" ; .byte 0
help_l21: .text "M CAST SPELL     F STUDY BOOK" ; .byte 0

// Pointer tables (lo/hi split)
help_line_ptrs_lo:
    .byte <help_l0,  <help_l1,  <help_l2,  <help_l3,  <help_l4
    .byte <help_l5,  <help_l6,  <help_l7,  <help_l8,  <help_l9
    .byte <help_l10, <help_l11, <help_l12, <help_l13, <help_l14
    .byte <help_l15, <help_l16, <help_l17, <help_l18, <help_l19
    .byte <help_l20, <help_l21

help_line_ptrs_hi:
    .byte >help_l0,  >help_l1,  >help_l2,  >help_l3,  >help_l4
    .byte >help_l5,  >help_l6,  >help_l7,  >help_l8,  >help_l9
    .byte >help_l10, >help_l11, >help_l12, >help_l13, >help_l14
    .byte >help_l15, >help_l16, >help_l17, >help_l18, >help_l19
    .byte >help_l20, >help_l21
