// store.s — Store restocking, price calculation, gold ops
//
// 6 town stores with persistent inventory (SoA layout, 12 slots each).
// Restocking on town re-entry. Buy/sell price adjusted by CHR stat.
//
// Inventory arrays and check_player_on_store_door live in store_data.s
// (main RAM) so they persist across $E000 overlay loads.

// Constants defined in store_data.s (imported in main RAM before overlay)

// ============================================================
// Store category bitmasks (16-bit, bit N = ICAT N)
// ============================================================
// Store 0 General:  FOOD(9), LIGHT(8)         = $0300
// Store 1 Armory:   ARMOR(3), SHIELD(4), HELM(5), GLOVES(6), BOOTS(7) = $00F8
// Store 2 Weapon:   WEAPON(2)                 = $0004
// Store 3 Temple:   SCROLL(11), POTION(10)    = $0C00
// Store 4 Alchemy:  POTION(10)                = $0400
// Store 5 Magic:    WAND(14), STAFF(15), RING(12) = $D000
store_cat_mask_lo:
    .byte <$0300, <$00F8, <$0004, <$0C00, <$0400, <$F000
store_cat_mask_hi:
    .byte >$0300, >$00F8, >$0004, >$0C00, >$0400, >$F000

// Fallback items per store (used when rejection sampling fails)
store_fallback:
    .byte 15, 7, 2, 20, 17, 23  // food, leather, dagger, scroll, CLW potion, ring

// Bit mask table for category checking (bit 0-7)
bit_mask_table:
    .byte $01, $02, $04, $08, $10, $20, $40, $80

// ============================================================
// Store name strings (screen codes, null-terminated)
// ============================================================
sn_general:  .text "GENERAL STORE"  ; .byte 0
sn_armory:   .text "ARMORY"         ; .byte 0
sn_weapon:   .text "WEAPONSMITH"    ; .byte 0
sn_temple:   .text "TEMPLE"         ; .byte 0
sn_alchemy:  .text "ALCHEMY SHOP"   ; .byte 0
sn_magic:    .text "MAGIC SHOP"     ; .byte 0

store_name_lo:
    .byte <sn_general, <sn_armory, <sn_weapon, <sn_temple, <sn_alchemy, <sn_magic
store_name_hi:
    .byte >sn_general, >sn_armory, >sn_weapon, >sn_temple, >sn_alchemy, >sn_magic

// ============================================================
// Store owner strings (screen codes, null-terminated)
// ============================================================
so_0: .text "BILBO THE FRIENDLY"    ; .byte 0
so_1: .text "GORN THE ARMORER"      ; .byte 0
so_2: .text "BRYN THE FORGEMASTER"  ; .byte 0
so_3: .text "GARATH THE HEALER"     ; .byte 0
so_4: .text "ELARA THE ALCHEMIST"   ; .byte 0
so_5: .text "ZOLAN THE ENCHANTER"   ; .byte 0

store_owner_lo:
    .byte <so_0, <so_1, <so_2, <so_3, <so_4, <so_5
store_owner_hi:
    .byte >so_0, >so_1, >so_2, >so_3, >so_4, >so_5

// ============================================================
// Scratch variables
// ============================================================
sb_price_lo:   .byte 0     // Computed price (16-bit)
sb_price_hi:   .byte 0
sb_abs_slot:   .byte 0     // Absolute store slot index
ss_inv_slot:   .byte 0     // Player inventory slot for sell
ss_item_id:    .byte 0     // Item type being sold
sd_row:        .byte 0     // Current screen row during drawing
sd_save_x:     .byte 0     // Saved index register
sr_retry:      .byte 0     // Rejection sampling retry counter
sr_store_idx:  .byte 0     // Store index for restock loop
sb_item_p1:    .byte 0     // Item enchantment/charges for pricing (RP14-3)
sb_item_type:  .byte 0     // Item type saved for p1 bonus lookup

// Haggling state (R6.1)
hg_ask_lo:     .byte 0     // Shopkeeper's current price (16-bit)
hg_ask_hi:     .byte 0
hg_min_lo:     .byte 0     // Floor (buy) or ceiling (sell) price
hg_min_hi:     .byte 0
hg_input_lo:   .byte 0     // Player's typed number (16-bit)
hg_input_hi:   .byte 0
hg_round:      .byte 0     // Round counter (0-3)
hg_insults:    .byte 0     // Insult counter per visit
hg_kicked:     .fill 6, 0  // Per-store kicked flag (resets on town re-entry)
hg_tmp0:       .byte 0     // Temp for gap/step calculation
hg_tmp1:       .byte 0
hg_digit_cnt:  .byte 0     // Digit count for number input

