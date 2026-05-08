// input.s — Plus/4 keyboard input and command parsing

#import "../common/input_contract.s"
#import "../common/input_tables.s"
#import "../common/input_run_cancel.s"

.const KERNAL_SCNKEY = $ff9f
.const KERNAL_GETIN  = $ffe4
.const TED_KEY_LATCH = $ff08
.const PLUS4_KEY_SELECT = $fd30

input_lock_charset_switch:
    jmp plus4_display_resync

input_run_key_held:
    jmp plus4_any_nonmodifier_key_held

input_run_key_check:
    jmp input_run_key_held

input_run_cancel_check:
    jsr input_run_key_held
    jmp input_run_process_sample

input_get_key:
#if PLUS4_TEST_SCRIPTED_DISK_SETUP_PRODUCT || PLUS4_TEST_SCRIPTED_LOAD_RESUME_PRODUCT || PLUS4_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
    ldx plus4_test_key_index
    lda plus4_test_key_script,x
    beq !wait+
    inc plus4_test_key_index
    rts
!wait:
    jmp !wait-
plus4_test_key_index: .byte 0
plus4_test_key_script:
#if PLUS4_TEST_SCRIPTED_LOAD_RESUME_PRODUCT
    .byte $4c, 0                                 // L
#elif PLUS4_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
    .byte $4c, $d3, 0                            // L, SHIFT+S
#else
    .byte $44, $59, $20, $59, 0       // D, Y, SPACE, Y
#endif
#else
    php
    sei
!poll:
    inc zp_entropy
    sta PLUS4_ROM_ENABLE
    jsr KERNAL_SCNKEY
    jsr KERNAL_GETIN
    sei
    pha
    sta PLUS4_RAM_ENABLE
    jsr plus4_display_resync
    pla
    beq !poll-
    sta igk_key
    lda #0
    sta zp_kbdbuf_count
    jsr input_wait_release
    plp
    lda igk_key
    rts

igk_key: .byte 0
#endif

input_wait_release:
    php
    sei
!drain:
    inc zp_entropy
    lda #0
    sta zp_kbdbuf_count
    sta PLUS4_ROM_ENABLE
    jsr KERNAL_GETIN
    sei
    sta PLUS4_RAM_ENABLE
    bne !drain-
!wait_up:
    jsr plus4_any_nonmodifier_key_held
    bne !wait_up-
    jsr plus4_input_settle
    jsr plus4_any_nonmodifier_key_held
    bne !wait_up-
    jsr plus4_display_resync
    plp
    rts

plus4_any_nonmodifier_key_held:
    ldx #0
!scan:
    lda plus4_key_select,x
    sta PLUS4_KEY_SELECT
    lda #$ff
    sta TED_KEY_LATCH
    lda TED_KEY_LATCH
    ora plus4_modifier_mask,x
    cmp #$ff
    bne !held+
    inx
    cpx #8
    bcc !scan-
    lda #$ff
    sta PLUS4_KEY_SELECT
    sta TED_KEY_LATCH
    lda #0
    rts
!held:
    lda #$ff
    sta PLUS4_KEY_SELECT
    sta TED_KEY_LATCH
    lda #1
    rts

plus4_input_settle:
    ldx #$08
!outer:
    ldy #0
!inner:
    dey
    bne !inner-
    dex
    bne !outer-
    rts

plus4_key_select:
    .byte $fe,$fd,$fb,$f7,$ef,$df,$bf,$7f

plus4_modifier_mask:
    .byte $00,$80,$00,$00,$00,$20,$00,$04

// input_get_command — Wait for a keypress, return command ID
// Output: A = command ID (CMD_* constant)
//         zp_input_cmd = same
//         zp_input_count = repeat count (currently always 1; numeric prefixes are deferred)
// Preserves: nothing
input_get_command:
    lda #1
    sta zp_input_count
!get_key:
    jsr input_get_key
    jsr petscii_to_command
    cmp #CMD_NONE
    beq !get_key-
    sta zp_input_cmd
    rts

// petscii_to_command — Convert PETSCII key code to command ID
// Input:  A = PETSCII code
// Output: A = command ID
// Preserves: X, Y
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
