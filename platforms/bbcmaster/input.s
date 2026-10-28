#importonce
// input.s — BBC Master 128 keyboard input and command parsing (< $3000).
//
// Uses MOS OSBYTE calls:
//   - OSBYTE $04, X=1 (at init): cursor keys emit $88 (Left), $89 (Right),
//     $8A (Down), $8B (Up)
//   - OSBYTE $CA, X=$20, Y=0 (at init): disable Caps Lock so unshifted letters
//     emit lowercase ASCII $61-$7A and shifted letters emit uppercase $41-$5A
//   - OSBYTE $E5, X=1, Y=0 (at init): Escape emits ASCII $1B
//   - OSBYTE $81, X=0, Y=0: non-blocking key read from keyboard buffer
//   - OSBYTE $79, X=$80: physical key-held scan (ignoring Shift/Ctrl)
//   - OSBYTE $0F, X=1: flush keyboard input buffer
//
// Entropy: every poll loop mixes System VIA Timer 1 ($FE44-$FE45) into the
// platform entropy counters at $90-$93.

#import "../../core/input_contract.s"
#import "../../core/input_tables.s"
#import "../../core/input_run_cancel.s"
#import "hal/entropy_consts.s"
#import "memory.s"

.label hal_input_kbdbuf_count = input_kbdbuf_shadow
.const hal_input_modal_dismiss_uses_fast_key = false
.const hal_input_followup_uses_fast_key = false
.const hal_input_selectable_overlay_prepare_followup = false
.const hal_input_modal_escape_primary = $1b   // ESC
.const hal_input_modal_escape_secondary = $03 // CTRL+C
.const hal_input_flush_run_cancel_buffer = false
.const hal_input_help_footer_uses_esc_stop = true
#define HAL_INPUT_HELP_FOOTER_USES_ESC_STOP
.const hal_input_inventory_letter_normalize_shifted = false
.const hal_input_selectable_overlay_filter_help_key = true
#define HAL_INPUT_SELECTABLE_OVERLAY_FILTER_HELP_KEY

// ============================================================
// HAL Exports
// ============================================================
.label hal_input_get_key = input_get_key
.label hal_input_get_text_char = input_get_key
.label hal_input_get_command = input_get_command
.label hal_input_wait_release = input_wait_release
.label hal_input_any_key_held = input_run_key_held
.label hal_input_run_cancel_check = input_run_cancel_check
.label hal_input_followup_prepare = input_modal_prepare
.label hal_input_modal_prepare = input_modal_prepare
.label hal_input_modal_finish = input_noop

input_noop:
    rts

// input_entropy_tick — Mix System VIA T1 ($FE44-$FE45) into $90-$93
// Preserves: A, X, Y
input_entropy_tick:
    pha
    lda SYSVIA_T1CL
    eor hal_entropy_timer0_lo
    clc
    adc #1
    sta hal_entropy_timer0_lo
    bne !iet_hi+
    inc hal_entropy_timer0_hi
!iet_hi:
    lda SYSVIA_T1CH
    eor hal_entropy_timer1_lo
    sta hal_entropy_timer1_lo
    inc hal_entropy_timer1_hi
    pla
    rts

// beeb_flush_kbd — Flush MOS keyboard buffer via OSBYTE $0F, X=1
beeb_flush_kbd:
    lda #$0f
    ldx #$01
    ldy #$00
    jmp MOS_OSBYTE

// input_get_key — Wait for a keypress, return normalized PETSCII code
// Output: A = normalized PETSCII code, C = 0
// Preserves: X, Y
input_get_key:
    phx
    phy
!igk_poll:
    jsr input_entropy_tick
    lda beeb_kbdbuf_len
    beq !igk_osbyte+
    lda #0
    sta beeb_kbdbuf_len
    lda beeb_kbdbuf
    jmp !igk_store+
!igk_osbyte:
    lda #$81
    ldx #$00
    ldy #$00
    jsr MOS_OSBYTE
    cpy #$00
    beq !got_key+
    cpy #$1b
    bne !igk_poll-
    // Acknowledge MOS Escape condition if raised
    lda #$7e
    jsr MOS_OSBYTE
    ldx #$1b
