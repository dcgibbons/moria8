#importonce
// test_dungeon128.s — Dungeon render color-path regression checks (C128)

#import "../../common/zeropage.s"
#import "test_helpers128.s"
#import "../memory128.s"
#import "../../common/dungeon_data.s"
#import "../../common/color.s"
#import "../screen_vdc.s"
#import "../monster_threat_vdc.s"
#import "../../common/dungeon_los.s"

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $3000 "Test Code"

c128_restore_runtime_state:
    rts

mmu_safe_map_read_ptr0:
    jsr mmu_select_bank1
    lda (zp_ptr0),y
    pha
    jsr mmu_select_bank0
    pla
    rts

mmu_safe_map_write_ptr0:
    pha
    jsr mmu_select_bank1
    pla
    sta (zp_ptr0),y
    pha
    jsr mmu_select_bank0
    pla
    rts

mmu_safe_map_read_ptr1:
    jsr mmu_select_bank1
    lda (zp_ptr1),y
    pha
    jsr mmu_select_bank0
    pla
    rts

mmu_safe_map_write_ptr1:
    pha
    jsr mmu_select_bank1
    pla
    sta (zp_ptr1),y
    pha
    jsr mmu_select_bank0
    pla
    rts

mmu_safe_mark_visited_row_ptr0:
    sta test_mark_visited_row_end
    lda #0
    sta test_mark_visited_seen_new
    jsr mmu_select_bank1
!mark:
    lda (zp_ptr0),y
    sta test_mark_visited_tile_tmp
    lda mmu_common_row_detect_new
    beq !write+
    lda test_mark_visited_tile_tmp
    and #FLAG_VISITED
    bne !write+
    lda #1
    sta test_mark_visited_seen_new
!write:
    lda test_mark_visited_tile_tmp
    ora mmu_common_row_mask
    sta (zp_ptr0),y
    cpy test_mark_visited_row_end
    beq !done+
    iny
    jmp !mark-
!done:
    jsr mmu_select_bank0
    lda test_mark_visited_seen_new
    rts

test_mark_visited_row_end:
    .byte 0
test_mark_visited_seen_new:
    .byte 0
test_mark_visited_tile_tmp:
    .byte 0

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
    ldx #17
    lda #COL_CYAN
    jsr screen_flash_set_color
    lda sfa_flash_attr
    cmp vic_to_vdc_color + COL_CYAN
    bne !fail2+
    cpx #17
    bne !fail2+

    ldx #17
    jsr screen_flash_reset_color
    lda sfa_flash_attr
    cmp #VDC_WHITE
    bne !fail2+
    cpx #17
    bne !fail2+

    jmp !after_fail2+
!fail2:
    jmp test_fail
!after_fail2:

    // Test 6: los_is_visible must read the live Bank 1 map on C128.
    // Bank 0 mirror at the same address is deliberately dark, while Bank 1
    // carries a lit tile; raw pointer reads would see the wrong bank.
    lda #10
    sta zp_player_y
    lda #10
    sta zp_player_x
    lda #0
    sta zp_light_radius

    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi

    ldy #12
    lda #TILE_FLOOR
    sta (zp_ptr0),y

    jsr mmu_select_bank1
    ldy #12
    lda #TILE_WALL_H | FLAG_LIT | FLAG_VISITED
    sta (zp_ptr0),y
    jsr mmu_select_bank0

    ldx #12
    ldy #10
    jsr los_is_visible
    bcc test_fail

    jmp test_pass

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass

cr_color: .fill 65, 0
cr_level: .fill 65, 0
