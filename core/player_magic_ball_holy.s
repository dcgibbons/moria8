#importonce
// player_magic_ball_holy.s — Orb of Draining's ball entry (ball_harm in
// player_magic_ball_harm.s). Owner: ped_s17. Lifetime: called only while the
// overlay holding eff_ball is loaded; resident or banked where the spell
// overlay is full (BALL_HARM_EXTERNAL; the C64 keeps it in RuntimeBanked).

// eff_ball_holy — Orb of Draining: a ball doubled against evil creatures.
// Input: A = base damage
eff_ball_holy:
    ldx #CF_EVIL
    stx ball_harm
    jsr eff_ball
    lda #0
    sta ball_harm
    rts
