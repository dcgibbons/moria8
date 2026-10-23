#importonce
// store_restock_overlay.s — Store initialization/restocking.
//
// Transition-only code. It is safe in a non-town overlay because callers enter
// from resident trampolines and return to resident code, not to an active
// TownOverlay frame.

#import "store_meta_macros.s"

// General Store stock choices: VMS store_choice (values.inc), 15 of 26 food.
// Moria8 has no Hard Biscuit, Beef Jerky, Ale or Wine (Slime Mold stands in)
// and no Cloak (dropped), so the table has 25 entries.
sro_general_choice:
    .byte 15, 15, 15, 15, 15, 15, 15, 15    // Ration of Food x8
    .byte 16, 16, 16, 16, 16, 16, 16        // Slime Mold x7 (biscuit 3, jerky 2, ale, wine)
    .byte 61, 61, 13, 13, 13, 14            // Flask of Oil x2, Wooden Torch x3, Brass Lantern
    .byte 135, 135, 62, 63                  // Iron Spike x2, Shovel, Pick
.const SRO_GENERAL_CHOICES = * - sro_general_choice
.assert "General Store choices", SRO_GENERAL_CHOICES, 25

// Fallback items per store (used when rejection sampling fails; the General
// Store's entry is unused since it picks from sro_general_choice)
store_fallback:
    .byte 15, 7, 2, 20, 17, 23, 2, 15  // food, leather, dagger, scroll, CLW potion, ring, dagger(BM), food(Home)

srr_abs_slot:  .byte 0
srr_save_x:    .byte 0
srr_retry:     .byte 0
srr_store_idx: .byte 0
srr_count:     .byte 0
srr_tmp0:      .byte 0

// store_init_all — Empty all store slots and restock
// Called once at game start. Only item ids are cleared: every path that
// fills a slot (stocking, selling, home deposit) writes all of its fields.
// Clobbers: everything
store_init_all:
    ldx #STORE_TOTAL_SLOTS - 1
    lda #FI_EMPTY
!sia_clr:
    :AuxWriteX(si_item_id)
    dex
    bpl !sia_clr-
    // fall through: stock the empty stores

// store_restock_all — Restock all stores + reset kicked flags
// Skips home (STORE_HOME) — player items persist, no restock.
// Clobbers: everything
store_restock_all:
    ldx #7
    lda #0
!sra_clr_kick:
    sta hg_kicked,x
    dex
    bpl !sra_clr_kick-

    sta srr_store_idx
!sra_loop:
    lda srr_store_idx
    cmp #STORE_COUNT
    bcs !sra_done+
    cmp #STORE_HOME
    beq !sra_skip+
    sta zp_store_idx
    jsr store_restock_one
!sra_skip:
    inc srr_store_idx
    jmp !sra_loop-
!sra_done:
    rts

// store_restock_one — VMS store_maint (store1.inc) for store zp_store_idx:
//   more than STORE_MAX_KEEP items: sell off (count - STORE_MAX_KEEP + 2)
//   fewer than STORE_MIN_KEEP items: stock (STORE_MIN_KEEP - count + 2)
//   otherwise: sell off 1+randint(STORE_TURN_AROUND), stock as many again
// Slots are chosen uniformly among the occupied (sell) or empty (stock) ones.
// Clobbers: everything
store_restock_one:
    jsr sro_count
    cmp #STORE_MAX_KEEP + 1
    bcc !sro_not_over+
    sbc #STORE_MAX_KEEP - 2         // carry set: count - MAX + 2
    bne sro_sell_off                // always taken
!sro_not_over:
    cmp #STORE_MIN_KEEP
    bcs !sro_turnover+
    eor #$ff                        // carry clear: MIN + 2 - count
    adc #STORE_MIN_KEEP + 3
    bne sro_stock                   // always taken
!sro_turnover:
    jsr sro_turn_around
    jsr sro_sell_off
    jsr sro_turn_around
    // fall through: stock 1+randint(STORE_TURN_AROUND)

// sro_stock — Stock A new items into empty slots (fewer if the store fills).
sro_stock:
    sta srr_retry
!sst_loop:
    dec srr_retry
    bmi !sst_done+
    jsr sro_count
    ldy srr_save_x                  // first empty slot
    bmi !sst_done+                  // none: the store is full
    sty srr_abs_slot
    jsr store_pick_item
    tax
    ldy srr_abs_slot
    :AuxWriteY(si_item_id)
    lda #1
    :AuxWriteY(si_qty)
    lda it_category,x
    jsr sro_set_p1
    jmp !sst_loop-
!sst_done:
    rts

// sro_sell_off — Empty A random occupied slots (fewer if the store runs out):
// VMS store_destroy(randint(store_ctr)). Only the item id is cleared:
// stocking and selling rewrite every field.
sro_sell_off:
    sta srr_retry
!sso_loop:
    dec srr_retry
    bmi !sst_done-
    jsr sro_count
    beq !sst_done-
!sso_retry:                         // uniform over occupied slots by rejection
    lda #STORE_MAX_ITEMS
    jsr rng_range
    clc
    adc srr_abs_slot
    tay
    :AuxReadY(si_item_id)
    cmp #FI_EMPTY
    beq !sso_retry-
    lda #FI_EMPTY
    :AuxWriteY(si_item_id)
    jmp !sso_loop-

