#importonce
// pick_item_type_cold.s — Depth-bucketed 349-item floor-spawn picker
//
// Module ownership:
//   owner: ChestOverlay (PICKER_IN_CHEST_OVERLAY) or DungeonGenOverlay
//     (PLATFORM_PRODUCT_OVERLAY_RUNTIME) in all 7 product builds; TestUnused
//     in C64 unit tests defining PICK_ITEM_TYPE_EXTERNAL; Default in unit tests
//     that exercise pick_item_type directly.
//   lifetime: one item-type roll during floor/chest/monster-drop spawning.
//   callers: resident pick_item_type wrapper (monster drops) and co-located
//     item_spawn_level_gen / chest_loot.

.const PIT_MAX_LEVEL = 12
.const PIT_SPAWNABLE_COUNT = 349
pit_best_lo: .byte 0
pit_best_hi: .byte 0
pit_tmp:     .byte 0

#if PICKER_IN_CHEST_OVERLAY
.segment ChestOverlay
#elif PLATFORM_PRODUCT_OVERLAY_RUNTIME
.segment DungeonGenOverlay
#endif

// 349 spawnable items (0..369 excluding gold #0/#1/#214..#231 and Ruined Chest #134),
// sorted ascending by min_lvl_m8 (0..12).
pit_sorted_lo:
    // Level 0 (25 items)
    .byte 13, 15, 61, 62, 63, 167, 182, 183, 184, 185, 232, 233, 234, 235, 236, 243
    .byte 244, 245, 246, 15, 16, 17, 18, 19, 40
    // Level 1 (55 items)
    .byte 2, 3, 6, 11, 12, 16, 17, 19, 20, 28, 29, 37, 51, 52, 54, 64
    .byte 77, 85, 98, 99, 103, 114, 135, 136, 161, 162, 186, 187, 188, 189, 190, 191
    .byte 237, 238, 239, 240, 241, 242, 247, 20, 21, 22, 23, 24, 25, 41, 42, 43
    .byte 44, 83, 84, 85, 86, 87, 88
    // Level 2 (50 items)
    .byte 5, 7, 9, 14, 21, 30, 31, 47, 48, 49, 53, 66, 74, 82, 84, 100
    .byte 102, 126, 128, 163, 168, 169, 192, 193, 248, 249, 250, 251, 252, 253, 254, 0
    .byte 45, 46, 47, 48, 62, 63, 64, 65, 66, 67, 68, 69, 70, 89, 94, 95
    .byte 96, 109
    // Level 3 (39 items)
    .byte 4, 18, 22, 25, 36, 39, 43, 44, 46, 50, 65, 70, 86, 88, 115, 164
    .byte 170, 171, 194, 1, 2, 3, 4, 5, 26, 49, 50, 51, 52, 53, 54, 90
    .byte 97, 98, 99, 100, 101, 102, 111
    // Level 4 (31 items)
    .byte 23, 27, 33, 40, 42, 55, 58, 67, 78, 87, 89, 95, 96, 109, 110, 129
    .byte 137, 172, 195, 196, 207, 208, 209, 210, 211, 6, 7, 8, 9, 55, 112
    // Level 5 (30 items)
    .byte 10, 32, 41, 45, 72, 79, 90, 92, 94, 101, 116, 124, 157, 158, 165, 197
    .byte 198, 199, 212, 10, 11, 12, 71, 72, 73, 91, 92, 103, 104, 110
    // Level 6 (6 items)
    .byte 34, 35, 68, 73, 93, 56
    // Level 7 (15 items)
    .byte 8, 26, 71, 80, 91, 122, 130, 173, 174, 13, 27, 28, 29, 93, 105
    // Level 8 (22 items)
    .byte 24, 38, 56, 59, 69, 75, 139, 140, 141, 142, 143, 144, 145, 149, 153, 166
    .byte 175, 200, 14, 74, 75, 76
    // Level 9 (9 items)
    .byte 76, 104, 106, 112, 131, 155, 176, 177, 201
    // Level 10 (20 items)
    .byte 83, 97, 108, 118, 121, 138, 159, 178, 202, 30, 31, 32, 33, 34, 35, 36
    .byte 37, 57, 106, 107
    // Level 11 (14 items)
    .byte 105, 117, 119, 132, 150, 154, 156, 179, 180, 77, 78, 79, 80, 81
    // Level 12 (33 items)
    .byte 57, 60, 81, 107, 111, 113, 120, 123, 125, 127, 133, 146, 147, 148, 151, 152
    .byte 160, 181, 203, 204, 205, 206, 213, 38, 39, 58, 59, 60, 61, 82, 108, 113
    .byte 114
