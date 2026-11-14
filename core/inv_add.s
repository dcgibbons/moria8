#importonce
// inv_add.s — Adding an item to the carried inventory (stacking included).
// item.s imports this file unless the port defines INV_ADD_EXTERNAL and
// imports it into another always-visible segment (C128: the main image).

#import "item_stack_macros.s"

// inv_add_item — Add an item to the carried slots (0-21): onto a stack of
// the same item, p1, bonuses and ego, of a kind that stacks (food, potions, scrolls, flasks of oil,
// wooden torches with equal turns left, spikes, ammunition: VMS
// inven_carry) while the count fits a byte, else into the first empty slot.
// Input: fi_add_id, fi_add_qty, fi_add_p1, fi_add_to_hit/dam/ac, flags, ego
// Output: carry set = success (X = slot), carry clear = full
// Clobbers: A, X
inv_add_item:
    ldx fi_add_id
    :ItemStacksX(iai_new)
    ldx #MAX_INV_SLOTS - 1
!iai_match:
    lda inv_item_id,x
    cmp fi_add_id
    bne !iai_next+
    lda inv_p1,x
    cmp fi_add_p1
    bne !iai_next+
    lda inv_to_hit,x
    cmp fi_add_to_hit
    bne !iai_next+
    lda inv_to_dam,x
    cmp fi_add_to_dam
    bne !iai_next+                  // (no stacking kind carries a to-AC)
    // Not the flags: VMS inven_carry stacks on tval and subval alone, and
    // Umoria on whether the kind is known, the same for every item of it.
    // Comparing them kept identified and unidentified potions of one kind
    // in separate slots until the 22 filled (Balrog queue, 2026-11-09:
    // clvl 38 Priests with two stacks each of Cure Serious Wounds and Phase
    // Door could not buy Word of Recall). The stack keeps its own flags.
    lda inv_ego,x
    cmp fi_add_ego
    bne !iai_next+
    lda inv_qty,x
    clc
    adc fi_add_qty
    bcs !iai_next+                  // a full stack: start another
    sta inv_qty,x
    sec                             // success
    rts
!iai_next:
    dex
    bpl !iai_match-
iai_new:
    ldx #0
!iai_scan:
    cpx #MAX_INV_SLOTS
    bcs !iai_full+
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !iai_found+
    inx
    jmp !iai_scan-
!iai_found:
    jsr fi_add_to_inv_slot          // flags too (preserves IF_CURSED etc.)
    sec
    rts
!iai_full:
    clc
    rts

// inv_add_carried — inv_add_item for an item newly carried (picked up,
// bought, taken from the home), refused as VMS inven_check_weight when every
// item carried and worn (VMS inven_weight counts both) and it would weigh
// more than weight_limit: STR x 130 + body weight, at most 3000, in 1/10 lb
// (VMS misc.inc; moria.inc carry and store2.inc purchase: "You can't carry
// that much weight.").
// Input: as inv_add_item
// Output: carry set = added (X = slot); carry clear: X = the refusal's message
// Clobbers: A, X, Y, zp_math_*
// A port short of resident room (HAL_PLATFORM_INV_ADD_CARRIED_EXTERNAL)
// expands the body in the overlays that call it instead (the Apple IIe:
// OVL.TOWN for the store and home, OVL.ITEMS for the floor pickup).
.macro InvAddCarriedBody() {
    ldx fi_add_id
    lda it_weight,x
    ldx fi_add_qty
    jsr math_multiply               // A = lo, zp_math_b = hi
    sta iac_lo
    lda zp_math_b
    sta iac_hi
    ldy #TOTAL_INV_SLOTS - 1
!iac_sum:
    ldx inv_item_id,y
    cpx #FI_EMPTY
    beq !iac_next+
    lda it_weight,x
    ldx inv_qty,y
    jsr math_multiply               // preserves Y
    clc
    adc iac_lo
    sta iac_lo
    lda zp_math_b
    adc iac_hi
    sta iac_hi
    bcs !iac_heavy+                 // past 6,553 lb: over any limit
!iac_next:
    dey
    bpl !iac_sum-
    lda player_data + PL_STR_CUR    // 3-118 (18/100), as VMS cstr
    ldx #130
    jsr math_multiply
    clc
    adc player_data + PL_WEIGHT     // body weight in lb, added as VMS adds it
    tax                             // the limit's low byte
    lda zp_math_b
    adc #0                          // and high
    cmp #>3000
    bcc !iac_limit+
    bne !iac_cap+
    cpx #<3000 + 1
    bcc !iac_limit+
!iac_cap:
    lda #>3000
    ldx #<3000
!iac_limit:
    sta zp_math_b
    cpx iac_lo                      // limit - weight: a borrow is too heavy
    sbc iac_hi
    bcc !iac_heavy+
    jsr inv_add_item
    bcs !iac_done+
    ldx #HSTR_UIS_PACK_FULL
    rts
!iac_heavy:
    ldx #HSTR_UIS_TOO_HEAVY
    clc
!iac_done:
    rts
iac_lo: .byte 0
iac_hi: .byte 0
}
#if !HAL_PLATFORM_INV_ADD_CARRIED_EXTERNAL
inv_add_carried:
    :InvAddCarriedBody()
#endif
