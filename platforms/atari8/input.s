#importonce
// input.s — Atari 8-bit POKEY keyboard & GTIA CONSOL input driver.
//
// Linked below $4000 so atari_irq_handler is always resident in unbanked RAM.
// Supports both IRQ-driven typeahead buffering (atari_irq_handler) and direct
// POKEY IRQST polling when SEI is active, plus MAME harness injection into
// atari_kbdbuf / atari_kbdbuf_len.

#import "memory.s"
#import "../../core/input_contract.s"
#import "../../core/input_tables.s"
#import "../../core/input_run_cancel.s"

.label hal_input_kbdbuf_count = atari_kbdbuf_len
.const hal_input_modal_dismiss_uses_fast_key = false
.const hal_input_followup_uses_fast_key = false
.const hal_input_selectable_overlay_prepare_followup = false
.const hal_input_modal_escape_primary = $1b
.const hal_input_modal_escape_secondary = $03
.const hal_input_flush_run_cancel_buffer = true
#define HAL_INPUT_FLUSH_RUN_CANCEL_BUFFER
.const hal_input_help_footer_uses_esc_stop = true
#define HAL_INPUT_HELP_FOOTER_USES_ESC_STOP
.const hal_input_inventory_letter_normalize_shifted = false
.const hal_input_selectable_overlay_filter_help_key = false

.label hal_input_get_key          = input_get_key
.label hal_input_get_text_char    = input_get_key
.label hal_input_get_command      = input_get_command
.label hal_input_wait_release     = input_wait_release
.label hal_input_any_key_held     = input_run_key_held
.label hal_input_run_cancel_check = input_run_cancel_check
.label hal_input_followup_prepare = input_noop
.label hal_input_modal_prepare    = input_wait_release
.label hal_input_modal_finish     = input_noop

.const ATARI_KBDBUF_MAX = 8

atari_kbdbuf_len: .byte 0
atari_kbdbuf:     .fill ATARI_KBDBUF_MAX, 0
consol_released:  .byte 1

input_noop:
    rts

// ============================================================
// input_init — Initialize POKEY keyboard scan & IRQ
// ============================================================
input_init:
    lda #0
    sta atari_kbdbuf_len
    lda #1
    sta consol_released
    lda #$03                // Enable POKEY keyboard scan + debounce
    sta SKCTL
    lda #$00
    sta IRQEN
    lda #$c0                // Enable POKEY Break (bit 7, MAME Backspace) + keyboard IRQ (bit 6)
    sta IRQEN
    rts

// ============================================================
// atari_irq_handler — POKEY Keyboard & Break(Backspace) IRQ (< $4000)
// ============================================================
// POKEY IRQST ($D20E read) is active-LOW:
// - bit 7 == 0: Break key IRQ (mapped to host Backspace in MAME a800xl/a130xe)
// - bit 6 == 0: Keyboard KBCODE IRQ
atari_irq_handler:
    pha
    txa
    pha
    tya
    pha
    lda IRQST
    bpl !break_bs+          // Bit 7 == 0 -> Break / MAME Backspace
    and #$40
    bne !irq_done+          // Bit 6 == 1 -> not a keyboard interrupt
    lda #$80
    sta IRQEN
    lda #$c0
    sta IRQEN
    lda KBCODE
    jsr atari_translate_kbcode
    jmp !queue_key+
!break_bs:
    lda #$40
    sta IRQEN
    lda #$c0
    sta IRQEN
    lda #$14                // PETSCII Delete/Backspace
!queue_key:
    beq !irq_done+
    ldx atari_kbdbuf_len
    cpx #ATARI_KBDBUF_MAX
    bcs !irq_done+
    sta atari_kbdbuf,x
    inc atari_kbdbuf_len
!irq_done:
    pla
    tay
    pla
    tax
    pla
    rti

// ============================================================
// atari_translate_kbcode — KBCODE ($D209) -> Normalized PETSCII
// ============================================================
// Input:  A = raw POKEY KBCODE (bits 0..5 = scan code, bit 6 = Shift, bit 7 = Ctrl)
// Output: A = normalized PETSCII keycode (or $00 if unmapped)
// Clobbers: X (preserves Y)
atari_translate_kbcode:
    tax
    bpl !no_ctrl+
    // Bit 7 set: Ctrl chord. Check Ctrl arrow keys first:
    cmp #$86                // Ctrl + '+' -> Left arrow
    bne !chk_right+
    lda #$9d
    rts
!chk_right:
    cmp #$87                // Ctrl + '*' -> Right arrow
    bne !chk_up+
    lda #$1d
    rts
