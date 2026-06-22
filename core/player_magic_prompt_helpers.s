#importonce
// player_magic_prompt_helpers.s — prompt selection for spell/prayer commands.

pm_book_prompt_huff_id:
    ldx #HSTR_IGS_PROMPT
    lda pm_mode
    bne !pm_prompt_done+
    ldx #HSTR_PM_YOU_PRAY
    lda pm_spell_type
    cmp #SPELL_MAGE
    bne !pm_prompt_done+
    ldx #HSTR_PM_YOU_CAST
!pm_prompt_done:
    rts
pm_book_prompt_huff_id_end:
