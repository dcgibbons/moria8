#importonce
// store_meta_macros.s — Store-slot metadata helpers (V2 paged 9-bit catalog).
// si_meta stores IF_* bits 0..3; si_meta_hi stores (page_bit | ego_id).

.macro LoadStoreFlagsX() {
    :AuxReadX(si_meta)
    and #ITEM_META_FLAGS_MASK
}

.macro LoadStoreFlagsY() {
    :AuxReadY(si_meta)
    and #ITEM_META_FLAGS_MASK
}

.macro LoadStoreEgoX() {
    :AuxReadX(si_meta_hi)
    and #EGO_ID_MASK
}

.macro LoadStoreEgoY() {
    :AuxReadY(si_meta_hi)
    and #EGO_ID_MASK
}

.macro LoadStorePageX() {
    :AuxReadX(si_meta_hi)
    and #ITEM_PAGE_BIT
}

.macro LoadStorePageY() {
    :AuxReadY(si_meta_hi)
    and #ITEM_PAGE_BIT
}

.macro LoadStoreMetaHiX() {
    :AuxReadX(si_meta_hi)
}

.macro StoreStoreFlagsYFromA() {
    and #ITEM_META_FLAGS_MASK
    :AuxWriteY(si_meta)
}

.macro StoreStoreEgoYFromA() {
    and #EGO_ID_MASK
    sta zp_temp0
    :AuxReadY(si_meta_hi)
    and #ITEM_PAGE_BIT
    ora zp_temp0
    :AuxWriteY(si_meta_hi)
}

.macro StoreStoreMetaY(flags, ego) {
    lda #flags
    :AuxWriteY(si_meta)
    lda item_cur_page
    and #ITEM_PAGE_BIT
    .if (ego != 0) {
        ora #(ego & EGO_ID_MASK)
    }
    :AuxWriteY(si_meta_hi)
}

.macro StoreStoreMetaYFromAdd() {
    lda fi_add_flags
    and #ITEM_META_FLAGS_MASK
    :AuxWriteY(si_meta)
    lda fi_add_ego
    :AuxWriteY(si_meta_hi)
}

.macro StoreStoreMetaYFromInvX() {
    lda inv_flags,x
    and #ITEM_META_FLAGS_MASK
    :AuxWriteY(si_meta)
    lda inv_ego,x
    :AuxWriteY(si_meta_hi)
}

