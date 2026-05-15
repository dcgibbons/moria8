#importonce
// input_ui_helpers.s — shared helpers for cross-platform prompt/dismiss
// keyboard policy. These keep raw platform details such as KBDBUF_COUNT out of
// common gameplay code.

#if C128
.const INPUT_UI_HELPER_KBDBUF_COUNT = $d0
#else
.const INPUT_UI_HELPER_KBDBUF_COUNT = $c6
#endif

// input_prepare_followup_key — Ensure the next read consumes a fresh follow-up
// key when the initiating command key should not leak into a secondary prompt.
input_prepare_followup_key:
#if C128
input_prepare_modal_dismiss_key:
    jmp hal_input_modal_prepare
#else
    rts
#endif

// input_prepare_modal_dismiss_key — Prepare for a read-only overlay/modal
// dismiss key. The platform HAL owns buffer flushing and physical-key release.
#if !C128
input_prepare_modal_dismiss_key:
    jmp hal_input_modal_prepare
#endif

// input_get_modal_dismiss_key — Read a dismiss key for a read-only modal.
// C128 keeps the existing fast-path get-key behavior after the release wait.
input_get_modal_dismiss_key:
#if C128
    jsr input_prepare_modal_dismiss_key
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
#if C128
    cmp #KEY_ESC
    beq !yes+
    cmp #$03                    // STOP key raw code on C128
!yes:
#else
    cmp #$03                    // RUN/STOP raw cancel on C64
    beq !yes+
    cmp #$1b                    // Synthetic/test ESC fallback
!yes:
#endif
    rts

// input_flush_run_cancel_buffer — Hide the raw keyboard-buffer flush needed
// when cancelling a run on C64. C128 direct-scan input does not use it.
input_flush_run_cancel_buffer:
#if !C128
    lda #0
    sta INPUT_UI_HELPER_KBDBUF_COUNT
#endif
    rts