pit_sorted_lo_end:

// Packed page bits (1 bit per sorted index: 1 = Page 1 [255..369], 0 = Page 0)
pit_sorted_hi_bits:
    .byte $00, $00, $f8, $01, $00, $00, $00, $00, $ff, $ff, $00, $00, $00, $80, $ff, $ff
    .byte $03, $00, $e0, $ff, $ff, $01, $00, $00, $fc, $00, $00, $f8, $3f, $08, $e0, $07
    .byte $00, $e0, $01, $00, $f8, $3f, $80, $0f, $00, $00, $f8, $1f
pit_sorted_hi_bits_end:

// Cumulative 16-bit item count per compressed depth tier (0..12)
pit_level_bounds_lo:
    .byte 25, 80, 130, 169, 200, 230, 236, 251, 17, 26, 46, 60, 93
pit_level_bounds_lo_end:
pit_level_bounds_hi:
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1
pit_level_bounds_hi_end:
pit_bit_masks:
    .byte $01, $02, $04, $08, $10, $20, $40, $80

#if PLATFORM_PRODUCT_OVERLAY_RUNTIME
pick_item_type_overlay:
#else
pick_item_type:
#endif
    // Compressed level: eff_level = min((dlvl + 3) / 4, PIT_MAX_LEVEL).
    lda zp_player_dlvl
    clc
    adc #3
    lsr
    lsr
    cmp #PIT_MAX_LEVEL + 1
    bcc !pit_level_ok+
    lda #PIT_MAX_LEVEL
!pit_level_ok:
    tay                          // Y = eff_level (preserved by rng_range)

    // Great item, 1 in 12 (none at town level 0)
    lda #12
    jsr rng_range                // [0, 11]
    bne !pit_no_great+
    tya
    beq !pit_no_great+
    lda #PIT_MAX_LEVEL
    jsr rng_range                // [0, 11]
    clc
    adc #1
    sta zp_temp1                 // randint(12)
    tya
    asl
    asl
    sta zp_temp0                 // eff * 4
    asl                          // C clear: eff * 8 <= 96
    adc zp_temp0                 // eff * 12 (<= 144)
    ldy #0
    sec
!pit_great_div:
    iny                          // quotient + 1
    sbc zp_temp1
    bcs !pit_great_div-
    cpy #PIT_MAX_LEVEL + 1
    bcc !pit_no_great+
    ldy #PIT_MAX_LEVEL
!pit_no_great:

    // 16-bit pool_size = pit_level_bounds[eff_level] -> zp_temp0/1
    lda pit_level_bounds_lo,y
    sta zp_temp0
    lda pit_level_bounds_hi,y
    sta zp_temp1

    // 50/50 coin flip: flat pick vs best-of-3
    lda #2
    jsr rng_range
    bne !pit_best_of_3+

    jsr rng_range_word           // [0, pool_size-1] in zp_temp2/3

!pit_return_idx:
    // Decode 16-bit index (zp_temp2=lo, zp_temp3=hi) into (item_cur_page, A=slot_lo)
    lda zp_temp2
    and #$07
    tay
    lda zp_temp2
    sta pit_tmp
    lda zp_temp3
    lsr
    ror pit_tmp
    lsr
    ror pit_tmp
    lsr
    ror pit_tmp
    ldx pit_tmp
    lda pit_sorted_hi_bits,x
    and pit_bit_masks,y
    beq !pit_page0+
    lda #ITEM_PAGE_BIT
    bne !pit_set_page+
!pit_page0:
    lda #0
!pit_set_page:
    sta item_cur_page
    ldx zp_temp2
    lda zp_temp3
    bne !pit_hi_slice+
    lda pit_sorted_lo,x
    rts
!pit_hi_slice:
    lda pit_sorted_lo + 256,x
    rts

!pit_best_of_3:
    jsr rng_range_word
    lda zp_temp2
    sta pit_best_lo
    lda zp_temp3
    sta pit_best_hi

    ldy #2
