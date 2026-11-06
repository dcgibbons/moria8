#importonce
// monster_catalog_a2.s — Apple IIe monster catalog placement
// (docs/MONSTER_CATALOG_DESIGN.md, core/monster_catalog.s;
// docs/APPLE2_MEMORY_POLICY.md and cache_layout.s own the aux spans).
//
// The fields (A2.CATALOG) load into aux RAM at A2_AUX_CATALOG with the boot
// pack; the Huffman-coded names ride after the corpus in A2.HUFFDATA
// (main.s), decoded through the corpus's aux reads. The level index is
// resident. The fetch reads the fields one byte at a time through the
// zero-page aux-read thunk and writes each name into the main-RAM name pool,
// so no banking state needs saving: the catalog maps nothing.

.segment A2Catalog
#import "../shared/catalog/catalog_fields.s"
.segment Default
#import "../shared/catalog/catalog_index.s"

.assert "Catalog fields start their aux span", catalog_fields, A2_AUX_CATALOG
.assert "Catalog fields fit below the UI cache slot", catalog_fields_end <= A2_AUX_CACHE_UI, true

.const CATALOG_NAME_POOL_BASE = PLATFORM_TIER_NAME_POOL_BASE
.const CATALOG_NAME_POOL_END  = PLATFORM_TIER_NAME_POOL_END

.macro CatalogWinBegin() {
}
.macro CatalogWinEnd() {
}
.macro CatalogMap() {
}
.macro CatalogUnmap() {
}
.macro CatalogFieldRead() {
    jsr mmu_safe_map_read_ptr0      // A = aux (zp_ptr0),y; X and Y kept
}
.macro CatalogPoolWrite() {
    sta (zp_ptr1),y
}
