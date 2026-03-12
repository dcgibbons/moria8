// test_soak128.s — C128 generation soak/integrity test for C4.7
//
// Runs 200 total dungeon generations (4 deterministic seed variants x 50).
// Fails on:
// - IRQ-state drift across dungeon_generate
// - Bank 0 map-address leakage at $4000/$4EFF
// - Invalid room/stairs invariants

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $3000 "Test Code"

c128_runtime_state_current: .byte 0

#import "../../common/zeropage.s"
#import "../memory128.s"
#import "../../common/rng.s"
#import "../../common/math.s"
#import "../../common/tables.s"
#import "../../common/dungeon_data.s"

// Minimal player struct surface required by dungeon_gen.s.
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

map_bulk_enter:
    jsr mmu_select_bank1
    rts

map_bulk_exit:
    jsr mmu_select_bank0
    rts

// Minimal generation-path stubs for features outside C4.7 soak scope.
trap_count: .byte 0
place_traps: rts
place_secrets: rts
tramp_assign_special_room: rts
tramp_vault_seal_entrance: rts

#import "../../common/dungeon_gen.s"

seed_idx: .byte 0
iter_count: .byte 0
irq_before: .byte 0
tmp_x: .byte 0
tmp_y: .byte 0

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

    lda #0
    sta seed_idx

!seed_loop:
    lda #50
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
    jsr mmu_select_bank0
    lda #$a5
    sta $4000
    lda #$5a
    sta $4eff

    php
    pla
    and #$04
    sta irq_before

    jsr dungeon_generate

    php
    pla
    and #$04
    cmp irq_before
    beq !ok_irq+
    jmp test_fail
!ok_irq:

    // Verify Bank0 sentinels remain unchanged (no bank leakage).
    lda $4000
    cmp #$a5
    beq !ok_s0+
    jmp test_fail
!ok_s0:
    lda $4eff
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
    // Town generation sanity pass (dlvl=0) to catch bank/map regressions.
    lda #0
    sta zp_player_dlvl

    // Bank0 sentinels must survive town generation as well.
    jsr mmu_select_bank0
    lda #$3c
    sta $4000
    lda #$c3
    sta $4eff

    jsr town_generate

    lda $4000
    cmp #$3c
    beq !ok_towns0+
    jmp test_fail
!ok_towns0:
    lda $4eff
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

    // Town down-stairs at (40,24).
    ldx #40
    ldy #24
    jsr map_get_tile
    and #TILE_TYPE_MASK
    cmp #TILE_STAIRS_DN
    beq !ok_tstairs+
    jmp test_fail
!ok_tstairs:

    // Sample two known store doors: (10,7) and (60,24) must be open doors.
    ldx #10
    ldy #7
    jsr map_get_tile
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    beq !ok_tdoor1+
    jmp test_fail
!ok_tdoor1:
    ldx #60
    ldy #24
    jsr map_get_tile
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    beq !ok_tdoor2+
    jmp test_fail
!ok_tdoor2:

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
    cmp #4
    beq !all_done+
    jmp !seed_loop-
!all_done:

    jmp test_pass

test_pass:
    jmp test_pass
