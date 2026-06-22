// input.s - Commander X16 keyboard input HAL

#import "../../core/input_contract.s"
#import "../../core/input_tables.s"
#import "../../core/input_run_cancel.s"

.const hal_input_kbdbuf_count = $a80a
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
    jmp input_wait_release

input_get_key:
!poll:
    inc zp_entropy
    lda CX16_RAM_BANK_REG
    pha
    lda #0
    sta CX16_RAM_BANK_REG
    jsr KERNAL_GETIN
    tax
    pla
    sta CX16_RAM_BANK_REG
    txa
    beq !poll-
    rts

input_wait_release:
!drain:
    inc zp_entropy
    lda CX16_RAM_BANK_REG
    pha
    lda #0
    sta CX16_RAM_BANK_REG
    sta hal_input_kbdbuf_count
    jsr KERNAL_GETIN
    tax
    pla
    sta CX16_RAM_BANK_REG
    txa
    bne !drain-
    rts

input_any_key_held:
    lda CX16_RAM_BANK_REG
    pha
    lda #0
    sta CX16_RAM_BANK_REG
    lda hal_input_kbdbuf_count
    tax
    pla
    sta CX16_RAM_BANK_REG
    txa
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
    :EmitCx16PetsciiKeyMap()
    .byte $56   // V — version view

key_map_cmd:
    :EmitCx16CommandKeyMap()
    .byte CMD_VERSION

key_map_end:
.label key_map_count = key_map_cmd - key_map_petscii
.assert "Key map tables same size", key_map_count, key_map_end - key_map_cmd

.macro EmitCx16PetsciiKeyMap() {
    // Vi-keys (movement)
    .byte $4b   // K — north
    .byte $4a   // J — south
    .byte $48   // H — west
    .byte $4c   // L — east
    .byte $59   // Y — northwest
    .byte $55   // U — northeast
    .byte $42   // B — southwest
    .byte $4e   // N — southeast
    // Cursor keys
    .byte $91   // Cursor up — north
    .byte $11   // Cursor down — south
    .byte $9d   // Cursor left — west
    .byte $1d   // Cursor right — east
    // Top-row number keys (numeric movement fallback)
    .byte $38   // 8 — north
    .byte $32   // 2 — south
    .byte $34   // 4 — west
    .byte $36   // 6 — east
    .byte $37   // 7 — northwest
    .byte $39   // 9 — northeast
    .byte $31   // 1 — southwest
    .byte $33   // 3 — southeast
    .byte $35   // 5 — rest
    // Playable CX16 commands
    .byte $3e   // > — stairs down
    .byte $3c   // < — stairs up
    .byte $2e   // . — run prefix
    .byte $53   // S — search
    .byte $73   // s — search
    .byte $4f   // O — open
    .byte $43   // C — close
    .byte $47   // G — pick up
    .byte $2c   // , — pick up (alt)
    .byte $44   // D — drop
    .byte $49   // I — inventory
    .byte $45   // E — equipment
    .byte $57   // W — wear/wield
    .byte $54   // T — take off
    .byte $51   // Q — quaff
    .byte $52   // R — read scroll
    .byte $41   // A — aim wand
    .byte $5a   // Z — use staff
    .byte $3f   // ? — help
    .byte $58   // X — look / examine
    // Shifted and control keys
    .byte $c3   // SHIFT+C — character info
    .byte $d1   // SHIFT+Q — quit to title
    .byte $c5   // SHIFT+E — eat
    .byte $d2   // SHIFT+R — refuel lamp
    .byte $c4   // SHIFT+D — disarm trap
    .byte $d3   // SHIFT+S — save game
    .byte $02   // CTRL+B — bash
    .byte $12   // CTRL+R — rest until recovered
    .byte $23   // # — toggle search mode
    .byte $2b   // + — tunnel
    .byte $2f   // / — identify a symbol
    // Shifted vi-keys (running)
    .byte $cb   // SHIFT+K — run north
    .byte $ca   // SHIFT+J — run south
    .byte $c8   // SHIFT+H — run west
    .byte $cc   // SHIFT+L — run east
    .byte $d9   // SHIFT+Y — run northwest
    .byte $d5   // SHIFT+U — run northeast
    .byte $c2   // SHIFT+B — run southwest
    .byte $ce   // SHIFT+N — run southeast
}

.macro EmitCx16CommandKeyMap() {
    .byte CMD_MOVE_N, CMD_MOVE_S, CMD_MOVE_W, CMD_MOVE_E
    .byte CMD_MOVE_NW, CMD_MOVE_NE, CMD_MOVE_SW, CMD_MOVE_SE
    .byte CMD_MOVE_N, CMD_MOVE_S, CMD_MOVE_W, CMD_MOVE_E
    .byte CMD_MOVE_N, CMD_MOVE_S, CMD_MOVE_W, CMD_MOVE_E
    .byte CMD_MOVE_NW, CMD_MOVE_NE, CMD_MOVE_SW, CMD_MOVE_SE
    .byte CMD_REST
    .byte CMD_STAIRS_DN, CMD_STAIRS_UP, CMD_RUN, CMD_SEARCH, CMD_SEARCH
    .byte CMD_OPEN, CMD_CLOSE, CMD_PICKUP, CMD_PICKUP
    .byte CMD_DROP, CMD_INVENTORY, CMD_EQUIPMENT, CMD_WEAR
    .byte CMD_TAKEOFF, CMD_QUAFF, CMD_READ, CMD_AIM
    .byte CMD_USE, CMD_HELP, CMD_LOOK
    .byte CMD_CHAR_INFO, CMD_QUIT, CMD_EAT, CMD_REFUEL
    .byte CMD_DISARM, CMD_SAVE, CMD_BASH, CMD_AUTOREST, CMD_SEARCH_MODE
    .byte CMD_TUNNEL, CMD_RECALL
    .byte CMD_RUN_N, CMD_RUN_S, CMD_RUN_W, CMD_RUN_E
    .byte CMD_RUN_NW, CMD_RUN_NE, CMD_RUN_SW, CMD_RUN_SE
}
