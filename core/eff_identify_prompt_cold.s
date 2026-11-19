#importonce
// eff_identify_prompt_cold.s — Cold interactive item-identification prompt
//
// Module ownership:
//   owner: Default resident / play-slot when !EFF_IDENTIFY_PROMPT_EXTERNAL, or
//     port spell/utility overlay when EFF_IDENTIFY_PROMPT_EXTERNAL is defined
//     (preserving piw_return_overlay across nested '?' show_inv_and_select).
//   lifetime: one Identify spell/staff/scroll prompt session.
//   callers: resident eff_identify_scroll_resident (via tramp_eff_identify_scroll_resident
//     when EFF_IDENTIFY_PROMPT_EXTERNAL) and spell/staff identify handlers.

// ============================================================
// eff_identify_prompt — Interactive item identification
// Input: none (prompts user for slot)
// Output: item type identified (id_known set), instance flagged IF_IDENTIFIED,
//         message printed
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
eff_identify_prompt:
    lda #$fd
    ldx #HSTR_PIQ_IDENTIFY_PROMPT
    jsr piw_prompt_filtered_inv
    bcs !eip_have_choices+
    clc
    rts
!eip_have_choices:
    jsr input_prepare_followup_key
!eip_retry:
    jsr hal_input_get_key
#if EFF_IDENTIFY_PROMPT_EXTERNAL && HAL_PLATFORM_ITEM_ACTION_KEY_RESTORES_BANK
    jsr hal_platform_item_action_restore_bank
#endif

    cmp #$3f
    bne !eip_not_inv+
#if EFF_IDENTIFY_PROMPT_EXTERNAL && PLATFORM_PRODUCT_OVERLAY_RUNTIME
    lda current_overlay
    sta piw_return_overlay
#endif
    lda #$fd
    jsr show_inv_and_select
!eip_not_inv:

    // Cancel check
    cmp #$03
    beq !eip_cancel+
    cmp #$20
    beq !eip_cancel+

    jsr piw_pick_filtered_inv_key
    bcc !eip_cancel+
    stx eff_target_slot

    // Identify that item type (preserve X -> page bit before id_known_set_y).
    tay
    pha
    lda inv_ego,x
    and #ITEM_PAGE_BIT
    sta item_cur_page
    jsr id_known_set_y

    // Set IF_IDENTIFIED on the item instance
    lda inv_flags,x
    and #~IF_SENSED & $ff
    ora #IF_IDENTIFIED
    sta inv_flags,x

    // Build message: "THIS IS A <real name>."
    lda #0
    sta cmb_buf_idx

    ldx #HSTR_PIQ_THISIS
    jsr huff_append_combat

    pla
    ldx eff_target_slot
    lda inv_p1,x
    sta fi_add_p1
    lda inv_to_hit,x
    sta fi_add_to_hit
    lda inv_to_dam,x
    sta fi_add_to_dam
    lda inv_to_ac,x
    sta fi_add_to_ac
    lda inv_flags,x
    sta fi_add_flags
    lda inv_ego,x
    sta fi_add_ego
    lda inv_item_id,x
    jsr item_append_name

    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str
!eip_print:

    jmp cmb_term_and_print

!eip_cancel:
    // Scroll already consumed — just print generic message
    ldx #HSTR_PIQ_NOTHING
    jmp huff_print_msg
