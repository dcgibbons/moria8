// test_dungeon128.s — Lightweight map/scratch safety smoke test for C4.1

#import "../../common/zeropage.s"
#import "../memory128.s"

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $3000 "Test Code"

test_start:
    sei
    cld
    ldx #$ff
    txs

    lda #MMU_ALL_RAM
    sta $ff00

    // Test 1: map base/end are writable/readable
    lda #$a5
    sta MAP_BASE
    lda #$5a
    sta MAP_END
    lda MAP_BASE
    cmp #$a5
    bne test_fail
    lda MAP_END
    cmp #$5a
    bne test_fail

    // Test 2: SCREEN_RAM writes don't clobber sampled map bytes
    lda MAP_BASE
    sta $02f0
    lda MAP_END
    sta $02f1

    lda #$11
    sta SCREEN_RAM + 0
    lda #$22
    sta SCREEN_RAM + 1
    lda #$33
    sta SCREEN_RAM + 2
    lda #$44
    sta SCREEN_RAM + 3

    lda MAP_BASE
    cmp $02f0
    bne test_fail
    lda MAP_END
    cmp $02f1
    bne test_fail

    jmp test_pass

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass
