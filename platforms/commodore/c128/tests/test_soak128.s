#importonce
// test_soak128.s — C128 generation soak/integrity test for C4.7
//
// The gate runs 4 dungeon generations (the first seed's last 4 levels);
// make test128-soak-long runs 200 (4 deterministic seed variants x 50).
// Fails on:
// - IRQ-state drift across dungeon_generate
// - Bank 0 map-address leakage at SOAK_SENTINEL_LO/HI (map space, past the test code)
// - Invalid room/stairs invariants
// - Loss of the row-batched C128 tunnel materialization path

#define C128_TEST_DUNGEON_OVERLAP
#define DUNGEON_TEST_OVERLAP_HELPERS
#define C128_TEST_COUNT_MAP_ROW_COPIES
#define C128_TEST_COUNT_MAP_ROW_STORES
#define DUNGEON_FEATURES_GENERATION_ONLY
#define SPECIAL_ROOMS_GENERATION_ONLY
#define C128_PRODUCT_OVERLAY_RUNTIME
#define PLATFORM_PRODUCT_OVERLAY_RUNTIME

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $3000 "Test Code"

c128_restore_runtime_state:
    rts

#import "../../../../core/zeropage.s"
#import "test_helpers128.s"
#import "../memory128.s"

// config128.s is not imported by tests; the unit test links all data into one
// RAM bank, so the db thunks are direct accesses here.
mmu_safe_db_read_ptr0:
mmu_safe_huff_read_ptr0:
    lda (zp_ptr0),y
    rts
mmu_safe_db_write_ptr0:
    sta (zp_ptr0),y
    rts
mmu_safe_db_read_ptr1:
mmu_safe_huff_read_ptr1:
    lda (zp_ptr1),y
    rts
mmu_safe_db_write_ptr1:
    sta (zp_ptr1),y
    rts

#import "../../../../core/rng.s"
#import "../../../../core/math.s"
#import "../../../../core/tables.s"
#import "../../../../core/dungeon_data.s"

// Minimal player struct surface required by dungeon_gen.s.
// Bank 0 canaries at map-space addresses, above this test's code (asserted at the end).
.const SOAK_SENTINEL_HI = MAP_END
.const SOAK_SENTINEL_LO = MAP_END - $0eff
.const PL_MAP_X = 49
.const PL_MAP_Y = 50
player_data:
    .fill 80, 0

// C128 map-safe wrappers required by mmu_macros.s / dungeon_data.s.
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

// Real generation hooks, trimmed to generation-only sections so the soak tests
// production topology without pulling in monster/item/trap gameplay.
#import "../../../../core/dungeon_features.s"
#import "../../../../core/special_rooms.s"

tramp_assign_special_room:
    jmp assign_special_room
tramp_vault_seal_entrance:
    jmp vault_seal_entrance

#import "../../../../core/dungeon_gen.s"
#undef C128_PRODUCT_OVERLAY_RUNTIME
#undef PLATFORM_PRODUCT_OVERLAY_RUNTIME

seed_idx: .byte 0
iter_count: .byte 0
irq_before: .byte 0
tmp_x: .byte 0
tmp_y: .byte 0
audit_door_x: .byte 0
audit_door_y: .byte 0
audit_check_x: .byte 0
audit_check_y: .byte 0
audit_pair_count: .byte 0
audit_up_count: .byte 0
audit_dn_count: .byte 0
stairs_seen: .byte 0                  // bit 0: a level with 2 up, bit 1: one with 4 down
audit_mineral_lo: .byte 0
audit_mineral_hi: .byte 0
// Seen flags, not counts: a byte count wrapped to 0 at 256 quartz tiles
// (long soak, seed 1, level 66) and failed the audit.
audit_magma_seen: .byte 0
audit_quartz_seen: .byte 0
audit_connect_tile: .byte 0
c128_test_row_copy_count_lo: .byte 0
c128_test_row_copy_count_hi: .byte 0
c128_test_row_copy_expect_lo: .byte 0
c128_test_row_copy_expect_hi: .byte 0
c128_test_row_store_count_lo: .byte 0
c128_test_row_store_count_hi: .byte 0

// A runaway-walk guard only, not a density check: the generation contract
// sets no aggregate streamer density (DGN-004, not implemented), so the
// budget is the walk's own worst case.
// Upper bound for carve_streamer's upstream walk: a streamer starts at
// x >= MAP_COLS/2 + 15 - 32 and steps until it leaves 1..MAP_COLS-2, so it
// visits at most MAP_COLS-1 - (MAP_COLS/2 - 17) positions, stamping
// STREAMER_DENSITY tiles at each; place_streamers carves 5 streamers.
.const C128_STREAMER_MAX_STEPS = MAP_COLS - 1 - (floor(MAP_COLS / 2) - 17)
.const C128_STREAMER_MAX_TILES = 5 * STREAMER_DENSITY * C128_STREAMER_MAX_STEPS

// The gate runs the first seed's last SOAK_ITERS levels, a subset of the
// long soak (make test128-soak-long: 4 seeds x 50 levels). A level costs
// about 350M cycles on average, and the connectivity flood needs one full
// pass per tile a path runs against the scan, so some levels take far longer.
#if SOAK128_LONG
.const SOAK_SEEDS = 4
.const SOAK_ITERS = 50
#else
.const SOAK_SEEDS = 1
.const SOAK_ITERS = 4
#endif

seed_table:
    .byte $42, $13, $7a, $f1
    .byte $55, $aa, $33, $cc
    .byte $01, $23, $45, $67
    .byte $de, $ad, $be, $ef

test_start:
    sei
    cld
    ldx #$ff
    txs

    lda #MMU_ALL_RAM
    sta $ff00
    jsr init_common_mmu_helpers

    lda #0
    sta seed_idx

    // Streamers must only rewrite plain granite. This catches the C128 reveal
    // failure mode where veins rewrote structural wall bytes into huge bands.
    lda #TILE_WALL_V
    jsr map_bulk_fill_all
    jsr place_streamers
    jsr audit_no_minerals128
    bcc !ok_streamer_granite_only+
    jmp test_fail
!ok_streamer_granite_only:

    // Upstream places streamers after topology; they may rewrite only granite,
    // never existing floor/corridor cells.
    lda #TILE_FLOOR
    jsr map_bulk_fill_all
    jsr place_streamers
    jsr audit_no_minerals128
    bcc !ok_tunnel_clears_streamer+
    jmp test_fail
!ok_tunnel_clears_streamer:

    // A straight east/west door with an open north side is bypassable.
    lda #TILE_WALL_H
    jsr map_bulk_fill_all
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #19
    lda #TILE_FLOOR
    :MapWrite_ptr0_y()
    iny
    lda #TILE_DOOR_CLOSED
    :MapWrite_ptr0_y()
    iny
    lda #TILE_FLOOR
    :MapWrite_ptr0_y()
    ldx #19
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_FLOOR
    :MapWrite_ptr0_y()
    jsr audit_final_door_chokepoints128
    bcs !ok_t_door_rejected+
    jmp test_fail
!ok_t_door_rejected:

    // The C128 row cache and generation door list must remain disjoint. A door
    // on an early row catches later row copies overwriting its coordinates.
    lda #TILE_WALL_H
    jsr map_bulk_fill_all
    lda #1
    sta zp_player_dlvl
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_DOOR_CLOSED
    :MapWrite_ptr0_y()
    jsr place_secrets
    ldx #20
    ldy #10
    jsr map_get_tile
    and #TILE_TYPE_MASK
    cmp #TILE_SECRET
    beq !secret_door_ok+
    jmp test_fail
!secret_door_ok:

!seed_loop:
    lda #SOAK_ITERS
    sta iter_count

!iter_loop:
    // Deterministic per-iteration seed variant.
    ldx seed_idx
    txa
    asl
    asl
    tay
    lda seed_table,y
    eor iter_count
    sta zp_rng_0
    iny
    lda seed_table,y
    sta zp_rng_1
    iny
    lda seed_table,y
    sta zp_rng_2
    iny
    lda seed_table,y
    sta zp_rng_3

    // Vary depth deterministically in [1..8].
    lda iter_count
    and #$07
    clc
    adc #1
    sta zp_player_dlvl

    lda #0
    sta level_entry_dir

    // Bank0 sentinels at map-space addresses must survive generation.
    // They sit at the top of the map range, clear of this test's own code
    // (asserted below SOAK_SENTINEL_LO).
    jsr mmu_select_bank0
    lda #$a5
    sta SOAK_SENTINEL_LO
    lda #$5a
    sta SOAK_SENTINEL_HI

    php
    pla
    and #$04
    sta irq_before

    lda #0
    sta c128_test_row_copy_count_lo
    sta c128_test_row_copy_count_hi
    sta c128_test_row_store_count_lo
    sta c128_test_row_store_count_hi
    jsr dungeon_generate

    // The two finishing passes copy every row, and place_secrets copies every
    // interior row. Tunnel materialization must stay strictly below the old
    // room_count full-map scans.
    lda #0
    sta c128_test_row_copy_expect_lo
    sta c128_test_row_copy_expect_hi
    ldx room_count
    inx
    inx
