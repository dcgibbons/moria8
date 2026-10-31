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
.const CX16_KEYHDL = $032e  // KERNAL key event vector: A = keynum, bit 7 set on key up
.const CX16_KEY_DOWN_BYTES = 16
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
.label hal_input_modal_prepare = input_wait_release
.label hal_input_modal_finish = input_noop

input_noop:
    rts

// input_get_key — Wait for a keypress from KERNAL GETIN, preserving X and Y
// as well as the caller's active RAM bank ($00). When cx16_testbench_enabled
// is nonzero and the keyboard queue is empty, yields to x16emu -testbench at
// $FFFD so the harness can inspect state and inject the next key.
input_get_key:
    stx igk_save_x
    sty igk_save_y
input_get_key_poll:
    inc zp_entropy
    jsr hal_sound_update
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

// input_wait_release — Wait until no key is held, then empty the KERNAL
// queue: a key typed ahead, or pressed while another was still down
// (rollover), never answers what follows (as on the other ports). The KERNAL
// queue holds only key-downs, so cx16_key_event keeps which keys are down.
// Preserves: X, Y
input_wait_release:
    phx
    phy
    lda CX16_RAM_BANK_REG
    pha
    lda #CX16_BANK_KERNAL_VARS
    sta CX16_RAM_BANK_REG
    stz iwr_count
    lda #42                 // Held: about 0.25 s (184-cycle loop at 8 MHz)
    sta iwr_count + 1
!held:
    inc zp_entropy
    jsr hal_sound_update
    ldx #CX16_KEY_DOWN_BYTES - 1
    lda #0
!any:
    ora cx16_key_down,x     // Every byte, every pass: a fixed-length loop
    dex
    bpl !any-
    tax
    beq !up+
    dec iwr_count           // Counted, not timed (the testbench's jiffy clock stops); longer while a sound plays
    bne !held-
    dec iwr_count + 1
    bne !held-
    ldx #CX16_KEY_DOWN_BYTES - 1
!forget:
    stz cx16_key_down,x     // Held too long, or a key-up was lost: stop waiting on it
    dex
    bpl !forget-
!up:
    stz hal_input_kbdbuf_count
!drain:
    jsr KERNAL_GETIN
    bne !drain-
    pla
    sta CX16_RAM_BANK_REG
    ply
    plx
    rts

iwr_count: .word 0

// cx16_key_event — keyhdl hook (IRQ): mark the key down or up in
// cx16_key_down, then hand the event on unchanged. Modifiers count too, as
// the C64's release wait counts them (hal_input.s contract).
cx16_key_event:
    sta ckev_code
    pha
    phx
    phy
    and #$7f
    tay
    and #7
    tax
    lda cx16_bit_masks,x
    sta ckev_mask
    tya
    lsr
    lsr
    lsr
    tax
    lda ckev_code
    bmi !key_up+
    lda cx16_key_down,x
    ora ckev_mask
    bra !store+
!key_up:
    lda ckev_mask
    eor #$ff
    and cx16_key_down,x
!store:
    sta cx16_key_down,x
    ply
    plx
    pla
    jmp (cx16_keyhdl_next)

// cx16_input_install_key_events — Chain cx16_key_event onto keyhdl, once:
// restarts (jmp entry_main) run hal_platform_init_early again, and chaining
// the hook onto itself would loop in the IRQ.
cx16_input_install_key_events:
    // keyhdl hands on key numbers from R43; before, raw PS/2 scancodes, so
    // a ROM known to be older gets no hook (and the wait only drains, as it
    // did). $FF80: R<N> as N, a build after R<N> as -N, $00/$FF unknown.
    lda CX16_KERNAL_REV     // ROM bank 0: hal_platform_init_early selects it
    beq !check_hook+
    cmp #$ff
    beq !check_hook+
    bpl !release+
    eor #$ff
    inc
!release:
    cmp #43
    bcc !installed+
!check_hook:
    lda CX16_KEYHDL
    cmp #<cx16_key_event
    bne !install+
    lda CX16_KEYHDL + 1
    cmp #>cx16_key_event
    beq !installed+
!install:
    php
    sei
    lda CX16_KEYHDL
    sta cx16_keyhdl_next
    lda CX16_KEYHDL + 1
    sta cx16_keyhdl_next + 1
    lda #<cx16_key_event
    sta CX16_KEYHDL
    lda #>cx16_key_event
    sta CX16_KEYHDL + 1
    plp
!installed:
    rts

cx16_key_down:      .fill CX16_KEY_DOWN_BYTES, 0    // one bit per keynum 0-127
cx16_keyhdl_next:   .word 0
ckev_code:          .byte 0
ckev_mask:          .byte 0
cx16_bit_masks:     .byte $01, $02, $04, $08, $10, $20, $40, $80
.assert "keyhdl hook and its state live in unbanked low RAM", cx16_key_event >= $0801 && * <= $9f00, true

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
