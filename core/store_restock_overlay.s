#importonce
// store_restock_overlay.s — Store initialization/restocking.
//
// Transition-only code. It is safe in a non-town overlay because callers enter
// from resident trampolines and return to resident code, not to an active
// TownOverlay frame.

#import "store_meta_macros.s"

// Fallback items per store (used when rejection sampling fails)
store_fallback:
    .byte 15, 7, 2, 20, 17, 23, 2, 15  // food, leather, dagger, scroll, CLW potion, ring, dagger(BM), food(Home)

srr_abs_slot:  .byte 0
srr_save_x:    .byte 0
srr_retry:     .byte 0
srr_store_idx: .byte 0
srr_count:     .byte 0
srr_tmp0:      .byte 0

// store_init_all — Clear all store slots and restock
// Called once at game start.
// Clobbers: everything
store_init_all:
    ldx #STORE_TOTAL_SLOTS - 1
    lda #FI_EMPTY
!sia_clr:
    :AuxWriteX(si_item_id)
    dex
    bpl !sia_clr-

    ldx #STORE_TOTAL_SLOTS - 1
    lda #0
!sia_clr2:
#if APPLE2
    jsr sia2_clear_slot
    dex
    bpl !sia_clr2-
#else
    :AuxWriteX(si_qty)
    :AuxWriteX(si_p1)
    :AuxWriteX(si_to_hit)
    :AuxWriteX(si_to_dam)
    :AuxWriteX(si_to_ac)
    :AuxWriteX(si_meta)
    dex
    bpl !sia_clr2-
#endif

    jmp store_restock_all

#if APPLE2
// sia2_clear_slot — Compact aux clear of one store slot's meta tables.
// The per-table AuxWrite macro costs ~19 bytes inline; six of them per slot
// overflowed the ITEMS window. The six si_* arrays are contiguous 96-byte
// blocks, so one pointer walks them all.
// In: X = slot (0..STORE_TOTAL_SLOTS-1). Clobbers: A, Y, zp_ptr1.
sia2_clear_slot:
    txa
    tay
    lda #<si_qty
    sta zp_ptr1
    lda #>si_qty
    sta zp_ptr1_hi
!scs_loop:
    lda #0
    jsr mmu_safe_map_write_ptr1     // preserves A
    lda zp_ptr1
    clc
    adc #STORE_TOTAL_SLOTS
    sta zp_ptr1
    lda zp_ptr1_hi
    adc #0
    sta zp_ptr1_hi
    cmp #>sia2_end
    bne !scs_loop-
    rts
.label sia2_end = si_meta + STORE_TOTAL_SLOTS
#endif

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

// store_restock_one — Restock empty slots in store zp_store_idx
// Variable probability: 75% if <6 items, 50% if 6-10, 25% if >10.
// Clobbers: everything
store_restock_one:
    ldx zp_store_idx
    lda store_base_idx,x
    sta srr_abs_slot
    lda #0
    sta srr_count

    ldx #0
!sro_loop:
    cpx #STORE_MAX_ITEMS
    bcs !sro_done+
    stx srr_save_x

    ldy srr_abs_slot
    :AuxReadY(si_item_id)
    cmp #FI_EMPTY
    bne !sro_cnt_inc+

    jsr rng_byte
    ldy srr_count
    cmp sro_prob_tbl,y
    bcc !sro_next+

    jsr store_pick_item
    ldy srr_abs_slot
    :AuxWriteY(si_item_id)
    lda #1
    :AuxWriteY(si_qty)
    :AuxReadY(si_item_id)
    tax
    lda it_category,x
    jsr sro_set_p1

!sro_cnt_inc:
    inc srr_count

!sro_next:
    ldx srr_save_x
    inc srr_abs_slot
    inx
    jmp !sro_loop-

!sro_done:
    rts

// Skip threshold table: rng < value -> don't stock
sro_prob_tbl:
    .byte 64, 64, 64, 64, 64, 64
    .byte 128, 128, 128, 128, 128
    .byte 192, 192

// sro_set_p1 — Set p1 and flags for newly stocked item
// Input: A = category, srr_abs_slot = target slot
// Clobbers: A, X, Y
sro_set_p1:
    cmp #ICAT_WEAPON
    bcc !sro_default+
    cmp #ICAT_BOOTS + 1
    bcc !sro_enchant+
    cmp #ICAT_BOOK
#if APPLE2
    bne !sro_not_book+
    jmp !sro_book+
!sro_not_book:
#else
    beq !sro_book+
#endif
    cmp #ICAT_RING
#if APPLE2
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

    jmp !sro_default+

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
    lda #3
    jsr rng_range
    sta srr_tmp0
    lda #0
    ldy srr_abs_slot
    :AuxWriteY(si_p1)
    :AuxWriteY(si_to_hit)
    :AuxWriteY(si_to_dam)
    :AuxWriteY(si_to_ac)
    :AuxReadY(si_item_id)
    tax
    lda it_category,x
    cmp #ICAT_WEAPON
    bne !sro_enchant_armor+
    lda srr_tmp0
    :AuxWriteY(si_to_hit)
    lda srr_tmp0
    :AuxWriteY(si_to_dam)
    jmp sro_store_identified
!sro_enchant_armor:
    lda srr_tmp0
    :AuxWriteY(si_to_ac)
    jmp sro_store_identified

!sro_book:
    lda #0
    jmp sro_store_p1

!sro_ring:
    lda #3
    jsr rng_range
    sta srr_tmp0
    ldy srr_abs_slot
    lda #0
    :AuxWriteY(si_p1)
    :AuxWriteY(si_to_hit)
    :AuxWriteY(si_to_dam)
    :AuxWriteY(si_to_ac)
    :AuxReadY(si_item_id)
    cmp #23
    beq !sro_ring_protection+
    cmp #24
    beq !sro_ring_strength+
    jmp sro_store_identified
!sro_ring_protection:
    lda srr_tmp0
    :AuxWriteY(si_to_ac)
    jmp sro_store_identified
!sro_ring_strength:
    lda srr_tmp0
    :AuxWriteY(si_p1)
    jmp sro_store_identified

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
sro_store_identified:
    :StoreStoreMetaY(IF_IDENTIFIED, 0)
    rts

// store_pick_item — Pick a random item suitable for store zp_store_idx
// Output: A = item type ID
// Clobbers: A, X, Y
store_pick_item:
    lda #STORE_PICK_RETRIES
    sta srr_retry

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
    dec srr_retry
    bne !spi_loop-

    ldx zp_store_idx
    lda store_fallback,x
    rts
