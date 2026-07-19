#importonce
// LOOK help-overlay dispatch. Both branches must exit through UI cleanup.

tramp_do_look:
    jsr tramp_ui_enter
    lda #C128_HELP_OVERLAY_ID
    jsr overlay_load
    bcs !done+
    jsr do_look
!done:
    jmp tramp_ui_exit