!row_copy_expect_loop:
    clc
    lda c128_test_row_copy_expect_lo
    adc #MAP_ROWS
    sta c128_test_row_copy_expect_lo
    lda c128_test_row_copy_expect_hi
    adc #0
    sta c128_test_row_copy_expect_hi
    dex
    bne !row_copy_expect_loop-
    lda c128_test_row_copy_count_hi
    cmp c128_test_row_copy_expect_hi
    bcc !row_copy_below_old+
    bne !row_copy_fail+
    lda c128_test_row_copy_count_lo
    cmp c128_test_row_copy_expect_lo
    bcc !row_copy_below_old+
!row_copy_fail:
    jmp test_fail
!row_copy_below_old:
    lda c128_test_row_copy_count_lo
    sec
    sbc #<(MAP_ROWS * 3 - 2)
    lda c128_test_row_copy_count_hi
    sbc #>(MAP_ROWS * 3 - 2)
    bcs !row_copy_count_ok+
    jmp test_fail
!row_copy_count_ok:
    // blank_cave and fill_cave_granite each store every map row once.
    lda c128_test_row_store_count_lo
    cmp #<(MAP_ROWS * 2)
    beq !row_store_lo_ok+
    jmp test_fail
!row_store_lo_ok:
    lda c128_test_row_store_count_hi
    cmp #>(MAP_ROWS * 2)
    beq !row_store_count_ok+
    jmp test_fail
!row_store_count_ok:

    php
    pla
    and #$04
    cmp irq_before
    beq !ok_irq+
    jmp test_fail
!ok_irq:

    // Verify Bank0 sentinels remain unchanged (no bank leakage).
    lda SOAK_SENTINEL_LO
    cmp #$a5
    beq !ok_s0+
    jmp test_fail
!ok_s0:
    lda SOAK_SENTINEL_HI
    cmp #$5a
    beq !ok_s1+
    jmp test_fail
!ok_s1:

    // Basic generation invariant: at least 2 rooms.
    lda room_count
    cmp #2
    bcs !ok_rooms+
    jmp test_fail
!ok_rooms:

    // Stairs-up coordinates must be in bounds and tile must match.
    lda stairs_up_x
    cmp #MAP_COLS
    bcc !ok_upx+
    jmp test_fail
!ok_upx:
    sta tmp_x
    lda stairs_up_y
    cmp #MAP_ROWS
    bcc !ok_upy+
    jmp test_fail
!ok_upy:
    sta tmp_y
    ldx tmp_x
    ldy tmp_y
    jsr map_get_tile
    and #TILE_TYPE_MASK
    cmp #TILE_STAIRS_UP
    beq !ok_uptile+
    jmp test_fail
!ok_uptile:

    // First down-stairs must be valid and correctly typed.
    lda stairs_dn1_x
    cmp #MAP_COLS
    bcc !ok_dn1x+
    jmp test_fail
!ok_dn1x:
    sta tmp_x
    lda stairs_dn1_y
    cmp #MAP_ROWS
    bcc !ok_dn1y+
    jmp test_fail
!ok_dn1y:
    sta tmp_y
    ldx tmp_x
    ldy tmp_y
    jsr map_get_tile
    and #TILE_TYPE_MASK
    cmp #TILE_STAIRS_DN
    beq !ok_dn1tile+
    jmp test_fail
!ok_dn1tile:

    // Second down-stairs must be valid and correctly typed.
    lda stairs_dn2_x
    cmp #MAP_COLS
    bcc !ok_dn2x+
    jmp test_fail
