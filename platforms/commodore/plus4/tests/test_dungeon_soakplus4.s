// Plus/4 shared dungeon-generator door topology coverage.

#define DUNGEON_FEATURES_GENERATION_ONLY
#define SPECIAL_ROOMS_GENERATION_ONLY
#define DUNGEON_TEST_OVERLAP_HELPERS

.pc = $1000 "Plus/4 dungeon soak"

.encoding "screencode_mixed"

#import "../../../../core/zeropage.s"
#import "../memory.s"
#import "../hal/layout.s"
#import "../hal/lifecycle_policy.s"
#import "../../common/mmu_macros.s"
#import "../../../../core/rng.s"
#import "../../../../core/math.s"
#import "../../../../core/tables.s"
#import "../../../../core/dungeon_data.s"

.const PL_MAP_X = 49
.const PL_MAP_Y = 50
player_data:
    .fill 80, 0

mmu_safe_map_read_ptr0:
    lda (zp_ptr0),y
    rts

mmu_safe_map_write_ptr0:
    sta (zp_ptr0),y
    rts

mmu_safe_map_read_ptr1:
    lda (zp_ptr1),y
    rts

mmu_safe_map_write_ptr1:
    sta (zp_ptr1),y
    rts

#import "../../../../core/dungeon_features.s"
#import "../../../../core/special_rooms.s"

tramp_assign_special_room:
    jmp assign_special_room

tramp_vault_seal_entrance:
    jmp vault_seal_entrance

#import "../../../../core/dungeon_gen.s"

test_seed_idx: .byte 0
audit_door_x: .byte 0
audit_door_y: .byte 0
audit_check_x: .byte 0
audit_check_y: .byte 0

test_seeds:
    .byte $42, $13, $7a, $f1
    .byte $55, $aa, $33, $cc
    .byte $01, $23, $45, $67
    .byte $de, $ad, $be, $ef

test_start:
    sei
    cld
    sta PLUS4_RAM_ENABLE
    ldx #$ff
    txs

    // A passable east/west door with an open north side is bypassable.
    lda #TILE_WALL_H
    jsr map_bulk_fill_all
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #19
    lda #TILE_FLOOR
    sta (zp_ptr0),y
    iny
    lda #TILE_DOOR_CLOSED
    sta (zp_ptr0),y
    iny
    lda #TILE_FLOOR
    sta (zp_ptr0),y
    ldx #19
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_FLOOR
    sta (zp_ptr0),y
    jsr audit_final_door_chokepoints_plus4
    bcc test_fail

    lda #0
    sta test_seed_idx
!seed_loop:
    lda test_seed_idx
    asl
    asl
    tax
    lda test_seeds,x
    sta zp_rng_0
    inx
    lda test_seeds,x
    sta zp_rng_1
    inx
    lda test_seeds,x
    sta zp_rng_2
    inx
    lda test_seeds,x
    sta zp_rng_3
    lda #1
    sta zp_player_dlvl
    lda #0
    sta level_entry_dir
    jsr dungeon_generate
    jsr audit_final_door_chokepoints_plus4
    bcs test_fail
    inc test_seed_idx
    lda test_seed_idx
    cmp #4
    bne !seed_loop-

test_pass:
    jmp test_pass

test_fail:
    brk

audit_coord_passable_plus4:
    ldx audit_check_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy audit_check_x
    lda (zp_ptr0),y
    jmp vc_tile_is_passable

audit_final_door_chokepoints_plus4:
    lda #~FLAG_OCCUPIED & $ff
    jsr map_bulk_and_all
    lda #1
    sta audit_door_y
!row:
    lda #1
    sta audit_door_x
!col:
    ldx audit_door_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy audit_door_x
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    beq !check+
    cmp #TILE_DOOR_CLOSED
    beq !check+
    cmp #TILE_SECRET
    bne !next+
!check:
    jsr audit_one_door_chokepoint_plus4
    bcs !fail+
!next:
    inc audit_door_x
    lda audit_door_x
    cmp #MAP_COLS - 1
    bne !col-
    inc audit_door_y
    lda audit_door_y
    cmp #MAP_ROWS - 1
    bne !row-
    clc
    rts
!fail:
    sec
    rts

audit_one_door_chokepoint_plus4:
    lda audit_door_x
    sta dg_cx1
    sec
    sbc #1
    sta audit_check_x
    lda audit_door_y
    sta dg_cy1
    sta audit_check_y
    jsr audit_coord_passable_plus4
    bcc !try_vertical+
    lda audit_door_x
    clc
    adc #1
    sta audit_check_x
    lda audit_door_y
    sta audit_check_y
    jsr audit_coord_passable_plus4
    bcc !try_vertical+
    lda audit_door_x
    sta dg_room_x
    lda audit_door_y
    sta dg_room_y
    jsr jdg_opposing_vertical
    bcs !pass+
    jmp !fail+
!try_vertical:
    lda audit_door_x
    sta audit_check_x
    lda audit_door_y
    sec
    sbc #1
    sta audit_check_y
    jsr audit_coord_passable_plus4
    bcc !fail+
    lda audit_door_x
    sta audit_check_x
    lda audit_door_y
    clc
    adc #1
    sta audit_check_y
    jsr audit_coord_passable_plus4
    bcc !fail+
    lda audit_door_x
    sta dg_room_x
    lda audit_door_y
    sta dg_room_y
    jsr jdg_opposing_horizontal
    bcc !fail+
!pass:
    clc
    rts
!fail:
    sec
    rts

test_end:
.assert "Plus/4 dungeon soak stays below live map", test_end < MAP_BASE, true
