// test_input.s — C64 input mapping/runtime smoke tests

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $0810 "Test Code"

#import "../../common/zeropage.s"
#import "../memory.s"
#import "../input.s"

input_tree_idx: .byte 0

input_tree_keys:
    .byte $4b, $4a, $48, $4c, $59, $55, $42, $4e
    .byte $91, $11, $9d, $1d
    .byte $3e, $3c, $2e, $53, $4f, $43, $47, $2c
    .byte $44, $49, $45, $57, $54, $51, $52, $41
    .byte $5a, $4d, $50, $3f, $58, $46, $66
    .byte $c3, $d1, $c5, $d3, $c6, $d4, $d2, $c4, $02
    .byte $23, $2b, $2f, $17
    .byte $cb, $ca, $c8, $cc, $d9, $d5, $c2, $ce

input_tree_cmds:
    .byte CMD_MOVE_N, CMD_MOVE_S, CMD_MOVE_W, CMD_MOVE_E
    .byte CMD_MOVE_NW, CMD_MOVE_NE, CMD_MOVE_SW, CMD_MOVE_SE
    .byte CMD_MOVE_N, CMD_MOVE_S, CMD_MOVE_W, CMD_MOVE_E
    .byte CMD_STAIRS_DN, CMD_STAIRS_UP, CMD_REST, CMD_SEARCH
    .byte CMD_OPEN, CMD_CLOSE, CMD_PICKUP, CMD_PICKUP
    .byte CMD_DROP, CMD_INVENTORY, CMD_EQUIPMENT, CMD_WEAR
    .byte CMD_TAKEOFF, CMD_QUAFF, CMD_READ, CMD_AIM
    .byte CMD_USE, CMD_CAST, CMD_PRAY, CMD_HELP
    .byte CMD_LOOK, CMD_GAIN, CMD_GAIN
    .byte CMD_CHAR_INFO, CMD_QUIT, CMD_EAT, CMD_SAVE
    .byte CMD_FIRE, CMD_THROW, CMD_REFUEL, CMD_DISARM, CMD_BASH
    .byte CMD_SEARCH_MODE, CMD_TUNNEL, CMD_RECALL, CMD_WIZARD
    .byte CMD_RUN_N, CMD_RUN_S, CMD_RUN_W, CMD_RUN_E
    .byte CMD_RUN_NW, CMD_RUN_NE, CMD_RUN_SW, CMD_RUN_SE

.label input_tree_expected_count = input_tree_cmds - input_tree_keys
.assert "input tree expected table sizes match", input_tree_expected_count, * - input_tree_cmds

test_start:
    sei
    cld
    ldx #$ff
    txs

    ldx #15
    lda #$ff
!clr:
    sta $0400,x
    dex
    bpl !clr-

    // ==========================================
    // Test 1: vi movement keys map correctly
    // ==========================================
    lda #$4b               // K
    jsr petscii_to_command
    cmp #CMD_MOVE_N
    bne !t1_fail+
    lda #$4a               // J
    jsr petscii_to_command
    cmp #CMD_MOVE_S
    bne !t1_fail+
    lda #$48               // H
    jsr petscii_to_command
    cmp #CMD_MOVE_W
    bne !t1_fail+
    lda #$4c               // L
    jsr petscii_to_command
    cmp #CMD_MOVE_E
    bne !t1_fail+
    lda #$01
    sta $0400
    jmp !t1_done+
!t1_fail:
    lda #$00
    sta $0400
!t1_done:

    // ==========================================
    // Test 2: diagonal vi movement maps correctly
    // ==========================================
    lda #$59               // Y
    jsr petscii_to_command
    cmp #CMD_MOVE_NW
    bne !t2_fail+
    lda #$55               // U
    jsr petscii_to_command
    cmp #CMD_MOVE_NE
    bne !t2_fail+
    lda #$42               // B
    jsr petscii_to_command
    cmp #CMD_MOVE_SW
    bne !t2_fail+
    lda #$4e               // N
    jsr petscii_to_command
    cmp #CMD_MOVE_SE
    bne !t2_fail+
    lda #$01
    sta $0401
    jmp !t2_done+
!t2_fail:
    lda #$00
    sta $0401