!ok_dn2x:
    sta tmp_x
    lda stairs_dn2_y
    cmp #MAP_ROWS
    bcc !ok_dn2y+
    jmp test_fail
!ok_dn2y:
    sta tmp_y
    ldx tmp_x
    ldy tmp_y
    jsr map_get_tile
    and #TILE_TYPE_MASK
    cmp #TILE_STAIRS_DN
    beq !ok_dn2tile+
    jmp test_fail
!ok_dn2tile:

    // Upstream counts: randint(2) up and randint(2)+2 down; the extras
    // beyond these three tracked coordinates are untracked tiles (DGN-016).
    lda #0
    sta audit_up_count
    sta audit_dn_count
    sta audit_check_y
!stair_count_row:
    lda #0
    sta audit_check_x
!stair_count_col:
    ldx audit_check_x
    ldy audit_check_y
    jsr map_get_tile
    and #TILE_TYPE_MASK
    cmp #TILE_STAIRS_UP
    bne !not_up_stair+
    inc audit_up_count
!not_up_stair:
    cmp #TILE_STAIRS_DN
    bne !not_down_stair+
    inc audit_dn_count
!not_down_stair:
    inc audit_check_x
    lda audit_check_x
    cmp #MAP_COLS
    bne !stair_count_col-
    inc audit_check_y
    lda audit_check_y
    cmp #MAP_ROWS
    bne !stair_count_row-

    lda audit_up_count
    sec
    sbc #1
    cmp #2                        // up 1..2
    bcc !ok_up_count+
    jmp test_fail
!ok_up_count:
    lda audit_dn_count
    sec
    sbc #3
    cmp #2                        // down 3..4
    bcc !ok_down_count+
    jmp test_fail
!ok_down_count:
    // Over the long soak both upstream extremes must occur: the extra up
    // stair (randint(2) = 2) and the second extra down (randint(2) + 2 = 4).
    // The gate's 4 levels are too few to require them.
    lda audit_up_count
    cmp #2
    bne !no_up2+
    lda #1
    ora stairs_seen
    sta stairs_seen
!no_up2:
    lda audit_dn_count
    cmp #4
    bne !no_dn4+
    lda #2
    ora stairs_seen
    sta stairs_seen
!no_dn4:

    lda stairs_dn1_x
    sta tmp_x
    lda stairs_dn1_y
    sta tmp_y
    jsr audit_stair_room128
    cmp #$ff
    bne !ok_dn1_room+
    jmp test_fail
!ok_dn1_room:
    sta audit_door_x

    lda stairs_dn2_x
    sta tmp_x
    lda stairs_dn2_y
    sta tmp_y
    jsr audit_stair_room128
    cmp #$ff
    bne !ok_dn2_room+
    jmp test_fail
!ok_dn2_room:
    cmp audit_door_x
    bne !ok_down_rooms+
    jmp test_fail
!ok_down_rooms:

    jsr audit_no_occupied128
    bcc !ok_no_occupied+
    jmp test_fail
!ok_no_occupied:

    jsr audit_mineral_budget128
    bcc !ok_mineral_budget+
    jmp test_fail
!ok_mineral_budget:

    jsr audit_room_spacing128
    bcc !ok_room_spacing+
    jmp test_fail
!ok_room_spacing:

    jsr audit_final_door_chokepoints128
    bcc !ok_doors+
    jmp test_fail
!ok_doors:
    jsr audit_no_adjacent_doors128
    bcc !ok_no_adjacent_doors+
    jmp test_fail
!ok_no_adjacent_doors:
    jsr audit_connectivity128
    bcc !ok_connected+
    jmp test_fail
!ok_connected:

    // Town generation sanity pass (dlvl=0) to catch bank/map regressions.
    lda #0
    sta zp_player_dlvl

    // Bank0 sentinels must survive town generation as well.
    jsr mmu_select_bank0
    lda #$3c
    sta SOAK_SENTINEL_LO
    lda #$c3
    sta SOAK_SENTINEL_HI

    jsr town_generate

    lda SOAK_SENTINEL_LO
    cmp #$3c
    beq !ok_towns0+
    jmp test_fail
!ok_towns0:
    lda SOAK_SENTINEL_HI
    cmp #$c3
    beq !ok_towns1+
    jmp test_fail
