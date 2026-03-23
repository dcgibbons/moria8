#importonce
// test_dungeon128.s — Dungeon render color-path regression checks (C128)

#import "../../common/zeropage.s"
#import "test_helpers128.s"
#import "../memory128.s"
#import "../../common/color.s"
#import "../screen_vdc.s"
#import "../monster_threat_vdc.s"

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
    bne !fail1+
    lda MAP_END
    cmp #$5a
    bne !fail1+

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
    bne !fail1+
    lda MAP_END
    cmp $02f1
    bne !fail1+

    // Test 3: Color translation consistency used by dungeon renderer
    // Floor in LOS: tile type 0 -> COL_DGREY -> VDC_DGREY
    ldx tile_colors + 0
    lda vic_to_vdc_color,x
    cmp #VDC_DGREY
    bne !fail1+

    // Floor out of LOS: dimming path writes VDC_DGREY directly.
    lda #VDC_DGREY
    cmp vic_to_vdc_color + COL_DGREY
    bne !fail1+

    // Corridor rock in LOS: hardcoded VDC_LGREY path must match palette.
    lda #VDC_LGREY
    cmp vic_to_vdc_color + COL_LGREY
    bne !fail1+

    // Rubble uses canonical grey, which intentionally falls back to VDC dark grey.
    ldx tile_colors + 11
    lda vic_to_vdc_color,x
    cmp #VDC_DGREY
    bne !fail1+

    // Magma in LOS: tile type 12 -> COL_RED -> VDC_RED
    ldx tile_colors + 12
    lda vic_to_vdc_color,x
    cmp #VDC_RED
    bne !fail1+

    // Guard runtime nibble encoding so dim floor/wall/magma don't drift.
    lda #VDC_DGREY
    cmp #(vdc_encode_rgbi(8) | VDC_ATTR_MODE)
    bne !fail1+
    lda #VDC_LGREY
    cmp #(vdc_encode_rgbi(7) | VDC_ATTR_MODE)
    bne !fail1+
    lda #VDC_RED
    cmp #(vdc_encode_rgbi(4) | VDC_ATTR_MODE)
    bne !fail1+

    jmp !after_fail1+
!fail1:
    jmp test_fail
!after_fail1:

    // Test 4: threat-coded monster colors stay stable on C128 live render path.
    lda #5
    sta zp_player_lvl

    lda #1
    sta cr_level + 1
    lda #3
    sta cr_level + 13
    lda #5
    sta cr_level + 24
    lda #COL_CYAN
    sta cr_color + 57

    ldx #1                      // cr_level = 1, town-safe dungeon creature
    jsr monster_get_threat_color
    cmp #COL_THREAT_LOW
    bne !fail2+

    ldx #13                     // cr_level = 3
    jsr monster_get_threat_color
    cmp #COL_THREAT_MED
    bne !fail2+

    lda #3
    sta zp_player_lvl
    ldx #24                     // cr_level = 5
    jsr monster_get_threat_color
    cmp #COL_THREAT_HIGH
    bne !fail2+

    lda #2
    sta zp_player_lvl
    ldx #24                     // cr_level = 5
    jsr monster_get_threat_color
    cmp #COL_THREAT_DEADLY
    bne !fail2+

    ldx #57                     // Town NPCs keep authored species colors
    jsr monster_get_threat_color
    cmp cr_color + 57
    bne !fail2+

    // Test 5: VDC special-effect flash color setter/resetter stay in sync
    // with the VIC->VDC palette translation table.
    lda #COL_CYAN
    jsr screen_flash_set_color
    lda sfa_flash_attr
    cmp vic_to_vdc_color + COL_CYAN
    bne !fail2+

    jsr screen_flash_reset_color
    lda sfa_flash_attr
    cmp #VDC_WHITE
    bne !fail2+

    jmp !after_fail2+
!fail2:
    jmp test_fail
!after_fail2:

    jmp test_pass

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass

cr_color: .fill 65, 0
cr_level: .fill 65, 0
