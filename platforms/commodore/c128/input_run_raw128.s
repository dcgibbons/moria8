#importonce
// input_run_raw128.s — C128 raw physical-key sampler for the running FSM
//
// Imported into the dedicated C128 runtime-input segment for shipping builds
// and directly into test_input128.s for unit coverage.
//
// Contract:
//   - raw physical state only
//   - no PETSCII decode
//   - modifier-only rows do not count as held/cancel input for running

// input_run_scan_held_raw — Non-blocking: returns nonzero if any non-modifier
// key is physically down according to the raw CIA matrix state.
// Output: A = 1 if a non-modifier key is down, 0 otherwise
// Destroys: A, X, Y
input_run_scan_held_raw:
    php
    sei

    lda CIA1_PORTA
    sta irs_save_pra
    lda CIA1_DDRA
    sta irs_save_ddra
    lda CIA1_DDRB
    sta irs_save_ddrb
    lda C128_KBD_EXT
    sta irs_ext_save

    lda #$ff
    sta CIA1_DDRA
    lda #$00
    sta CIA1_DDRB
    lda #$ff
    sta CIA1_PORTA
    lda irs_ext_save
    ora #%00000111
    sta C128_KBD_EXT

    lda #$fe
    ldx #0
!irs_row:
    sta irs_drive_mask
    sta CIA1_PORTA
    nop
    nop
    lda CIA1_PORTB
    jsr input_run_row_has_nonmodifier
    bne !irs_pressed+
    lda irs_drive_mask
    sec
    rol
    inx
    cpx #8
    bcc !irs_row-

    lda #$ff
    sta CIA1_PORTA
    ldy #0
!irs_ext_row:
    lda irs_ext_save
    ora #%00000111
    and irs_ext_masks,y
    sta C128_KBD_EXT
    nop
    nop
    tya
    clc
    adc #8
    tax
    lda CIA1_PORTB
    jsr input_run_row_has_nonmodifier
    bne !irs_pressed+
    iny
    cpy #3
    bcc !irs_ext_row-
    bcs !irs_none+

!irs_pressed:
    ldx #1
    bne !irs_store+
!irs_none:
    ldx #0
!irs_store:
    lda irs_save_pra
    sta CIA1_PORTA
    lda irs_save_ddra
    sta CIA1_DDRA
    lda irs_save_ddrb
    sta CIA1_DDRB
    lda irs_ext_save
    sta C128_KBD_EXT

    plp
    txa
    rts

// input_run_row_has_nonmodifier — classify one raw keyboard row sample for the
// running subsystem.
// Input:  X = row index (0-9), A = raw CIA1_PORTB sample (active low)
// Output: A = 1 if any non-modifier key in the row is pressed, 0 otherwise
// Destroys: A
input_run_row_has_nonmodifier:
    sta irs_row_raw

    cpx #1
    bne !irrn_not_lshift+
    lda irs_row_raw
    ora #$80            // Ignore left shift
    sta irs_row_raw
!irrn_not_lshift:
    cpx #6
    bne !irrn_not_rshift+
    lda irs_row_raw
    ora #$10            // Ignore right shift
    sta irs_row_raw
!irrn_not_rshift:
    cpx #7
    bne !irrn_not_ctrl+
    lda irs_row_raw
    ora #$24            // Ignore CTRL and C=
    sta irs_row_raw
!irrn_not_ctrl:
    cpx #10
    bne !irrn_not_alt+
    lda irs_row_raw
    ora #$01            // Ignore ALT
    sta irs_row_raw
!irrn_not_alt:
    lda irs_row_raw
    cmp #$ff
    beq !irrn_none+
    lda #1
    rts
!irrn_none:
    lda #0
    rts

irs_save_pra:   .byte 0
irs_save_ddra:  .byte 0
irs_save_ddrb:  .byte 0
irs_ext_save:   .byte 0
irs_drive_mask: .byte 0
irs_row_raw:    .byte 0
irs_ext_masks:
    .byte %11111110, %11111101, %11111011

#if !C128_INPUT_TEST
// Restore the spell-execution overlay after a cross-overlay Earthquake call so
// the original return address lands in live code again.
c128_return_to_death_overlay:
    lda #3                      // OVL_DEATH
    jsr overlay_load
    bcs !fatal+
    jsr c128_restore_runtime_guards
    sei
    :BankOutKernal()
    rts
!fatal:
    jmp entry_main
#endif
