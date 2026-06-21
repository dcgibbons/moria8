// item_message.s - CX16 resident implementation of shared item text helpers.

.const COMBAT_MSG_BUF_SIZE = PLATFORM_COMBAT_MSG_BUF_SIZE
.const COMBAT_MSG_BUF_LAST = COMBAT_MSG_BUF_SIZE - 1

cmb_buf_idx: .byte 0
combat_msg_buf: .fill COMBAT_MSG_BUF_SIZE, 0
combat_msg_buf_end:

cmb_period: .text "." ; .byte 0

cmb_term_and_print:
    jsr combat_clamp_msg_idx
    ldx cmb_buf_idx
    lda #0
    sta combat_msg_buf,x
    lda #<combat_msg_buf
    sta zp_ptr0
    lda #>combat_msg_buf
    sta zp_ptr0_hi
    jmp msg_print

combat_append_str:
    sta zp_ptr1
    sty zp_ptr1_hi
    ldx cmb_buf_idx
    ldy #0
!loop:
    cpx #COMBAT_MSG_BUF_LAST
    bcs !done+
    lda (zp_ptr1),y
    beq !done+
    sta combat_msg_buf,x
    inx
    iny
    jmp !loop-
!done:
    stx cmb_buf_idx
    lda #0
    sta combat_msg_buf + COMBAT_MSG_BUF_LAST
    rts

combat_append_char:
    ldx cmb_buf_idx
    cpx #COMBAT_MSG_BUF_LAST
    bcs !done+
    sta combat_msg_buf,x
    inx
    stx cmb_buf_idx
!done:
    lda #0
    sta combat_msg_buf + COMBAT_MSG_BUF_LAST
    rts

combat_append_decimal:
    jsr numeric_format_u8
    jmp combat_append_digits

combat_append_decimal_16:
    jsr numeric_format_u16

combat_append_digits:
    ldx cmb_buf_idx
    ldy #0
!emit:
    cpx #COMBAT_MSG_BUF_LAST
    bcs !done+
    lda nf_digit_buf,y
    sta combat_msg_buf,x
    inx
    iny
    cpy zp_temp2
    bne !emit-
!done:
    stx cmb_buf_idx
    lda #0
    sta combat_msg_buf + COMBAT_MSG_BUF_LAST
    rts

combat_clamp_msg_idx:
    lda cmb_buf_idx
    cmp #COMBAT_MSG_BUF_SIZE
    bcc !done+
    lda #COMBAT_MSG_BUF_LAST
    sta cmb_buf_idx
!done:
    rts

banked_ego_put_suffix:
    cmp #0
    beq !done+
    cmp #EGO_TYPE_COUNT
    bcs !done+
    jsr ego_get_suffix_ptr
    ldy #0
!loop:
    lda (zp_ptr0),y
    beq !done+
    sty cx16_item_msg_y
    jsr hal_screen_put_char
    ldy cx16_item_msg_y
    iny
    jmp !loop-
!done:
    rts

put_tool_ego_prefix:
    cpx #62
    beq !valid_tool+
    cpx #63
    bne !done+
!valid_tool:
    sec
    sbc #1
    sta cx16_item_msg_temp
    txa
    sec
    sbc #62
    asl
    clc
    adc cx16_item_msg_temp
    tax
    lda cx16_tool_ego_prefix_lo,x
    sta zp_ptr0
    lda cx16_tool_ego_prefix_hi,x
    sta zp_ptr0_hi
    jsr hal_screen_put_string
!done:
    rts

cx16_item_msg_y: .byte 0
cx16_item_msg_temp: .byte 0

cx16_ego_prefix_gnomish: .text "Gnomish " ; .byte 0
cx16_ego_prefix_orcish:  .text "Orcish " ; .byte 0
cx16_ego_prefix_dwarven: .text "Dwarven " ; .byte 0

cx16_tool_ego_prefix_lo:
    .byte <cx16_ego_prefix_gnomish, <cx16_ego_prefix_dwarven
    .byte <cx16_ego_prefix_orcish,  <cx16_ego_prefix_dwarven
cx16_tool_ego_prefix_hi:
    .byte >cx16_ego_prefix_gnomish, >cx16_ego_prefix_dwarven
    .byte >cx16_ego_prefix_orcish,  >cx16_ego_prefix_dwarven

.assert "CX16 item message buffer size", combat_msg_buf_end - combat_msg_buf, COMBAT_MSG_BUF_SIZE
