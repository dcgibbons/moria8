// input.s — Commander X16 keyboard input HAL.
//
// Calls KERNAL GETIN ($FFE4) with RAM Bank 0 ($00 = 0) selected so the
// KERNAL keyboard buffer variables ($A80A in KVARSB0) are visible, then
// restores the caller's active RAM bank. Uses the full shared Moria8
// PETSCII command table (core/input_tables.s).

#import "../../core/input_contract.s"
#import "../../core/input_tables.s"
#import "../../core/input_run_cancel.s"

.const KERNAL_GETIN = $ffe4
.const hal_input_kbdbuf_count = $a80a
.const hal_input_modal_dismiss_uses_fast_key = false
.const hal_input_followup_uses_fast_key = false
.const hal_input_selectable_overlay_prepare_followup = false
.const hal_input_modal_escape_primary = $03
.const hal_input_modal_escape_secondary = $1b
.const hal_input_flush_run_cancel_buffer = true
#define HAL_INPUT_FLUSH_RUN_CANCEL_BUFFER
.const hal_input_help_footer_uses_esc_stop = false
.const hal_input_inventory_letter_normalize_shifted = false
.const hal_input_selectable_overlay_filter_help_key = false

.label hal_input_get_key = input_get_key
.label hal_input_get_text_char = input_get_key
.label hal_input_get_command = input_get_command
.label hal_input_wait_release = input_wait_release
.label hal_input_any_key_held = input_any_key_held
.label hal_input_run_cancel_check = input_run_cancel_check
.label hal_input_followup_prepare = input_noop
.label hal_input_modal_prepare = input_modal_prepare
.label hal_input_modal_finish = input_noop

input_noop:
    rts

input_modal_prepare:
    jmp input_wait_release

// input_get_key — Wait for a keypress from KERNAL GETIN, preserving X and Y
// as well as the caller's active RAM bank ($00). When cx16_testbench_enabled
// is nonzero and the keyboard queue is empty, yields to x16emu -testbench at
// $FFFD so the harness can inspect state and inject the next key.
input_get_key:
    stx igk_save_x
    sty igk_save_y
input_get_key_poll:
    inc zp_entropy
    lda CX16_RAM_BANK_REG
    sta igk_save_bank
    lda #CX16_BANK_KERNAL_VARS
    sta CX16_RAM_BANK_REG
    jsr KERNAL_GETIN
    sta igk_char
    lda igk_save_bank
    sta CX16_RAM_BANK_REG
    lda igk_char
    bne !got_key+
    lda cx16_testbench_enabled
    beq input_get_key_poll
    jmp $fffd
!got_key:
    ldx igk_save_x
    ldy igk_save_y
    rts

input_get_key_testbench_resume:
    pla
    pla
    lda igk_char
    bne !got_key-
    jmp input_get_key_poll

cx16_testbench_enabled: .byte 0
igk_save_bank:          .byte 0
igk_save_x:             .byte 0
igk_save_y:             .byte 0
igk_char:               .byte 0

input_wait_release:
    phx
    phy
    lda CX16_RAM_BANK_REG
    pha
    lda #CX16_BANK_KERNAL_VARS
    sta CX16_RAM_BANK_REG
    stz hal_input_kbdbuf_count
!drain:
    inc zp_entropy
    jsr KERNAL_GETIN
    bne !drain-
    pla
    sta CX16_RAM_BANK_REG
    ply
    plx
    rts

input_any_key_held:
    lda CX16_RAM_BANK_REG
    pha
    lda #CX16_BANK_KERNAL_VARS
    sta CX16_RAM_BANK_REG
    lda hal_input_kbdbuf_count
    sta igk_char
    pla
    sta CX16_RAM_BANK_REG
    lda igk_char
    rts

input_run_cancel_check:
    jsr input_any_key_held
    jmp input_run_process_sample

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
    .byte $73   // s — search (lowercase fallback)
    .byte $56   // V — version view

key_map_cmd:
    :EmitBaseCommandKeyMap()
    .byte CMD_SEARCH
    .byte CMD_VERSION

key_map_end:
.label key_map_count = key_map_cmd - key_map_petscii
.assert "Key map tables same size", key_map_count, key_map_end - key_map_cmd
