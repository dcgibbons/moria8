#importonce
// store.s — Store restocking, price calculation, gold ops
//
// 8 town stores/buildings with persistent inventory (SoA layout, 12 slots each).
// Restocking on town re-entry. Buy/sell price adjusted by CHR stat.
//
// Inventory arrays and check_player_on_store_door live in store_data.s
// (main RAM) so they persist across $E000 overlay loads.

// Constants defined in store_data.s (imported in main RAM before overlay)

// Product builds keep store text in TownOverlay. Unit tests keep fixture text
// in store_data.s so tests can import store_data without overlay ownership.

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
sd_save_item_id: .byte 0   // Saved item type for prefix check (R14)
sb_item_p1:    .byte 0     // Item enchantment/charges for pricing (RP14-3)
sb_item_to_hit: .byte 0    // Split item stats for pricing
sb_item_to_dam: .byte 0
sb_item_to_ac:  .byte 0
sb_item_type:  .byte 0     // Item type saved for p1 bonus lookup
sb_item_ego:   .byte 0     // Ego byte for pricing (R14)

// Haggling state (R6.1)
hg_ask_lo:     .byte 0     // Shopkeeper's current price (16-bit)
hg_ask_hi:     .byte 0
hg_min_lo:     .byte 0     // Floor (buy) or ceiling (sell) price
hg_min_hi:     .byte 0
hg_last_lo:    .byte 0     // Player's last valid offer/ask
hg_last_hi:    .byte 0
hg_input_lo:   .byte 0     // Player's typed number (16-bit)
hg_input_hi:   .byte 0
hg_den_lo:     .byte 0     // Ratio denominator scratch
hg_den_hi:     .byte 0
hg_pct:        .byte 0     // Derived concession percentage (8-bit)
hg_round:      .byte 0     // Round counter (0-3)
hg_insults:    .byte 0     // Insult counter per visit
hg_tmp0:       .byte 0     // Temp for gap/step calculation
hg_tmp1:       .byte 0
hg_digit_cnt:  .byte 0     // Digit count for number input

// ============================================================
// Price calculation helpers
// ============================================================

// load_item_base_cost — Load item base cost to zp_temp0/1
// Input: A = item type ID
// Output: zp_temp0/1 = base cost, sb_item_type = item ID
// Clobbers: A, X
load_item_base_cost:
    sta sb_item_type
    tax
#if HAL_PLATFORM_ITEM_CATALOG_BANKED
    jsr item_load_cost_lo_x
#else
    lda it_cost_lo,x
#endif
    sta zp_temp0
#if C64_PRODUCT_OVERLAY_RUNTIME || C128_PRODUCT_OVERLAY_RUNTIME || PLUS4_PRODUCT_OVERLAY_RUNTIME
    lda #0
    sta zp_temp1
    txa
    ldy #IT_COST_HI_EXTRA_COUNT - 1
!libc_hi_loop:
    cmp it_cost_hi_extra_id,y
    beq !libc_hi_found+
    dey
    bpl !libc_hi_loop-
    rts
!libc_hi_found:
    lda it_cost_hi_extra_value,y
    sta zp_temp1
    rts
#else
#if HAL_PLATFORM_ITEM_CATALOG_BANKED
    jsr item_load_cost_hi_x
#else
    lda it_cost_hi,x
#endif
    sta zp_temp1
    rts
#endif

// apply_tool_ego_multiplier — Multiply base cost by ego factor for digging tools (R14)
// Input: zp_temp0/1 = base cost, sb_item_type and sb_item_ego set
// Output: zp_temp0/1 updated
// ego=0: ×1, ego=1: ×5, ego=2: ×15
// Clobbers: A, X
apply_tool_ego_multiplier:
    lda sb_item_ego
    beq !atem_done+             // ego=0, no change
    ldx sb_item_type
#if HAL_PLATFORM_ITEM_CATALOG_BANKED
    jsr item_load_category_x
#else
    lda it_category,x
