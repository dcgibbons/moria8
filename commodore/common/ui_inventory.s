// ui_inventory.s — Inventory and Equipment display screens
//
// Full-screen overlays following the ui_help.s / ui_character.s pattern.
// CMD_INVENTORY shows carried items (slots 0-21).
// CMD_EQUIPMENT shows equipped items (slots 22-29).

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
    lda #15
    sta zp_cursor_col
    lda #<uinv_title_str
    sta zp_ptr0
    lda #>uinv_title_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // Separator
    lda #1
    sta zp_cursor_row
    lda #15
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

!uinv_loop:
    lda uinv_slot
    cmp #MAX_INV_SLOTS
    bcs !uinv_loop_done+

    // Check if slot occupied
    tax
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !uinv_next+

    // Apply category filter
    ldy uinv_filter
    cpy #$ff
    beq !uinv_show+             // $FF = no filter, show all
    // A still = item type ID from inv_item_id,x
    tax
    lda it_category,x           // A = category of this item
    cpy #$fe
    beq !uinv_wearable+
    // Exact category match
    cmp uinv_filter
    beq !uinv_show+
    jmp !uinv_next+
!uinv_wearable:
    tax
    lda equip_slot_for_cat,x
    cmp #$ff
    bne !uinv_show+
    jmp !uinv_next+
!uinv_show:

    // Print letter and item name
    lda uinv_row
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col

    // Letter: 'A' + slot_index (screen code for 'A' = $01)
    lda uinv_slot
    clc
    adc #$01                    // Screen code 'A'
    jsr screen_put_char

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
    lda #12
    sta zp_cursor_col
    lda #<press_key_str
    sta zp_ptr0
    lda #>press_key_str
    sta zp_ptr0_hi
    jsr screen_put_string

    rts

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
    lda #15
    sta zp_cursor_col
    lda #<ueq_title_str
    sta zp_ptr0
    lda #>ueq_title_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // Separator
    lda #1
    sta zp_cursor_row
    lda #15
    sta zp_cursor_col
    lda #<uinv_sep_str
    sta zp_ptr0
    lda #>uinv_sep_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // Iterate 8 equipment slots
    lda #0
    sta uinv_slot               // 0-7 (maps to inv slot 22-29)

!ueq_loop:
    lda uinv_slot
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

    // Print slot label
    lda #COL_LGREY
    sta zp_text_color
    ldx uinv_slot
    lda ueq_label_ptrs_lo,x
    sta zp_ptr0
    lda ueq_label_ptrs_hi,x
    sta zp_ptr0_hi
    jsr screen_put_string

    // Check if slot has an item
    lda uinv_slot
    clc
    adc #EQUIP_WEAPON           // Map 0-7 → 22-29
    tax
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !ueq_none+

    // Print item name with ego prefix/suffix (R14)
    stx uinv_equip_idx              // Save absolute slot index
    lda #COL_WHITE
    sta zp_text_color
    jsr put_inv_name_with_ego
    // Pseudo-ID quality tag for unidentified items with IF_TRIED
    ldx uinv_equip_idx
    lda inv_flags,x
    and #IF_IDENTIFIED
    bne !ueq_no_pid+
    lda inv_flags,x
    and #IF_TRIED
    beq !ueq_no_pid+
    lda #COL_YELLOW
    sta zp_text_color
    lda #$20                    // Space
    jsr screen_put_char
    lda #$28                    // '('
    jsr screen_put_char
    // X still = uinv_equip_idx (screen_put_char only clobbers Y)
    jsr pid_get_quality         // A = quality index 0-4, X preserved
    clc
    adc #HSTR_PID_TERRIBLE      // Sequential: TERRIBLE=0, BAD=1, ...
    tax
    jsr huff_decode_string      // zp_ptr0/hi → hd_decode_buf
    lda #<(hd_decode_buf + 7)   // Skip "Sense: " prefix (hi byte unchanged)
    sta zp_ptr0
    jsr screen_put_string
    lda #$29                    // ')'
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
    inc uinv_slot
    jmp !ueq_loop-

!ueq_done:
    lda #COL_WHITE
    sta zp_text_color
    lda #24
    sta zp_cursor_row
    lda #12
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
uinv_slot:      .byte 0
uinv_row:       .byte 0
uinv_any:       .byte 0
uinv_equip_idx: .byte 0
uinv_filter:    .byte $ff       // $FF=all, $FE=wearable, 0-15=exact ICAT match

// ============================================================
// String data (screen codes via inherited encoding)
// ============================================================
uinv_title_str:   .text "Inventory" ; .byte 0
uinv_sep_str:     .text "---------" ; .byte 0
uinv_nothing_str: .text "You have nothing." ; .byte 0

ueq_title_str:    .text "Equipment" ; .byte 0
ueq_none_str:     .text "(none)" ; .byte 0

// Equipment slot label strings
ueq_lbl_weapon: .text "Weapon: " ; .byte 0
ueq_lbl_body:   .text "Body:   " ; .byte 0
ueq_lbl_shield: .text "Shield: " ; .byte 0
ueq_lbl_head:   .text "Head:   " ; .byte 0
ueq_lbl_hands:  .text "Hands:  " ; .byte 0
ueq_lbl_feet:   .text "Feet:   " ; .byte 0
ueq_lbl_light:  .text "Light:  " ; .byte 0
ueq_lbl_ring:   .text "Ring:   " ; .byte 0

ueq_label_ptrs_lo:
    .byte <ueq_lbl_weapon, <ueq_lbl_body, <ueq_lbl_shield, <ueq_lbl_head
    .byte <ueq_lbl_hands, <ueq_lbl_feet, <ueq_lbl_light, <ueq_lbl_ring

ueq_label_ptrs_hi:
    .byte >ueq_lbl_weapon, >ueq_lbl_body, >ueq_lbl_shield, >ueq_lbl_head
    .byte >ueq_lbl_hands, >ueq_lbl_feet, >ueq_lbl_light, >ueq_lbl_ring

// banked_ego_put_suffix — relocated to main.s (R14)
