#importonce
// monster_polymorph.s — VMS spells.inc poly_monster / mass_poly, emitted into
// each overlay that polymorphs (the item effects: Wand of Polymorph, Staff of
// Mass Polymorph; the spells: Polymorph Other), so neither crosses overlays.

// PolymorphResist — poly_monster's roll for the monster in slot X:
// randint(max_mons_level) > level changes it, else "The <name> is
// unaffected." through `unaffected` (a tail call; cmb_type names it). The
// win creatures (levels 50 and 100) always resist. Falls through into
// PolymorphReplace when the roll succeeds.
.macro PolymorphResist(slot, unaffected) {
    stx slot
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    sta cmb_type
    lda #MONS_LEVEL_MAX
    jsr rng_range               // 0-39: randint(40) > level <=> r >= level
    ldx cmb_type
    cmp cr_level,x
    bcs !changed+
    jmp unaffected
!changed:
    ldx slot
}

// PolymorphReplace — Slot X becomes an awake creature of any level 1-40 on
// the same square (place_monster(y, x, randint(m_level[max_mons_level]) +
// m_level[0], false)). Ends with rts.
.macro PolymorphReplace(slot) {
    stx slot
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    sta ms_spawn_x
    iny                         // MX_Y
    lda (zp_ptr0),y
    sta ms_spawn_y
    ldx slot
    jsr monster_remove
    jsr pick_any_creature_type
    jsr monster_spawn_awake
    inc zp_dirty_count
    rts
}
.assert "PolymorphReplace: MX_Y follows MX_X", MX_Y, MX_X + 1
