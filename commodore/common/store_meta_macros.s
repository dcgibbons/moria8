#importonce
// store_meta_macros.s — Packed store-slot metadata helpers.

.macro LoadStoreFlagsX() {
    lda si_meta,x
    and #ITEM_META_FLAGS_MASK
}

.macro LoadStoreFlagsY() {
    lda si_meta,y
    and #ITEM_META_FLAGS_MASK
}

.macro LoadStoreEgoX() {
    lda si_meta,x
    lsr
    lsr
    lsr
    lsr
}

.macro LoadStoreEgoY() {
    lda si_meta,y
    lsr
    lsr
    lsr
    lsr
}

.macro StoreStoreFlagsYFromA() {
    and #ITEM_META_FLAGS_MASK
    sta zp_temp0
    lda si_meta,y
    and #ITEM_META_EGO_MASK
    ora zp_temp0
    sta si_meta,y
}

.macro StoreStoreEgoYFromA() {
    asl
    asl
    asl
    asl
    and #ITEM_META_EGO_MASK
    sta zp_temp0
    lda si_meta,y
    and #ITEM_META_FLAGS_MASK
    ora zp_temp0
    sta si_meta,y
}

.macro StoreStoreMetaY(flags, ego) {
    lda #ego
    asl
    asl
    asl
    asl
    ora #flags
    sta si_meta,y
}

.macro StoreStoreMetaYFromAdd() {
    lda fi_add_ego
    asl
    asl
    asl
    asl
    and #ITEM_META_EGO_MASK
    sta zp_temp0
    lda fi_add_flags
    and #ITEM_META_FLAGS_MASK
    ora zp_temp0
    sta si_meta,y
}

.macro StoreStoreMetaYFromInvX() {
    lda inv_ego,x
    asl
    asl
    asl
    asl
    and #ITEM_META_EGO_MASK
    sta zp_temp0
    lda inv_flags,x
    and #ITEM_META_FLAGS_MASK
    ora zp_temp0
    sta si_meta,y
}
