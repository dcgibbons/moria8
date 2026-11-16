// Diagnostic driver only: executes the linked product catalog reader for
// every source ID, with RAM enabled at entry. Output is two independent byte
// sums per record at $C800+ AND all 279 x 8 B extended records at $CB00+;
// host compares both against source records.
#import "cartridge_contract.s"
#import "cartridge_product_symbols.inc"
#import "../common/catalog_records.s"
.const TEST_RAM_ENABLE = $ff3f
.const TEST_EXT_OUT_BASE = $cb00
.pc = $c400
test_start:
    sei
    lda #0
    sta CART_REG_BANK
    sta CART_REG_BASIC_KERNAL
    sta TEST_RAM_ENABLE
    lda #0
    sta record_id
    sta record_id + 1
!record:
    lda record_id
    sta cat_id_lo
    lda record_id + 1
    sta cat_id_hi
    ldx #3
!seed_math:
    txa
    ora #$a0
    sta zp_math_a,x
    dex
    bpl !seed_math-
    jsr catalog_fetch_record
    ldx #3
!check_math:
    txa
    ora #$a0
    cmp zp_math_a,x
    beq !ok_math+
    jmp test_fail
!ok_math:
    dex
    bpl !check_math-
    jsr catalog_fetch_ext
    ldx #3
!check_math_ext:
    txa
    ora #$a0
    cmp zp_math_a,x
    beq !ok_math_ext+
    jmp test_fail
!ok_math_ext:
    dex
    bpl !check_math_ext-
    lda #0
    sta sum1
    sta sum2
    ldx #0
!byte:
    clc
    lda sum1
    adc cat_record,x
    sta sum1
    clc
    adc sum2
    sta sum2
    inx
    cpx #CATALOG_RECORD_SIZE
    bne !byte-
    lda sum1
out1:
    sta $c800
    lda sum2
out2:
    sta $c801
    clc
    lda out1 + 1
    adc #2
    sta out1 + 1
    sta out2 + 1
    inc out2 + 1
    bcc !ext_copy_init+
    inc out1 + 2
    inc out2 + 2
!ext_copy_init:
    ldx #0
!ext_copy:
    lda cat_ext_record,x
ext_out:
    sta TEST_EXT_OUT_BASE,x
    inx
    cpx #8
    bne !ext_copy-
    clc
    lda ext_out + 1
    adc #8
    sta ext_out + 1
    bcc !id+
    inc ext_out + 2
!id:
    inc record_id
    bne !check+
    inc record_id + 1
!check:
    lda record_id + 1
    cmp #>cart_catalog_count
    bne !next_record+
    lda record_id
    cmp #<cart_catalog_count
    beq test_pass
!next_record:
    jmp !record-
test_pass:
    jmp test_pass
test_fail:
    jmp test_fail
record_id: .word 0
sum1: .byte 0
sum2: .byte 0
.assert "Diagnostic driver leaves result scratch free", * <= $c800, true
.assert "Record checksum buffer stays below extended dump", $c800 + 2 * 279 <= TEST_EXT_OUT_BASE, true
.assert "Extended catalog dump fits map scratch", TEST_EXT_OUT_BASE + 8 * 279 <= $d600, true
