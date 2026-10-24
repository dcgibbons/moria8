#importonce
// monster_acid.s — The monster acid attack's armour damage (MON-015).
// Imported by monster_attack.s, unless a port defines MON_ATK_ACID_EXTERNAL
// and imports it into a segment with room that play code can always call
// (C128 main image, Apple IIe and BBC Master resident images).

// mon_atk_effect_acid — Acid attack: pinned VMS Moria creature.inc acid
// attack -> moria.inc acid_dam/minus_ac (Umoria identical; MON-015). After
// the effect message, one worn armour piece is chosen at random among the
// occupied body, shield, head and hands slots (VMS also has a cloak slot;
// Moria8 has none). If its AC + to-AC is above 0 it is damaged: "Your <item>
// is damaged!", to-AC - 1, equipment recalculated, and the damage halved.
// No Moria8 armour resists acid, and the player has no acid resistance, so
// those VMS branches do not exist; acid damage to pack items (VMS
// inven_damage) is not implemented.
// Input: zp_combat_dmg = rolled damage. Output: zp_combat_dmg (maybe halved).
// Clobbers: everything except zp_combat_dmg and the mat_* scratch
mon_atk_effect_acid:
    ldx #HSTR_MAT_ACID
    jsr huff_decode_to_ptr2
    jsr mon_atk_build_effect_msg

    // Count the occupied armour slots
    ldy #0
    ldx #EQUIP_BODY
!maea_count:
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !maea_count_next+
    iny
!maea_count_next:
    inx
    cpx #EQUIP_HANDS + 1
    bne !maea_count-
    tya
    beq !maea_done+             // Nothing worn: full damage

    // randint(count): the chosen occupied slot, 0-based
    jsr rng_range               // A = [0, count-1]; preserves Y
    tay
    ldx #EQUIP_BODY - 1
!maea_find:
    inx
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !maea_find-
    dey
    bpl !maea_find-
    stx mat_acid_slot

    // ac + toac > 0? Base AC is 0-15; to-AC is signed. A negative to-AC
    // sum cannot overflow; a non-negative one is checked unsigned.
    ldy inv_item_id,x
    jsr item_get_base_ac        // A = base AC (Y = item id)
    ldx mat_acid_slot
    ldy inv_to_ac,x             // Flags from to-AC; A keeps the base
    bpl !maea_nonneg+
    clc
    adc inv_to_ac,x             // Signed sum in [-128, 14]
    bmi !maea_done+
    beq !maea_done+             // No AC left to lose: full damage
    bne !maea_damaged+          // Always taken
!maea_nonneg:
    clc
    adc inv_to_ac,x             // Unsigned sum <= 142
    beq !maea_done+
!maea_damaged:

    // "Your <item> is damaged!" (VMS objdes before the to-AC drop)
    lda #0
    sta cmb_buf_idx
    ldx #HSTR_MAT_YOUR
    jsr huff_append_combat
    ldx mat_acid_slot
    jsr inv_slot_to_fi_add      // A = item id
    jsr item_append_desc
    ldx #HSTR_MAT_DAMAGED
    jsr huff_append_combat
    jsr cmb_term_and_print

    ldx mat_acid_slot
    dec inv_to_ac,x             // > -16 here: cannot wrap
    jsr player_recalc_equipment
    lsr zp_combat_dmg           // dam div 2
!maea_done:
    rts

mat_acid_slot: .byte 0
