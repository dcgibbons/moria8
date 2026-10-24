#importonce
// inv_add.s — Adding an item to the carried inventory (stacking included).
// item.s imports this file unless the port defines INV_ADD_EXTERNAL and
// imports it into another always-visible segment (C128: the main image).

// inv_add_item — Add an item to the carried slots (0-21): onto an identical
// stack of a kind that stacks (food, potions, scrolls, flasks of oil,
// spikes, ammunition: VMS inven_carry) while the count fits a byte, else
// into the first empty slot.
// Input: fi_add_id, fi_add_qty, fi_add_p1, fi_add_to_hit/dam/ac, flags, ego
// Output: carry set = success (X = slot), carry clear = full
// Clobbers: A, X
inv_add_item:
    ldx fi_add_id
    lda it_category,x
    sec
    sbc #ICAT_FOOD
    cmp #ICAT_SCROLL - ICAT_FOOD + 1
    bcc !iai_stacks+                // food, potion, scroll
    cmp #ICAT_SPIKE - ICAT_FOOD
    beq !iai_stacks+
    cpx #ITEM_TYPE_FLASK_OF_OIL
    beq !iai_stacks+
    jsr item_get_missile            // bit 7 = ammunition; preserves X
    bpl !iai_new+
!iai_stacks:
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
    lda inv_flags,x
    cmp fi_add_flags
    bne !iai_next+
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
!iai_new:
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