!ok_towns1:

    // Top-left corner must be a lit+visited TL corner.
    ldx #0
    ldy #0
    jsr map_get_tile
    cmp #(TILE_CORNER_TL | TOWN_FLAGS)
    beq !ok_tcorner+
    jmp test_fail
!ok_tcorner:

    // Top-right town corner must land at the fixed umoria-derived width.
    ldx #TOWN_MAP_COLS - 1
    ldy #0
    jsr map_get_tile
    cmp #(TILE_CORNER_TR | TOWN_FLAGS)
    beq !ok_tcorner_tr+
    jmp test_fail
!ok_tcorner_tr:

    // Bottom-right town corner must land at the fixed umoria-derived height.
    ldx #TOWN_MAP_COLS - 1
    ldy #TOWN_MAP_ROWS - 1
    jsr map_get_tile
    cmp #(TILE_CORNER_BR | TOWN_FLAGS)
    beq !ok_tcorner_br+
    jmp test_fail
!ok_tcorner_br:

    // Town down-stairs at the new lower-center position.
    ldx #TOWN_STAIRS_X
    ldy #TOWN_STAIRS_Y
    jsr map_get_tile
    and #TILE_TYPE_MASK
    cmp #TILE_STAIRS_DN
    beq !ok_tstairs+
    jmp test_fail
!ok_tstairs:

    // Sample two known store doors from the shared 4x2 town layout.
    ldx #15
    ldy #6
    jsr map_get_tile
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    beq !ok_tdoor1+
    jmp test_fail
!ok_tdoor1:
    ldx #51
    ldy #16
    jsr map_get_tile
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    beq !ok_tdoor2+
    jmp test_fail
!ok_tdoor2:

    // The larger C128 backing map must remain blocked outside the 66x22 town.
    ldx #TOWN_MAP_COLS
    ldy #TOWN_STAIRS_Y
    jsr map_get_tile
    and #TILE_TYPE_MASK
    cmp #TILE_WALL_H
    beq !ok_toutside+
    jmp test_fail
!ok_toutside:

    jmp !iter_continue+

test_fail:
    jmp test_fail

!iter_continue:
    dec iter_count
    beq !seed_done+
    jmp !iter_loop-
!seed_done:

    inc seed_idx
    lda seed_idx
    cmp #SOAK_SEEDS
    beq !all_done+
    jmp !seed_loop-
!all_done:
#if SOAK128_LONG
    lda stairs_seen
    cmp #3
    beq !stairs_ok+
    jmp test_fail
!stairs_ok:
#endif

    jmp test_pass

test_pass:
    jmp test_pass

audit_coord_passable128:
    ldx audit_check_x
    ldy audit_check_y
    jsr map_get_tile
    jmp vc_tile_is_passable

audit_connectivity128:
    lda #~FLAG_OCCUPIED & $ff
    jsr map_bulk_and_all

    ldx stairs_up_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy stairs_up_x
    :MapRead_ptr0_y()
    ora #FLAG_OCCUPIED
    :MapWrite_ptr0_y()

!ac128_pass:
    lda #0
    sta vc_changed
    sta bfs_cur_y
!ac128_row:
    ldx bfs_cur_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    lda #0
    sta bfs_cur_x
!ac128_col:
    ldy bfs_cur_x
    :MapRead_ptr0_y()
    sta audit_connect_tile
    and #FLAG_OCCUPIED
    bne !ac128_next_col+
    lda audit_connect_tile
    jsr vc_tile_is_passable
    bcc !ac128_next_col+
    jsr vc_has_visited_neighbor
    bcc !ac128_next_col+
    ldy bfs_cur_x
    lda audit_connect_tile
    ora #FLAG_OCCUPIED
    :MapWrite_ptr0_y()
    lda #1
    sta vc_changed
!ac128_next_col:
    inc bfs_cur_x
    lda bfs_cur_x
    cmp #MAP_COLS
    bne !ac128_col-
    inc bfs_cur_y
    lda bfs_cur_y
    cmp #MAP_ROWS
    bne !ac128_row-
    lda vc_changed
    bne !ac128_pass-

    ldx #0
!ac128_check_room:
    cpx room_count
    bcs !ac128_ok+
    stx bfs_cur_x
    ldy room_y,x
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldy room_x,x
    :MapRead_ptr0_y()
    and #FLAG_OCCUPIED
    beq !ac128_fail+
    ldx bfs_cur_x
    inx
    jmp !ac128_check_room-

