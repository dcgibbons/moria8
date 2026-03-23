#importonce
// player_magic_levelup.s — level-up spell-learning helper
//
// Imported into the C64 main segment and the C128 low-runtime segment.
// Kept separate so C128 does not leave the level-up path in the I/O hole.

// ============================================================
// magic_check_new_spells — Learn any spells the player qualifies for
// Checks each spell 0-15: if spell_level <= player_level and not
// already known, set the known bit and print message.
// Called on level-up. Scans inventory for books matching
// the player's class, then learns qualifying spells from
// each book's 4-spell range.
// Clobbers: A, X, Y, zp_ptr0, zp_ptr2
// ============================================================
pm_learn_idx:    .byte 0     // Current spell index being checked
mcns_class:      .byte 0     // Player's spell class
mcns_inv_idx:    .byte 0     // Inventory scan index
mcns_spell_start:.byte 0     // First spell index for current book

magic_check_new_spells:
    lda player_data + PL_SPELL_TYPE
    bne !mcns_has_type+
    rts                             // SPELL_NONE — nothing to learn
!mcns_has_type:
    sta mcns_class

    // Set up table pointers based on class
    cmp #SPELL_MAGE
    bne !mcns_priest+

    // Mage: use mage tables
    lda #<mage_spell_level
    sta pm_lvl_tbl_lo
    lda #>mage_spell_level
    sta pm_lvl_tbl_hi
    lda #<mage_spell_name_lo
    sta pm_name_lo_lo
    lda #>mage_spell_name_lo
    sta pm_name_lo_hi
    lda #<mage_spell_name_hi
    sta pm_name_hi_lo
    lda #>mage_spell_name_hi
    sta pm_name_hi_hi
    jmp !mcns_scan_inv+

!mcns_priest:
    // Priest: use priest tables
    lda #<priest_spell_level
    sta pm_lvl_tbl_lo
    lda #>priest_spell_level
    sta pm_lvl_tbl_hi
    lda #<priest_spell_name_lo
    sta pm_name_lo_lo
    lda #>priest_spell_name_lo
    sta pm_name_lo_hi
    lda #<priest_spell_name_hi
    sta pm_name_hi_lo
    lda #>priest_spell_name_hi
    sta pm_name_hi_hi

!mcns_scan_inv:
    lda #0
    sta mcns_inv_idx

!mcns_inv_loop:
    ldx mcns_inv_idx
    cpx #MAX_INV_SLOTS
    bcs !mcns_done+

    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !mcns_inv_next+

    tax
    lda it_category,x
    cmp #ICAT_BOOK
    bne !mcns_inv_next+

    txa
    jsr book_get_info
    bcs !mcns_inv_next+

    cpx mcns_class
    bne !mcns_inv_next+

    sta mcns_spell_start
    jsr mcns_learn_from_book

!mcns_inv_next:
    inc mcns_inv_idx
    jmp !mcns_inv_loop-

!mcns_done:
    rts

mcns_learn_from_book:
    lda mcns_spell_start
    sta pm_learn_idx

!mcns_loop:
    lda pm_learn_idx
    sec
    sbc mcns_spell_start
    cmp #4
    bcc !mcns_cont+
    rts
!mcns_cont:

    lda pm_learn_idx
    cmp #8
    bcs !mcns_hi_check+

    tax
    lda spell_bit_mask,x
    and player_data + PL_SPELLS_KNOWN
    beq !mcns_check_level+
    jmp !mcns_next+

!mcns_hi_check:
    sec
    sbc #8
    tax
    lda spell_bit_mask,x
    and player_data + PL_SPELLS_KNOWN_HI
    beq !mcns_check_level+
    jmp !mcns_next+

!mcns_check_level:
    lda pm_lvl_tbl_lo
    sta zp_ptr0
    lda pm_lvl_tbl_hi
    sta zp_ptr0_hi
    ldy pm_learn_idx
    lda (zp_ptr0),y
    cmp zp_player_lvl
    beq !mcns_learn+
    bcc !mcns_learn+
    jmp !mcns_next+

!mcns_learn:
    lda pm_learn_idx
    cmp #8
    bcs !mcns_set_hi+

    tax
    lda player_data + PL_SPELLS_KNOWN
    ora spell_bit_mask,x
    sta player_data + PL_SPELLS_KNOWN
    jmp !mcns_msg+

!mcns_set_hi:
    sec
    sbc #8
    tax
    lda player_data + PL_SPELLS_KNOWN_HI
    ora spell_bit_mask,x
    sta player_data + PL_SPELLS_KNOWN_HI

!mcns_msg:
    lda #0
    sta cmb_buf_idx

    ldx #HSTR_PM_LEARNED
    jsr huff_append_combat

    lda pm_name_lo_lo
    sta zp_ptr0
    lda pm_name_lo_hi
    sta zp_ptr0_hi
    ldy pm_learn_idx
    lda (zp_ptr0),y
    sta zp_ptr2

    lda pm_name_hi_lo
    sta zp_ptr0
    lda pm_name_hi_hi
    sta zp_ptr0_hi
    ldy pm_learn_idx
    lda (zp_ptr0),y

    tay
    lda zp_ptr2
    jsr combat_append_str

    lda #<pm_bang_str
    ldy #>pm_bang_str
    jsr combat_append_str

    jsr cmb_term_and_print

!mcns_next:
    inc pm_learn_idx
    jmp !mcns_loop-

pm_bang_str:
    .byte $21, 0
