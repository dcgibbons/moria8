#importonce
// LOOK modal overlay dispatch. Both branches must exit through runtime resync.

tramp_do_look:
    lda #OVL_MODAL_MISC
    jsr overlay_load_no_kernal
    bcs !done+
    jsr do_look
!done:
    jmp tramp_sr_epilogue
