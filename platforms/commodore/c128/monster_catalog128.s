#importonce
// monster_catalog128.s — C128 monster catalog placement
// (docs/MONSTER_CATALOG_DESIGN.md, core/monster_catalog.s; memory128.s and
// C128M-007 own the Bank 1 spans).
//
// The level index is resident (here, in the world payload): the picker reads
// it directly. The fields (128.CAT) and Huffman-coded names (128.CNM) load
// into Bank 1 at boot (main.s c128_load_core_residents); the fetch reads
// them, and writes the decoded name into the Bank 1 name pool, through the
// Bank 1 safe helpers, which keep the caller's banking and IRQ state (the
// caller may run from the $E000 overlay window).

#import "../../shared/catalog/catalog_index.s"

.segment C128Bank1Catalog
#import "../../shared/catalog/catalog_fields.s"
.assert "Catalog fields fit their Bank1 span", catalog_fields_end <= BANK1_CATALOG_FIELDS_END + 1, true
.segment C128Bank1CatalogNames
#import "../../shared/catalog/catalog_names.s"
.assert "Catalog names fit their Bank1 span", catalog_names_end <= BANK1_CATALOG_NAMES_END + 1, true
.segment Default
// The monster catalog's fields and names, into their Bank 1 spans.
catalog_filename:
    .text "128.CAT"
catalog_filename_end:
.const CATALOG_FILENAME_LEN = catalog_filename_end - catalog_filename
catalog_names_filename:
    .text "128.CNM"
catalog_names_filename_end:
.const CATALOG_NAMES_FILENAME_LEN = catalog_names_filename_end - catalog_names_filename
#if !C128_CARTRIDGE
catalog_ext_filename:
    .text "128.CEX"
catalog_ext_filename_end:
.const CATALOG_EXT_FILENAME_LEN = catalog_ext_filename_end - catalog_ext_filename
.macro C128Bank1LoadFile(filename, filename_len, dest) {
    lda #RESIDENT_HUFFMAN_FILE_NUM
    sta disk_temp
    lda #filename_len
    sta disk_status
    lda #<filename
    sta zp_ptr0
    lda #>filename
    sta zp_ptr0_hi
    lda #<dest
    sta zp_ptr1
    lda #>dest
    sta zp_ptr1_hi
    lda #1
    sta c128_runtime_load_bank
    jmp c128_load_runtime_prg
}
#endif
c128_load_catalog_prg:
#if C128_CARTRIDGE
    lda #CART_ASSET_CAT
    jmp cart_load_asset
#else
    :C128Bank1LoadFile(catalog_filename, CATALOG_FILENAME_LEN, BANK1_CATALOG_FIELDS_BASE)
#endif
c128_load_catalog_names_prg:
#if C128_CARTRIDGE
    lda #CART_ASSET_CNM
    jmp cart_load_asset
#else
    :C128Bank1LoadFile(catalog_names_filename, CATALOG_NAMES_FILENAME_LEN, BANK1_CATALOG_NAMES_BASE)
#endif
c128_load_catalog_ext_prg:
#if C128_CARTRIDGE
    lda #CART_ASSET_CEX
    jmp cart_load_asset
#else
    :C128Bank1LoadFile(catalog_ext_filename, CATALOG_EXT_FILENAME_LEN, BANK1_CATALOG_EXT_BASE)
#endif

#import "catalog_ext_fetch128.s"

.const CATALOG_NAME_POOL_BASE = BANK1_CATALOG_POOL_BASE
.const CATALOG_NAME_POOL_END  = BANK1_CATALOG_POOL_END

// The win creature and the turn's wanderer (catalog_place_far) live in the
// $AF00 play payload (128.play): the Bank 0 resident image has no room. Their
// only callers, monster_spawn_level (from game_loop.s) and turn_post_action,
// run from the play payload itself, so it is loaded whenever they run; the
// modal persist payload that shares $AF00 never calls them.
.macro CatalogWinBegin() {
    .segment C128ResidentPlay
}
.macro CatalogWinEnd() {
    .segment Default
}
.macro CatalogMap() {
}
.macro CatalogUnmap() {
}
.macro CatalogFieldRead() {
    jsr mmu_safe_db_read_ptr0
}
.macro CatalogPoolWrite() {
    jsr mmu_safe_db_write_ptr1
}
