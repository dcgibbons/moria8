// player_gain_spell_impl.s — shared study-book implementation
//
// Included by the C64 resident build and the C128 UI overlay build.

igs_pick_idx: .byte 0

item_gain_spell:
    lda player_data + PL_SPELL_TYPE
    bne !igs_has_magic+
    ldx #HSTR_IGS_NO_MAGIC
    jsr huff_print_msg
    clc
    rts
!igs_has_magic:
    lda player_data + PL_NEW_SPELLS
    bne !igs_has_pending+
    ldx #HSTR_IGS_NO_NEW
    jsr huff_print_msg
    clc
    rts
!igs_has_pending:
    lda player_data + PL_SPELL_TYPE
    sta pm_spell_type
    lda #1
    sta pm_mode
    jsr pm_setup_active_tables
    jsr pm_select_book
    bcc !igs_cancel+

    jsr pm_build_learnable_list_from_book
    lda pm_spell_count
    bne !igs_have_choices+
    ldx #HSTR_IGS_NO_NEW
    jsr huff_print_msg
    clc
    rts

!igs_have_choices:
    lda pm_spell_type
    cmp #SPELL_PRIEST
    beq !igs_random_prayer+

    jsr tramp_spell_list_display
    jsr input_prepare_followup_key
    jsr input_get_key
    jsr pm_pick_visible_spell
    bcc !igs_cancel_restore+
    jsr ui_view_restore_modal_overlay
    jsr pm_learn_selected_spell
    lda #SFX_LEVELUP
    jsr sound_play
    sec
    rts

!igs_random_prayer:
    lda pm_spell_count
    jsr rng_range
    sta igs_pick_idx
    tay
    lda pm_spell_list,y
    sta pm_spell_idx
    jsr pm_learn_selected_spell
    lda #SFX_LEVELUP
    jsr sound_play
    sec
    rts

!igs_cancel_restore:
    jsr ui_view_restore_modal_overlay
!igs_cancel:
    clc
    rts
