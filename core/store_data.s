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

// ============================================================
// Constants
// ============================================================
.const STORE_MAX_ITEMS   = 12
.const STORE_TOTAL_SLOTS = 96   // 8 × 12
.const STORE_PICK_RETRIES = 30  // Max rejection sampling attempts
.const STORE_BM   = 6          // Black Market store index
.const STORE_HOME = 7          // Player Home store index

// Store category bitmasks (16-bit, bit N = ICAT N)
// Store 0 General: FOOD(9), LIGHT(8)
// Store 1 Armory: ARMOR(3), SHIELD(4), HELM(5), GLOVES(6), BOOTS(7)
// Store 2 Weapon: WEAPON(2)
// Store 3 Temple: SCROLL(11), POTION(10)
// Store 4 Alchemy: POTION(10)
// Store 5 Magic: WAND(14), STAFF(15), RING(12)
store_cat_mask_lo:
    .byte <$0301, <$00F8, <$0004, <$0C00, <$0400, <$F000, <$FFFF, <$FFFF
store_cat_mask_hi:
    .byte >$0300, >$00F8, >$0004, >$0C00, >$0400, >$F000, >$FFFF, >$FFFF

bit_mask_table:
    .byte $01, $02, $04, $08, $10, $20, $40, $80

// ============================================================
// Store inventory arrays (Struct-of-Arrays, 288 bytes)
// ============================================================
si_item_id:     .fill STORE_TOTAL_SLOTS, $FF   // $FF = empty
si_qty:         .fill STORE_TOTAL_SLOTS, 0
si_p1:          .fill STORE_TOTAL_SLOTS, 0
si_to_hit:      .fill STORE_TOTAL_SLOTS, 0
si_to_dam:      .fill STORE_TOTAL_SLOTS, 0
si_to_ac:       .fill STORE_TOTAL_SLOTS, 0
si_meta:        .fill STORE_TOTAL_SLOTS, 0   // bits 0-3 flags, bits 4-6 ego
hg_kicked:      .fill 8, 0                    // Resets on town re-entry

// Base index into SoA arrays for each store (store * 12)
store_base_idx:
    .byte 0, 12, 24, 36, 48, 60, 72, 84

// ============================================================
// Store name strings (screen codes, null-terminated)
// ============================================================
#if !(C64_PRODUCT_OVERLAY_RUNTIME || C128_PRODUCT_OVERLAY_RUNTIME || PLUS4_PRODUCT_OVERLAY_RUNTIME)
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

store_name_lo:
    .byte <sn_general, <sn_armory, <sn_weapon, <sn_temple, <sn_alchemy, <sn_magic, <sn_bmarket, <sn_home
store_name_hi:
    .byte >sn_general, >sn_armory, >sn_weapon, >sn_temple, >sn_alchemy, >sn_magic, >sn_bmarket, >sn_home

// ============================================================
// Store owner strings (screen codes, null-terminated)
// ============================================================
#if !(C64_PRODUCT_OVERLAY_RUNTIME || C128_PRODUCT_OVERLAY_RUNTIME || PLUS4_PRODUCT_OVERLAY_RUNTIME)
so_0: .text "BILBO THE FRIENDLY"    ; .byte 0
so_1: .text "GORN THE ARMORER"      ; .byte 0
so_2: .text "BRYN THE FORGEMASTER"  ; .byte 0
so_3: .text "GARATH THE HEALER"     ; .byte 0
so_4: .text "ELARA THE ALCHEMIST"   ; .byte 0
so_5: .text "ZOLAN THE ENCHANTER"   ; .byte 0
so_6: .text "THE FENCE"             ; .byte 0
so_7: .byte 0                        // Home has no owner
#endif

store_owner_lo:
    .byte <so_0, <so_1, <so_2, <so_3, <so_4, <so_5, <so_6, <so_7
store_owner_hi:
    .byte >so_0, >so_1, >so_2, >so_3, >so_4, >so_5, >so_6, >so_7

// ============================================================
// check_player_on_store_door — Check if player is on a store door
// ============================================================
// Input: zp_player_x/y
// Output: carry set + A = store index (0-7) if on door
//         carry clear if not on any door
// Clobbers: A, X
check_player_on_store_door:
    ldx #7
!cpsd_loop:
    lda zp_player_x
    cmp store_door_x,x
    bne !cpsd_next+
    lda zp_player_y
    cmp store_door_y,x
    bne !cpsd_next+
    // Match
    txa
    sec
    rts
!cpsd_next:
    dex
    bpl !cpsd_loop-
    clc
    rts

// check_store_category — Test if item category matches store
// Input: A = ICAT value (0-15), zp_store_idx = store index
// Output: carry set = category sold here, carry clear = not
// Clobbers: A, X
check_store_category:
    cmp #8
    bcs !csc_hi+

    tax
    lda bit_mask_table,x
    ldx zp_store_idx
    and store_cat_mask_lo,x
    beq !csc_no+
    sec
    rts

!csc_hi:
    sec
    sbc #8
    tax
    lda bit_mask_table,x
    ldx zp_store_idx
    and store_cat_mask_hi,x
    beq !csc_no+
    sec
    rts

!csc_no:
    clc
    rts
