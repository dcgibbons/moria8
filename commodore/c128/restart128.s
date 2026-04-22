#importonce
// restart128.s — tiny C128 restart owner in resident runtime common RAM
//
// `S)tart` from the quit prompt returns to the title/menu path on an already
// live runtime. Do not jump back through restart_entry, because that is the
// boot-time preload owner on C128.

game_restart:
    sei
    ldx #$ff
    txs
    jsr tier_invalidate_state
    lda #0
    sta current_overlay
    jmp title_enter_menu
