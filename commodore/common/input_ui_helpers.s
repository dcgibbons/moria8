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
    jmp input_wait_release
#else
    rts
#endif

// input_prepare_modal_dismiss_key — Prepare for a read-only overlay/modal
// dismiss key. C64 needs the explicit keyboard-buffer flush before waiting for
// release; C128 only needs the release wait.
input_prepare_modal_dismiss_key:
#if C128
    jmp input_wait_release
#else
    lda #0
    sta INPUT_UI_HELPER_KBDBUF_COUNT
    jmp input_wait_release
#endif

// input_get_modal_dismiss_key — Read a dismiss key for a read-only modal.
// C128 keeps the existing fast-path get-key behavior after the release wait.
input_get_modal_dismiss_key:
#if C128
    jsr input_prepare_modal_dismiss_key
    jmp input_get_key_fast
#else
    jmp input_get_key
#endif

// input_flush_run_cancel_buffer — Hide the raw keyboard-buffer flush needed
// when cancelling a run on C64. C128 direct-scan input does not use it.
input_flush_run_cancel_buffer:
#if !C128
    lda #0
    sta INPUT_UI_HELPER_KBDBUF_COUNT
#endif
    rts
