#importonce
// cache_layout.s — Shared boot/runtime aux-RAM layout above the map: aux
// data, the monster catalog's fields, and the overlay cache slots.
// Slots are page-aligned because boot.s copies ceil(payload/256) pages.
//
// The monster catalog (2026-11-05, docs/MONSTER_CATALOG_DESIGN.md): its
// fields take A2_AUX_CATALOG, its Huffman names ride after the corpus in the
// HUFF slot, and OVL.TOWN left the cache for the disk (the maintainer: the
// town overlay only; look/recall's MODAL stays cached). Aux data is capped
// at A2_AUX_DATA_LIMIT for them.

.const A2_AUX_DATA_BASE     = $3b0c       // after the 198x66 map
.const A2_AUX_DATA_LIMIT    = $5000       // first byte after aux data
.const A2_AUX_CATALOG       = $5000       // catalog_fields (5,859 B)
.const A2_AUX_CACHE_UI      = $6700
.const A2_AUX_CACHE_SPELL   = $6d00
.const A2_AUX_CACHE_MODAL   = $8100
.const A2_AUX_CACHE_HUFF    = $8d00       // Huffman corpus, then the catalog's names
.const A2_AUX_CACHE_ITEMS   = $aa00
.const A2_AUX_CACHE_END     = $c000       // first byte after items payload slot
.const A2_AUX_CACHE_LIMIT   = $c000       // aux RAM below ProDOS global page

.assert "A2 aux slots are page aligned", <A2_AUX_DATA_LIMIT | <A2_AUX_CATALOG | <A2_AUX_CACHE_UI | <A2_AUX_CACHE_SPELL | <A2_AUX_CACHE_MODAL | <A2_AUX_CACHE_HUFF | <A2_AUX_CACHE_ITEMS | <A2_AUX_CACHE_END, 0
.assert "A2 aux slots are strictly ordered", A2_AUX_DATA_BASE < A2_AUX_DATA_LIMIT && A2_AUX_DATA_LIMIT <= A2_AUX_CATALOG && A2_AUX_CATALOG < A2_AUX_CACHE_UI && A2_AUX_CACHE_UI < A2_AUX_CACHE_SPELL && A2_AUX_CACHE_SPELL < A2_AUX_CACHE_MODAL && A2_AUX_CACHE_MODAL < A2_AUX_CACHE_HUFF && A2_AUX_CACHE_HUFF < A2_AUX_CACHE_ITEMS && A2_AUX_CACHE_ITEMS < A2_AUX_CACHE_END, true
.assert "A2 cache payload span stays below ProDOS global page", A2_AUX_CACHE_END <= A2_AUX_CACHE_LIMIT, true
