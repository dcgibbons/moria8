#importonce
// item_refresh_known_cold.s — Fixed-description / fixed-flavour id_known initializer
//
// Module ownership:
//   owner: StorageOverlay / C128ResidentPersist when ITEM_REFRESH_KNOWN_EXTERNAL
//     is defined (co-located with platforms/shared/save.s); Default / ResidentItems
//     otherwise (imported by core/item_identification.s).
//   lifetime: once per New Game (item_init_identification) and once per Load Game
//     (save.s post-load refresh).
//   callers: platforms/shared/save.s (tail-jumps to item_refresh_fixed_known) and
//     item_init_identification (via tramp_item_refresh_fixed_known when external
//     and !ITEM_REFRESH_KNOWN_CO_LOCATED).

// ============================================================
// item_refresh_fixed_known — Ensure all fixed-description & fixed-flavour
// items across Pages 0 and 1 are marked known in id_known_bits.
// Preserves: item_cur_page. Clobbers: A, X, Y.
// ============================================================
item_refresh_fixed_known:
    lda item_cur_page
    pha
    lda #0
    sta item_cur_page
    ldy #ITEM_PAGE_SIZE
    jsr !irfk_scan_page+
    lda #ITEM_PAGE_BIT
    sta item_cur_page
    ldy #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE)
    jsr !irfk_scan_page+
    pla
    sta item_cur_page
    rts

!irfk_scan_page:
    sty irfk_limit
    ldx #0
!irfk_loop:
    txa
    jsr item_get_category_a
    cmp #ICAT_POTION
    bcc !irfk_set+
    cmp #ICAT_AMULET
    bcs !irfk_set+                  // AMULET, CHEST, CLOAK, JUNK, and fixed classes
    cmp #ICAT_BOOK
    beq !irfk_set+
    txa
    jsr item_get_unknown_idx_a
    cmp #$ff                        // Fixed-flavour items (#271/#273/#274)
    bne !irfk_next+
!irfk_set:
    jsr id_known_set
!irfk_next:
    inx
    cpx irfk_limit
    bcc !irfk_loop-
    rts

irfk_limit: .byte 0
