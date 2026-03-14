#importonce
// test_msg_prompt128.s — C128 message prompt rendering race regression tests
//
// Reproduces the intermittent garbled prompt issue by running a high-rate CIA1
// IRQ that clobbers zp_ptr0 while prompts are rendered. The vulnerable window
// is in screen_put_string before IRQs are masked.

#import "../../common/zeropage.s"
#import "../screen_vdc.s"

.const MACHINE_C128 = $80
.const COL_WHITE = 1
.const COL_LGREY = 15
.const COL_MSG_TEXT = COL_LGREY

// Stubbed dependency from ui_messages.s C128 guard path
c128_restore_runtime_vectors:
    rts

// Stubbed dependency from ui_messages.s (only needed for -MORE- path)
input_get_key:
    lda #0
    rts

// Stubbed dependency from huffman.s (unused by this suite)
combat_append_str:
    rts

#import "../../common/ui_messages.s"
#import "../../common/huffman.s"

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $4000 "Test Code"

.const TEST_ITERS = 96
.const TEST_PREFIX_LEN = 12

test_start:
    sei
    cld
    ldx #$ff
    txs

    lda #MACHINE_C128
    sta zp_machine_type
    lda #COL_LGREY
    sta zp_text_color

    // Hard integrity guard for critical prompt Huffman entries.
    jsr assert_huff_prompt_integrity
    bcc test_fail

    // Hard decode correctness guard (literal content, not self-comparison).
    ldx #HSTR_PIW_TAKEOFF_PROMPT
    lda #<expected_takeoff
    ldy #>expected_takeoff
    jsr assert_decode_literal
    bcc test_fail
    ldx #HSTR_DF_DIRECTION
    lda #<expected_direction
    ldy #>expected_direction
    jsr assert_decode_literal
    bcc test_fail

    jsr screen_clear
    jsr msg_init
    jsr setup_irq_clobber

    // Case A: TAKE-OFF prompt (HSTR_PIW_TAKEOFF_PROMPT)
    ldx #HSTR_PIW_TAKEOFF_PROMPT
    jsr assert_prompt_stable
    bcc test_fail

    // Case B: LOOK direction prompt (HSTR_DF_DIRECTION)
    ldx #HSTR_DF_DIRECTION
    jsr assert_prompt_stable
    bcc test_fail

    // Case C: LOOK-style compound render ("You see a " + name append)
    jsr assert_compound_look_stable
    bcc test_fail

    jsr teardown_irq_clobber
    jmp test_pass

test_fail:
    jsr teardown_irq_clobber
    jmp test_fail

// assert_prompt_stable
// Input: X = HSTR_* prompt ID
// Output: carry set = stable across TEST_ITERS renders, carry clear = mismatch
assert_prompt_stable:
    // Deterministic guard: prompt rendering is only safe when
    // screen_put_string preserves caller IRQ state (php; sei ... plp).
    lda screen_put_string
    cmp #$08                    // PHP opcode
    bne !bad+
    lda screen_put_string + 1
    cmp #$78                    // SEI opcode
    bne !bad+

    stx test_str_id
    jsr capture_expected_prefix

    ldx #0
!iter_loop:
    cpx #TEST_ITERS
    bcs !ok+

    // Reset message state to force row 0 path every time.
    jsr msg_init
    lda #MSG_ROW
    jsr screen_clear_row
    lda #MSG_ROW + 1
    jsr screen_clear_row

    lda #1
    sta irq_armed
    ldx test_str_id
    jsr huff_print_msg
    lda #0
    sta irq_armed

    jsr compare_screen_prefix
    bcc !bad+

    inx
    jmp !iter_loop-

!ok:
    sec
    rts
!bad:
    clc
    rts

// assert_huff_prompt_integrity
// Verifies huff index offsets and leading compressed bytes for two
// critical prompt strings used by take-off and look direction input.
// Output: carry set = integrity OK, carry clear = mismatch
assert_huff_prompt_integrity:
    // HSTR_DF_DIRECTION index offset must be $02D4.
    lda huff_str_index + (HSTR_DF_DIRECTION * 2)
    cmp #<$02d4
    bne !bad+
    lda huff_str_index + (HSTR_DF_DIRECTION * 2) + 1
    cmp #>$02d4
    bne !bad+

    // HSTR_PIW_TAKEOFF_PROMPT index offset must be $045C.
    lda huff_str_index + (HSTR_PIW_TAKEOFF_PROMPT * 2)
    cmp #<$045c
    bne !bad+
    lda huff_str_index + (HSTR_PIW_TAKEOFF_PROMPT * 2) + 1
    cmp #>$045c
    bne !bad+

    // Leading compressed bytes (from generated huffman_data.s).
    lda huff_str_data + $02d4
    cmp #$8c
    bne !bad+
    lda huff_str_data + $02d5
    cmp #$77
    bne !bad+
    lda huff_str_data + $045c
    cmp #$4c
    bne !bad+
    lda huff_str_data + $045d
    cmp #$e8
    bne !bad+

    sec
    rts
!bad:
    clc
    rts

// assert_decode_literal
// Input: X = HSTR_* id, A/Y = expected null-terminated screen-code string
// Output: carry set = decoded bytes exactly match expected literal
assert_decode_literal:
    sta adl_expected_lo
    sty adl_expected_hi
    jsr huff_decode_string
    ldy #0
