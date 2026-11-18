#importonce
// monster_acid.s — The monster acid & corrosion armour damage (MON-015) and
// extended VMS Moria 4.8 attack effects (monster_attack_effects.s).
// Imported by monster_attack.s, unless a port defines MON_ATK_ACID_EXTERNAL
// and imports it into a segment with room that play code can always call
// (C128 main image, Apple IIe and BBC Master resident images).

// mon_atk_effect_acid — Acid attack: pinned VMS Moria creature.inc acid
// attack -> moria.inc acid_dam/minus_ac (Umoria identical; MON-015).
mon_atk_effect_acid:
    ldx #HSTR_MAT_ACID
    jsr mon_atk_huff_effect_msg
    jsr mon_atk_acid_armour
    lda #1
    adc #0                      // VMS acid_dam: divisor 1, + 1 for a piece
    tax
    lda player_pflags
    and #PFLAG_RESIST_ACID
    beq mat_div_dmg
    inx                         // + 2 for acid resistance: 3 or 4
    inx
// mat_div_dmg — zp_combat_dmg = zp_combat_dmg div X (X = 1: unchanged).
mat_div_dmg:
    cpx #1
    beq !mdd_done+
    lda zp_combat_dmg
    sta zp_math_a
    lda #0
    sta zp_math_b
    jsr math_div_16x8           // zp_math_a = dam div X
    lda zp_math_a
    sta zp_combat_dmg
!mdd_done:
    rts

// mon_atk_acid_armour — VMS minus_ac(resist acid): C set when a worn armour
// piece took it: resisted ("Your <item> resists damage!") or damaged ("Your
// <item> is damaged!"), so acid_dam halves.
// Clobbers: everything except zp_combat_dmg and the mat_* scratch
mon_atk_acid_armour:
    lda #$80                    // Mode $80: uniform random worn armour slot
    jsr mae_pick_slot
    beq !maaa_none+             // Nothing worn: full damage

    // A piece that resists acid takes it unharmed (VMS minus_ac flags test):
    // (Resist), (Resist Acid) and the Magi (%X'01380008' has TR_RES_ACID).
    lda inv_ego,x
    and #EGO_ID_MASK
    cmp #EGO_RESIST
    beq !maea_resists+
    cmp #EGO_RESIST_ACID
    beq !maea_resists+
    cmp #EGO_MAGI
    bne !maea_ac+
!maea_resists:
    ldx #HSTR_MAT_RESISTS
    jsr maea_piece_msg
    sec
    rts
!maea_ac:
    // X == mat_acid_slot (preserved from mae_pick_slot).
    // ac + toac > 0? Base AC is 0-28; to-AC is signed [-128, +127].
    lda inv_ego,x
    and #ITEM_PAGE_BIT
    sta item_cur_page
    ldy inv_item_id,x
    jsr item_get_base_ac        // A = base AC (0..28)
    ldx mat_acid_slot
    clc
    adc inv_to_ac,x
    beq !maaa_none+             // Sum == 0: worn out
    bpl !maea_damaged+          // Sum in 1..127: damaged
    ldy inv_to_ac,x             // Sum bit 7 set: > 0 iff inv_to_ac >= 0 (128..155)
    bmi !maaa_none+
!maea_damaged:
    ldx #HSTR_MAT_DAMAGED
    jsr maea_piece_msg

    ldx mat_acid_slot
    dec inv_to_ac,x             // > -16 here: cannot wrap
    jsr mat_recalc_equip
    sec                         // Damaged: dam div 2
    rts
!maaa_none:
    clc
    rts

// mat_recalc_equip — Recalculate worn equipment bonuses, saving/restoring
// zp_combat_dmg and any active overlay (e.g. OVL_CHEST on acid/corrode traps).
mat_recalc_equip:
#if HAL_PLATFORM_CHARGEN_ITEM_RECALC_TRAMPOLINE
#if TRAP_TRIGGER_EXTERNAL && PLATFORM_PRODUCT_OVERLAY_RUNTIME
    lda current_overlay
    pha
#endif
    lda zp_combat_dmg
    pha
    jsr tramp_item_recalc
    pla
    sta zp_combat_dmg
#if TRAP_TRIGGER_EXTERNAL && PLATFORM_PRODUCT_OVERLAY_RUNTIME
    pla
    beq !maea_recalc_done+
    jmp overlay_load
!maea_recalc_done:
    rts
#else
    rts
#endif
#else
    jmp player_recalc_equipment
#endif

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
maea_slots:    .byte EQUIP_BODY, EQUIP_SHIELD, EQUIP_HEAD, EQUIP_HANDS, EQUIP_FEET, EQUIP_CLOAK

#if HAL_PLATFORM_RUNTIME_BANKED_ALWAYS_VISIBLE
.segment Default
#endif
#import "monster_attack_effects.s"
#if HAL_PLATFORM_RUNTIME_BANKED_ALWAYS_VISIBLE
.segment RuntimeBanked
#endif
