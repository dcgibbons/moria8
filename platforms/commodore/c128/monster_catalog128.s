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
.segment C128ResidentWorld

// Boot loads (main.s c128_load_core_residents, after this world payload has
// loaded): the main image has no room for them.
// The monster catalog's fields and names, into their Bank 1 spans.
catalog_filename:
    .text "128.CAT"
catalog_filename_end:
.const CATALOG_FILENAME_LEN = catalog_filename_end - catalog_filename
catalog_names_filename:
    .text "128.CNM"
catalog_names_filename_end:
.const CATALOG_NAMES_FILENAME_LEN = catalog_names_filename_end - catalog_names_filename
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
c128_load_catalog_prg:
    :C128Bank1LoadFile(catalog_filename, CATALOG_FILENAME_LEN, BANK1_CATALOG_FIELDS_BASE)
c128_load_catalog_names_prg:
    :C128Bank1LoadFile(catalog_names_filename, CATALOG_NAMES_FILENAME_LEN, BANK1_CATALOG_NAMES_BASE)

.const CATALOG_NAME_POOL_BASE = BANK1_CATALOG_POOL_BASE
.const CATALOG_NAME_POOL_END  = BANK1_CATALOG_POOL_END

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