!pit_bo3_loop:
    sty pit_tmp
    jsr rng_range_word
    lda pit_best_lo
    cmp zp_temp2
    lda pit_best_hi
    sbc zp_temp3
    bcs !pit_bo3_keep+
    lda zp_temp2
    sta pit_best_lo
    lda zp_temp3
    sta pit_best_hi
!pit_bo3_keep:
    ldy pit_tmp
    dey
    bne !pit_bo3_loop-

    // Find winner's depth tier X (0..PIT_MAX_LEVEL) where pit_best < bounds[X]
    ldx #0
!pit_find_tier:
    lda pit_best_lo
    cmp pit_level_bounds_lo,x
    lda pit_best_hi
    sbc pit_level_bounds_hi,x
    bcc !pit_found_tier+
    inx
    cpx #PIT_MAX_LEVEL
    bcc !pit_find_tier-
!pit_found_tier:
    txa
    beq !pit_reroll_l0+
    stx pit_tmp
    lda pit_level_bounds_lo,x
    sec
    sbc pit_level_bounds_lo - 1,x   // Every tier span <= 55 < 256
    jsr rng_range
    ldx pit_tmp
    clc
    adc pit_level_bounds_lo - 1,x
    sta zp_temp2
    lda pit_level_bounds_hi - 1,x
    adc #0
    sta zp_temp3
    jmp !pit_return_idx-

!pit_reroll_l0:
    lda pit_level_bounds_lo
    jsr rng_range
    sta zp_temp2
    lda #0
    sta zp_temp3
    jmp !pit_return_idx-

#if HAL_PLATFORM_PICK_ITEM_RESIDENT_ITEMS_SEGMENT
:ResidentItemsSegment()
#elif HAL_PLATFORM_PICK_ITEM_IN_GEN_OVERLAY
.segment Default
#endif

#if HAL_PLATFORM_PICK_ITEM_PLUS4_BANK_RAM
pick_item_type:
    lda current_overlay
#if PICKER_IN_CHEST_OVERLAY
    cmp #OVL_CHEST
#else
    cmp #OVL_DUNGEON_GEN
#endif
    beq !pit_overlay_loaded+

#if PICKER_IN_CHEST_OVERLAY
    ldx #OVL_CHEST - 1
#else
    ldx #OVL_DUNGEON_GEN - 1
#endif
    jsr overlay_load_disk        // asks for the program disk until it loads
#if PICKER_IN_CHEST_OVERLAY
    lda #OVL_CHEST
#else
    lda #OVL_DUNGEON_GEN
#endif
    sta current_overlay

!pit_overlay_loaded:
    sei
    jsr plus4_bank_ram
    jsr pick_item_type_overlay
    pha
    jsr plus4_bank_ram
    cli
    pla
    rts
#elif PLATFORM_PRODUCT_OVERLAY_RUNTIME
pick_item_type:
#if PICKER_IN_CHEST_OVERLAY
    lda #OVL_CHEST
#else
    lda #OVL_DUNGEON_GEN
#endif
    jsr overlay_load
    bcc !pit_overlay_loaded+
    lda #2                      // Fallback to first non-gold type on media error.
    rts
!pit_overlay_loaded:
    sei
    :BankOutKernal()
    jsr pick_item_type_overlay
    pha
    :BankInKernal()
    cli
    pla
    rts
#endif

.assert "pit_sorted_lo size (excludes gold and ruined chest)", pit_sorted_lo_end - pit_sorted_lo, PIT_SPAWNABLE_COUNT
.assert "pit_sorted_hi_bits size", pit_sorted_hi_bits_end - pit_sorted_hi_bits, (PIT_SPAWNABLE_COUNT + 7) >> 3
.assert "pit_level_bounds_lo size", pit_level_bounds_lo_end - pit_level_bounds_lo, PIT_MAX_LEVEL + 1
.assert "pit_level_bounds_hi size", pit_level_bounds_hi_end - pit_level_bounds_hi, PIT_MAX_LEVEL + 1
#if !PICK_ITEM_TYPE_EXTERNAL
.assert "pick_item_type entry stays resident", pick_item_type < $e000, true
#else
.assert "pick_item_type parked in TestUnused window", pick_item_type >= $e100 && pick_item_type <= $fff9, true
#endif
#if PLATFORM_PRODUCT_OVERLAY_RUNTIME
.assert "pick_item_type overlay impl lives in the $E000 overlay window", pick_item_type_overlay >= BANKED_DATA_BASE && pick_item_type_overlay <= BANKED_DATA_END, true
#endif