!t2_done:

    // ==========================================
    // Test 3: cursor keys map to movement
    // ==========================================
    lda #$91               // Cursor up
    jsr petscii_to_command
    cmp #CMD_MOVE_N
    bne !t3_fail+
    lda #$11               // Cursor down
    jsr petscii_to_command
    cmp #CMD_MOVE_S
    bne !t3_fail+
    lda #$9d               // Cursor left
    jsr petscii_to_command
    cmp #CMD_MOVE_W
    bne !t3_fail+
    lda #$1d               // Cursor right
    jsr petscii_to_command
    cmp #CMD_MOVE_E
    bne !t3_fail+
    lda #$01
    sta $0402
    jmp !t3_done+
!t3_fail:
    lda #$00
    sta $0402
!t3_done:

    // ==========================================
    // Test 4: common commands map correctly
    // ==========================================
    lda #$53               // S
    jsr petscii_to_command
    cmp #CMD_SEARCH
    bne !t4_fail+
    lda #$4f               // O
    jsr petscii_to_command
    cmp #CMD_OPEN
    bne !t4_fail+
    lda #$43               // C
    jsr petscii_to_command
    cmp #CMD_CLOSE
    bne !t4_fail+
    lda #$47               // G
    jsr petscii_to_command
    cmp #CMD_PICKUP
    bne !t4_fail+
    lda #$2c               // ,
    jsr petscii_to_command
    cmp #CMD_PICKUP
    bne !t4_fail+
    lda #$01
    sta $0403
    jmp !t4_done+
!t4_fail:
    lda #$00
    sta $0403
!t4_done:

    // ==========================================
    // Test 5: spell/help/look mappings
    // ==========================================
    lda #$4d               // M
    jsr petscii_to_command
    cmp #CMD_CAST
    bne !t5_fail+
    lda #$50               // P
    jsr petscii_to_command
    cmp #CMD_PRAY
    bne !t5_fail+
    lda #$3f               // ?
    jsr petscii_to_command
    cmp #CMD_HELP
    bne !t5_fail+
    lda #$58               // X
    jsr petscii_to_command
    cmp #CMD_LOOK
    bne !t5_fail+
    lda #$2f               // /
    jsr petscii_to_command
    cmp #CMD_RECALL
    bne !t5_fail+
    lda #$01
    sta $0404
    jmp !t5_done+
!t5_fail:
    lda #$00
    sta $0404
!t5_done:

    // ==========================================
    // Test 6: shifted action keys map correctly
    // ==========================================
    lda #$c3               // SHIFT+C
    jsr petscii_to_command
    cmp #CMD_CHAR_INFO
    bne !t6_fail+
    lda #$d1               // SHIFT+Q
    jsr petscii_to_command
    cmp #CMD_QUIT
    bne !t6_fail+
    lda #$d3               // SHIFT+S
    jsr petscii_to_command
    cmp #CMD_SAVE
    bne !t6_fail+
    lda #$c4               // SHIFT+D
    jsr petscii_to_command
    cmp #CMD_DISARM
    bne !t6_fail+
    lda #$02               // CTRL+B
    jsr petscii_to_command
    cmp #CMD_BASH
    bne !t6_fail+
    lda #$01
    sta $0405
    jmp !t6_done+
!t6_fail:
    lda #$00
    sta $0405
!t6_done:

    // ==========================================
    // Test 7: shifted vi keys map to running commands
    // ==========================================
    lda #$cb               // SHIFT+K
    jsr petscii_to_command
    cmp #CMD_RUN_N
    bne !t7_fail+
    lda #$ca               // SHIFT+J
    jsr petscii_to_command
    cmp #CMD_RUN_S
    bne !t7_fail+
    lda #$c8               // SHIFT+H
    jsr petscii_to_command
    cmp #CMD_RUN_W
    bne !t7_fail+
    lda #$cc               // SHIFT+L
    jsr petscii_to_command
    cmp #CMD_RUN_E
    bne !t7_fail+
    lda #$d9               // SHIFT+Y
    jsr petscii_to_command
    cmp #CMD_RUN_NW
    bne !t7_fail+
    lda #$d5               // SHIFT+U
    jsr petscii_to_command
    cmp #CMD_RUN_NE
    bne !t7_fail+
    lda #$c2               // SHIFT+B
    jsr petscii_to_command
    cmp #CMD_RUN_SW
    bne !t7_fail+
    lda #$ce               // SHIFT+N
    jsr petscii_to_command
    cmp #CMD_RUN_SE
    bne !t7_fail+
    lda #$01
    sta $0406
    jmp !t7_done+
