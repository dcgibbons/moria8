#importonce
// monster_catalog_bank.s — Commander X16 monster catalog placement
// (docs/MONSTER_CATALOG_DESIGN.md, core/6502/monster_catalog.s).
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

.macro CatalogWinBegin() {
}
.macro CatalogWinEnd() {
}
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

// ============================================================
// Phase 5 Extended Monster Catalog (MONSTER.EXT in Bank 5)
// ============================================================
// Bank 5 (CX16_BANK_CATALOG_EXT) holds 279 x 8 B row-major extension records
// at $A000-$A8B7, preloaded at boot alongside MONSTER.CAT (Bank 23).
.const CATALOG_EXT_RECORD_SIZE = 8
cat_ext_record: .fill CATALOG_EXT_RECORD_SIZE, 0

// catalog_fetch_ext — Copy creature cat_id_lo/hi's 8 extended bytes from
// HiRAM Bank 5 ($A000 + id * 8) into cat_ext_record[0..7].
// Preserves: CX16_RAM_BANK_REG ($00), processor flags (I/C/V), and all ZP.
// Clobbers: A, X
catalog_fetch_ext:
    php
    sei
    lda CX16_RAM_BANK_REG
    pha
    lda #CX16_BANK_CATALOG_EXT
    sta CX16_RAM_BANK_REG
    lda cat_id_hi
    sta cfe_lda + 2
    lda cat_id_lo
    asl
    rol cfe_lda + 2
    asl
    rol cfe_lda + 2
    asl
    rol cfe_lda + 2
    sta cfe_lda + 1
    lda cfe_lda + 2
    ora #>BANKED_DATA_BASE
    sta cfe_lda + 2
    ldx #CATALOG_EXT_RECORD_SIZE - 1
!cfe_copy:
cfe_lda:
    lda $a000,x
    sta cat_ext_record,x
    dex
    bpl !cfe_copy-
    pla
    sta CX16_RAM_BANK_REG
    plp
    rts
catalog_fetch_ext_end:

.assert "cat_ext_record and catalog_fetch_ext stay in fixed Low RAM below $9980", cat_ext_record >= CX16_RESIDENT_BASE && catalog_fetch_ext_end <= $9980, true
