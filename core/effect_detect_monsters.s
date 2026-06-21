#importonce
// effect_detect_monsters.s — shared detect-monsters timer effect.

.const DETECT_TIMER_TURNS = 20
.const EDEO_MX_X = 0
.const EDEO_MX_Y = 1
.const EDEO_CF_EVIL = $04

eff_detect_timer: .byte 0

// eff_detect_monsters — Activate detect monsters effect (timer)
// While timer > 0, renderer shows detected monsters regardless
// of tile visibility. No permanent FLAG_VISITED side-effect.
// Input: none
// Output: eff_detect_timer set, vis_room_revealed = 1
// Clobbers: A
eff_detect_monsters:
    lda #DETECT_TIMER_TURNS
    sta eff_detect_timer
    lda #1
    sta vis_room_revealed
    rts
