#importonce
// C64 cartridge catalog adapter. Owner: low resident RAM, session lifetime.
// catalog_fetch_record is called unmapped from generation and summon paths;
// it supplies the exact disk-record representation to core/monster_catalog.s.
#import "../common/catalog_records.s"
.segmentdef CatalogHidden [start=CATALOG_HIDDEN_BASE, virtual]
.segment CatalogHidden
#import "../../shared/catalog/catalog_index.s"
.label cart_catalog_count = CATALOG_COUNT
cat_hidden_end:
.segment Default
.const CATALOG_IDX_SIZE = cat_hidden_end - cat_level_raw
.assert "Cartridge index starts the existing hidden span", cat_level_raw, CATALOG_HIDDEN_BASE
.assert "Cartridge index fits existing hidden owner", cat_hidden_end - 1 <= CATALOG_HIDDEN_END, true
#if PLATFORM_CAT_RECORD_EXTERNAL
.label cat_record = PLATFORM_CAT_RECORD_BASE   // page 3 on C64 (config.s)
.assert "The record buffer is the size config.s gives it", CATALOG_RECORD_SIZE, 49
#else
cat_record: .fill CATALOG_RECORD_SIZE, 0
#endif
.assert "Catalog copy buffer stays below cartridge ROM", cat_record + CATALOG_RECORD_SIZE <= $8000, true

// Even a descriptor source at $9FFF plus the last record must fit 16 bits.
.assert "Catalog source-offset addition fits 16 bits", CATALOG_COUNT * CATALOG_RECORD_SIZE <= $6000, true

.assert "Catalog IDs have at most one high bit", CATALOG_COUNT <= 512, true
.assert "Multiply scratch is contiguous", zp_math_tmp1 - zp_math_a, 3

catalog_fetch_record:
    lda cat_id_hi
    cmp #>CATALOG_COUNT
    bcc !valid+
    bne !invalid+
    lda cat_id_lo
    cmp #<CATALOG_COUNT
    bcc !valid+
!invalid:
    jmp cart_invalid_asset
!valid:
    // Reuse the bounded 8x8 multiply, preserving its caller-owned ZP.
    // The asserted source-offset bound limits cat_id_hi to zero or one.
    ldx #3
!save_math:
    lda zp_math_a,x
    pha
    dex
    bpl !save_math-
    lda cat_id_lo
    ldx #CATALOG_RECORD_SIZE
    jsr math_multiply
    sta cart_offset
    lda zp_math_b
    ldx cat_id_hi
    beq !high_ready+
    clc
    adc #CATALOG_RECORD_SIZE
!high_ready:
    sta cart_offset + 1
    ldx #0
!restore_math:
    pla
    sta zp_math_a,x
    inx
    cpx #4
    bne !restore_math-
    lda #1
    sta cart_is_record
    lda #CART_ASSET_CATALOG
    jmp cart_read