!got_key:
    txa
    jsr input_translate
!igk_store:
    sta igk_key
    ply
    plx
    lda igk_key
    clc
    rts

igk_key:             .byte 0
input_kbdbuf_shadow: .byte 0
beeb_kbdbuf:         .byte 0
beeb_kbdbuf_len:     .byte 0

// input_wait_release — Flush keyboard buffer and wait until no key is held
// (bounded so emulator-injected keys never deadlock).
// Preserves: X, Y
input_wait_release:
    phx
    phy
    jsr beeb_flush_kbd
    ldy #8
    ldx #0
!iwr_poll:
    phx
    phy
    jsr input_entropy_tick
    jsr input_run_key_held
    ply
    plx
    cmp #0
    beq !iwr_done+
    inx
    bne !iwr_poll-
    dey
    bne !iwr_poll-
!iwr_done:
    jsr beeb_flush_kbd
    ply
    plx
    rts

// input_run_key_held — Non-blocking check for any non-modifier key held.
// OSBYTE $79, X=$10 scans keyboard from internal key 16 (skipping Shift/Ctrl/links);
// returns X=$FF (N=1) if no key pressed, or X>=0 (N=0) if a key is pressed.
// Output: A = nonzero if any key held, 0 if no key; Z/N set from A, as on
//         every port: core/game_loop.s branches on them. Restoring X last
//         left Z from the caller's X, cancelling auto-rest and running at
//         once whenever X was nonzero (M6 playtest).
// Preserves: X, Y
input_run_key_held:
    phx
    phy
    lda #$79
    ldx #$10
    jsr MOS_OSBYTE
    txa
    bmi !none+
    lda #$80
    jmp !done+
!none:
    lda #$00
!done:
    ply
    plx
    cmp #0
    rts

input_run_cancel_check:
    jsr input_run_key_held
    jmp input_run_process_sample

input_modal_prepare:
    jmp input_wait_release

// input_translate — BBC Master key code -> normalized PETSCII
//   lowercase ASCII $61-$7A -> unshifted PETSCII $41-$5A
//   uppercase ASCII $41-$5A -> shifted PETSCII $C1-$DA
//   cursor keys $88-$8B     -> $9D/$1D/$11/$91
//   DELETE $7F / BS $08     -> $14
// Preserves: Y
input_translate:
    cmp #$61
    bcc !it_not_lower+
    cmp #$7b
    bcs !it_not_lower+
    and #$df
    rts
!it_not_lower:
    cmp #$41
    bcc !it_table+
    cmp #$5b
    bcs !it_table+
    ora #$80
    rts
!it_table:
    ldx #beeb_special_key_count - 1
!it_scan:
    cmp beeb_special_key_raw,x
    beq !it_found+
    dex
    bpl !it_scan-
    rts
!it_found:
    lda beeb_special_key_norm,x
    rts

beeb_special_key_raw:
    .byte $88               // Cursor Left (*FX 4,1)
    .byte $89               // Cursor Right (*FX 4,1)
    .byte $8b               // Cursor Up (*FX 4,1)
    .byte $8a               // Cursor Down (*FX 4,1)
    .byte $7f               // DELETE
    .byte $08               // Backspace
beeb_special_key_norm:
    .byte $9d               // PETSCII cursor left
    .byte $1d               // PETSCII cursor right
    .byte $91               // PETSCII cursor up
    .byte $11               // PETSCII cursor down
    .byte $14               // PETSCII DEL
    .byte $14               // PETSCII DEL
beeb_special_key_end:
.label beeb_special_key_count = beeb_special_key_norm - beeb_special_key_raw
.assert "Special key tables same size", beeb_special_key_count, beeb_special_key_end - beeb_special_key_norm

// input_get_command — Wait for a keypress, return command ID
input_get_command:
    jsr beeb_flush_kbd
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

key_map_cmd:
    :EmitBaseCommandKeyMap()

key_map_end:
.label key_map_count = key_map_cmd - key_map_petscii
.assert "Key map tables same size", key_map_count, key_map_end - key_map_cmd
