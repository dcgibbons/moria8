#importonce
// cache_layout.s — Shared boot/runtime aux-cache slot addresses.
// Slots are page-aligned because boot.s copies ceil(payload/256) pages.

.const A2_AUX_CACHE_TOWN    = $5700
.const A2_AUX_CACHE_UI      = $6c00
.const A2_AUX_CACHE_SPELL   = $7900
.const A2_AUX_CACHE_MODAL   = $8d00
.const A2_AUX_CACHE_GEN     = $9900
.const A2_AUX_CACHE_ITEMS   = $aa00
.const A2_AUX_CACHE_END     = $c000       // first byte after items payload slot
.const A2_AUX_CACHE_LIMIT   = $c000       // aux RAM below ProDOS global page

.assert "A2 cache slots are page aligned", <A2_AUX_CACHE_TOWN | <A2_AUX_CACHE_UI | <A2_AUX_CACHE_SPELL | <A2_AUX_CACHE_MODAL | <A2_AUX_CACHE_GEN | <A2_AUX_CACHE_ITEMS | <A2_AUX_CACHE_END, 0
.assert "A2 cache slots are strictly ordered", A2_AUX_CACHE_TOWN < A2_AUX_CACHE_UI && A2_AUX_CACHE_UI < A2_AUX_CACHE_SPELL && A2_AUX_CACHE_SPELL < A2_AUX_CACHE_MODAL && A2_AUX_CACHE_MODAL < A2_AUX_CACHE_GEN && A2_AUX_CACHE_GEN < A2_AUX_CACHE_ITEMS && A2_AUX_CACHE_ITEMS < A2_AUX_CACHE_END, true
.assert "A2 cache payload span stays below ProDOS global page", A2_AUX_CACHE_END <= A2_AUX_CACHE_LIMIT, true
