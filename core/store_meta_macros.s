#importonce
// store_meta_macros.s — Packed store-slot metadata helpers.

.macro LoadStoreFlagsX() {
    :AuxReadX(si_meta)
    and #ITEM_META_FLAGS_MASK
}

.macro LoadStoreFlagsY() {
    :AuxReadY(si_meta)
    and #ITEM_META_FLAGS_MASK
}

.macro LoadStoreEgoX() {
    :AuxReadX(si_meta)
    lsr
    lsr
    lsr
    lsr
}

.macro LoadStoreEgoY() {
    :AuxReadY(si_meta)
    lsr
    lsr
    lsr
    lsr
}

.macro StoreStoreFlagsYFromA() {
    and #ITEM_META_FLAGS_MASK
    sta zp_temp0
    :AuxReadY(si_meta)
    and #ITEM_META_EGO_MASK
    ora zp_temp0
    :AuxWriteY(si_meta)
}

.macro StoreStoreEgoYFromA() {
    asl
    asl
    asl
    asl
    and #ITEM_META_EGO_MASK
    sta zp_temp0
    :AuxReadY(si_meta)
    and #ITEM_META_FLAGS_MASK
    ora zp_temp0
    :AuxWriteY(si_meta)
}

.macro StoreStoreMetaY(flags, ego) {
    lda #ego
    asl
    asl
    asl
    asl
    ora #flags
    :AuxWriteY(si_meta)
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
    :AuxWriteY(si_meta)
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
    :AuxWriteY(si_meta)
}
