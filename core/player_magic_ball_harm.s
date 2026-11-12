#importonce
// player_magic_ball_harm.s — a ball's damage to each creature it reaches,
// doubled against the creatures its harm type hurts (VMS spells.inc
// fire_ball: `if uand(harm_type, cdefense) <> 0 then dam := dam * 2`; a holy
// orb's harm type is evil, Umoria spellGetAreaAffectFlags HolyOrb CD_EVIL).
// Owner: player_magic_ball.s's eff_ball. Lifetime: called only while the
// overlay holding eff_ball is loaded, so it may sit beside it or resident
// (BALL_HARM_EXTERNAL: the C64 and Apple IIe spell overlays are full).
// Orb of Draining's entry is player_magic_ball_holy.s.

ball_harm: .byte 0      // cr_mflags bits the ball doubles against; 0 = none

// ball_target_damage — The damage for the creature at zp_ptr0 (slot
// ball_work_idx).
// Output: zp_math_a/b = damage, X = ball_work_idx
// Clobbers: A, Y
ball_target_damage:
    lda ball_work_damage
    sta zp_math_a
    lda #0
    sta zp_math_b
    lda ball_harm
    beq !btd_done+
    ldy #MX_TYPE
    lda (zp_ptr0),y
    tax
    lda cr_mflags,x
    and ball_harm
    beq !btd_done+
    asl zp_math_a
    rol zp_math_b
!btd_done:
    ldx ball_work_idx
    rts
