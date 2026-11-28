#importonce
// ui_help_cmd_cold.s — Cold Help (?) modal page/key loop (S8)
//
// Module ownership:
//   owner: HelpOverlay (`ovl.help`) on ports defining HELP_CMD_BODY_EXTERNAL.
//   lifetime: one page-browsing burst inside cmd_show_help_view; returns C=1
//     when 'L' requests LEGALUI (so resident cmd_show_help_view can load
//     LEGALUI over HelpOverlay and re-enter via tramp_help_cmd_body), or C=0
//     when exiting back to gameplay.
//   callers: tramp_help_cmd_body (from resident cmd_show_help_view).

#if !HELP_CMD_KEYS_DEFINED
#define HELP_CMD_KEYS_DEFINED
.const HELP_KEY_Q = $51
.const HELP_KEY_SPACE = $20
.const HELP_KEY_RETURN = $0d
#endif

help_cmd_body:
    lda zp_input_cmd
    cmp #CMD_MSG_HISTORY
    bne !help_page_loop+
    jsr ui_msg_history_draw
    jsr input_prepare_modal_dismiss_key
    jsr hal_input_get_key
#if HAL_PLATFORM_ITEM_ACTION_KEY_RESTORES_BANK
    jsr hal_platform_item_action_restore_bank
#endif
    clc
    rts
!help_page_loop:
    jsr ui_help_display
!help_key_loop:
    jsr input_prepare_modal_dismiss_key
    jsr hal_input_get_key
#if HAL_PLATFORM_ITEM_ACTION_KEY_RESTORES_BANK
    jsr hal_platform_item_action_restore_bank
#endif
#if HAL_PLATFORM_LEGAL_VIEWER
    cmp #$4c                    // License/source viewer is a free Help modal.
    bne !not_legal+
    sec
    rts
!not_legal:
#endif
    cmp #HELP_KEY_Q
    beq !help_exit+
    jsr input_is_modal_escape_key
    beq !help_exit+
    cmp #HELP_KEY_SPACE
    beq !help_advance+
    cmp #HELP_KEY_RETURN
    beq !help_advance+
    jmp !help_key_loop-
!help_advance:
    ldx help_page_idx
    inx
    cpx help_page_count
    bcs !help_exit+
    stx help_page_idx
    jmp !help_page_loop-
!help_exit:
    clc
    rts
