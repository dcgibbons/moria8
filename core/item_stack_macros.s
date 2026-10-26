#importonce
// item_stack_macros.s — Which items stack, shared by the pack and the stores.

// ItemStacksX — Fall through when item type X is a kind that stacks (food,
// potions, scrolls, spikes, flasks of oil, wooden torches, ammunition: VMS
// inven_carry, Umoria inventoryItemSingleStackable); branch to `no` when it
// does not. Preserves X and Y.
.macro ItemStacksX(no) {
    lda it_category,x
    sec
    sbc #ICAT_FOOD
    cmp #ICAT_SCROLL - ICAT_FOOD + 1
    bcc stacks                      // food, potion, scroll
    cmp #ICAT_SPIKE - ICAT_FOOD
    beq stacks
    cpx #ITEM_TYPE_FLASK_OF_OIL
    beq stacks
    cpx #ITEM_TYPE_WOODEN_TORCH
    beq stacks                      // turns left must match too
    jsr item_get_missile            // bit 7 = ammunition; preserves X
    bpl no
stacks:
}
