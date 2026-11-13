#importonce
// cache_layout.s — Shared boot/runtime Sideways RAM cache layout (Banks 5-7).
// Authority: docs/BBCMASTER_MEMORY_CONTRACT.md.
//
// Bank 5 ($8000-$BFFF):
//   $8000-$B30B  Live 198x66 Map (13,068 B)
//   $B400-$BFFF  Cached OVL.MODAL (12 pages = 3,072 B)
//
// Bank 6 ($8000-$BFFF):
//   $8000-$94FF  BeebAuxData (21 pages = 5,376 B, virtual $6000-$74FF)
//   $9500-$B9FF  The monster catalog: fields, then Huffman names (37 pages)
//   $BA00-$BFFF  Cached OVL.UI (6 pages = 1,536 B)
//
// The monster catalog (2026-11-05, docs/MONSTER_CATALOG_DESIGN.md) took
// OVL.TOWN's pages: TOWN loads from disk (the maintainer: the town overlay
// only), MODAL moved to Bank 5's tail and UI to Bank 6's, and the aux-data
// reservation shrank from 23 to 21 pages.
//
// Bank 7 ($8000-$BFFF):
//   $8000-$94FF  Cached OVL.SPELL (21 pages = 5,376 B)
//   $9500-$A9FF  Cached OVL.ITEMS (21 pages = 5,376 B)
//   $AA00-$BEFF  Cached OVL.GEN (21 pages = 5,376 B; item_spawn_level moved in)

.const BEEB_CACHE_MODAL_BANK  = $05
.const BEEB_CACHE_MODAL_ADDR  = $b400
.const BEEB_CACHE_MODAL_PAGES = 12

.const BEEB_CACHE_AUX_BANK   = $06
.const BEEB_CACHE_AUX_ADDR   = $8000
.const BEEB_CACHE_AUX_PAGES  = 21

.const BEEB_CATALOG_BANK     = $06
.const BEEB_CATALOG_ADDR     = $9500
.const BEEB_CATALOG_PAGES    = 37

.const BEEB_CACHE_UI_BANK    = $06
.const BEEB_CACHE_UI_ADDR    = $ba00
.const BEEB_CACHE_UI_PAGES   = 6


.const BEEB_CACHE_SPELL_BANK  = $07
.const BEEB_CACHE_SPELL_ADDR  = $8000
.const BEEB_CACHE_SPELL_PAGES = 21

.const BEEB_CACHE_ITEMS_BANK  = $07
.const BEEB_CACHE_ITEMS_ADDR  = $9500
.const BEEB_CACHE_ITEMS_PAGES = 22   // Bank 7's free last page (resistance armour, 2026-11-11)

.const BEEB_CACHE_GEN_BANK   = $07
.const BEEB_CACHE_GEN_ADDR   = $ab00
.const BEEB_CACHE_GEN_PAGES  = 21

.const BEEB_SWR_BANK_UI      = BEEB_CACHE_UI_BANK
.const BEEB_SWR_ADDR_UI      = BEEB_CACHE_UI_ADDR
.const BEEB_SWR_PAGES_UI     = BEEB_CACHE_UI_PAGES

.const BEEB_SWR_BANK_MODAL   = BEEB_CACHE_MODAL_BANK
.const BEEB_SWR_ADDR_MODAL   = BEEB_CACHE_MODAL_ADDR
.const BEEB_SWR_PAGES_MODAL  = BEEB_CACHE_MODAL_PAGES


.const BEEB_SWR_BANK_SPELL   = BEEB_CACHE_SPELL_BANK
.const BEEB_SWR_ADDR_SPELL   = BEEB_CACHE_SPELL_ADDR
.const BEEB_SWR_PAGES_SPELL  = BEEB_CACHE_SPELL_PAGES

.const BEEB_SWR_BANK_ITEMS   = BEEB_CACHE_ITEMS_BANK
.const BEEB_SWR_ADDR_ITEMS   = BEEB_CACHE_ITEMS_ADDR
.const BEEB_SWR_PAGES_ITEMS  = BEEB_CACHE_ITEMS_PAGES

.const BEEB_SWR_BANK_GEN     = BEEB_CACHE_GEN_BANK
.const BEEB_SWR_ADDR_GEN     = BEEB_CACHE_GEN_ADDR
.const BEEB_SWR_PAGES_GEN    = BEEB_CACHE_GEN_PAGES

.assert "Bank 5 MODAL cache starts after MAP_END ($B30B)", BEEB_CACHE_MODAL_ADDR > $b30b, true
.assert "Bank 5 MODAL cache fits below $C000", BEEB_CACHE_MODAL_ADDR + BEEB_CACHE_MODAL_PAGES * $100 <= $c000, true
.assert "Bank 6 slots are contiguous and fit below $C000", BEEB_CACHE_AUX_ADDR + BEEB_CACHE_AUX_PAGES * $100 == BEEB_CATALOG_ADDR && BEEB_CATALOG_ADDR + BEEB_CATALOG_PAGES * $100 == BEEB_CACHE_UI_ADDR && BEEB_CACHE_UI_ADDR + BEEB_CACHE_UI_PAGES * $100 <= $c000, true
.assert "The catalog sits above ANDY's span (the Huffman reads select Bank 6 from $9000)", BEEB_CATALOG_ADDR >= $9000, true
.assert "Bank 7 slots are contiguous and fit below $C000", BEEB_CACHE_SPELL_ADDR + BEEB_CACHE_SPELL_PAGES * $100 == BEEB_CACHE_ITEMS_ADDR && BEEB_CACHE_ITEMS_ADDR + BEEB_CACHE_ITEMS_PAGES * $100 == BEEB_CACHE_GEN_ADDR && BEEB_CACHE_GEN_ADDR + BEEB_CACHE_GEN_PAGES * $100 <= $c000, true
