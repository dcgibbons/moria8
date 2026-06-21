#importonce
// item_refuel.s — shared lantern refuel command.

// item_refuel — Refuel a brass lantern with a flask of oil
// Output: carry set = turn consumed, carry clear = no valid refuel
// Clobbers: A, X
item_refuel:
    ldx #EQUIP_LIGHT
    lda inv_item_id,x
    cmp #14
    beq !ir_has_lamp+

    ldx #HSTR_PIR_NOT_LAMP
    jsr huff_print_msg
    clc
    rts

!ir_has_lamp:
    ldx #0
!ir_scan:
    cpx #MAX_INV_SLOTS
    bcs !ir_no_oil+
    lda inv_item_id,x
    cmp #ITEM_FLASK_OIL
    beq !ir_found_oil+
    inx
    jmp !ir_scan-

!ir_no_oil:
    ldx #HSTR_PIR_NO_OIL
    jsr huff_print_msg
    clc
    rts

!ir_found_oil:
    stx piw_slot

    lda inv_p1,x
    clc
    adc inv_p1 + EQUIP_LIGHT
    bcs !ir_overflow+
    cmp #LANTERN_MAX_CHARGES + 1
    bcc !ir_no_overflow+

!ir_overflow:
    lda #LANTERN_MAX_CHARGES
    sta inv_p1 + EQUIP_LIGHT

    ldx #HSTR_PIR_OVERFLOW
    jsr huff_print_msg
    ldx #HSTR_PIR_FULL
    jsr huff_print_msg
    jmp !ir_remove_flask+

!ir_no_overflow:
    sta inv_p1 + EQUIP_LIGHT
    ldx #HSTR_PIR_REFUELED
    jsr huff_print_msg

!ir_remove_flask:
    ldx piw_slot
    jsr inv_remove_item
    sec
    rts
