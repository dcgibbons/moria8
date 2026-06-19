#importonce
// royal.s — Winner retirement art overlay.

.const ROYAL_COL_BASE = (SCREEN_COLS - 40) / 2

royal_screen:
    lda #COL_BLACK
    sta zp_text_color
    jsr ui_clear_full_screen_safe

    lda #COL_YELLOW
    sta zp_text_color
    lda #2
    ldx #<royal_crown_0
    ldy #>royal_crown_0
    jsr royal_put_line
    lda #3
    ldx #<royal_crown_1
    ldy #>royal_crown_1
    jsr royal_put_line
    lda #4
    ldx #<royal_crown_2
    ldy #>royal_crown_2
    jsr royal_put_line
    lda #5
    ldx #<royal_crown_3
    ldy #>royal_crown_3
    jsr royal_put_line
    lda #6
    ldx #<royal_crown_4
    ldy #>royal_crown_4
    jsr royal_put_line
    lda #7
    ldx #<royal_crown_5
    ldy #>royal_crown_5
    jsr royal_put_line
    lda #8
    ldx #<royal_crown_6
    ldy #>royal_crown_6
    jsr royal_put_line

    lda #COL_WHITE
    sta zp_text_color
    lda #12
    ldx #<royal_vvv
    ldy #>royal_vvv
    jsr royal_put_line
    lda #14
    ldx #<royal_hail
    ldy #>royal_hail
    jsr royal_put_line
    lda #16
    ldx #<royal_title
    ldy #>royal_title
    jsr royal_put_line
    lda #17
    sta zp_cursor_row
    lda #ROYAL_COL_BASE + 12
    sta zp_cursor_col
    lda #COL_WHITE
    sta zp_text_color
    lda #<player_data + PL_NAME
    sta zp_ptr0
    lda #>player_data + PL_NAME
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    lda #COL_LGREY
    sta zp_text_color
    lda #23
    ldx #<royal_press
    ldy #>royal_press
    jsr royal_put_line
    jmp input_get_modal_dismiss_key

royal_put_line:
    sta zp_cursor_row
    lda #ROYAL_COL_BASE
    sta zp_cursor_col
    stx zp_ptr0
    sty zp_ptr0_hi
    jmp hal_screen_put_string

royal_crown_0: .text "                 #                  " ; .byte 0
royal_crown_1: .text "               #####                " ; .byte 0
royal_crown_2: .text "                 #                  " ; .byte 0
royal_crown_3: .text "           ,,,  $$$  ,,,            " ; .byte 0
royal_crown_4: .text "        ,,=$   $$$$$   $=,,         " ; .byte 0
royal_crown_5: .text "       $$      $$$$$      $$        " ; .byte 0
royal_crown_6: .text "        *#######*#######*           " ; .byte 0
royal_vvv:     .text "          Veni, Vidi, Vici!         " ; .byte 0
royal_hail:    .text "      I came, I saw, I conquered!   " ; .byte 0
royal_title:   .text "          All Hail the Mighty       " ; .byte 0
royal_press:   .text "             Press any key          " ; .byte 0