// ============================================================
// Subroutines
// ============================================================

// store_init_all — Clear all store slots and restock
// Called once at game start.
// Clobbers: everything
store_init_all:
    // Clear all 72 slots to empty
    ldx #STORE_TOTAL_SLOTS - 1
    lda #FI_EMPTY
!sia_clr:
    sta si_item_id,x
    dex
    bpl !sia_clr-

    ldx #STORE_TOTAL_SLOTS - 1
    lda #0
!sia_clr2:
    sta si_qty,x
    sta si_p1,x
    sta si_flags,x
    dex
    bpl !sia_clr2-

    jmp store_restock_all       // Tail call

// store_restock_all — Restock all 6 stores + reset kicked flags
// Clobbers: everything
store_restock_all:
    // Reset haggling kicked flags for all stores
    ldx #5
    lda #0
!sra_clr_kick:
    sta hg_kicked,x
    dex
    bpl !sra_clr_kick-

    sta sr_store_idx
!sra_loop:
    lda sr_store_idx
    cmp #STORE_COUNT
    bcs !sra_done+
    sta zp_store_idx
    jsr store_restock_one
    inc sr_store_idx
    jmp !sra_loop-
!sra_done:
    rts

// store_restock_one — Restock empty slots in store zp_store_idx
// For each of 12 slots: if empty, 50% chance to stock.
// Clobbers: everything
store_restock_one:
    ldx zp_store_idx
    lda store_base_idx,x
    sta sb_abs_slot             // Starting absolute slot

    ldx #0                      // Slot counter 0-11
!sro_loop:
    cpx #STORE_MAX_ITEMS
    bcc !sro_cont+
    jmp !sro_done+
!sro_cont:
    stx sd_save_x

    // Check if slot is empty
    ldy sb_abs_slot
    lda si_item_id,y
    cmp #FI_EMPTY
    bne !sro_next+

    // 50% chance to stock
    jsr rng_byte
    and #$01
    beq !sro_next+

    // Pick an item for this store
    jsr store_pick_item         // Returns A = item type

    // Write to store slot
    ldy sb_abs_slot
    sta si_item_id,y
    lda #1
    sta si_qty,y

    // Determine p1 value based on category
    lda si_item_id,y
    tax
    lda it_category,x
    jsr sro_set_p1              // Subroutine handles enchant/charges/zero

!sro_next:
    ldx sd_save_x
    inc sb_abs_slot
    inx
    jmp !sro_loop-
!sro_done:
    rts

// sro_set_p1 — Set p1 and flags for newly stocked item
// Input: A = category, sb_abs_slot = target slot
// Clobbers: A, X, Y
sro_set_p1:
    // Equipment categories get enchantment 0-2
    cmp #ICAT_WEAPON
    beq !sro_enchant+
    cmp #ICAT_ARMOR
    beq !sro_enchant+
    cmp #ICAT_SHIELD
    beq !sro_enchant+
    cmp #ICAT_HELM
    beq !sro_enchant+
    cmp #ICAT_GLOVES
    beq !sro_enchant+
    cmp #ICAT_BOOTS
    beq !sro_enchant+
    cmp #ICAT_BOOK
    beq !sro_book+

    // Wands/staffs get charges 3-8
    cmp #ICAT_WAND
    beq !sro_charges+
    cmp #ICAT_STAFF
    beq !sro_charges+

    // Default: p1 = 0, flags = 0
    lda #0
    ldy sb_abs_slot
    sta si_p1,y
    sta si_flags,y
    rts

!sro_charges:
    lda #6
    jsr rng_range               // 0-5
    clc
    adc #3
    ldy sb_abs_slot
    sta si_p1,y
    lda #0
    sta si_flags,y
    rts

!sro_enchant:
    lda #3
    jsr rng_range               // 0-2
    ldy sb_abs_slot
    sta si_p1,y
    lda #0
    sta si_flags,y
    rts

!sro_book:
    // Books: p1=0 (spell range determined by book type)
    ldy sb_abs_slot
    lda #0
    sta si_p1,y
    sta si_flags,y
    rts

// store_pick_item — Pick a random item suitable for store zp_store_idx
// Output: A = item type ID
// Uses rejection sampling with fallback.
// Clobbers: A, X, Y
store_pick_item:
    lda #STORE_PICK_RETRIES
    sta sr_retry

