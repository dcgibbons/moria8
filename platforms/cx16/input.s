// input.s - Commander X16 keyboard input HAL

#import "../../core/input_contract.s"
#import "../../core/input_tables.s"
#import "../../core/input_run_cancel.s"

.const hal_input_kbdbuf_count = $c6
.const hal_input_modal_dismiss_uses_fast_key = false
.const hal_input_followup_uses_fast_key = false
.const hal_input_selectable_overlay_prepare_followup = false
.const hal_input_modal_escape_primary = $03
.const hal_input_modal_escape_secondary = $1b
.const hal_input_flush_run_cancel_buffer = true
.const hal_input_help_footer_uses_esc_stop = false
.const hal_input_inventory_letter_normalize_shifted = false

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
    lda #0
    sta hal_input_kbdbuf_count
    jmp input_wait_release

input_get_key:
!poll:
    inc zp_entropy
    jsr KERNAL_GETIN
    beq !poll-
    rts

input_wait_release:
!drain:
    inc zp_entropy
    lda #0
    sta hal_input_kbdbuf_count
    jsr KERNAL_GETIN
    bne !drain-
    rts

input_any_key_held:
    lda #0
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

// petscii_to_command - Convert PETSCII key code to command ID
// Input:  A = PETSCII code
// Output: A = command ID
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