!ac128_ok:
    lda #~FLAG_OCCUPIED & $ff
    jsr map_bulk_and_all
    clc
    rts
!ac128_fail:
    lda #~FLAG_OCCUPIED & $ff
    jsr map_bulk_and_all
    sec
    rts

audit_no_occupied128:
    lda #0
    sta audit_check_y
!ano128_row:
    lda #0
    sta audit_check_x
!ano128_col:
    ldx audit_check_x
    ldy audit_check_y
    jsr map_get_tile
    and #FLAG_OCCUPIED
    bne !ano128_fail+
    inc audit_check_x
    lda audit_check_x
    cmp #MAP_COLS
    bne !ano128_col-
    inc audit_check_y
    lda audit_check_y
    cmp #MAP_ROWS
    bne !ano128_row-
    clc
    rts
!ano128_fail:
    sec
    rts

audit_no_minerals128:
    lda #0
    sta audit_check_y
!anm128_row:
    lda #0
    sta audit_check_x
!anm128_col:
    ldx audit_check_x
    ldy audit_check_y
    jsr map_get_tile
    and #TILE_TYPE_MASK
    cmp #TILE_MAGMA
    beq !anm128_fail+
    cmp #TILE_QUARTZ
    beq !anm128_fail+
    inc audit_check_x
    lda audit_check_x
    cmp #MAP_COLS
    bne !anm128_col-
    inc audit_check_y
    lda audit_check_y
    cmp #MAP_ROWS
    bne !anm128_row-
    clc
    rts
!anm128_fail:
    sec
    rts

audit_mineral_budget128:
    lda #0
    sta audit_mineral_lo
    sta audit_mineral_hi
    sta audit_magma_seen
    sta audit_quartz_seen
    sta audit_check_y
!amb128_row:
    lda #0
    sta audit_check_x
!amb128_col:
    ldx audit_check_x
    ldy audit_check_y
    jsr map_get_tile
    and #TILE_TYPE_MASK
    cmp #TILE_MAGMA
    beq !amb128_count_magma+
    cmp #TILE_QUARTZ
    bne !amb128_next+
    lda #1
    sta audit_quartz_seen
    jmp !amb128_count+
!amb128_count_magma:
    lda #1
    sta audit_magma_seen
!amb128_count:
    inc audit_mineral_lo
    bne !amb128_next+
    inc audit_mineral_hi
!amb128_next:
    inc audit_check_x
    lda audit_check_x
    cmp #MAP_COLS
    bne !amb128_col-
    inc audit_check_y
    lda audit_check_y
    cmp #MAP_ROWS
    bne !amb128_row-

    lda audit_mineral_hi
    cmp #>C128_STREAMER_MAX_TILES
    bcc !amb128_ok+
    bne !amb128_fail+
    lda audit_mineral_lo
    cmp #<(C128_STREAMER_MAX_TILES + 1)
    bcc !amb128_ok+
!amb128_fail:
    sec
    rts
!amb128_ok:
    lda audit_magma_seen
    beq !amb128_fail-
    lda audit_quartz_seen
    beq !amb128_fail-
    clc
    rts

audit_stair_room128:
    lda #0
    sta audit_pair_count
!asr128_loop:
    ldx audit_pair_count
    cpx room_count
    bcs !asr128_not_found+

    lda tmp_x
    cmp room_x,x
    bcc !asr128_next+
    lda room_x,x
    clc
    adc room_w,x
    cmp tmp_x
    bcc !asr128_next+

    lda tmp_y
    cmp room_y,x
    bcc !asr128_next+
    lda room_y,x
    clc
    adc room_h,x
    cmp tmp_y
    bcc !asr128_next+

    lda audit_pair_count
    rts

!asr128_next:
    inc audit_pair_count
    jmp !asr128_loop-
!asr128_not_found:
    lda #$ff
    rts

audit_room_spacing128:
    lda #1
    sta audit_pair_count
!ars128_loop:
    lda audit_pair_count
    cmp room_count
    bcs !ars128_ok+
    tax
    lda room_x,x
    sta dg_room_x
    lda room_y,x
    sta dg_room_y
    lda room_w,x
    sta dg_room_w
    lda room_h,x
    sta dg_room_h
    lda audit_pair_count
    sta dg_idx
    jsr check_room_overlap
    bcs !ars128_fail+
    inc audit_pair_count
    jmp !ars128_loop-
