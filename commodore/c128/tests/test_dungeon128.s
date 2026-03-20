#importonce
// test_dungeon128.s — Dungeon render color-path regression checks (C128)

#import "../../common/zeropage.s"
#import "test_helpers128.s"
#import "../memory128.s"
#import "../../common/color.s"
#import "../screen_vdc.s"

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $3000 "Test Code"

c128_restore_runtime_state:
    rts

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

    // Test 3: Color translation consistency used by dungeon renderer
    // Floor in LOS: tile type 0 -> COL_DGREY -> VDC_DGREY
    ldx tile_colors + 0
    lda vic_to_vdc_color,x
    cmp #VDC_DGREY
    bne test_fail

    // Floor out of LOS: dimming path writes VDC_DGREY directly.
    lda #VDC_DGREY
    cmp vic_to_vdc_color + COL_DGREY
    bne test_fail

    // Corridor rock in LOS: hardcoded VDC_LGREY path must match palette.
    lda #VDC_LGREY
    cmp vic_to_vdc_color + COL_LGREY
    bne test_fail

    // Rubble uses canonical grey, which intentionally falls back to VDC dark grey.
    ldx tile_colors + 11
    lda vic_to_vdc_color,x
    cmp #VDC_DGREY
    bne test_fail

    // Magma in LOS: tile type 12 -> COL_RED -> VDC_RED
    ldx tile_colors + 12
    lda vic_to_vdc_color,x
    cmp #VDC_RED
    bne test_fail

    // Guard runtime nibble encoding so dim floor/wall/magma don't drift.
    lda #VDC_DGREY
    cmp #(vdc_encode_rgbi(8) | VDC_ATTR_MODE)
    bne test_fail
    lda #VDC_LGREY
    cmp #(vdc_encode_rgbi(7) | VDC_ATTR_MODE)
    bne test_fail
    lda #VDC_RED
    cmp #(vdc_encode_rgbi(4) | VDC_ATTR_MODE)
    bne test_fail

    jmp test_pass

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass
