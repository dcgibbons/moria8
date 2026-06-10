#importonce
// test_input128.s — C128 input mapping smoke test for C2.5

#define C128
#define C128_INPUT_TEST
#import "../../common/zeropage.s"
#import "../input128.s"
#import "../input_run_raw128.s"

c128_restore_runtime_vectors:
    rts

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $3000 "Test Code"

input_tree_idx: .byte 0

input_tree_keys:
    .byte $4b, $4a, $48, $4c, $59, $55, $42, $4e
    .byte $91, $11, $9d, $1d
    .byte $38, $32, $34, $36, $37, $39, $31, $33, $35
    .byte $3e, $3c, $2e, $53, $4f, $43, $47, $2c
    .byte $44, $49, $45, $57, $54, $51, $52, $41
    .byte $5a, $4d, $50, $3f, $58, $46, $66
    .byte $c3, $d1, $c5, $d3, $c6, $d4, $d2, $c4, $02
    .byte $12, $23, $2b, $2f, $17
    .byte $cb, $ca, $c8, $cc, $d9, $d5, $c2, $ce
    .byte KEY_ESC
    .byte KEY_KP_MINUS, KEY_KP0, KEY_ALT, KEY_LF

input_tree_cmds:
    .byte CMD_MOVE_N, CMD_MOVE_S, CMD_MOVE_W, CMD_MOVE_E
    .byte CMD_MOVE_NW, CMD_MOVE_NE, CMD_MOVE_SW, CMD_MOVE_SE
    .byte CMD_MOVE_N, CMD_MOVE_S, CMD_MOVE_W, CMD_MOVE_E
    .byte CMD_MOVE_N, CMD_MOVE_S, CMD_MOVE_W, CMD_MOVE_E
    .byte CMD_MOVE_NW, CMD_MOVE_NE, CMD_MOVE_SW, CMD_MOVE_SE
    .byte CMD_REST
    .byte CMD_STAIRS_DN, CMD_STAIRS_UP, CMD_RUN, CMD_SEARCH
    .byte CMD_OPEN, CMD_CLOSE, CMD_PICKUP, CMD_PICKUP
    .byte CMD_DROP, CMD_INVENTORY, CMD_EQUIPMENT, CMD_WEAR
    .byte CMD_TAKEOFF, CMD_QUAFF, CMD_READ, CMD_AIM
    .byte CMD_USE, CMD_CAST, CMD_PRAY, CMD_HELP
    .byte CMD_LOOK, CMD_GAIN, CMD_GAIN
    .byte CMD_CHAR_INFO, CMD_QUIT, CMD_EAT, CMD_SAVE
    .byte CMD_FIRE, CMD_THROW, CMD_REFUEL, CMD_DISARM, CMD_BASH
    .byte CMD_AUTOREST, CMD_SEARCH_MODE, CMD_TUNNEL, CMD_RECALL, CMD_WIZARD
    .byte CMD_RUN_N, CMD_RUN_S, CMD_RUN_W, CMD_RUN_E
    .byte CMD_RUN_NW, CMD_RUN_NE, CMD_RUN_SW, CMD_RUN_SE
    .byte CMD_QUIT
    .byte CMD_NONE, CMD_NONE, CMD_NONE, CMD_NONE

.label input_tree_expected_count = input_tree_cmds - input_tree_keys
.assert "input128 tree expected table sizes match", input_tree_expected_count, * - input_tree_cmds

test_start:
    sei
    cld
    ldx #$ff
    txs
    jmp !test0_start+

test_fail0:
    jmp test_fail_loop

!test0_start:

    // Top-row number movement mappings. The C128 keypad scanner emits these
    // same PETSCII values for keypad 1-9/+.
    lda #$38
    jsr petscii_to_command
    cmp #CMD_MOVE_N
    bne test_fail0

    lda #$32
    jsr petscii_to_command
    cmp #CMD_MOVE_S
    bne test_fail0

    lda #$34
    jsr petscii_to_command
    cmp #CMD_MOVE_W
    bne test_fail0

    lda #$36
    jsr petscii_to_command
    cmp #CMD_MOVE_E
    bne test_fail0

    lda #$37
    jsr petscii_to_command
    cmp #CMD_MOVE_NW
    bne test_fail0

    lda #$39
    jsr petscii_to_command
    cmp #CMD_MOVE_NE
    bne test_fail0

    lda #$31
    jsr petscii_to_command
    cmp #CMD_MOVE_SW
    bne test_fail0

    lda #$33
    jsr petscii_to_command
    cmp #CMD_MOVE_SE
    bne test_fail0

    lda #$35
    jsr petscii_to_command
    cmp #CMD_REST
    bne test_fail0

    lda #$2e
    jsr petscii_to_command
    cmp #CMD_RUN
    bne test_fail0

    lda #$2b
    jsr petscii_to_command
    cmp #CMD_TUNNEL
    bne test_fail0

    // C128 extended matrix table layout:
    // K2: HELP, KP8, KP5, TAB, KP2, KP4, KP7, KP1
    // K1: ESC, KP+, KP-, LF, KPENTER, KP6, KP9, KP3
    // K0: ALT, KP0, KP., UP, DOWN, LEFT, RIGHT, NO-SCROLL
    ldx #65
    lda cia_scancode_table,x
    cmp #$38
    bne !ext_table_fail+

    ldx #66
    lda cia_scancode_table,x
    cmp #$35
    bne !ext_table_fail+

    ldx #68
    lda cia_scancode_table,x
    cmp #$32
    bne !ext_table_fail+

    ldx #77
    lda cia_scancode_table,x
    cmp #$36
    bne !ext_table_fail+

    ldx #78
    lda cia_scancode_table,x
    cmp #$39
    bne !ext_table_fail+

    ldx #81
    lda cia_scancode_table,x
    cmp #KEY_KP0
    bne !ext_table_fail+

    ldx #82
    lda cia_scancode_table,x
    cmp #$2e
    bne !ext_table_fail+
    lda irs_ext_masks
    cmp #%11111110
    bne !ext_table_fail+
    lda irs_ext_masks + 1
    cmp #%11111101
    bne !ext_table_fail+
    lda irs_ext_masks + 2
    cmp #%11111011
    bne !ext_table_fail+
    jmp !ext_table_done+
!ext_table_fail:
    jmp test_fail_loop
!ext_table_done:
    
    // Ctrl+W normalization helper should rescue fast-path chord races.
    lda #$57               // W
    ldy #1                 // Ctrl held
    jsr input_normalize_ctrl_chords_with_state
    cmp #$17
    bne test_fail

    lda #$d7               // SHIFT+W fallback
    ldy #1
    jsr input_normalize_ctrl_chords_with_state
    cmp #$17
    bne test_fail

    lda #$33               // Shifted 3 should normalize to #
    ldy #1
    jsr input_normalize_shifted_symbols_with_state
    cmp #$23
    bne test_fail

    lda #$33
    ldy #0                 // Unshifted 3 stays 3
    jsr input_normalize_shifted_symbols_with_state
    cmp #$33
    bne test_fail

    lda #$57
    ldy #0                 // No Ctrl => stays W
    jsr input_normalize_ctrl_chords_with_state
    cmp #$57
    bne test_fail

    lda #$42               // B
    ldy #1                 // Ctrl held
    jsr input_normalize_ctrl_chords_with_state
    cmp #$02
    bne test_fail

    lda #$52               // R
    ldy #1                 // Ctrl held
    jsr input_normalize_ctrl_chords_with_state
    cmp #$12
    bne test_fail

    lda #$d2               // SHIFT+R
    ldy #1                 // Ctrl held
    jsr input_normalize_ctrl_chords_with_state
    cmp #$12
    bne test_fail

    lda #$52               // Plain R still reads scrolls
    ldy #0
    jsr input_normalize_ctrl_chords_with_state
    cmp #$52
    bne test_fail

    lda #$17               // Normalized CTRL+W should map to wizard mode
    jsr petscii_to_command
    cmp #CMD_WIZARD
    bne test_fail
    lda #$12               // Normalized CTRL+R should map to auto-rest
    jsr petscii_to_command
    cmp #CMD_AUTOREST
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

    lda #$23               // #
    jsr petscii_to_command
    cmp #CMD_SEARCH_MODE
    bne test_fail

    lda #$c4               // SHIFT+D
    jsr petscii_to_command
    cmp #CMD_DISARM
    bne test_fail

    lda #$02               // CTRL+B
    jsr petscii_to_command
    cmp #CMD_BASH
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
    bne test_fail2

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

    lda #0
    sta input_tree_idx
!full_tree_loop:
    ldx input_tree_idx
    cpx #input_tree_expected_count
    beq !full_tree_done+
    lda input_tree_keys,x
    jsr petscii_to_command
    ldx input_tree_idx
    cmp input_tree_cmds,x
    bne test_fail2
    inc input_tree_idx
    jmp !full_tree_loop-
!full_tree_done:

    jmp test_edge_checks

test_fail2:
    jmp test_fail_loop

test_edge_checks:
    // Fast command-entry edge behavior:
    // - key-down from idle is accepted on first sample
    // - key release requires 2 stable samples
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

    lda #$45               // Retap sample 1 => event again (fast path)
    jsr input_process_sample
    cmp #$45
    bne test_fail2

    jmp test_strict_prompt_checks

