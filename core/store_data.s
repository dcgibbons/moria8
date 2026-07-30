#importonce
// store_data.s — Store persistent data and main-RAM helpers
//
// Store inventory arrays must persist across overlay loads ($E000).
// When creature tiers overwrite $E000, store data survives here.
// check_player_on_store_door also stays in main RAM since it's
// called on every town move (loading the overlay each time would
// be wasteful).
//
// Constants defined here (not in store.s) because store_data.s
// is imported first in main RAM, before the overlay segment.

#import "store_data_defs.s"

#if !STORE_RUNTIME_DATA_EXTERNAL
#import "store_runtime_data.s"
#endif

#if !STORE_INVENTORY_DATA_EXTERNAL
#import "store_inventory_data.s"
#endif

// ============================================================
// Store name strings (screen codes, null-terminated)
// ============================================================
#if !(C64_PRODUCT_OVERLAY_RUNTIME || C128_PRODUCT_OVERLAY_RUNTIME || PLUS4_PRODUCT_OVERLAY_RUNTIME || APPLE2_PRODUCT_OVERLAY_RUNTIME)
// Unit-test fixture strings. Product builds define these labels in TownOverlay.
sn_general:  .text "General Store"  ; .byte 0
sn_armory:   .text "Armory"         ; .byte 0
sn_weapon:   .text "Weaponsmith"    ; .byte 0
sn_temple:   .text "Temple"         ; .byte 0
sn_alchemy:  .text "Alchemy Shop"   ; .byte 0
sn_magic:    .text "Magic Shop"     ; .byte 0
sn_bmarket:  .text "Black Market"   ; .byte 0
sn_home:     .text "Home"            ; .byte 0
#endif

// ============================================================
// Store owner strings (screen codes, null-terminated)
// ============================================================
#if !(C64_PRODUCT_OVERLAY_RUNTIME || C128_PRODUCT_OVERLAY_RUNTIME || PLUS4_PRODUCT_OVERLAY_RUNTIME || APPLE2_PRODUCT_OVERLAY_RUNTIME)
so_0: .text "BILBO THE FRIENDLY"    ; .byte 0
so_1: .text "GORN THE ARMORER"      ; .byte 0
so_2: .text "BRYN THE FORGEMASTER"  ; .byte 0
so_3: .text "GARATH THE HEALER"     ; .byte 0
so_4: .text "ELARA THE ALCHEMIST"   ; .byte 0
so_5: .text "ZOLAN THE ENCHANTER"   ; .byte 0
so_6: .text "THE FENCE"             ; .byte 0
so_7: .byte 0                        // Home has no owner
#endif

// ============================================================
// check_player_on_store_door — Check if player is on a store door
// ============================================================
// Input: zp_player_x/y
// Output: carry set + A = store index (0-7) if on door
//         carry clear if not on any door
// Clobbers: A, X, zp_ptr1, zp_ptr1_hi
check_player_on_store_door:
    lda zp_player_x
    ldy zp_player_y

#import "store_door_lookup.s"

// check_store_category — Test if item category matches store
// Input: A = ICAT value (0-15), zp_store_idx = store index
// Output: carry set = category sold here, carry clear = not
// Clobbers: A, X
check_store_category:
    cmp #8
    bcs !csc_hi+

    tax
    :AuxReadX(bit_mask_table)
    sta zp_temp0
    ldx zp_store_idx
    :AuxReadX(store_cat_mask_lo)
    and zp_temp0
    beq !csc_no+
    sec
    rts

!csc_hi:
    sec
    sbc #8
    tax
    :AuxReadX(bit_mask_table)
    sta zp_temp0
    ldx zp_store_idx
    :AuxReadX(store_cat_mask_hi)
    and zp_temp0
    beq !csc_no+
    sec
    rts

!csc_no:
    clc
    rts