!spi_loop:
    // Random item type [2, 60] (skip gold types 0-1)
    lda #59                     // 59 possible types (2..60)
    jsr rng_range               // 0-58
    clc
    adc #2                      // 2-60

    // Check if this item's category matches the store
    pha                         // Save item type on stack
    tax
    lda it_category,x           // A = item category
    jsr check_store_category    // Carry set = match (clobbers X)
    bcc !spi_reject+

    // Match — return item type
    pla
    rts

!spi_reject:
    pla                         // Discard saved item type
    dec sr_retry
    bne !spi_loop-

    // Fallback — use guaranteed item for this store
    ldx zp_store_idx
    lda store_fallback,x
    rts

// check_store_category — Test if item category matches store
// Input: A = ICAT value (0-15), zp_store_idx = store index
// Output: carry set = category sold here, carry clear = not
// Clobbers: A, X
check_store_category:
    // Category value determines which bit to test
    // Low byte handles bits 0-7, high byte handles bits 8-15
    cmp #8
    bcs !csc_hi+

    // Test low byte
    tax
    lda bit_mask_table,x
    ldx zp_store_idx
    and store_cat_mask_lo,x
    beq !csc_no+
    sec
    rts

!csc_hi:
    // Test high byte (category 8-15, bit index = category - 8)
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

// ============================================================
// Price calculation
// ============================================================

// calc_buy_price — Calculate buy price for item type
// Input: A = item type ID, sb_item_p1 = enchantment/charges
// Output: sb_price_lo/hi = price (16-bit)
// Formula: (base_price × chr_price_adj[CHR-3] / 100) + p1_bonus
// Clobbers: everything
calc_buy_price:
    sta sb_item_type            // Save for p1 bonus lookup
    tax
    lda it_cost_lo,x
    sta zp_temp0
    lda it_cost_hi,x
    sta zp_temp1

    // Get CHR price adjustment
    lda player_data + PL_CHR_CUR
    jsr stat_bonus_index        // X = 0-15
    lda chr_price_adj,x         // A = 100-130
    tax

    // 16-bit × 8-bit multiply
    jsr math_mul_16x8           // Result in mul_result_0/1/2

    // Divide by 100
    lda mul_result_0
    sta zp_math_a
    lda mul_result_1
    sta zp_math_b
    ldx #100
    jsr math_div_16x8           // Quotient in zp_math_a/b

    // Ensure minimum price of 1
    lda zp_math_a
    ora zp_math_b
    bne !cbp_ok+
    lda #1
    sta zp_math_a
!cbp_ok:
    lda zp_math_a
    sta sb_price_lo
    lda zp_math_b
    sta sb_price_hi

    // Add enchantment/charges bonus (RP14-3)
    jmp price_add_p1_bonus      // Tail call

// calc_sell_price — Calculate sell price for item type
// Input: A = item type ID, sb_item_p1 = enchantment/charges
// Output: sb_price_lo/hi = price (16-bit)
// Formula: (base_price × chr_sell_adj[CHR-3] / 100) + p1_bonus
// Clobbers: everything
calc_sell_price:
    sta sb_item_type            // Save for p1 bonus lookup
    tax
    lda it_cost_lo,x
    sta zp_temp0
    lda it_cost_hi,x
    sta zp_temp1

    // Get CHR sell adjustment
    lda player_data + PL_CHR_CUR
    jsr stat_bonus_index        // X = 0-15
    lda chr_sell_adj,x          // A = 25-50
    tax

    // 16-bit × 8-bit multiply
    jsr math_mul_16x8           // Result in mul_result_0/1/2

    // Divide by 100
    lda mul_result_0
    sta zp_math_a
    lda mul_result_1
    sta zp_math_b
    ldx #100
    jsr math_div_16x8           // Quotient in zp_math_a/b

    // Sell price can be 0 for cheap items — that's valid
    lda zp_math_a
    sta sb_price_lo
    lda zp_math_b
    sta sb_price_hi

    // Add enchantment/charges bonus (RP14-3)
    jmp price_add_p1_bonus      // Tail call

// calc_buy_min_price — Minimum acceptable buy price (no CHR markup)
// Input: A = item type ID, sb_item_p1 = enchantment/charges
// Output: sb_price_lo/hi = base_cost + p1_bonus
// Clobbers: everything
calc_buy_min_price:
    sta sb_item_type
    tax
    lda it_cost_lo,x
    sta sb_price_lo
    lda it_cost_hi,x
    sta sb_price_hi
    jmp price_add_p1_bonus      // Tail call

