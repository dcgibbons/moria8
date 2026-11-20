#importonce
// load_resume_reset_cold.s — Pre-restore transient state reset on save resume
//
// Module ownership:
//   owner: StorageOverlay / DeathOverlay / HelpOverlay when
//     LOAD_RESUME_RESET_EXTERNAL is defined; inline inside load_resume_game
//     (core/game_loop.s, +0 B overhead) otherwise.
//   lifetime: once per Load Game resume, at the start of load_resume_game
//     while OVL_STORAGE is still resident from load_game (0 extra disk reads
//     on StorageOverlay ports) and before tramp_item_recalc / player_calc_stats.
//   callers: load_resume_game (via tramp_load_resume_reset when external).

#if LOAD_RESUME_RESET_EXTERNAL
load_resume_reset:
#endif
    jsr wizard_reset_session_state
    jsr player_search_clear_transient_state

    // Stop any running and clear unsaved transient session latches
    lda #$ff
    sta zp_run_dir
    lda #0
    sta auto_rest_active
    sta zp_disturb
    sta regen_frac_lo           // not saved (zp_regen_frac, the high byte, is)
    sta md_count                // no drop staged before the load
#if HAL_PLATFORM_LEVELUP_MAGIC_USES_TRAMPOLINE
    sta levelup_magic_pending   // none owed by the game played before the load
#endif
    lda player_data + PL_FLAGS
    and #($ff - PLF_RESTING)
    sta player_data + PL_FLAGS

    // Re-init sound and seed neutral viewport origin before screen clear
    jsr hal_sound_init
    lda #0
    sta zp_view_x
    sta zp_view_y
#if LOAD_RESUME_RESET_EXTERNAL
    rts
#endif
