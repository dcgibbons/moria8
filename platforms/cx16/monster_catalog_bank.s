#importonce
// monster_catalog_bank.s — Commander X16 monster catalog placement
// (docs/MONSTER_CATALOG_DESIGN.md, core/monster_catalog.s).
//
// Bank 22 (MONSTER.CAT) holds the catalog's engine fields and its level
// index; cx16_preload_banks loads it at boot. The names ride in Bank 4 after
// the Huffman corpus (main.s), read through the same virtual-map reads. The
// picker and fetch run with Bank 22 mapped; the caller may be an overlay in
// Banks 9-20, so the unmap restores the bank (and interrupt state) it found.

.segment Cx16Catalog
#import "../shared/catalog/catalog_fields.s"
#import "../shared/catalog/catalog_index.s"
catalog_bank_end:
.segment Default

.assert "Catalog fields start the banked window", catalog_fields, BANKED_DATA_BASE

.const CATALOG_NAME_POOL_BASE = PLATFORM_TIER_NAME_POOL_BASE
.const CATALOG_NAME_POOL_END  = PLATFORM_TIER_NAME_POOL_END

.macro CatalogMap() {
    jsr cx16_catalog_map
}
.macro CatalogUnmap() {
    jsr cx16_catalog_unmap
}
.macro CatalogFieldRead() {
    lda (zp_ptr0),y
}
.macro CatalogPoolWrite() {
    sta (zp_ptr1),y
}

cx16_catalog_saved_bank: .byte 0
cx16_catalog_saved_p:    .byte 0

// cx16_catalog_map — Map the catalog bank (interrupts masked).
// Clobbers: A
cx16_catalog_map:
    php
    pla
    sta cx16_catalog_saved_p
    sei
    lda CX16_RAM_BANK_REG
    sta cx16_catalog_saved_bank
    lda #CX16_BANK_CATALOG
    sta CX16_RAM_BANK_REG
    rts

// cx16_catalog_unmap — Restore the bank and interrupt state the map saved.
// Clobbers: A
cx16_catalog_unmap:
    lda cx16_catalog_saved_bank
    sta CX16_RAM_BANK_REG
    lda cx16_catalog_saved_p
    pha
    plp
    rts
