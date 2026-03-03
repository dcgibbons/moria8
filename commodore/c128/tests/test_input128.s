// test_input128.s — C128 input mapping smoke test for C2.5

#import "../../common/zeropage.s"
#import "../input128.s"

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
    // ESC mapping (current C2.4 policy: quit shortcut)
    lda #KEY_ESC
    jsr petscii_to_command
    cmp #CMD_QUIT
    bne test_fail

    // Unmapped keypad/extended keys should return CMD_NONE
    lda #KEY_KP_MINUS
    jsr petscii_to_command
    cmp #CMD_NONE
    bne test_fail

    lda #KEY_KP_DOT
    jsr petscii_to_command
    cmp #CMD_NONE
    bne test_fail

    lda #KEY_KP0
    jsr petscii_to_command
    cmp #CMD_NONE
    bne test_fail

    lda #KEY_ALT
    jsr petscii_to_command
    cmp #CMD_NONE
    bne test_fail

    lda #KEY_LF
    jsr petscii_to_command
    cmp #CMD_NONE
    bne test_fail

    jmp test_pass

test_fail_loop:
    jmp test_fail_loop

test_pass:
    jmp test_pass
