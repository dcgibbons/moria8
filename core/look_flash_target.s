#importonce
// look_flash_target.s — transient viewport-cell flash for look/examine feedback.
// Owner: Default resident on C64, Plus/4, CX16, Atari 8-bit, and BBC Master 128;
// C128ResidentWorld (128.world) on C128; A2PlaySlot (a2.play) on Apple IIe.
// Lifetime: one target-step or examine flash call during gameplay.
// Callers: look_command (core/player_move.s) in ModalMiscOverlay on all seven
// product ports (resident in unit tests); calls resident screen_flash_at without
// touching the overlay window.

// look_flash_target — Flash the looked-at target if it is inside the viewport
// Uses the same transient screen flash primitive as bolt animation.
// Input: df_target_x/df_target_y = map coordinates
// Clobbers: A, X, Y
look_flash_target:
    lda df_target_y
    sec
    sbc zp_view_y
    cmp #VIEWPORT_H
    bcs !lft_done+               // Off-screen above/below viewport
    adc #VIEWPORT_Y
    tax                          // X = absolute screen row

    lda df_target_x
    sec
    sbc zp_view_x
    cmp #VIEWPORT_W
    bcs !lft_done+               // Off-screen left/right of viewport
    adc #VIEWPORT_X
    tay                          // Y = absolute screen column

    jmp screen_flash_at
!lft_done:
    rts
