#importonce
// store_check_category_macro.s — Shared check_store_category body macro (S7)
//
// Module ownership:
//   owner: Default resident (via store_data.s when !STORE_CHECK_CAT_DUPLICATED)
//     or duplicated locally into TownOverlay (ui_store.s:check_store_category_town)
//     and StoreRestockOverlay (store_restock_overlay.s:check_store_category_restock)
//     when STORE_CHECK_CAT_DUPLICATED is defined.
//   lifetime: inline macro expansion in its caller segment; ends with rts so
//     overlay expansions never fall through.
//   callers: store_data.s, ui_store.s, store_restock_overlay.s.

// Input: A = ICAT value (0-20), zp_store_idx = store index
// Output: carry set = category sold here, carry clear = not
// Clobbers: A, X
.macro CheckStoreCategoryBody() {
    cmp #8
    bcs !csc_hi+

    tax
    jsr !csc_bit+
    :AuxReadX(store_cat_mask_lo)
    and zp_temp0
    beq !csc_no+
    sec
    rts

!csc_hi:
    cmp #ICAT_SPIKE
    beq !csc_spike+
    cmp #ICAT_CLOAK
    beq !csc_cloak+
    cmp #ICAT_AMULET
    beq !csc_amulet+
    bcs !csc_no+            // Categories > AMULET (CHEST=17, JUNK=20) buy nowhere;
                            // also keeps the 8-entry bit_mask_table in bounds.
    sec
    sbc #8
    tax
    jsr !csc_bit+
    :AuxReadX(store_cat_mask_hi)
    and zp_temp0
    beq !csc_no+
    sec
    rts

!csc_cloak:
    ldx zp_store_idx
    :AuxReadX(store_cat_mask_x)
    and #$08                // Bit 3 (ICAT 19 = ICAT_CLOAK)
    beq !csc_no+
    sec
    rts

!csc_spike:
    // Spikes sell only at the general store (store 0), matching upstream.
    lda zp_store_idx
    beq !csc_spike_ok+
    clc
    rts
!csc_spike_ok:
    sec
    rts

!csc_amulet:
    ldx zp_store_idx
    :AuxReadX(store_cat_mask_x)
    lsr                     // Bit 0 -> carry = sold-here result
    rts

!csc_no:
    clc
    rts

// Load the bit mask for category offset X into zp_temp0 and store index into X.
!csc_bit:
    txa
    :AuxReadX(bit_mask_table)
    sta zp_temp0
    ldx zp_store_idx
    rts
}
