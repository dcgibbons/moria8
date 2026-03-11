// test_input128.s — C128 input mapping smoke test for C2.5

#import "../../common/zeropage.s"
#import "../input128.s"

c128_restore_runtime_vectors:
    rts

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $3000 "Test Code"

test_start:
    sei
    cld
    ldx #$ff
    txs

    // Keypad directional movement mappings
    lda #KEY_KP8
    jsr petscii_to_command
    cmp #CMD_MOVE_N
    bne test_fail

    lda #KEY_KP2
    jsr petscii_to_command
    cmp #CMD_MOVE_S
    bne test_fail

    lda #KEY_KP4
    jsr petscii_to_command
    cmp #CMD_MOVE_W
    bne test_fail

    lda #KEY_KP6
    jsr petscii_to_command
    cmp #CMD_MOVE_E
    bne test_fail

    lda #KEY_KP7
    jsr petscii_to_command
    cmp #CMD_MOVE_NW
    bne test_fail

    lda #KEY_KP9
    jsr petscii_to_command
    cmp #CMD_MOVE_NE
    bne test_fail

    lda #KEY_KP1
    jsr petscii_to_command
    cmp #CMD_MOVE_SW
    bne test_fail

    lda #KEY_KP3
    jsr petscii_to_command
    cmp #CMD_MOVE_SE
    bne test_fail

    lda #KEY_KP5
    jsr petscii_to_command
    cmp #CMD_REST
    bne test_fail

    lda #KEY_KP_PLUS
    jsr petscii_to_command
    cmp #CMD_TUNNEL
    bne test_fail
    jmp test_continue

test_fail:
    jmp test_fail_loop

test_continue:
    // Unshifted vi movement mappings.
    lda #$4b               // K
    jsr petscii_to_command
    cmp #CMD_MOVE_N
    bne test_fail
    lda #$4a               // J
    jsr petscii_to_command
    cmp #CMD_MOVE_S
    bne test_fail
    lda #$48               // H
    jsr petscii_to_command
    cmp #CMD_MOVE_W
    bne test_fail
    lda #$4c               // L
    jsr petscii_to_command
    cmp #CMD_MOVE_E
    bne test_fail

    // Core command mappings involved in recent regressions
    lda #$54               // T
    jsr petscii_to_command
    cmp #CMD_TAKEOFF
    bne test_fail

    lda #$58               // X
    jsr petscii_to_command
    cmp #CMD_LOOK
    bne test_fail

    lda #$d1               // SHIFT+Q
    jsr petscii_to_command
    cmp #CMD_QUIT
    bne test_fail

    // Shifted vi-keys map to running commands.
    lda #$cb               // SHIFT+K
    jsr petscii_to_command
    cmp #CMD_RUN_N
    bne test_fail
    lda #$ca               // SHIFT+J
    jsr petscii_to_command
    cmp #CMD_RUN_S
    bne test_fail
    lda #$c8               // SHIFT+H
    jsr petscii_to_command
    cmp #CMD_RUN_W
    bne test_fail
    lda #$cc               // SHIFT+L
    jsr petscii_to_command
    cmp #CMD_RUN_E
    bne test_fail

    // ESC mapping (current C2.4 policy: quit shortcut)
    lda #KEY_ESC
    jsr petscii_to_command
    cmp #CMD_QUIT
    bne test_fail2

    // Unmapped keypad/extended keys should return CMD_NONE
    lda #KEY_KP_MINUS
    jsr petscii_to_command
    cmp #CMD_NONE
    bne test_fail2

    lda #KEY_KP_DOT
    jsr petscii_to_command
    cmp #CMD_NONE
    bne test_fail2

    lda #KEY_KP0
    jsr petscii_to_command
    cmp #CMD_NONE
    bne test_fail2

    lda #KEY_ALT
    jsr petscii_to_command
    cmp #CMD_NONE
    bne test_fail2

    lda #KEY_LF
    jsr petscii_to_command
    cmp #CMD_NONE
    bne test_fail2

    jmp test_edge_checks

test_fail2:
    jmp test_fail_loop

test_edge_checks:
    // Edge-transition behavior:
    // - key-down from idle is accepted on first sample
    // - key release also requires 2 stable samples
    lda #0
    sta igk_last_sample
    sta igk_stable

    lda #0
    jsr input_process_sample
    cmp #0
    bne test_fail2

    lda #$45               // First sample of 'E' => immediate key-down event
    jsr input_process_sample
    cmp #$45
    bne test_fail2

    lda #$45               // Stable held key => no repeat event
    jsr input_process_sample
    cmp #0
    bne test_fail2

    lda #$45               // Held key => no repeated event
    jsr input_process_sample
    cmp #0
    bne test_fail2

    lda #0                 // First release sample: no event, still armed
    jsr input_process_sample
    cmp #0
    bne test_fail2
    lda igk_stable
    cmp #$45
    bne test_fail2

    lda #0                 // Second release sample: rearmed
    jsr input_process_sample
    cmp #0
    bne test_fail2
    lda igk_stable
    cmp #0
    bne test_fail2

    lda #$45               // Retap sample 1 => no event
    jsr input_process_sample
    cmp #0
    bne test_fail2

    lda #$45               // Retap sample 2 => event again
    jsr input_process_sample
    cmp #$45
    bne test_fail2

    jmp test_scan_restore_checks

test_fail3:
    jmp test_fail_loop

test_scan_restore_checks:
    // Scan routine must always restore keyboard drive registers.
    lda C128_KBD_EXT
    sta test_ext_orig
    lda #%00001111
    sta C128_KBD_EXT
    lda #$00
    sta CIA1_PORTA
    jsr cia_scan_petscii
    lda CIA1_PORTA
    cmp #$FF
    bne test_fail3
    lda C128_KBD_EXT
    cmp #%00001111
    bne test_fail3
    lda test_ext_orig
    sta C128_KBD_EXT

    jmp test_pass

test_fail_loop:
    jmp test_fail_loop

test_pass:
    jmp test_pass

test_ext_orig:
    .byte 0
