#importonce
// catalog_ext_fetch128.s — C128 Phase 5 extended monster catalog fetch
//
// Reads 8 bytes (cat_atk2_type/dice/sides, cat_atk3_type/dice/sides,
// cat_spell_flags2, cat_cdefense) for creature ID cat_id_lo/cat_id_hi (0..278)
// from Bank 1 $D000 + id * 8 into Bank 0 cat_ext_record[0..7] via the
// IRQ-safe $7F common-RAM pointer thunk (mmu_common_b1_noio_read_ptr0).

.const CATALOG_EXT_RECORD_SIZE = 8
.assert "Bank1 extended catalog base is page-aligned", <BANK1_CATALOG_EXT_BASE, 0
.assert "Bank1 extended catalog size matches 279 * 8", BANK1_CATALOG_EXT_SIZE, 279 * CATALOG_EXT_RECORD_SIZE

cat_ext_record:
    .fill CATALOG_EXT_RECORD_SIZE, 0
cat_ext_saved_x:
    .byte 0

// catalog_fetch_ext — Read creature cat_id_lo/hi's 8 extended Phase 5 bytes
// into cat_ext_record[0..7].
// Preserves: X, zp_ptr0/zp_ptr0_hi, caller IRQ/MMU state. Clobbers: A, Y.
catalog_fetch_ext:
    stx cat_ext_saved_x
    lda zp_ptr0
    pha
    lda zp_ptr0_hi
    pha

    lda cat_id_hi
    sta zp_ptr0_hi
    lda cat_id_lo
    asl
    rol zp_ptr0_hi
    asl
    rol zp_ptr0_hi
    asl
    rol zp_ptr0_hi
    sta zp_ptr0
    lda zp_ptr0_hi
    clc
    adc #>BANK1_CATALOG_EXT_BASE
    sta zp_ptr0_hi

    ldy #CATALOG_EXT_RECORD_SIZE - 1
!cfe_loop:
    jsr mmu_common_b1_noio_read_ptr0
    sta cat_ext_record,y
    dey
    bpl !cfe_loop-

    pla
    sta zp_ptr0_hi
    pla
    sta zp_ptr0
    ldx cat_ext_saved_x
    rts
