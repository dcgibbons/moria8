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
    ldy #MX_TYPE
    lda (zp_ptr0),y
    tax
    lda ball_harm
    beq !btd_elem+
    and cr_mflags,x
    beq !btd_done+
    asl zp_math_a
    rol zp_math_b
    jmp !btd_done+
!btd_elem:
#if (!C64_UNIT_TEST || MONSTER_MAGIC_PRODUCTION_EXTENDED) && (PLACE_SECRETS_EXTERNAL || PLACE_SECRETS_EMITTED) && !C64_TEST_FULL_ITEMDESC_STUB
    lda zp_math_a
    ldy #7
!btd_loop:
    cmp btd_ball_dmg_tbl,y
    beq !btd_hit+
    dey
    bpl !btd_loop-
    bmi !btd_done+
!btd_hit:
    lda btd_ball_typ_tbl,y
    jsr eff_scale_elem_damage
#endif
!btd_done:
    ldx ball_work_idx
    rts

#if (!C64_UNIT_TEST || MONSTER_MAGIC_PRODUCTION_EXTENDED) && (PLACE_SECRETS_EXTERNAL || PLACE_SECRETS_EMITTED) && !C64_TEST_FULL_ITEMDESC_STUB
btd_ball_dmg_tbl:
    .byte 8, 9, 24, 32, 33, 40, 48, 49
btd_ball_typ_tbl:
    .byte 2, 2, 1,  4,  4,  3,  5,  5
#endif
