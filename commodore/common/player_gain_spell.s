#importonce
// player_gain_spell.s — C128 UI-overlay copy of item_gain_spell

item_gain_spell:
    // Check if player has a spell type at all
    lda player_data + PL_SPELL_TYPE
    bne !igs_can_cast+
    ldx #HSTR_IGS_NO_MAGIC
    jsr huff_print_msg
    clc
    rts

!igs_can_cast:
    lda #ICAT_BOOK
    ldx #HSTR_IGS_PROMPT
    jsr piw_prompt_filtered_inv
    bcs !igs_have_choices+
    clc
    rts
!igs_have_choices:
    jsr input_prepare_followup_key

    jsr input_get_key

    // '?' shows inventory (books only) and re-prompts
    cmp #$3f
    bne !igs_not_inv+
    lda #ICAT_BOOK
    jsr show_inv_and_restore
    jmp !igs_can_cast-
!igs_not_inv:

    // ESC or space → cancel
    cmp #$20
    beq !igs_cancel_early+
    cmp #$1b
    beq !igs_cancel_early+

    jsr piw_pick_filtered_inv_key
    bcs !igs_slot_ok+
!igs_cancel_early:
    clc
    rts
!igs_slot_ok:
    stx piw_slot
    // Look up book metadata: spell range and class
    jsr book_get_info           // A = spell_start, X = spell_class, C=0
    bcc !igs_book_ok+
    jmp !igs_cancel+
!igs_book_ok:
    sta igs_spell_start
    stx igs_spell_class

    // Check class matches player's spell type
    lda player_data + PL_SPELL_TYPE
    cmp igs_spell_class
    beq !igs_type_ok+
    ldx #HSTR_IGS_WRONG_TYPE
    jsr huff_print_msg
    clc
    rts

!igs_type_ok:
    // Set up spell level table pointer
    lda igs_spell_class
    cmp #SPELL_MAGE
    bne !igs_priest_lvl+
    lda #<mage_spell_level
    sta zp_ptr1
    lda #>mage_spell_level
    sta zp_ptr1_hi
    jmp !igs_lvl_set+
!igs_priest_lvl:
    lda #<priest_spell_level
    sta zp_ptr1
    lda #>priest_spell_level
    sta zp_ptr1_hi
!igs_lvl_set:

    // Loop over 4 spells in this book's range
    lda #0
    sta igs_learned_count
    lda igs_spell_start
    sta igs_spell_idx

!igs_spell_loop:
    // Check player_level >= required spell level
    ldy igs_spell_idx
    lda player_data + PL_LEVEL
    cmp (zp_ptr1),y
    bcc !igs_next_spell+

    // Check if spell already known
    lda igs_spell_idx
    cmp #8
    bcs !igs_hi_check+

    // Lo byte (spells 0-7)
    tax
    lda spell_bit_mask,x
    and player_data + PL_SPELLS_KNOWN
    bne !igs_next_spell+
    // Learn: set bit in lo byte
    lda spell_bit_mask,x
    ora player_data + PL_SPELLS_KNOWN
    sta player_data + PL_SPELLS_KNOWN
    inc igs_learned_count
    jmp !igs_next_spell+

!igs_hi_check:
    // Hi byte (spells 8-15)
    sec
    sbc #8
    tax
    lda spell_bit_mask,x
    and player_data + PL_SPELLS_KNOWN_HI
    bne !igs_next_spell+
    // Learn: set bit in hi byte
    lda spell_bit_mask,x
    ora player_data + PL_SPELLS_KNOWN_HI
    sta player_data + PL_SPELLS_KNOWN_HI
    inc igs_learned_count

!igs_next_spell:
    inc igs_spell_idx
    lda igs_spell_idx
    sec
    sbc igs_spell_start
    cmp #4
    bcc !igs_spell_loop-

    // Check results
    lda igs_learned_count
    beq !igs_none_learned+

    // Learned at least one spell
    ldx #HSTR_IGS_SUCCESS
    jsr huff_print_msg

    lda #SFX_LEVELUP
    jsr sound_play

    sec
    rts

!igs_none_learned:
    ldx #HSTR_IGS_NO_NEW
    jsr huff_print_msg
    clc
    rts

!igs_cancel:
    clc
    rts

igs_spell_idx:      .byte 0
igs_spell_start:    .byte 0
igs_spell_class:    .byte 0
igs_learned_count:  .byte 0