#endif
    cmp #ICAT_DIGGING
    bne !atem_done+             // Not a digging tool
    // Multiply base cost by factor
    lda sb_item_ego
    cmp #2
    beq !atem_x15+
    // ego=1: multiply by 5
    ldx #5
    jmp !atem_mul+
!atem_x15:
    ldx #15
!atem_mul:
    jsr math_mul_16x8           // Result in mul_result_0/1
    lda mul_result_0
    sta zp_temp0
    lda mul_result_1
    sta zp_temp1
!atem_done:
    rts

// store_price_and_p1 — Store zp_math_a/b as price, add p1 bonus
// Input: zp_math_a/b = price value, sb_item_type/sb_item_p1 set
// Output: sb_price_lo/hi updated
// Clobbers: A, X
store_price_and_p1:
    lda zp_math_a
    sta sb_price_lo
    lda zp_math_b
    sta sb_price_hi
    jmp price_add_p1_bonus

// ============================================================
// Price calculation
// ============================================================

// ============================================================
// Black Market pricing
// ============================================================

// calc_store_buy_price — Dispatch: BM uses inflated price, others use CHR-adjusted
// Input: A = item type ID, sb_item_p1 = enchantment/charges
// Output: sb_price_lo/hi = price (16-bit)
// Clobbers: everything
calc_store_buy_price:
    ldx zp_store_idx
    cpx #STORE_BM
    beq calc_bm_buy_price
    jmp calc_buy_price          // Normal store — fall through

// calc_bm_buy_price — BM buy: base_cost × 3 + p1_bonus (no CHR adjustment)
// Input: A = item type ID, sb_item_p1 = enchantment/charges
// Output: sb_price_lo/hi = price (16-bit)
// Clobbers: everything
calc_bm_buy_price:
    jsr load_item_base_cost
    jsr apply_tool_ego_multiplier
    ldx #3
    jsr math_mul_16x8           // Result in mul_result_0/1/2
    lda mul_result_0
    sta sb_price_lo
    lda mul_result_1
    sta sb_price_hi
    // Ensure minimum price of 1
    ora sb_price_lo
    bne !cbm_ok+
    lda #1
    sta sb_price_lo
!cbm_ok:
    jmp price_add_p1_bonus      // Tail call

// calc_store_sell_price — Dispatch: BM uses low sell price, others use CHR-adjusted
// Input: A = item type ID, sb_item_p1 = enchantment/charges
// Output: sb_price_lo/hi = price (16-bit)
// Clobbers: everything
calc_store_sell_price:
    ldx zp_store_idx
    cpx #STORE_BM
    beq calc_bm_sell_price
    jmp calc_sell_price         // Normal store — fall through

// calc_bm_sell_price — BM sell: base_cost / 10 + p1_bonus (no CHR adjustment)
// Input: A = item type ID, sb_item_p1 = enchantment/charges
// Output: sb_price_lo/hi = price (16-bit)
// Clobbers: everything
calc_bm_sell_price:
    jsr load_item_base_cost
    jsr apply_tool_ego_multiplier
    lda zp_temp0
    sta zp_math_a
    lda zp_temp1
    sta zp_math_b
    ldx #10
    jsr math_div_16x8           // Quotient in zp_math_a/b
    jmp store_price_and_p1      // Store price + add p1 bonus

// calc_buy_price — Calculate buy price for item type
// Input: A = item type ID, sb_item_p1 = enchantment/charges
// Output: sb_price_lo/hi = price (16-bit)
// Formula: (base_price × chr_price_adj[CHR-3] / 100) + p1_bonus
// Clobbers: everything
calc_buy_price:
    jsr load_item_base_cost
    jsr apply_tool_ego_multiplier

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
    jmp store_price_and_p1      // Store price + add p1 bonus

// calc_sell_price — Calculate sell price for item type
// Input: A = item type ID, sb_item_p1 = enchantment/charges
// Output: sb_price_lo/hi = price (16-bit)
// Formula: (base_price × chr_sell_adj[CHR-3] / 100) + p1_bonus
// Clobbers: everything
calc_sell_price:
    jsr load_item_base_cost
    jsr apply_tool_ego_multiplier

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
    jmp store_price_and_p1      // Store price + add p1 bonus

