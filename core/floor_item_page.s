#importonce
// floor_item_page.s — The floor item's page around a renderer's item lookup.
//
// Module ownership:
//   owner: Resident with core/item_tables.s (imported there); the render
//     tests import it alone beside their stubs.
//   lifetime: one renderer floor-item lookup (glyph, then colour).
//   callers: every platform dungeon renderer (render_viewport and
//     render_single_tile paths) before item_get_display_char /
//     item_get_floor_color, which read item_cur_page.

// floor_item_page_x — A = fi_item_id,x with item_cur_page set from the floor
// item's page (fi_meta_hi,x); the caller's page is kept for
// floor_item_page_restore. The renderers looked floor items up under whatever
// page the last item code left: chests (Page 0) drew as '@' and ')' and a
// Dwarf Skeleton (Page 1) as floor while chest loot came and went (C64
// cartridge, maintainer, 2026-11-17; latent since the paged catalog).
// Input: X = floor slot. Preserves: X, Y
floor_item_page_x:
    lda item_cur_page
    sta fip_saved_page
    lda fi_meta_hi,x
    and #ITEM_PAGE_BIT
    sta item_cur_page
    lda fi_item_id,x
    rts

// floor_item_page_restore — Put back the page floor_item_page_x replaced.
// Preserves: A, X, Y
floor_item_page_restore:
    pha
    lda fip_saved_page
    sta item_cur_page
    pla
    rts
fip_saved_page: .byte 0
