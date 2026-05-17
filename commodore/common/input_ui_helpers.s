#importonce
// input_ui_helpers.s — shared helpers for cross-platform prompt/dismiss
// keyboard policy. These keep raw platform details such as KBDBUF_COUNT out of
// common gameplay code.

// input_prepare_followup_key — Ensure the next read consumes a fresh follow-up
// key when the initiating command key should not leak into a secondary prompt.
.label input_prepare_followup_key = hal_input_followup_prepare

// input_prepare_modal_dismiss_key — Prepare for a read-only overlay/modal
// dismiss key. The platform HAL owns buffer flushing and physical-key release.
input_prepare_modal_dismiss_key:
    jmp hal_input_modal_prepare

// input_get_modal_dismiss_key — Read a dismiss key for a read-only modal.
// C128 keeps the existing fast-path get-key behavior after the release wait.
input_get_modal_dismiss_key:
    jsr input_prepare_modal_dismiss_key
#if hal_input_modal_dismiss_uses_fast_key
    jmp input_get_key_fast
#else
    jmp hal_input_get_key
#endif

// input_is_modal_escape_key — classify the platform's escape-equivalent key
// for read-only modal dismissal.
// Input: A = raw key from input_get_key/input_get_key_fast
// Output: Z set when the key is the platform escape-equivalent, Z clear otherwise
// Preserves: A
input_is_modal_escape_key:
    cmp #hal_input_modal_escape_primary
    beq !yes+
    cmp #hal_input_modal_escape_secondary
!yes:
    rts

// input_flush_run_cancel_buffer — Hide the raw keyboard-buffer flush needed
// when cancelling a run on C64. C128 direct-scan input does not use it.
input_flush_run_cancel_buffer:
#if hal_input_flush_run_cancel_buffer
    lda #0
    sta hal_input_kbdbuf_count
#endif
    rts

// input_normalize_inventory_letter_key — Normalize platform-specific shifted
// letter encodings before common inventory slot math consumes A-V.
// Input/Output: A = PETSCII key
// Preserves: X, Y
input_normalize_inventory_letter_key:
#if hal_input_inventory_letter_normalize_shifted
    cmp #$c1
    bcc !done+
    cmp #$db
    bcs !done+
    and #$7f
!done:
#endif
    rts