!ars128_ok:
    clc
    rts
!ars128_fail:
    sec
    rts

audit_no_adjacent_doors128:
    lda #1
    sta audit_door_y
!anad128_row:
    lda #1
    sta audit_door_x
!anad128_col:
    ldx audit_door_x
    ldy audit_door_y
    jsr map_get_tile
    jsr audit_tile_is_door128
    bcc !anad128_next+

    lda audit_door_x
    clc
    adc #1
    sta audit_check_x
    lda audit_door_y
    sta audit_check_y
    ldx audit_check_x
    ldy audit_check_y
    jsr map_get_tile
    jsr audit_tile_is_door128
    bcs !anad128_fail+

    lda audit_door_x
    sta audit_check_x
    lda audit_door_y
    clc
    adc #1
    sta audit_check_y
    ldx audit_check_x
    ldy audit_check_y
    jsr map_get_tile
    jsr audit_tile_is_door128
    bcs !anad128_fail+

!anad128_next:
    inc audit_door_x
    lda audit_door_x
    cmp #MAP_COLS - 2
    bne !anad128_col-
    inc audit_door_y
    lda audit_door_y
    cmp #MAP_ROWS - 2
    bne !anad128_row-
    clc
    rts
!anad128_fail:
    sec
    rts

audit_tile_is_door128:
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    beq !atid128_yes+
    cmp #TILE_DOOR_CLOSED
    beq !atid128_yes+
    cmp #TILE_SECRET
    beq !atid128_yes+
    clc
    rts
!atid128_yes:
    sec
    rts

audit_final_door_chokepoints128:
    lda #~FLAG_OCCUPIED & $ff
    jsr map_bulk_and_all
    lda #1
    sta audit_door_y
!afd128_row:
    lda #1
    sta audit_door_x
!afd128_col:
    ldx audit_door_x
    ldy audit_door_y
    jsr map_get_tile
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    beq !afd128_check+
    cmp #TILE_DOOR_CLOSED
    beq !afd128_check+
    cmp #TILE_SECRET
    bne !afd128_next+
!afd128_check:
    jsr audit_one_door_chokepoint128
    bcs !afd128_fail+
!afd128_next:
    inc audit_door_x
    lda audit_door_x
    cmp #MAP_COLS - 1
    bne !afd128_col-
    inc audit_door_y
    lda audit_door_y
    cmp #MAP_ROWS - 1
    bne !afd128_row-
    clc
    rts
!afd128_fail:
    sec
    rts

audit_one_door_chokepoint128:
    lda audit_door_x
    sta dg_cx1
    lda audit_door_y
    sta dg_cy1
    lda audit_door_x
    sec
    sbc #1
    sta audit_check_x
    lda audit_door_y
    sta audit_check_y
    jsr audit_coord_passable128
    bcc !aod128_try_vertical+
    lda audit_door_x
    clc
    adc #1
    sta audit_check_x
    lda audit_door_y
    sta audit_check_y
    jsr audit_coord_passable128
    bcc !aod128_try_vertical+
    lda audit_door_x
    sta dg_room_x
    lda audit_door_y
    sta dg_room_y
    jsr jdg_opposing_vertical
    bcs !aod128_pass+
    jmp !aod128_fail+

!aod128_try_vertical:
    lda audit_door_x
    sta audit_check_x
    lda audit_door_y
    sec
    sbc #1
    sta audit_check_y
    jsr audit_coord_passable128
    bcc !aod128_fail+
    lda audit_door_x
    sta audit_check_x
    lda audit_door_y
    clc
    adc #1
    sta audit_check_y
    jsr audit_coord_passable128
    bcc !aod128_fail+
    lda audit_door_x
    sta dg_room_x
    lda audit_door_y
    sta dg_room_y
    jsr jdg_opposing_horizontal
    bcc !aod128_fail+
!aod128_pass:
    clc
    rts
!aod128_fail:
    sec
    rts

soak_code_end:
.assert "Soak test code stays below its Bank 0 sentinels", soak_code_end <= SOAK_SENTINEL_LO, true
