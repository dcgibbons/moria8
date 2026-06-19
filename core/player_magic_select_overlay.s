// player_magic_select_overlay.s — spell/prayer selection UI for the overlay

pm_header_str:
    .text "   Name              Mana Lvl" ; .byte 0
pm_footer_cast_prefix:
    .text "Cast which? (a-" ; .byte 0
pm_footer_pray_prefix:
    .text "Pray which? (a-" ; .byte 0
pm_footer_learn_prefix:
    .text "Learn which? (a-" ; .byte 0
pm_footer_suffix:
    .text ", esc)" ; .byte 0
pm_title_mage_str:
    .text "Mage Book" ; .byte 0
pm_title_prayer_str:
    .text "Prayer Book" ; .byte 0
pm_title_learn_str:
    .text "Study" ; .byte 0

spell_list_display:
    lda #COL_WHITE
    sta zp_text_color
    jsr ui_help_clear_all

    lda #0
    sta zp_cursor_row
    lda #14
    sta zp_cursor_col
    lda pm_mode
    beq !sld_not_learn+
    lda #<pm_title_learn_str
    sta zp_ptr0
    lda #>pm_title_learn_str
    sta zp_ptr0_hi
    jmp !sld_title_ready+
!sld_not_learn:
    lda pm_spell_type
    cmp #SPELL_MAGE
    bne !sld_pray_title+
    lda #<pm_title_mage_str
    sta zp_ptr0
    lda #>pm_title_mage_str
    sta zp_ptr0_hi
    jmp !sld_title_ready+
!sld_pray_title:
    lda #<pm_title_prayer_str
    sta zp_ptr0
    lda #>pm_title_prayer_str
    sta zp_ptr0_hi
!sld_title_ready:
    jsr hal_screen_put_string

    lda #COL_LGREY
    sta zp_text_color
    lda #1
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<pm_header_str
    sta zp_ptr0
    lda #>pm_header_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    lda #0
    sta pm_row_counter
!sld_loop:
    lda pm_row_counter
    cmp pm_spell_count
    bcc !sld_show+
    jmp !sld_done+
!sld_show:
    tay
    lda pm_spell_list,y
    sta pm_spell_idx

    lda pm_row_counter
    clc
    adc #2
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col

    lda pm_mana_tbl_lo
    sta zp_ptr0
    lda pm_mana_tbl_hi
    sta zp_ptr0_hi
    ldy pm_spell_idx
    lda (zp_ptr0),y
    sta pm_cost_tmp
    cmp zp_player_mp
    beq !sld_affordable+
    bcc !sld_affordable+
    lda #COL_DGREY
    sta zp_text_color
    jmp !sld_print+
!sld_affordable:
    lda #COL_LGREY
    sta zp_text_color

!sld_print:
    lda pm_row_counter
    clc
    adc #$01
    jsr hal_screen_put_char
    lda #$29
    jsr hal_screen_put_char
    lda #$20
    jsr hal_screen_put_char

    lda pm_name_lo_lo
    sta zp_ptr0
    lda pm_name_lo_hi
    sta zp_ptr0_hi
    ldy pm_spell_idx
    lda (zp_ptr0),y
    sta zp_ptr2
    lda pm_name_hi_lo
    sta zp_ptr0
    lda pm_name_hi_hi
    sta zp_ptr0_hi
    ldy pm_spell_idx
    lda (zp_ptr0),y
    sta zp_ptr2_hi
    lda zp_ptr2
    sta zp_ptr0
    lda zp_ptr2_hi
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    lda #30
    sta zp_cursor_col
    lda pm_cost_tmp
    jsr screen_put_decimal_rj2

    lda #35
    sta zp_cursor_col
    lda pm_lvl_tbl_lo
    sta zp_ptr0
    lda pm_lvl_tbl_hi
    sta zp_ptr0_hi
    ldy pm_spell_idx
    lda (zp_ptr0),y
    jsr screen_put_decimal_rj2

    inc pm_row_counter
    jmp !sld_loop-

!sld_done:
    lda #COL_WHITE
    sta zp_text_color
    lda #24
    sta zp_cursor_row
    lda #5
    sta zp_cursor_col
    lda pm_mode
    beq !sld_not_learn_footer+
    lda #<pm_footer_learn_prefix
    sta zp_ptr0
    lda #>pm_footer_learn_prefix
    sta zp_ptr0_hi
    jmp !sld_footer_prefix+
!sld_not_learn_footer:
    lda pm_spell_type
    cmp #SPELL_MAGE
    bne !sld_pray_footer+
    lda #<pm_footer_cast_prefix
    sta zp_ptr0
    lda #>pm_footer_cast_prefix
    sta zp_ptr0_hi
    jmp !sld_footer_prefix+
!sld_pray_footer:
    lda #<pm_footer_pray_prefix
    sta zp_ptr0
    lda #>pm_footer_pray_prefix
    sta zp_ptr0_hi
!sld_footer_prefix:
    jsr hal_screen_put_string

    lda pm_spell_count
    sec
    sbc #1
    clc
    adc #$01
    jsr hal_screen_put_char

    lda #<pm_footer_suffix
    sta zp_ptr0
    lda #>pm_footer_suffix
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    rts
