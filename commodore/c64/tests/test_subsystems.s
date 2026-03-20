.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_exit_trampoline:
    ldx #6
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk

.pc = $0828 "Main"

.encoding "screencode_mixed"

#import "../../common/zeropage.s"
#import "../memory.s"

// Minimal shared dependencies needed by huffman.s in isolated context.
cmb_buf_idx:     .byte 0
combat_msg_buf:  .fill 42, 0

combat_append_str:
    sta zp_ptr1
    sty zp_ptr1_hi
    ldx cmb_buf_idx
    ldy #0
!loop:
    lda (zp_ptr1),y
    beq !done+
    sta combat_msg_buf,x
    inx
    iny
    cpx #41
    bcc !loop-
!done:
    stx cmb_buf_idx
    rts

msg_print:
    rts

#import "../../common/huffman.s"
#import "../../common/string_bank_banked.s"

tc_results: .fill 7, $ff

test_start:
    sei
    cld
    ldx #$ff
    txs

    ldx #6
    lda #$ff
!clr:
    sta tc_results,x
    dex
    bpl !clr-

    jsr test_huff_integrity
    jsr test_huff_direction
    jsr test_huff_takeoff
    jsr test_huff_decode_to_ptr2
    jsr test_huff_append_combat
    jsr test_bank_decode_direction
    jsr test_bank_decode_takeoff

    jmp test_exit_trampoline

test_huff_integrity:
    lda huff_str_index + (HSTR_DF_DIRECTION * 2)
    cmp #<$02d4
    bne !fail+
    lda huff_str_index + (HSTR_DF_DIRECTION * 2) + 1
    cmp #>$02d4
    bne !fail+
    lda huff_str_index + (HSTR_PIW_TAKEOFF_PROMPT * 2)
    cmp #<$045c
    bne !fail+
    lda huff_str_index + (HSTR_PIW_TAKEOFF_PROMPT * 2) + 1
    cmp #>$045c
    bne !fail+
    lda huff_str_data + $02d4
    cmp #$8c
    bne !fail+
    lda huff_str_data + $02d5
    cmp #$77
    bne !fail+
    lda huff_str_data + $045c
    cmp #$4c
    bne !fail+
    lda huff_str_data + $045d
    cmp #$e8
    bne !fail+
    lda #$01
    bne !store+
!fail:
    lda #$00
!store:
    sta tc_results + 0
    rts

test_huff_direction:
    ldx #HSTR_DF_DIRECTION
    lda #<expected_direction
    ldy #>expected_direction
    jsr assert_decode_literal
    lda #$00
    bcc !store+
    lda #$01
!store:
    sta tc_results + 1
    rts

test_huff_takeoff:
    ldx #HSTR_PIW_TAKEOFF_PROMPT
    lda #<expected_takeoff
    ldy #>expected_takeoff
    jsr assert_decode_literal
    lda #$00
    bcc !store+
    lda #$01
!store:
    sta tc_results + 2
    rts

test_huff_decode_to_ptr2:
    ldx #HSTR_DF_DIRECTION
    jsr huff_decode_to_ptr2
    lda zp_ptr2
    cmp #<hd_decode_buf
    bne !fail_ptr+
    lda zp_ptr2_hi
    cmp #>hd_decode_buf
    bne !fail_ptr+
    lda #<expected_direction
    sta zp_ptr1
    lda #>expected_direction
    sta zp_ptr1_hi
    jsr compare_ptr2_literal
    bcc !fail_lit+
    lda #$01
    bne !store+
!fail_ptr:
    lda #$00
    bne !store+
!fail_lit:
    lda #$00
!store:
    sta tc_results + 3
    rts

