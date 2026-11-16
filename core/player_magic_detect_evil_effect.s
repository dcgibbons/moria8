#importonce

#if !EFF_DETECT_EVIL_EXTERNAL
#import "eff_detect_evil_cold.s"
#endif

detect_evil_clear_reveal:
    lda eff_detect_evil_mode
    beq !decr_done+
    dec eff_detect_evil_mode
    sta muv_clear_detected
    sta vis_room_revealed
#if HAL_LAYOUT_VISIBILITY_FORCE_REDRAW
    sta vis_force_redraw_pending
#endif
    jsr monster_update_visibility_all
!decr_done:
    rts
