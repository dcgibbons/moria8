#importonce
// wand_bolt_entries.s — The Wand of Fire Bolts and Wand of Drain Life
// effects, the VMS wands of 2026-11-11. Overlay code: imported beside the
// Phase 3 wand dispatch that calls them (core/scroll_effects_p3.s), or by a
// port that places them apart (the C128's play payload, the compact ports'
// OVL.SPELL). Everything they call is resident (core/spell_effects.s,
// core/combat.s).

#if HAL_PLATFORM_COMPACT_PLAY_SLOT || HAL_PLATFORM_SCROLL_P3_MODAL_DEATH_TRAMP
// eff_wand_fire_bolt — Wand of Fire Bolts: a 6d8 bolt (VMS wands.inc case 4),
// for the ports whose dispatch calls a handler (the others inline it).
eff_wand_fire_bolt:
    lda #6
    ldx #8
    ldy #0
    jmp eff_bolt
#endif

// eff_wand_drain_life — Wand of Drain Life: 50 to the first creature in line
// that is not undead; an undead one stops it unharmed and unwoken (VMS
// spells.inc drain_life: mon_take_hit(cptr, 50) unless cdefense $0008).
// The hit message is the bolt's.
eff_wand_drain_life:
    jsr eff_directional_monster
    bcc !ewdl_done+                 // no creature in line
    stx zp_temp2
    stx cmb_slot
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    sta cmb_type
    tay
    lda cr_mflags,y
    and #CF_UNDEAD
    bne !ewdl_done+                 // the undead are not drained
    lda #50
    sta zp_math_a
    lda #0
    sta zp_math_b
    ldx zp_temp2
    jsr combat_apply_damage_16
    bcc !ewdl_alive+
    jmp combat_kill_message         // X preserved by helper
!ewdl_alive:
    ldx zp_temp2
    jsr monster_wake
    lda #0
    sta cmb_buf_idx
    ldx #HSTR_EB_SPELL_HITS
    jmp projectile_msg_suffix
!ewdl_done:
    rts
