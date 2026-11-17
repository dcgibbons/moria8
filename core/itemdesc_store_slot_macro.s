#importonce
// itemdesc_store_slot_macro.s — Shared itemdesc_put_store_slot body macro
//
// Module ownership:
//   owner: RuntimeBanked / play-slot / Default (via item_desc_banked.s when
//     !ITEMDESC_STORE_SLOT_DUPLICATED) or duplicated locally into TownOverlay
//     (ui_store.s:itemdesc_put_store_slot_town) and HomeOverlay
//     (ui_home.s:itemdesc_put_store_slot_home) when ITEMDESC_STORE_SLOT_DUPLICATED
//     is defined.
//   lifetime: inline macro expansion in its caller segment; ends with jmp so
//     overlay expansions never fall through.
//   callers: item_desc_banked.s, ui_store.s, ui_home.s.

#import "store_meta_macros.s"

// Print store/home item description for absolute slot index X.
// Clobbers: A, X, Y, zp_ptr0
.macro ItemdescPutStoreSlotBody() {
    :AuxReadX(si_item_id)
    sta itemdesc_item_id
    lda #1
    sta itemdesc_qty
    :AuxReadX(si_p1)
    sta itemdesc_p1
    :AuxReadX(si_to_hit)
    sta itemdesc_to_hit
    :AuxReadX(si_to_dam)
    sta itemdesc_to_dam
    :AuxReadX(si_to_ac)
    sta itemdesc_to_ac
    :LoadStoreFlagsX()
    sta itemdesc_flags
    :LoadStoreMetaHiX()
    sta itemdesc_ego
    jmp itemdesc_put_staged
}