!cmp:
    lda hd_decode_buf,y
    cmp (adl_expected_lo),y
    bne !bad+
    beq !chk_done+
!chk_done:
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

// assert_compound_look_stable
// Reproduces dl_print_you_see pattern under IRQ pressure:
//   1) huff_print_msg("You see a ")
//   2) set zp_ptr0 to name buffer
//   3) screen_put_string append
// with an outer sei bracket.
assert_compound_look_stable:
    lda #0
    sta acl_iter
!acl_loop:
    lda acl_iter
    cmp #16
    bcs !acl_ok+

    jsr msg_init
    lda #MSG_ROW
    jsr screen_clear_row
    lda #MSG_ROW + 1
    jsr screen_clear_row

    lda #1
    sta irq_armed

    php
    sei
    ldx #HSTR_DL_YOU_SEE
    jsr huff_print_msg
    lda #<compound_name
    sta zp_ptr0
    lda #>compound_name
    sta zp_ptr0_hi
    jsr compound_delay
    jsr screen_put_string
    plp

    lda #0
    sta irq_armed

    // Verify append started at expected column with "Sq"
    ldx #9
    jsr read_msg_row0_char
    cmp #$53                    // 'S'
    bne !acl_bad+
    ldx #10
    jsr read_msg_row0_char
    cmp #$11                    // 'q' in Set 1 lowercase
    bne !acl_bad+

    inc acl_iter
    jmp !acl_loop-
!acl_ok:
    sec
    rts
!acl_bad:
    clc
    rts

// capture_expected_prefix
// Input: test_str_id set
capture_expected_prefix:
    ldx test_str_id
    jsr huff_decode_string

    ldx #0
!cap_loop:
    cpx #TEST_PREFIX_LEN
    bcs !cap_done+
    lda hd_decode_buf,x
    beq !cap_done+
    sta expected_prefix,x
    inx
    jmp !cap_loop-
!cap_done:
    stx expected_len
    rts

// compare_screen_prefix
// Output: carry set = matches expected prefix, carry clear = mismatch
compare_screen_prefix:
    ldx #0
!cmp_loop:
    cpx expected_len
    bcs !cmp_ok+
    jsr read_msg_row0_char
    cmp expected_prefix,x
    bne !cmp_bad+
    inx
    jmp !cmp_loop-
!cmp_ok:
    sec
    rts
!cmp_bad:
    clc
    rts

// read_msg_row0_char
// Input: X = column in message row 0
// Output: A = VDC screen code at row 0, col X
read_msg_row0_char:
    stx read_col
    lda #MSG_ROW
    sta zp_cursor_row
    lda read_col
    sta zp_cursor_col
    jsr screen_set_cursor
    lda zp_screen_hi
    ldy zp_screen_lo
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_read_reg
    ldx read_col
    rts

setup_irq_clobber:
    sei
    lda $0314
    sta irq_vec_save_lo
    lda $0315
    sta irq_vec_save_hi
    lda #<test_irq
    sta $0314
    lda #>test_irq
    sta $0315

    // Clear + mask first, then enable Timer A IRQ.
    lda #$7f
    sta $dc0d
    lda $dc0d

    // Timer A latch: short period to maximize IRQ pressure.
    lda #$10
    sta $dc04
    lda #$00
    sta $dc05

    lda #%10000001
    sta $dc0d               // Enable Timer A interrupt source
    lda #%00010001
    sta $dc0e               // Force load + start (continuous mode)
    cli
    rts

teardown_irq_clobber:
    sei
    lda #0
    sta irq_armed
    lda #%00000000
    sta $dc0e               // Stop Timer A
    lda #$7f
    sta $dc0d               // Disable CIA1 IRQ sources
    lda $dc0d               // Acknowledge pending

    lda irq_vec_save_lo
    sta $0314
    lda irq_vec_save_hi
    sta $0315
    cli
    rts

// test_irq — intentionally clobbers zp_ptr0 while armed
test_irq:
    pha
    txa
    pha
    tya
    pha

    lda irq_armed
    beq !done+
    lda #<irq_garble
    sta zp_ptr0
    lda #>irq_garble
    sta zp_ptr0_hi
!done:
    lda $dc0d               // Ack CIA1 IRQ

    pla
    tay
    pla
    tax
    pla
    rti

test_str_id:      .byte 0
expected_len:     .byte 0
read_col:         .byte 0
irq_armed:        .byte 0
irq_vec_save_lo:  .byte 0
irq_vec_save_hi:  .byte 0
acl_iter:         .byte 0
adl_expected_lo:  .byte 0
adl_expected_hi:  .byte 0
expected_prefix:  .fill TEST_PREFIX_LEN, 0
irq_garble:       .text "fsY0llffoBd"; .byte 0
compound_name:    .text "Squint-Eyed Rogue."; .byte 0
expected_direction:
    .text "Direction?"
    .byte 0
expected_takeoff:
    .text "Take off which item (a-h)?"
    .byte 0

compound_delay:
    ldy #$20
!cd_outer:
    ldx #$ff
!cd_inner:
    dex
    bne !cd_inner-
    dey
    bne !cd_outer-
    rts

test_pass:
    jmp test_pass
