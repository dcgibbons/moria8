#importonce
// item_exchange.s — SHIFT+X: swap the primary and secondary weapons.
//
// VMS Moria 4.8 `x` (moria.inc:616-648, :699-706): with neither weapon slot
// occupied, refuse; with a cursed primary, refuse; otherwise take a turn,
// swap EQUIP_WEAPON and EQUIP_SECONDARY, recompute the bonuses, and report
// each occupied slot. Both refusals take no turn. The secondary's bonuses
// count for nothing (player_recalc_equipment reads EQUIP_WEAPON only).
//
// Imported by each port into an overlay (the C64 Chest overlay, the Items
// overlay elsewhere), never through item_actions_overlay.s.

.assert "Inventory arrays contiguous, stream order", inv_qty == inv_item_id + TOTAL_INV_SLOTS && inv_p1 == inv_item_id + 2 * TOTAL_INV_SLOTS && inv_to_hit == inv_item_id + 3 * TOTAL_INV_SLOTS && inv_to_dam == inv_item_id + 4 * TOTAL_INV_SLOTS && inv_to_ac == inv_item_id + 5 * TOTAL_INV_SLOTS && inv_flags == inv_item_id + 6 * TOTAL_INV_SLOTS && inv_ego == inv_item_id + 7 * TOTAL_INV_SLOTS, true
.assert "Swap walk wraps once after 8 arrays", 7 * TOTAL_INV_SLOTS < 256 && 8 * TOTAL_INV_SLOTS >= 256, true

// item_exchange — Output: carry set = turn consumed, carry clear = refused.
// Clobbers: everything
item_exchange:
    lda inv_item_id + EQUIP_SECONDARY   // corrupt-save guard: the secondary
    cmp #FI_EMPTY                       // may hold only a weapon or nothing
    beq !ix_sec_ok+
    tax
    lda it_category,x
    tax
    lda equip_slot_for_cat,x            // weapons and digging tools map here
    cmp #EQUIP_WEAPON
    bne !ix_none+                       // anything else: refuse; `t` recovers it
!ix_sec_ok:
    lda inv_item_id + EQUIP_WEAPON
    and inv_item_id + EQUIP_SECONDARY   // AND == $ff only when both slots
    cmp #FI_EMPTY                       // hold FI_EMPTY ($ff)
    bne !ix_have+
!ix_none:
    lda #<ix_no_weapons_str
    ldy #>ix_no_weapons_str
    jsr msg_print_ay
    clc
    rts
!ix_have:
    lda inv_flags + EQUIP_WEAPON        // empty slots hold flags 0
    and #IF_CURSED
    beq !ix_swap+
    ldx #HSTR_PIW_CURSED                // "You cannot remove it, it is cursed!"
    jmp piw_msg_no_turn
!ix_swap:
    ldx #0
!ix_loop:                               // all 8 arrays, stride TOTAL_INV_SLOTS
    lda inv_item_id + EQUIP_WEAPON,x
    ldy inv_item_id + EQUIP_SECONDARY,x
    sta inv_item_id + EQUIP_SECONDARY,x
    tya
    sta inv_item_id + EQUIP_WEAPON,x
    txa
    clc
    adc #TOTAL_INV_SLOTS
    tax
    bcc !ix_loop-                       // carry after the 8th array
    jsr player_recalc_equipment
    ldx #EQUIP_WEAPON
    lda #<ix_primary_str
    ldy #>ix_primary_str
    jsr ix_report
    ldx #EQUIP_SECONDARY
    lda #<ix_secondary_str
    ldy #>ix_secondary_str
    jsr ix_report
    sec
    rts

// ix_report — Print prefix A/Y plus the description of slot X, if occupied.
ix_report:
    sta zp_ptr1                         // prefix lo (Y = hi survives)
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !ix_skip+
    stx piw_slot
    lda #0
    sta cmb_buf_idx
    lda zp_ptr1
    jsr combat_append_str
    ldx piw_slot
    jsr inv_slot_to_fi_add              // A = item id, fi_add_* staged
    jsr item_append_desc
    jmp cmb_term_and_print
!ix_skip:
    rts

ix_no_weapons_str: .text "No weapons to exchange." ; .byte 0
ix_primary_str:    .text "Primary: " ; .byte 0
ix_secondary_str:  .text "Secondary: " ; .byte 0