// calc_buy_min_price — Minimum acceptable buy price (no CHR markup)
// Input: A = item type ID, sb_item_p1 = enchantment/charges
// Output: sb_price_lo/hi = base_cost + p1_bonus
// Clobbers: everything
calc_buy_min_price:
    jsr load_item_base_cost
    jsr apply_tool_ego_multiplier
    lda zp_temp0
    sta sb_price_lo
    lda zp_temp1
    sta sb_price_hi
    jmp price_add_p1_bonus      // Tail call

// price_add_p1_bonus — Add enchantment/charges bonus to price (RP14-3)
// Input: sb_price_lo/hi = base adjusted price, sb_item_p1 = p1,
//        sb_item_type = item type ID
// Output: sb_price_lo/hi updated with bonus
// Equipment: +100 GP per positive split stat
// Wand/Staff: +10 GP per charge (p1)
// Other: no bonus
// Clobbers: A, X
price_add_p1_bonus:
    // Look up category
    ldx sb_item_type
#if HAL_PLATFORM_ITEM_CATALOG_BANKED
    jsr item_load_category_x
#else
    lda it_category,x
#endif

    // Equipment range: WEAPON(2) through BOOTS(7)
    cmp #ICAT_WEAPON
    bcc !pap_check_ring+
    cmp #ICAT_BOOTS + 1
    bcc !pap_equip+

!pap_check_ring:
    cmp #ICAT_RING
    beq !pap_ring+

    // Wand(14)/Staff(15)
    cmp #ICAT_WAND
    bcc !pap_done+
    cmp #ICAT_STAFF + 1
    bcc !pap_charges+

    // Other categories: no bonus
!pap_done:
    rts

!pap_equip:
    lda sb_item_to_hit
    jsr price_add_signed_stat_100
    lda sb_item_to_dam
    jsr price_add_signed_stat_100
    lda sb_item_to_ac
    jsr price_add_signed_stat_100
    rts

!pap_ring:
    lda sb_item_to_ac
    jsr price_add_signed_stat_100
    lda sb_item_p1
    jsr price_add_signed_stat_100
    rts

!pap_charges:
    lda sb_item_p1
    beq !pap_done-
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

price_add_signed_stat_100:
    beq !passt_done+
    bmi !passt_done+
    ldx #100
    jsr math_multiply           // A = lo, zp_math_b = hi
    clc
    adc sb_price_lo
    sta sb_price_lo
    lda zp_math_b
    adc sb_price_hi
    sta sb_price_hi
!passt_done:
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

#if C64_PRODUCT_OVERLAY_RUNTIME || C128_PRODUCT_OVERLAY_RUNTIME || PLUS4_PRODUCT_OVERLAY_RUNTIME
// ============================================================
// Store name/owner strings (screen codes, null-terminated)
// ============================================================
// Keep these after store code/scratch. store_restock_overlay.s shares store.s
// scratch label addresses while running from ItemActionsOverlay.
sn_general:  .text "General Store"  ; .byte 0
sn_armory:   .text "Armory"         ; .byte 0
sn_weapon:   .text "Weaponsmith"    ; .byte 0
sn_temple:   .text "Temple"         ; .byte 0
sn_alchemy:  .text "Alchemy Shop"   ; .byte 0
sn_magic:    .text "Magic Shop"     ; .byte 0
sn_bmarket:  .text "Black Market"   ; .byte 0
sn_home:     .text "Home"            ; .byte 0

so_0: .text "BILBO THE FRIENDLY"    ; .byte 0
so_1: .text "GORN THE ARMORER"      ; .byte 0
so_2: .text "BRYN THE FORGEMASTER"  ; .byte 0
so_3: .text "GARATH THE HEALER"     ; .byte 0
so_4: .text "ELARA THE ALCHEMIST"   ; .byte 0
so_5: .text "ZOLAN THE ENCHANTER"   ; .byte 0
so_6: .text "THE FENCE"             ; .byte 0
so_7: .byte 0                        // Home has no owner
#endif
