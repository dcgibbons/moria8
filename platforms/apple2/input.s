// input.s — Apple IIe keyboard input and command parsing
//
// Reads the keyboard hardware directly: $C000 bit 7 = latched keypress
// (data = ASCII, high bit set, pre-shifted by the encoder), any write to
// $C010 clears the strobe, and $C010 read bit 7 = any-key-down (IIe AKD,
// excludes SHIFT/CTRL/CAPS modifiers). The machine runs SEI always; polling
// is the only input path. There is no KERNAL-style typeahead buffer: the
// strobe latch holds exactly one pending key, so buffer-flush semantics map
// to a single strobe clear.
//
// ASCII -> normalized PETSCII translation feeds core/input_tables.s:
//   lowercase ASCII $61-$7A -> unshifted PETSCII letters $41-$5A
//   uppercase ASCII $41-$5A -> shifted PETSCII letters $C1-$DA
//   arrows $08/$15/$0B/$0A  -> $9D/$1D/$91/$11 (cursor keys)
//   DELETE $7F              -> $14 (PETSCII DEL, backspace in text entry)
//   everything else passes through unchanged (digits, punctuation, ESC $1B,
//   RETURN $0D, and CTRL chords $02/$12/$17 already match PETSCII).
// Note: with Caps Lock engaged the IIe encoder emits uppercase for unshifted
// letter presses, which then decode as shifted commands — a hardware
// limitation shared with every pre-shifted keyboard.
//
// Entropy: every wait/poll loop ticks the platform zero-page counters at
// $90-$93 (hal/entropy_consts.s), the RNG's keypress-timing entropy source.
//
// Numeric repeat prefixes are intentionally unimplemented.
// zp_input_count is currently fixed to 1 for all commands.
//
// IIe semantics are authoritative; IIc AKD behavior is verified separately.

#import "../../core/input_contract.s"
#import "../../core/input_tables.s"
#import "../../core/input_run_cancel.s"
#import "hal/entropy_consts.s"

// Keyboard hardware registers
.const A2_KBD         = $c000 // Read: bit 7 set = key latched, low 7 = ASCII
.const A2_KBDSTRB     = $c010 // Write: clear strobe. Read: bit 7 = any key down

// No KERNAL keyboard buffer exists on this platform; the constant names a
// harmless shadow byte so the (disabled) core flush path has a writable
// address. hal_input_flush_run_cancel_buffer = false keeps it unused.
.label hal_input_kbdbuf_count = input_kbdbuf_shadow
.const hal_input_modal_dismiss_uses_fast_key = false
.const hal_input_followup_uses_fast_key = false
.const hal_input_selectable_overlay_prepare_followup = false
.const hal_input_modal_escape_primary = $1b   // ESC — the Apple II cancel key
.const hal_input_modal_escape_secondary = $03 // CTRL+C — STOP-key equivalent
.const hal_input_flush_run_cancel_buffer = false
.const hal_input_help_footer_uses_esc_stop = true
#define HAL_INPUT_HELP_FOOTER_USES_ESC_STOP
.const hal_input_inventory_letter_normalize_shifted = false

// ============================================================
// Subroutines
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

// input_entropy_tick — Cascade-increment the platform entropy counters
// Preserves: A, X, Y
input_entropy_tick:
    inc hal_entropy_timer0_lo
    bne !iet_done+
    inc hal_entropy_timer0_hi
    bne !iet_done+
    inc hal_entropy_timer1_lo
    bne !iet_done+
    inc hal_entropy_timer1_hi
!iet_done:
    rts

// input_sound_update — Keep the speaker-click sound driver alive during
// long input waits (SEI world: no interrupt source ticks it for us).
input_sound_update:
    jmp hal_sound_update

// input_get_key — Wait for a keypress, return normalized PETSCII code
// Debounce policy: the encoder latch is inherently edge-based — one press
// produces one strobe, a held key never re-strobes (no IIe typematic), and
// the strobe is cleared as soon as the value is captured so the next press
// can latch immediately.
// Output: A = normalized PETSCII code of key pressed, C = 0 (success)
// Preserves: X, Y
input_get_key:
#if A2_DEBUG_SCRIPTED_INPUT
    // Harness-only scripted input: returns script bytes in order, then jams
    // so the reached page stays on screen for Lua dumps.
    ldx a2_script_idx
    lda a2_input_script,x
    beq !script_done+
    inc a2_script_idx
    clc
    rts
!script_done:
    jmp !script_done-
a2_script_idx: .byte 0
a2_input_script:
    // 'A' race Human, RETURN accept roll, 'A' class Warrior,
    // 'BOB'+RETURN name, 'A' male, RETURN dismiss summary, 6/6/6 move east
    .byte $41, $0d, $41, $42, $4f, $42, $0d, $41, $0d, $36, $36, $36, 0
#endif
    txa
    pha
    tya
    pha
!igk_poll:
    jsr input_entropy_tick
    jsr input_sound_update
    lda A2_KBD
    bpl !igk_poll-          // Bit 7 clear = no latched key
    sta A2_KBDSTRB          // Any write clears the keyboard strobe
    and #$7f
    jsr input_translate
    sta igk_key
    pla
    tay
    pla
    tax
    lda igk_key
    clc
    rts

igk_key: .byte 0
input_kbdbuf_shadow: .byte 0

