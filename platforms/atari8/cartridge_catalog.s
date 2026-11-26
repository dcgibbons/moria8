#importonce
#import "../commodore/common/catalog_records.s"
// AtariMax 128 KB cartridge catalog adapter.
// Owner: platforms/atari8/ low resident RAM (< $4000, imported by monster_catalog_a8.s).
// Lifetime: session-long.
// Callers: core/6502/monster_catalog.s (generation, summon, and UI inspection paths),
// callable with overlays mapped at $E000 or unmapped, without disk I/O.
// Note: catalog_index.s stays in RuntimeBanked ($F000-$FFF9) via monster_catalog_a8.s.

.label cart_catalog_count = CATALOG_COUNT

cat_record: .byte $ff, $ff                     // Cold sentinel != 0..278
            .fill A8_CATALOG_RECORD_SIZE - 2, 0
.label cat_ext_record = cat_record + CATALOG_RECORD_SIZE
.assert "Atari catalog copy buffer stays below $4000", cat_record + A8_CATALOG_RECORD_SIZE <= $4000, true
.assert "Atari catalog offsets fit 16 bits", CATALOG_COUNT * A8_CATALOG_RECORD_SIZE <= $6000, true
.assert "Atari catalog IDs have at most one high bit", CATALOG_COUNT <= 512, true
.assert "Multiply scratch is contiguous", zp_math_tmp1 - zp_math_a, 3

// catalog_boot_load — tier_init hook (no disk scan needed on cartridge).
catalog_boot_load:
    clc
    rts

// catalog_fetch_record — Read creature cat_id_lo/hi's 57-byte record from
// CART_ASSET_CATALOG into cat_record, preserving caller zp_math_a..zp_math_tmp1.
// Clobbers: A, X, Y
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
    ldx #3
!save_math:
    lda zp_math_a,x
    pha
    dex
    bpl !save_math-

    lda cat_id_lo
    ldx #A8_CATALOG_RECORD_SIZE
    jsr math_multiply
    sta cart_offset
    lda zp_math_b
    ldx cat_id_hi
    beq !high_ready+
    clc
    adc #A8_CATALOG_RECORD_SIZE
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
    jsr cart_read
    bcs !invalid-
    lda cat_record + 0
    cmp cat_id_lo
    bne !invalid-
    lda cat_record + 1
    cmp cat_id_hi
    bne !invalid-
    rts
