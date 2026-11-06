#importonce
// monster_catalog_beeb.s — BBC Master 128 monster catalog placement
// (docs/MONSTER_CATALOG_DESIGN.md, core/monster_catalog.s;
// docs/BBCMASTER_MEMORY_CONTRACT.md and cache_layout.s own the banks).
//
// The fields and the Huffman-coded names (BEEB.CATALOG) load into sideways
// Bank 6 at BEEB_CATALOG_ADDR with the boot pack. The Huffman reads
// (memory_bank.s mmu_safe_huff_read_ptr0/1) select Bank 6 for a pointer at
// $9000 and up and ANDY below it, so the names decode like the corpus and
// the fields read through the same helper. The level index is resident; the
// names go to the old tier name pool in Bank 4, written directly.

.segment BeebCatalog
#import "../shared/catalog/catalog_fields.s"
#import "../shared/catalog/catalog_names.s"
beeb_catalog_end:
.segment Default
#import "../shared/catalog/catalog_index.s"

.assert "Catalog starts its Bank 6 span", catalog_fields, BEEB_CATALOG_ADDR
.assert "Catalog fits its Bank 6 span", beeb_catalog_end <= BEEB_CATALOG_ADDR + BEEB_CATALOG_PAGES * $100, true

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
    jsr mmu_safe_huff_read_ptr0     // A = Bank 6 (zp_ptr0),y; X, Y and C kept
}
.macro CatalogPoolWrite() {
    sta (zp_ptr1),y
}