test_huff_append_combat:
    lda #$31                    // '1'
    sta combat_msg_buf
    lda #$3a                    // ':'
    sta combat_msg_buf + 1
    lda #$20                    // ' '
    sta combat_msg_buf + 2
    lda #3
    sta cmb_buf_idx
    ldx #HSTR_DF_DIRECTION
    jsr huff_append_combat

    lda combat_msg_buf + 0
    cmp #$31
    bne !fail_prefix+
    lda combat_msg_buf + 1
    cmp #$3a
    bne !fail_prefix+
    lda combat_msg_buf + 2
    cmp #$20
    bne !fail_prefix+
    lda combat_msg_buf + 3
    cmp #$44                    // 'D'
    bne !fail_body+
    lda combat_msg_buf + 4
    cmp #$09                    // 'i'
    bne !fail_body+
    lda combat_msg_buf + 12
    cmp #$3f                    // '?'
    bne !fail_body+
    lda cmb_buf_idx
    cmp #13
    bne !fail_len+
    lda #$01
    bne !store+
!fail_prefix:
    lda #$00
    bne !store+
!fail_body:
    lda #$00
    bne !store+
!fail_len:
    lda #$00
!store:
    sta tc_results + 4
    rts

test_bank_decode_direction:
    jsr install_test_bank
    sei
    :BankOutKernal()
    lda #0
    jsr bank_decode_string
    :BankInKernal()
    cli
    lda #<expected_direction
    ldy #>expected_direction
    jsr compare_hd_literal
    lda #$00
    bcc !store+
    lda #$01
!store:
    sta tc_results + 5
    rts

test_bank_decode_takeoff:
    jsr install_test_bank
    sei
    :BankOutKernal()
    lda #1
    jsr bank_decode_string
    :BankInKernal()
    cli
    lda #<expected_takeoff
    ldy #>expected_takeoff
    jsr compare_hd_literal
    lda #$00
    bcc !store+
    lda #$01
!store:
    sta tc_results + 6
    rts

// assert_decode_literal
// Input: X = HSTR_* id, A/Y = expected null-terminated screen-code string
// Output: carry set = decoded bytes exactly match expected literal
assert_decode_literal:
    sta zp_ptr1
    sty zp_ptr1_hi
    jsr huff_decode_string
    ldy #0
!cmp:
    lda hd_decode_buf,y
    cmp (zp_ptr1),y
    bne !bad+
    cmp #0
    beq !ok+
    iny
    cpy #41
    bcc !cmp-
!bad:
    clc
    rts
!ok:
    sec
    rts

compare_ptr2_literal:
    ldy #0
!cmp:
    lda (zp_ptr2),y
    cmp (zp_ptr1),y
    bne !bad+
    cmp #0
    beq !ok+
    iny
    cpy #41
    bcc !cmp-
!bad:
    clc
    rts
!ok:
    sec
    rts

compare_hd_literal:
    sta zp_ptr1
    sty zp_ptr1_hi
    ldy #0
!cmp:
    lda hd_decode_buf,y
    cmp (zp_ptr1),y
    bne !bad+
    cmp #0
    beq !ok+
    iny
    cpy #41
    bcc !cmp-
!bad:
    clc
    rts
!ok:
    sec
    rts

install_test_bank:
    lda #<test_bank_image
    sta zp_ptr0
    lda #>test_bank_image
    sta zp_ptr0_hi
    lda #<$e000
    sta zp_ptr1
    lda #>$e000
    sta zp_ptr1_hi
    lda #$21
    sta zp_temp0
    lda #$00
    sta zp_temp1
    jmp copy_to_e000

expected_direction:
    .byte $44,$09,$12,$05,$03,$14,$09,$0f,$0e,$3f,$00

expected_takeoff:
    .byte $54,$01,$0b,$05,$20,$0f,$06,$06,$20,$17,$08,$09,$03,$08,$20,$09,$14,$05,$0d,$20,$28,$01,$2d,$08,$29,$3f,$00

test_bank_image:
    .byte 2
    .byte 7, 0
    .byte 0, 0
    .byte 8, 0
    .byte $8c, $77, $fe, $98, $f7, $9a, $42, $a0
    .byte $4c, $e8, $3a, $e0, $01, $45, $96, $e6, $95, $d9, $f2, $56, $71, $da, $a5, $3a, $85, $40
.const TEST_BANK_IMAGE_LEN = * - test_bank_image
