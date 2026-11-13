#importonce
// Help controller: outside the cold overlay window on all ports so it survives
// both OVL_HELP and LEGALUI loading there.
// Owner: Default resident on C64, Plus/4, CX16, and Atari 8-bit (< $4000);
// C128ResidentPlay (128.play) on C128; A2PlaySlot (a2.play) on Apple IIe;
// BeebPlaySlot (beeb.play) on BBC Master 128.
// Lifetime: one gameplay Help (?) modal session, entered from main_loop.
.const HELP_KEY_Q = $51
.const HELP_KEY_SPACE = $20
.const HELP_KEY_RETURN = $0d

cmd_show_help_view:
    lda #0
    sta help_page_idx
!help_page_loop:
    jsr tramp_ui_help_display
!help_key_loop:
    jsr input_prepare_modal_dismiss_key
    jsr hal_input_get_key
#if HAL_PLATFORM_LEGAL_VIEWER
    cmp #$4c                    // License/source viewer is a free Help modal.
    bne !not_legal+
    jsr tramp_ui_legal_display
#if HAL_PLATFORM_LEGAL_CANCEL_EXITS_HELP
    bcs !help_done+             // The program disk can still be unavailable.
#endif
    jmp !help_page_loop-
!not_legal:
#endif
    cmp #HELP_KEY_Q
    beq !help_done+
    jsr input_is_modal_escape_key
    beq !help_done+
    cmp #HELP_KEY_SPACE
    beq !help_advance+
    cmp #HELP_KEY_RETURN
    beq !help_advance+
    jmp !help_key_loop-
!help_advance:
    lda help_page_idx
    clc
    adc #1
    cmp help_page_count
    bcs !help_done+
    inc help_page_idx
    jmp !help_page_loop-
!help_done:
    jmp ui_view_return_to_gameplay_view