// price_add_p1_bonus — Add enchantment/charges bonus to price (RP14-3)
// Input: sb_price_lo/hi = base adjusted price, sb_item_p1 = p1,
//        sb_item_type = item type ID
// Output: sb_price_lo/hi updated with bonus
// Equipment (weapon/armor/shield/helm/gloves/boots/cloak): +100 GP per p1
// Wand/Staff: +10 GP per charge (p1)
// Other: no bonus
// Clobbers: A, X
price_add_p1_bonus:
    lda sb_item_p1
    beq !pap_done+              // p1=0, no bonus

    // Look up category
    ldx sb_item_type
    lda it_category,x

    // Check equipment categories
    cmp #ICAT_WEAPON
    beq !pap_equip+
    cmp #ICAT_ARMOR
    beq !pap_equip+
    cmp #ICAT_SHIELD
    beq !pap_equip+
    cmp #ICAT_HELM
    beq !pap_equip+
    cmp #ICAT_GLOVES
    beq !pap_equip+
    cmp #ICAT_BOOTS
    beq !pap_equip+

    // Check wand/staff
    cmp #ICAT_WAND
    beq !pap_charges+
    cmp #ICAT_STAFF
    beq !pap_charges+

    // Other categories: no bonus
!pap_done:
    rts

!pap_equip:
    // Add p1 × 100 to price
    lda sb_item_p1
    ldx #100
    jsr math_multiply           // A = lo, zp_math_b = hi
    clc
    adc sb_price_lo
    sta sb_price_lo
    lda zp_math_b
    adc sb_price_hi
    sta sb_price_hi
    rts

!pap_charges:
    // Add p1 × 10 to price (max 8×10 = 80, fits in byte)
    lda sb_item_p1
    asl                         // ×2
    asl                         // ×4
    clc
    adc sb_item_p1              // ×5
    asl                         // ×10
    clc
    adc sb_price_lo
    sta sb_price_lo
    lda #0
    adc sb_price_hi
    sta sb_price_hi
    rts

// ============================================================
// Gold operations
// ============================================================

// gold_check_afford — Check if player can afford price
// Input: sb_price_lo/hi = price (16-bit)
// Output: carry set = can afford, carry clear = cannot
// Clobbers: A
gold_check_afford:
    // If PL_GOLD_2 > 0, player has >65535 gold, always affordable
    lda player_data + PL_GOLD_2
    bne !gca_yes+

    // Compare PL_GOLD_1:PL_GOLD_0 >= price_hi:price_lo
    lda player_data + PL_GOLD_1
    cmp sb_price_hi
    bcc !gca_no+                // Gold hi < price hi
    bne !gca_yes+               // Gold hi > price hi
    // Hi bytes equal — compare lo
    lda player_data + PL_GOLD_0
    cmp sb_price_lo
    bcc !gca_no+                // Gold lo < price lo
!gca_yes:
    sec
    rts
!gca_no:
    clc
    rts

// gold_subtract_price — Subtract price from player gold (24-bit)
// Input: sb_price_lo/hi = price
// Clobbers: A
gold_subtract_price:
    lda player_data + PL_GOLD_0
    sec
    sbc sb_price_lo
    sta player_data + PL_GOLD_0
    lda player_data + PL_GOLD_1
    sbc sb_price_hi
    sta player_data + PL_GOLD_1
    lda player_data + PL_GOLD_2
    sbc #0
    sta player_data + PL_GOLD_2
    rts

// gold_add_price — Add price to player gold (24-bit)
// Input: sb_price_lo/hi = price
// Clobbers: A
gold_add_price:
    lda player_data + PL_GOLD_0
    clc
    adc sb_price_lo
    sta player_data + PL_GOLD_0
    lda player_data + PL_GOLD_1
    adc sb_price_hi
    sta player_data + PL_GOLD_1
    lda player_data + PL_GOLD_2
    adc #0
    sta player_data + PL_GOLD_2
    rts

// store_find_empty_slot — Find first empty slot in current store
// Input: zp_store_idx = store index
// Output: carry set + X = absolute slot index, carry clear = full
// Clobbers: A, X
store_find_empty_slot:
    ldx zp_store_idx
    lda store_base_idx,x
    tax                         // X = base slot
    lda #0
    sta sd_save_x               // Counter 0-11
!sfes_loop:
    lda sd_save_x
    cmp #STORE_MAX_ITEMS
    bcs !sfes_full+
    lda si_item_id,x
    cmp #FI_EMPTY
    beq !sfes_found+
    inx
    inc sd_save_x
    jmp !sfes_loop-
!sfes_found:
    sec
    rts
!sfes_full:
    clc
    rts