test_strict_prompt_checks:
    // Prompt-input behavior:
    // - key-down requires 2 stable samples
    // - key release requires 2 stable samples
    lda #0
    sta igk_last_sample
    sta igk_stable

    lda #0
    jsr input_process_sample_strict
    cmp #0
    bne !strict_fail+

    lda #$45               // First prompt sample => no event
    jsr input_process_sample_strict
    cmp #0
    bne !strict_fail+
    lda igk_stable
    cmp #0
    bne !strict_fail+

    lda #$45               // Second prompt sample => stable key-down event
    jsr input_process_sample_strict
    cmp #$45
    bne !strict_fail+
    lda igk_stable
    cmp #$45
    bne !strict_fail+

    lda #$45               // Held key => no repeat event
    jsr input_process_sample_strict
    cmp #0
    bne !strict_fail+

    lda #0                 // First release sample => no event, still armed
    jsr input_process_sample_strict
    cmp #0
    bne !strict_fail+
    lda igk_stable
    cmp #$45
    bne !strict_fail+

    lda #0                 // Second release sample => rearmed
    jsr input_process_sample_strict
    cmp #0
    bne !strict_fail+
    lda igk_stable
    cmp #0
    bne !strict_fail+

    jmp test_run_cancel_checks
!strict_fail:
    jmp test_fail2

test_run_cancel_checks:
    jsr input_run_cancel_reset

    lda #0
    jsr input_run_process_sample
    cmp #0
    bne test_fail3

    lda #$58               // First press sample => no event yet
    jsr input_run_process_sample
    cmp #0
    bne test_fail3

    lda #$58               // Stable held key => cancel edge
    jsr input_run_process_sample
    cmp #1
    bne test_fail3

    lda #0                 // First release sample => no event
    jsr input_run_process_sample
    cmp #0
    bne test_fail3

    lda #0                 // Stable release => fully rearmed
    jsr input_run_process_sample
    cmp #0
    bne test_fail3

    lda #$51               // First press sample after rearm => no event yet
    jsr input_run_process_sample
    cmp #0
    bne test_fail3

    lda #$51               // Stable press => cancel edge again
    jsr input_run_process_sample
    cmp #1
    bne test_fail3

    jmp test_run_raw_row_checks

test_fail3:
    jmp test_fail_loop

test_run_raw_row_checks:
    lda #$7f               // Row 1: left shift only
    ldx #1
    jsr input_run_row_has_nonmodifier
    cmp #0
    bne test_fail3

    lda #$fd               // Row 1: W pressed
    ldx #1
    jsr input_run_row_has_nonmodifier
    cmp #1
    bne test_fail3

    lda #$ef               // Row 6: right shift only
    ldx #6
    jsr input_run_row_has_nonmodifier
    cmp #0
    bne test_fail3

    lda #$fb               // Row 7: CTRL only
    ldx #7
    jsr input_run_row_has_nonmodifier
    cmp #0
    bne test_fail3

    lda #$df               // Row 7: C= only
    ldx #7
    jsr input_run_row_has_nonmodifier
    cmp #0
    bne test_fail3

    lda #$7f               // Row 7: STOP pressed
    ldx #7
    jsr input_run_row_has_nonmodifier
    cmp #1
    bne test_fail3

    lda #$fe               // Row 10/K0: ALT only
    ldx #10
    jsr input_run_row_has_nonmodifier
    cmp #0
    bne test_fail3

    lda #$fd               // Row 8/K2: keypad 8 pressed
    ldx #8
    jsr input_run_row_has_nonmodifier
    cmp #1
    bne test_fail3

    lda #$fd               // Row 10/K0: keypad 0 pressed
    ldx #10
    jsr input_run_row_has_nonmodifier
    cmp #1
    bne test_fail3

    lda #$fe               // Row 9/K1: ESC pressed
    ldx #9
    jsr input_run_row_has_nonmodifier
    cmp #1
    bne test_fail3

    jmp test_scan_restore_checks

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
    bne !scan_restore_fail+
    lda C128_KBD_EXT
    cmp #%00001111
    bne !scan_restore_fail+
    lda test_ext_orig
    sta C128_KBD_EXT

    lda #%00110011
    sta C128_KBD_EXT
    lda #$12
    sta CIA1_PORTA
    lda #$34
    sta CIA1_DDRA
    lda #$56
    sta CIA1_DDRB
    jsr input_run_scan_held_raw
    cmp #0
    bne !scan_restore_fail+
    lda CIA1_PORTA
    cmp #$12
    bne !scan_restore_fail+
    lda CIA1_DDRA
    cmp #$34
    bne !scan_restore_fail+
    lda CIA1_DDRB
    cmp #$56
    bne !scan_restore_fail+
    lda C128_KBD_EXT
    cmp #%00110011
    bne !scan_restore_fail+

    jmp test_pass
!scan_restore_fail:
    jmp test_fail3

test_fail_loop:
    jmp test_fail_loop

test_pass:
    jmp test_pass

test_ext_orig:
    .byte 0