!chk_up:
    cmp #$8e                // Ctrl + '-' -> Up arrow
    bne !chk_down+
    lda #$91
    rts
!chk_down:
    cmp #$8f                // Ctrl + '=' -> Down arrow
    bne !ctrl_letter+
    lda #$11
    rts
!ctrl_letter:
    and #$3f
    tax
    lda atari_kbcode_table,x
    cmp #$14
    beq !ctrl_ret+
    cmp #$48                // Ctrl + 'H' -> Backspace ($14)
    bne !chk_ctrl_az+
    lda #$14
    rts
!chk_ctrl_az:
    cmp #$41
    bcc !unmapped+
    cmp #$5b
    bcs !unmapped+
    and #$1f                // 'A'..'Z' ($41..$5A) -> Ctrl+A..Ctrl+Z ($01..$1A)
!ctrl_ret:
    rts
!unmapped:
    lda #0
    rts
!no_ctrl:
    // Bits 0..6 ($00..$7F): 0..63 = unshifted, 64..127 = shifted
    lda atari_kbcode_table,x
    rts

// ============================================================
// 128-Byte POKEY KBCODE -> Normalized PETSCII Lookup Table
// ============================================================
atari_kbcode_table:
    // Unshifted ($00..$3F)
    // $00..$07: L, J, ;, F1, F2, K, +, *
    .byte $4c, $4a, $3b, $00, $00, $4b, $2b, $2a
    // $08..$0F: O, None, P, U, RETURN, I, -, =
    .byte $4f, $00, $50, $55, $0d, $49, $2d, $3d
    // $10..$17: V, HELP('?'), C, F3, F4, B, X, Z
    .byte $56, $3f, $43, $00, $00, $42, $58, $5a
    // $18..$1F: 4, None, 3, 6, ESC, 5, 2, 1
    .byte $34, $00, $33, $36, $1b, $35, $32, $31
    // $20..$27: ',', SPACE, '.', N, None, M, /, INV
    .byte $2c, $20, $2e, $4e, $00, $4d, $2f, $00
    // $28..$2F: R, None, E, Y, TAB, T, W, Q
    .byte $52, $00, $45, $59, $00, $54, $57, $51
    // $30..$37: 9, None, 0, 7, BACKSPACE($14), 8, <, >
    .byte $39, $00, $30, $37, $14, $38, $3c, $3e
    // $38..$3F: F, H, D, None, CAPS, G, S, A
    .byte $46, $48, $44, $00, $00, $47, $53, $41

    // Shifted ($40..$7F)
    // $40..$47: Shift+L, J, ':', F1, F2, K, '\', '^'
    .byte $cc, $ca, $3a, $00, $00, $cb, $5c, $5e
    // $48..$4F: Shift+O, None, P, U, RETURN, I, '_', '+' (PC/Mac Shift+'=')
    .byte $cf, $00, $d0, $d5, $0d, $c9, $5f, $2b
    // $50..$57: Shift+V, Shift+HELP($93=Version), C, F3, F4, B, X, Z
    .byte $d6, $93, $c3, $00, $00, $c2, $d8, $da
    // $58..$5F: '$', None, '#', '&', ESC, '%', '"', '!'
    .byte $24, $00, $23, $26, $1b, $25, $22, $21
    // $60..$67: '<' (PC/Mac Shift+','), SPACE, '>' (PC/Mac Shift+'.'), Shift+N, None, M, '?', INV
    .byte $3c, $20, $3e, $ce, $00, $cd, $3f, $00
    // $68..$6F: Shift+R, None, E, Y, TAB, T, W, Q
    .byte $d2, $00, $c5, $d9, $00, $d4, $d7, $d1
    // $70..$77: '(', None, ')', ''', BACKSPACE($14), '@', '<', '+' (MAME Shift+'=')
    .byte $28, $00, $29, $27, $14, $40, $3c, $2b
    // $78..$7F: Shift+F, H, D, None, CAPS, G, S, A
    .byte $c6, $c8, $c4, $00, $00, $c7, $d3, $c1

.assert "Atari KBCODE table is 128 bytes", * - atari_kbcode_table == 128, true

// ============================================================
// input_get_key — Wait for a keypress, return normalized PETSCII in A
// ============================================================
// Preserves: X, Y
input_get_key:
    stx igk_save_x
    sty igk_save_y
!poll:
    inc zp_entropy

    // 1. Check queued key in atari_kbdbuf (from IRQ or MAME test harness)
    sei
    ldx atari_kbdbuf_len
    beq !check_consol+
    lda atari_kbdbuf
    sta igk_char
    ldx #0