// input_wait_release — Discard any latched keypress and wait until no key is
// physically held. Used before one-shot "press any key" prompts so a prior
// selection key does not auto-dismiss the next screen. Bound the AKD wait so
// an emulator-lost key-up event cannot deadlock the game; the strobe is still
// cleared on that exceptional fallback. Modifier keys need no explicit
// handling: they produce no latch and IIe AKD ignores them.
// Preserves: X, Y
input_wait_release:
    txa
    pha
    tya
    pha
    ldx #0
    ldy #16                 // About 0.25 s at 1 MHz before AKD fallback
!iwr_poll:
    jsr input_entropy_tick
    jsr input_sound_update
    lda A2_KBD
    bpl !iwr_no_latch+
    sta A2_KBDSTRB          // Discard latched keypress
!iwr_no_latch:
    bit A2_KBDSTRB          // Read: bit 7 = any-key-down
    bpl !iwr_stable+
!iwr_held:
    inx
    bne !iwr_poll-
    dey
    bne !iwr_poll-
    sta A2_KBDSTRB          // Lost key-up fallback: leave no pending strobe
    jmp !iwr_done+
!iwr_stable:
    // Require two consecutive clean polls for stability (C64 parity).
    lda A2_KBD
    bmi !iwr_held-
    bit A2_KBDSTRB
    bmi !iwr_held-
!iwr_done:
    pla
    tay
    pla
    tax
    rts

// input_run_key_held — Non-blocking: returns nonzero if any non-modifier key
// is physically held. Used by the run pre-arm/cancel path in game_loop.s;
// must ignore latched (already-consumed) presses, so it reads AKD only.
// Output: A = nonzero if any key held, 0 if no key
// Preserves: X, Y
input_run_key_held:
    lda A2_KBDSTRB
    and #$80
    rts

// input_run_cancel_check — Non-blocking run cancel poll
// Uses the shared edge detector, sampling only physical held state.
input_run_cancel_check:
    jsr input_run_key_held
    jmp input_run_process_sample

// input_modal_prepare — Enter modal prompt input policy
// Drops any latched key so the press that opened the modal cannot
// auto-dismiss it, then waits for full physical release.
input_modal_prepare:
    sta A2_KBDSTRB
    jmp input_wait_release

// input_translate — ASCII (7-bit) -> normalized PETSCII
// Input:  A = raw ASCII with high bit already cleared
// Output: A = normalized PETSCII per core/input_tables.s conventions
// Preserves: Y
input_translate:
    cmp #$61
    bcc !it_not_lower+
    cmp #$7b
    bcs !it_not_lower+
    and #$df                // Lowercase ASCII -> unshifted PETSCII letter
    rts
!it_not_lower:
    cmp #$41
    bcc !it_table+
    cmp #$5b
    bcs !it_table+
    ora #$80                // Uppercase ASCII -> shifted PETSCII letter
    rts
!it_table:
    ldx #a2_special_key_count - 1
!it_scan:
    cmp a2_special_key_raw,x
    beq !it_found+
    dex
    bpl !it_scan-
    rts                     // Identity: digits, punctuation, space, ESC, CTRL
!it_found:
    lda a2_special_key_norm,x
    rts

// Special (non-identity, non-letter) key translations
a2_special_key_raw:
    .byte $08               // Left arrow
    .byte $15               // Right arrow
    .byte $0b               // Up arrow
    .byte $0a               // Down arrow
    .byte $7f               // DELETE
a2_special_key_norm:
    .byte $9d               // PETSCII cursor left
    .byte $1d               // PETSCII cursor right
    .byte $91               // PETSCII cursor up
    .byte $11               // PETSCII cursor down
    .byte $14               // PETSCII DEL (backspace in text entry)
a2_special_key_end:
.label a2_special_key_count = a2_special_key_norm - a2_special_key_raw
.assert "Special key tables same size", a2_special_key_count, a2_special_key_end - a2_special_key_norm

// input_get_command — Wait for a keypress, return command ID
// Output: A = command ID (CMD_* constant)
//         zp_input_cmd = same
//         zp_input_count = repeat count (currently always 1; numeric prefixes are deferred)
// Preserves: nothing
input_get_command:
    // Discard keys pressed during rendering (C64 KBDBUF_COUNT flush parity:
    // the strobe latch is the only pending-key storage on this platform).
    sta A2_KBDSTRB

    lda #1
    sta zp_input_count      // Default repeat count = 1
    // Numeric repeat prefixes are not implemented.
    // Keep `zp_input_count` pinned to 1 until the feature is explicitly revived.

!get_key:
    jsr input_get_key
    jsr petscii_to_command
    cmp #CMD_RUN
    beq !run_prefix+
    cmp #CMD_NONE
    beq !get_key-           // Unknown key, try again

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

// petscii_to_command — Convert normalized PETSCII key code to command ID
// Input:  A = normalized PETSCII code
// Output: A = command ID
// Preserves: X, Y
petscii_to_command:
    // Check the key mapping table
    ldx #0
!loop:
    cmp key_map_petscii,x
    beq !found+
    inx
    cpx #key_map_count
    bcc !loop-
    // Not found
    lda #CMD_NONE
    rts
!found:
    lda key_map_cmd,x
    rts

// ============================================================
// Key mapping table
// Normalized PETSCII codes -> command IDs. Identical to C64: the
// translation above emits exactly the codes the shared base map consumes.
// ESC is deliberately absent here — it is a modal-escape/run-cancel key
// (hal_input_modal_escape_primary), not a gameplay command.
// ============================================================

key_map_petscii:
    :EmitBasePetsciiKeyMap()

key_map_cmd:
    :EmitBaseCommandKeyMap()

key_map_end:
.label key_map_count = key_map_cmd - key_map_petscii
.assert "Key map tables same size", key_map_count, key_map_end - key_map_cmd
