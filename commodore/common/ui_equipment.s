#importonce
// ui_equipment.s — Equipment display screen
//
// Full-screen equipment view for slots 22-29.

#if C128
.const UEQ_TITLE_COL = (SCREEN_COLS - 9) / 2
.const UEQ_FOOTER_COL = (SCREEN_COLS - 13) / 2
#else
.const UEQ_TITLE_COL = 15
.const UEQ_FOOTER_COL = 12
#endif

// ui_equip_display — Show equipped items (slots 22-29)
// 8 slots: WEAPON, BODY, SHIELD, HEAD, HANDS, FEET, LIGHT, RING
// Preserves: nothing
ui_equip_display:
    lda #COL_WHITE
    sta zp_text_color
    jsr ui_help_clear_all

    // Title
    lda #0
    sta zp_cursor_row
    lda #UEQ_TITLE_COL
    sta zp_cursor_col
    lda #<ueq_title_str
    sta zp_ptr0
    lda #>ueq_title_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // Separator
    lda #1
    sta zp_cursor_row
    lda #UEQ_TITLE_COL
    sta zp_cursor_col
    lda #<ueq_sep_str
    sta zp_ptr0
    lda #>ueq_sep_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // Iterate 8 equipment slots
    lda #0
    sta ueq_slot               // 0-7 (maps to inv slot 22-29)
    sta ueq_visible            // Visible ordinal for non-empty selection rows

!ueq_loop:
    lda ueq_slot
    cmp #MAX_EQUIP_SLOTS
    bcc !ueq_cont+
    jmp !ueq_done+
!ueq_cont:

    // Row = slot + 2
    clc
    adc #2
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col

    lda ueq_slot
    clc
    adc #EQUIP_WEAPON          // Map 0-7 -> 22-29
    sta ueq_equip_idx
    tax
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !ueq_empty_prefix+

    lda #COL_LGREY
    sta zp_text_color
    lda ueq_visible
    clc
    adc #$01                   // Screen code 'A'
    jsr screen_put_char
    lda #$29                   // ')'
    jsr screen_put_char
    lda #$20                   // space
    jsr screen_put_char
    inc ueq_visible
    jmp !ueq_prefix_done+

!ueq_empty_prefix:
    lda #4
    sta zp_cursor_col

!ueq_prefix_done:
    // Print slot label
    lda #COL_LGREY
    sta zp_text_color
    ldx ueq_slot
    lda ueq_label_ptrs_lo,x
    sta zp_ptr0
    lda ueq_label_ptrs_hi,x
    sta zp_ptr0_hi
    jsr screen_put_string

    // Check if slot has an item
    ldx ueq_equip_idx
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !ueq_none+

    // Print item name with ego prefix/suffix (R14)
    lda #COL_WHITE
    sta zp_text_color
    jsr put_inv_name_with_ego
    // Pseudo-ID quality tag for unidentified items with IF_TRIED
    ldx ueq_equip_idx
    lda inv_flags,x
    and #IF_IDENTIFIED
    bne !ueq_no_pid+
    lda inv_flags,x
    and #IF_TRIED
    beq !ueq_no_pid+
    lda #COL_YELLOW
    sta zp_text_color
    lda #$20                   // Space
    jsr screen_put_char
    lda #$28                   // '('
    jsr screen_put_char
    // X still = ueq_equip_idx (screen_put_char only clobbers Y)
    jsr pid_get_quality        // A = quality index 0-4, X preserved
    tax
    lda ueq_pid_ptrs_lo,x
    sta zp_ptr0
    lda ueq_pid_ptrs_hi,x
    sta zp_ptr0_hi
    jsr screen_put_string
    lda #$29                   // ')'
    jsr screen_put_char
!ueq_no_pid:
    jmp !ueq_next+

!ueq_none:
    lda #COL_DGREY
    sta zp_text_color
    lda #<ueq_none_str
    sta zp_ptr0
    lda #>ueq_none_str
    sta zp_ptr0_hi
    jsr screen_put_string

!ueq_next:
    inc ueq_slot
    jmp !ueq_loop-

!ueq_done:
    lda #COL_WHITE
    sta zp_text_color
    lda #24
    sta zp_cursor_row
    lda #UEQ_FOOTER_COL
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
ueq_slot:      .byte 0
ueq_equip_idx: .byte 0
ueq_visible:   .byte 0

// ============================================================
// String data (screen codes via inherited encoding)
// ============================================================
ueq_title_str: .text "Equipment" ; .byte 0
ueq_sep_str:   .text "---------" ; .byte 0
ueq_none_str:  .text "(none)" ; .byte 0

// Equipment slot label strings
ueq_lbl_weapon: .text "Weapon: " ; .byte 0
ueq_lbl_body:   .text "Body:   " ; .byte 0
ueq_lbl_shield: .text "Shield: " ; .byte 0
ueq_lbl_head:   .text "Head:   " ; .byte 0
ueq_lbl_hands:  .text "Hands:  " ; .byte 0
ueq_lbl_feet:   .text "Feet:   " ; .byte 0
ueq_lbl_light:  .text "Light:  " ; .byte 0
ueq_lbl_ring:   .text "Ring:   " ; .byte 0

ueq_pid_terrible:  .text "Terrible" ; .byte 0
ueq_pid_bad:       .text "Bad" ; .byte 0
ueq_pid_average:   .text "Average" ; .byte 0
ueq_pid_good:      .text "Good" ; .byte 0
ueq_pid_excellent: .text "Excellent" ; .byte 0

ueq_label_ptrs_lo:
    .byte <ueq_lbl_weapon, <ueq_lbl_body, <ueq_lbl_shield, <ueq_lbl_head
    .byte <ueq_lbl_hands, <ueq_lbl_feet, <ueq_lbl_light, <ueq_lbl_ring

ueq_label_ptrs_hi:
    .byte >ueq_lbl_weapon, >ueq_lbl_body, >ueq_lbl_shield, >ueq_lbl_head
    .byte >ueq_lbl_hands, >ueq_lbl_feet, >ueq_lbl_light, >ueq_lbl_ring

ueq_pid_ptrs_lo:
    .byte <ueq_pid_terrible, <ueq_pid_bad, <ueq_pid_average, <ueq_pid_good, <ueq_pid_excellent

ueq_pid_ptrs_hi:
    .byte >ueq_pid_terrible, >ueq_pid_bad, >ueq_pid_average, >ueq_pid_good, >ueq_pid_excellent
