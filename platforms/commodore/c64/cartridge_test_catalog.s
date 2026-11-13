// Diagnostic driver only: executes the linked product catalog reader for
// every source ID, with all ROMs hidden at entry. Output is two independent
// byte sums per record in map scratch; host compares against source records.
#import "cartridge_product_symbols.inc"
#import "../common/catalog_records.s"
.pc = $c400
test_start:
    sei
    lda #$34
    sta $01
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
    bne test_fail
    dex
    bpl !check_math-
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
    bcc !id+
    inc out1 + 2
    inc out2 + 2
!id:
    inc record_id
    bne !check+
    inc record_id + 1
!check:
    lda record_id + 1
    cmp #>cart_catalog_count
    bne !record-
    lda record_id
    cmp #<cart_catalog_count
    bne !record-
    lda #$36
    sta $01
test_pass:
    jmp test_pass
test_fail:
    jmp test_fail
record_id: .word 0
sum1: .byte 0
sum2: .byte 0
.assert "Diagnostic driver leaves result scratch free", * <= $c800, true