// sro_turn_around — A = 1 + randint(STORE_TURN_AROUND) (VMS randint is 1..n)
sro_turn_around:
    lda #STORE_TURN_AROUND
    jsr rng_range
    clc
    adc #2
    rts

// sro_count — A = occupied slots in store zp_store_idx (Z set when none);
// srr_abs_slot = the store's first slot; srr_save_x = its first empty slot,
// or $FF when full.
sro_count:
    ldx zp_store_idx
    lda store_base_idx,x
    sta srr_abs_slot
    tay
    lda #$ff
    sta srr_save_x
    lda #0
    sta srr_count
    ldx #STORE_MAX_ITEMS
!src_loop:
    :AuxReadY(si_item_id)
    cmp #FI_EMPTY
    bne !src_full+
    lda srr_save_x
    bpl !src_next+
    sty srr_save_x
    bmi !src_next+                  // always taken (srr_save_x was $FF)
!src_full:
    inc srr_count
!src_next:
    iny
    dex
    bne !src_loop-
    lda srr_count
    rts

// sro_set_p1 — Set p1 and flags for newly stocked item
// Input: A = category, srr_abs_slot = target slot
// Clobbers: A, X, Y
sro_set_p1:
    cmp #ICAT_WEAPON
    bcc !sro_default+
    cmp #ICAT_BOOTS + 1
    bcc !sro_enchant+
    cmp #ICAT_BOOK
    beq !sro_default+
    cmp #ICAT_RING
#if HAL_PLATFORM_AUX_PERSISTENT_DATA
    bne !sro_not_ring+
    jmp !sro_ring+
!sro_not_ring:
#else
    beq !sro_ring+
#endif
    cmp #ICAT_LIGHT
    bne !sro_not_light+
    jmp !sro_light+
!sro_not_light:
    cmp #ICAT_WAND
    bcc !sro_default+
    cmp #ICAT_STAFF + 1
    bcc !sro_charges+
    cmp #ICAT_AMULET
#if HAL_PLATFORM_AUX_PERSISTENT_DATA
    bne !sro_default+
    jmp !sro_ring+
#else
    beq !sro_ring+
    jmp !sro_default+
#endif

!sro_default:
    lda #0
    jmp sro_store_p1

!sro_charges:
    lda #6
    jsr rng_range
    clc
    adc #3
    jmp sro_store_p1

!sro_enchant:
    sta srr_count                   // category (free: sro_count recounts)
    jsr sro_bonus_base
    lda srr_count
    cmp #ICAT_WEAPON
    bne !sro_enchant_armor+
    lda srr_tmp0
    :AuxWriteY(si_to_hit)
    lda srr_tmp0
    :AuxWriteY(si_to_dam)
    rts

!sro_ring:
    jsr sro_bonus_base
    :AuxReadY(si_item_id)
    cmp #23
    beq !sro_enchant_armor+         // Ring of Protection: AC bonus
    cmp #24
    beq !sro_ring_strength+
    sec
    sbc #ITEM_TYPE_AMULET_WISDOM
    cmp #2
    bcc !sro_ring_strength+
    rts
!sro_enchant_armor:
    lda srr_tmp0
    :AuxWriteY(si_to_ac)
    rts
!sro_ring_strength:
    lda srr_tmp0
    :AuxWriteY(si_p1)
    rts

// sro_bonus_base — srr_tmp0 = bonus 0..2; zero p1/to_hit/to_dam/to_ac and
// mark identified; Y = srr_abs_slot.
sro_bonus_base:
    lda #3
    jsr rng_range
    sta srr_tmp0
    lda #0
    jmp sro_store_p1

!sro_light:
    ldy srr_abs_slot
    :AuxReadY(si_item_id)
    cmp #13
    beq !sro_light_torch+
    lda #LANTERN_MAX_CHARGES
    jmp sro_store_p1
!sro_light_torch:
    lda #134

sro_store_p1:
    ldy srr_abs_slot
    :AuxWriteY(si_p1)
    lda #0
    :AuxWriteY(si_to_hit)
    :AuxWriteY(si_to_dam)
    :AuxWriteY(si_to_ac)
    :StoreStoreMetaY(IF_IDENTIFIED, 0)
    rts

// store_pick_item — Pick a random item suitable for store zp_store_idx
// Output: A = item type ID
// Clobbers: A, X, Y
store_pick_item:
    lda zp_store_idx
    bne !spi_category+
    lda #SRO_GENERAL_CHOICES        // General Store: VMS store_choice table
    jsr rng_range
    tax
    lda sro_general_choice,x
    rts
!spi_category:
    lda #STORE_PICK_RETRIES
    sta srr_count                   // free here: sro_count recounts each pass

!spi_loop:
    lda #ITEM_TYPE_COUNT - 2
    jsr rng_range
    clc
    adc #2

    pha
    tax
    lda it_category,x
    jsr check_store_category
    bcc !spi_reject+

    pla
    rts

!spi_reject:
    pla
    dec srr_count
    bne !spi_loop-

    ldx zp_store_idx
    lda store_fallback,x
    rts
