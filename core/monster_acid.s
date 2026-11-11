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
// A piece of Resist or Resist Acid armour is not damaged but still takes it
// ("Your <item> resists damage!"); with acid resistance (PFLAG_RESIST_ACID)
// the damage is divided by 3, or by 4 when a piece took it too (2026-11-11).
// Acid damage to pack items (VMS inven_damage) is not implemented
// (docs/BACKLOG.md). Acid breath also calls mon_atk_acid_armour
// (core/monster_magic.s).
// Input: zp_combat_dmg = rolled damage. Output: zp_combat_dmg (maybe divided).
// Clobbers: everything except zp_combat_dmg and the mat_* scratch
mon_atk_effect_acid:
    ldx #HSTR_MAT_ACID
    jsr huff_decode_to_ptr2
    jsr mon_atk_build_effect_msg
    jsr mon_atk_acid_armour
    lda #1
    adc #0                      // VMS acid_dam: divisor 1, + 1 for a piece
    tax
    lda player_pflags
    and #PFLAG_RESIST_ACID
    beq !maea_divide+
    inx                         // + 2 for acid resistance: 3 or 4
    inx
!maea_divide:
    cpx #1
    beq !maea_done+
    lda zp_combat_dmg
    sta zp_math_a
    lda #0
    sta zp_math_b
    jsr math_div_16x8           // zp_math_a = dam div X
    lda zp_math_a
    sta zp_combat_dmg
!maea_done:
    rts

// mon_atk_acid_armour — VMS minus_ac(resist acid): C set when a worn armour
// piece took it: resisted ("Your <item> resists damage!") or damaged ("Your
// <item> is damaged!"), so acid_dam halves.
// Clobbers: everything except zp_combat_dmg and the mat_* scratch
mon_atk_acid_armour:

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
    beq !maaa_none+             // Nothing worn: full damage

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

    // A piece that resists acid takes it unharmed (VMS minus_ac flags test);
    // only body armour and shields carry the resistance egos.
    lda inv_ego,x
    cmp #EGO_RESIST
    beq !maea_resists+
    cmp #EGO_RESIST_ACID
    bne !maea_ac+
!maea_resists:
    ldx #HSTR_MAT_RESISTS
    jsr maea_piece_msg
    sec
    rts
!maea_ac:
    ldx mat_acid_slot

    // ac + toac > 0? Base AC is 0-15; to-AC is signed. A negative to-AC
    // sum cannot overflow; a non-negative one is checked unsigned.
    ldy inv_item_id,x
    jsr item_get_base_ac        // A = base AC (Y = item id)
    ldx mat_acid_slot
    ldy inv_to_ac,x             // Flags from to-AC; A keeps the base
    bpl !maea_nonneg+
    clc
    adc inv_to_ac,x             // Signed sum in [-128, 14]
    bmi !maaa_none+
    beq !maaa_none+             // No AC left to lose: full damage
    bne !maea_damaged+          // Always taken
!maea_nonneg:
    clc
    adc inv_to_ac,x             // Unsigned sum <= 142
    beq !maaa_none+
!maea_damaged:

    // "Your <item> is damaged!" (VMS objdes before the to-AC drop)
    ldx #HSTR_MAT_DAMAGED
    jsr maea_piece_msg

    ldx mat_acid_slot
    dec inv_to_ac,x             // > -16 here: cannot wrap
#if HAL_PLATFORM_CHARGEN_ITEM_RECALC_TRAMPOLINE
    // player_recalc_equipment lives in OVL_ITEMS on this port: a direct jsr
    // ran whatever overlay was loaded (X16 M7 queue, 2026-11-02). The
    // overlay load may touch $80-$8F, so the damage rides the stack.
    lda zp_combat_dmg
    pha
    jsr tramp_item_recalc
    pla
    sta zp_combat_dmg
#else
    jsr player_recalc_equipment
#endif
    sec                         // Damaged: dam div 2
    rts
!maaa_none:
    clc
    rts

// maea_piece_msg — "Your <item at mat_acid_slot>" and huffman string X.
maea_piece_msg:
    stx mat_acid_msg
    lda #0
    sta cmb_buf_idx
    ldx #HSTR_MAT_YOUR
    jsr huff_append_combat
    ldx mat_acid_slot
    jsr inv_slot_to_fi_add      // A = item id
    jsr item_append_desc
    ldx mat_acid_msg
    jsr huff_append_combat
    jmp cmb_term_and_print

mat_acid_slot: .byte 0
mat_acid_msg:  .byte 0
