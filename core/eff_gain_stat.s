#importonce
// eff_gain_stat.s — Potions of gain stat (VMS Moria potions.inc, cases 1, 4,
// 7, 10, 17, 26; maintainer, 2026-11-07: "high-value add-ons").
//
// VMS raises the current stat by in_statp (misc.inc): +1 below 18, else
// +1d25 below 88 (18/70), +1d10 below 108 (18/90), else +1, at most 118
// (18/100), and the maximum to it when it passes. Moria8 keeps the maximum
// as PL_*_BASE (race and class baked in) and drain lowers PL_*_CUR only: the
// step is rolled on the base and both move by it, so an undrained stat is
// raised exactly as VMS does and a drained one keeps its drain.
// Constitution adds 1 to max HP as VMS does; VMS then adds max HP to HP,
// which can pass the maximum, so Moria8 heals to full instead.
//
// Owner: Default resident on C64, Plus/4, and C128; RuntimeBanked (ATARI.BNK)
// on Atari 8-bit; A2PlaySlot (a2.play) on Apple IIe; ItemActionsOverlay
// (OVL.ITEMS) on CX16; SpellOverlay (OVL.SPELL) on BBC Master 128.
// Lifetime: one potion quaff (ITEM_POTION_OF_GAIN_STRENGTH..ITEM_POTION_OF_CHARISMA).
// Callers: Phase 3 quaff dispatch (iq_dispatch_p3 in player_item_commands.s on
// C64/Plus/4/CX16/Atari, resident c128_quaff_p3_dispatch on C128, or
// iq_dispatch_p3_spell in OVL.SPELL on Apple IIe and BBC Master, where the
// items-overlay router reloads OVL.ITEMS on return). Calls only resident helpers.

// eff_potion_gain_stat — Raise the stat of potion type A and say so.
// Input: A = Page-0 slot_lo of one of the 6 gain-stat potions (unmatched -> rts)
// Clobbers: A, X, Y
eff_potion_gain_stat:
    ldy #5
!egs_find:
    cmp egs_pot_ids,y
    beq !egs_found+
    dey
    bpl !egs_find-
    rts
!egs_found:                     // Y = the stat (0..5); rng_range keeps Y
    lda player_data + PL_STR_BASE,y
    sta egs_old
    cmp #18
    bcc !egs_one+
    ldx #25
    cmp #88
    bcc !egs_roll+
    ldx #10
    cmp #108
    bcc !egs_roll+
!egs_one:
    lda #0
    beq !egs_add+               // Always
!egs_roll:
    txa
    jsr rng_range               // [0, n-1]
!egs_add:
    sec                         // + 1: randint(n) is 1..n
    adc egs_old
    cmp #119
    bcc !egs_base_ok+
    lda #118
!egs_base_ok:
    sta player_data + PL_STR_BASE,y
    sec
    sbc egs_old                 // the step taken
    clc
    adc player_data + PL_STR_CUR,y
    cmp #119
    bcc !egs_cur_ok+
    lda #118
!egs_cur_ok:
    sta player_data + PL_STR_CUR,y
    sta zp_player_str,y         // the ZP mirror (absolute,y: no zp,y sta)
    cpy #PL_CON_BASE - PL_STR_BASE
    bne !egs_msg+
    inc zp_player_mhp_lo
    bne !egs_mhp_ok+
    inc zp_player_mhp_hi
!egs_mhp_ok:
    lda zp_player_mhp_lo
    sta player_data + PL_MHP_LO
    lda zp_player_mhp_hi
    sta player_data + PL_MHP_HI
    jsr eff_heal_full
!egs_msg:
    tya
    clc
    adc #HSTR_PIQ_GAIN_STR
    tax
    jsr huff_print_msg
    jmp status_draw

egs_old:  .byte 0
// Indexed by stat 0..5 (PL_STR_BASE..PL_CHR_BASE): VMS potions are non-contiguous.
egs_pot_ids:
    .byte ITEM_SLOT_POTION_OF_GAIN_STRENGTH, ITEM_SLOT_POTION_OF_GAIN_INTELLIGENCE
    .byte ITEM_SLOT_POTION_OF_GAIN_WISDOM, ITEM_SLOT_POTION_OF_GAIN_DEXTERITY
    .byte ITEM_SLOT_POTION_OF_GAIN_CONSTITUTION, ITEM_SLOT_POTION_OF_CHARISMA
.assert "All six gain-stat potions live on Page 0", ITEM_PAGE_POTION_OF_GAIN_STRENGTH == 0 && ITEM_PAGE_POTION_OF_GAIN_INTELLIGENCE == 0 && ITEM_PAGE_POTION_OF_GAIN_WISDOM == 0 && ITEM_PAGE_POTION_OF_GAIN_DEXTERITY == 0 && ITEM_PAGE_POTION_OF_GAIN_CONSTITUTION == 0 && ITEM_PAGE_POTION_OF_CHARISMA == 0, true
.assert "Gain messages are consecutive in PL_*_BASE order", HSTR_PIQ_GAIN_INT == HSTR_PIQ_GAIN_STR + 1 && HSTR_PIQ_GAIN_WIS == HSTR_PIQ_GAIN_STR + 2 && HSTR_PIQ_GAIN_DEX == HSTR_PIQ_GAIN_STR + 3 && HSTR_PIQ_GAIN_CON == HSTR_PIQ_GAIN_STR + 4 && HSTR_PIQ_GAIN_CHR == HSTR_PIQ_GAIN_STR + 5, true
.assert "PL_*_CUR follows PL_*_BASE order", PL_CHR_CUR - PL_STR_CUR, PL_CHR_BASE - PL_STR_BASE
.assert "The ZP stat mirrors follow PL_*_BASE order", zp_player_chr - zp_player_str, PL_CHR_BASE - PL_STR_BASE
