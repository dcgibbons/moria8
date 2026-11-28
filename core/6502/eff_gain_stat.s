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
// Owner: ModalMiscOverlay (ovl.modal) on C64, ItemActionsOverlay (ovl.items) on
// Plus/4 and CX16, StorageOverlay (ovl.storage, with player_gain_stat_helpers.s
// in C128ResidentPlay) on C128, RuntimeBanked (ATARI.BNK) on Atari 8-bit,
// DeathOverlay (ovl.death) on Apple IIe, and SpellOverlay (OVL.SPELL) on
// BBC Master 128.
// Lifetime: one potion quaff (ITEM_POTION_OF_GAIN_STRENGTH..ITEM_POTION_OF_CHARISMA).
// Callers: Phase 3 quaff dispatch (iq_dispatch_p3 in player_item_commands.s on
// C64/Plus/4/CX16/Atari, c128_quaff_p3_dispatch in C128 StorageOverlay, or
// iq_dispatch_p3_spell in OVL.SPELL on Apple IIe and BBC Master, where the
// items-overlay router reloads OVL.ITEMS on return). Calls resident player.s
// helpers plus player_gain_stat_helpers.s (inline in Default or co-located /
// C128ResidentPlay).

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
#if CORE_PLAYER_IMPORTED
    cmp egs_old                     // A = new_base; egs_old = old_base
    beq !egs_no_delta+
    sta player_data + PL_STR_BASE,y
    jsr player_sum_eq_y             // A = stat_work = signed eq_mod, preserves Y
    bmi !egs_neg+
    // eq_mod >= 0: exact unclamped VMS in_statt delta (never collapses at +127 res)
    lda egs_old                     // old_base
    cmp #18
    bcc !egs_pos_lo+
    lda player_data + PL_STR_BASE,y // new_base
    sbc egs_old                     // C=1 guaranteed -> new_base - old_base
    bne !egs_apply+                 // Always taken (new_base != old_base)
!egs_pos_lo:
    // old_base < 18 (C=0, Gain Stat rolled +1): +10 iff old_base + eq_mod >= 18
    adc stat_work                   // old_base (3..17) + eq_mod (0..127) <= 144
    cmp #18
    lda #10
    bcs !egs_apply+
    lda #1
    bne !egs_apply+
!egs_neg:
    // eq_mod < 0: healthy never approaches +127; step single stat Y preserving X
    lda player_data + PL_STR_CUR,y
    pha
    lda player_stat_res,y
    pha
    ldx #0
    lda egs_old
    jsr player_step_healthy_sum_y   // A = h_old, preserves X, Y
    tax
    lda player_data + PL_STR_BASE,y
    jsr player_step_healthy_sum_y   // A = (h_new - h_old) & $FF
    tax
    pla
    sta player_stat_res,y
    pla
    jsr pses_write_cur_y            // Restores cur[Y] & zp_player_str[Y], preserves X, Y
    txa
!egs_apply:
    jsr player_apply_stat_delta_y
!egs_no_delta:
    tya
    pha
    cpy #PL_CON_BASE - PL_STR_BASE
    bne !egs_combat+
    jsr player_calc_hp
    jsr eff_heal_full
!egs_combat:
    jsr player_calc_combat
#if HAL_PLATFORM_LEVELUP_MAGIC_USES_TRAMPOLINE
    pla                             // A = saved stat index (0..5)
    beq !egs_no_magic+              // STR (0) never changes mana/spells
    cmp player_data + PL_SPELL_TYPE // INT(1)==SPELL_MAGE, WIS(2)==SPELL_PRIEST; C=1 on match
    bne !egs_no_magic+
    rol levelup_magic_pending       // C=1 sets bit 0 (pending is 0 at cmd entry; preserves A)
!egs_no_magic:
#else
    pla                             // A = saved stat index (0..5)
    pha
    beq !egs_no_magic+
    cmp player_data + PL_SPELL_TYPE
    bne !egs_no_magic+
    jsr magic_recalc_mana
    jsr magic_check_new_spells
!egs_no_magic:
    pla                             // A = saved stat index (0..5)
#endif
.assert "Gain-stat magic guard relies on INT==SPELL_MAGE and WIS==SPELL_PRIEST", (PL_INT_BASE - PL_STR_BASE) == SPELL_MAGE && (PL_WIS_BASE - PL_STR_BASE) == SPELL_PRIEST, true
#else
    sta player_data + PL_STR_BASE,y
    sec
    sbc egs_old
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
#endif
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
