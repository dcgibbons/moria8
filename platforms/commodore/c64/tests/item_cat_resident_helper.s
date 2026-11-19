#importonce
// KERNAL-banked item_cat_data reader for C64 unit tests (loaded variant).
// Same contract as item_cat_kernal_helper.s: define HAL_PLATFORM_ITEM_CAT_CUSTOM
// before core/item.s, then import this file in Default after core/item.s.
//
// Unlike item_cat_kernal_helper.s, item_cat_data.s is emitted as a block of
// the Default segment at $E100 (not a separate segment), so it is part of the
// PRG that VICE injects into RAM. A separate segment is never written to the
// test PRG, so its bytes would read back as RAM garbage at run time.

.var tic_resume_pc = *
.pc = $E100 "TestItemCat"
#import "../../../../platforms/shared/item_catalog/item_cat_data.s"
.assert "TestItemCat data ends below the RAM CPU vectors", * <= $FFF9, true
.pc = tic_resume_pc "TestItemCatReader"

test_icat_tmp: .byte 0

hal_item_cat_read_byte:
    php
    sei
    lda $01
    pha
    lda zp_ptr0
    pha
    lda zp_ptr0_hi
    pha
    :BankOutKernal()
    clc
    lda #<item_cat_data
    adc item_cat_off_lo
    sta zp_ptr0
    lda #>item_cat_data
    adc item_cat_off_hi
    sta zp_ptr0_hi
    ldy #0
    lda (zp_ptr0),y
    sta test_icat_tmp
    pla
    sta zp_ptr0_hi
    pla
    sta zp_ptr0
    pla
    sta $01
    plp
    lda test_icat_tmp
    rts