!shift:
    lda atari_kbdbuf + 1,x
    sta atari_kbdbuf,x
    inx
    cpx #ATARI_KBDBUF_MAX - 1
    bcc !shift-
    dec atari_kbdbuf_len
    cli
    jmp !got_key+

!check_consol:
    cli
    // 2. Poll GTIA CONSOL ($D01F) active-low START/SELECT/OPTION buttons
    lda CONSOL
    and #$07
    cmp #$07
    bne !consol_down+
    lda #1
    sta consol_released
    jmp !poll-
!consol_down:
    ldx consol_released
    beq !poll-
    ldx #0
    stx consol_released
    lsr                     // Bit 0: START -> 'N' ($4E)
    bcs !chk_select+
    lda #$4e
    sta igk_char
    jmp !got_key+
!chk_select:
    lsr                     // Bit 1: SELECT -> 'L' ($4C)
    bcs !chk_option+
    lda #$4c
    sta igk_char
    jmp !got_key+
!chk_option:
    lda #$44                // Bit 2: OPTION -> 'D' ($44)
    sta igk_char

!got_key:
    ldx igk_save_x
    ldy igk_save_y
    lda igk_char
    clc
    rts

igk_save_x: .byte 0
igk_save_y: .byte 0
igk_char:   .byte 0

// ============================================================
// input_wait_release & Modal / Run Cancel Helpers
// ============================================================
// input_wait_release — Wait until no key is held, then empty the key buffer:
// a key typed ahead, or pressed while another was still down (rollover),
// never answers what follows (as the C64's, Plus/4's and BBC's waits).
// Preserves: X, Y
input_wait_release:
    txa
    pha
    tya
    pha
    ldx #0
    ldy #80                 // Held: about 0.25 s (20-cycle loop), as the Apple IIe
!wait_loop:
    inc zp_entropy
    lda SKSTAT
    and #$0c                // Bit 2 == 0 while a key is held, bit 3 while SHIFT is
    cmp #$0c                // (POKEY shows no held CTRL: it cannot count)
    beq !settle+
!wait_next:
    inx
    bne !wait_loop-
    dey
    bne !wait_loop-
    beq !released+
!settle:
    // A key held under the one let go shows only on POKEY's next scans
    // (8 ms in MAME), so stay clear for about 20 ms before trusting it.
    ldx #0
    lda #6
    sta iwr_settle
!settle_loop:
    inc zp_entropy
    lda SKSTAT
    and #$0c
    cmp #$0c
    bne !wait_next-         // A key is down after all: keep waiting
    inx
    bne !settle_loop-
    dec iwr_settle
    bne !settle_loop-
!released:
    stx atari_kbdbuf_len    // X is 0 on both ways here. The IRQ only appends,
                            // and runs whole: a key it queues after this store
                            // is a real answer.
    pla
    tay
    pla
    tax
    rts

iwr_settle: .byte 0

// input_run_key_held — Return non-zero in A if a key is queued or physically held
// Preserves: X, Y
input_run_key_held:
    lda atari_kbdbuf_len
    bne !held+
    lda SKSTAT
    and #$04
    eor #$04
!held:
    rts

input_run_cancel_check:
    jsr input_run_key_held
    jmp input_run_process_sample

// ============================================================
// input_get_command & PETSCII-to-Command Table
// ============================================================
input_get_command:
    lda #1
    sta zp_input_count
!get_key:
    jsr input_get_key
    jsr petscii_to_command
    cmp #CMD_RUN
    beq !run_prefix+
    cmp #CMD_NONE
    beq !get_key-
    sta zp_input_cmd
    rts

!run_prefix:
    jsr input_wait_release
    jsr input_get_key
    jsr petscii_to_command
    cmp #CMD_MOVE_N
    bcc !get_key-
    cmp #CMD_MOVE_SE + 1
    bcs !get_key-
    clc
    adc #(CMD_RUN_N - CMD_MOVE_N)
    sta zp_input_cmd
    rts

petscii_to_command:
    ldx #0
!loop:
    cmp key_map_petscii,x
    beq !found+
    inx
    cpx #key_map_count
    bcc !loop-
    lda #CMD_NONE
    rts
!found:
    lda key_map_cmd,x
    rts

key_map_petscii:
    :EmitBasePetsciiKeyMap()
    .byte $56   // V — version view
    .byte $93   // Shift+HELP — version view

key_map_cmd:
    :EmitBaseCommandKeyMap()
    .byte CMD_VERSION
    .byte CMD_VERSION

key_map_end:
.label key_map_count = key_map_cmd - key_map_petscii
.assert "Key map tables same size", key_map_count, key_map_end - key_map_cmd