!t7_fail:
    lda #$00
    sta $0406
!t7_done:

    // ==========================================
    // Test 8: alternate/special command mappings
    // ==========================================
    lda #$c5               // SHIFT+E
    jsr petscii_to_command
    cmp #CMD_EAT
    bne !t8_fail+
    lda #$c6               // SHIFT+F
    jsr petscii_to_command
    cmp #CMD_FIRE
    bne !t8_fail+
    lda #$d4               // SHIFT+T
    jsr petscii_to_command
    cmp #CMD_THROW
    bne !t8_fail+
    lda #$d2               // SHIFT+R
    jsr petscii_to_command
    cmp #CMD_REFUEL
    bne !t8_fail+
    lda #$2b               // +
    jsr petscii_to_command
    cmp #CMD_TUNNEL
    bne !t8_fail+
    lda #$01
    sta $0407
    jmp !t8_done+
!t8_fail:
    lda #$00
    sta $0407
!t8_done:

    // ==========================================
    // Test 9: unmapped key returns CMD_NONE
    // ==========================================
    lda #$30               // 0
    jsr petscii_to_command
    cmp #CMD_NONE
    bne !t9_fail+
    lda #$20               // Space
    jsr petscii_to_command
    cmp #CMD_NONE
    bne !t9_fail+
    lda #$0d               // Return
    jsr petscii_to_command
    cmp #CMD_NONE
    bne !t9_fail+
    lda #$01
    sta $0408
    jmp !t9_done+
!t9_fail:
    lda #$00
    sta $0408
!t9_done:

    // ==========================================
    // Test 10: run cancel edge logic ignores held state and rearms on release
    // ==========================================
    jsr input_run_cancel_reset

    lda #0
    jsr input_run_process_sample
    cmp #0
    bne !t10_fail+

    lda #1
    jsr input_run_process_sample
    cmp #0
    bne !t10_fail+

    lda #1
    jsr input_run_process_sample
    cmp #1
    bne !t10_fail+

    lda #0
    jsr input_run_process_sample
    cmp #0
    bne !t10_fail+

    lda #0
    jsr input_run_process_sample
    cmp #0
    bne !t10_fail+

    lda #1
    jsr input_run_process_sample
    cmp #0
    bne !t10_fail+

    lda #1
    jsr input_run_process_sample
    cmp #1
    bne !t10_fail+

    lda #$01
    sta $0409
    jmp !t10_done+
!t10_fail:
    lda #$00
    sta $0409
!t10_done:

    // ==========================================
    // Test 11: # maps to search-mode toggle
    // ==========================================
    lda #$23               // #
    jsr petscii_to_command
    cmp #CMD_SEARCH_MODE
    bne !t11_fail+
    lda #$01
    sta $040a
    jmp !t11_done+
!t11_fail:
    lda #$00
    sta $040a
!t11_done:

    // ==========================================
    // Test 12: lowercase f maps to learn, not fire
    // ==========================================
    lda #$66               // f
    jsr petscii_to_command
    cmp #CMD_GAIN
    bne !t12_fail+
    lda #$01
    sta $040b
    jmp !t12_done+
!t12_fail:
    lda #$00
    sta $040b
!t12_done:

    // ==========================================
    // Test 13: full PETSCII command map contract
    // ==========================================
    lda #0
    sta input_tree_idx
!t13_loop:
    ldx input_tree_idx
    cpx #input_tree_expected_count
    beq !t13_pass+
    lda input_tree_keys,x
    jsr petscii_to_command
    ldx input_tree_idx
    cmp input_tree_cmds,x
    bne !t13_fail+
    inc input_tree_idx
    jmp !t13_loop-
!t13_pass:
    lda #$01
    sta $040c
    jmp !t13_done+
!t13_fail:
    lda #$00
    sta $040c
!t13_done:

    // ==========================================
    // Test 14: input locks out KERNAL Shift+C= charset switching
    // ==========================================
    lda #0
    sta KERNAL_SHIFT_MODE
    jsr input_lock_charset_switch
    lda KERNAL_SHIFT_MODE
    and #KERNAL_CHARSET_SWITCH_LOCK
    cmp #KERNAL_CHARSET_SWITCH_LOCK
    bne !t14_fail+
    lda #$01
    sta $040d
    jmp !t14_done+
!t14_fail:
    lda #$00
    sta $040d
!t14_done:

    brk
