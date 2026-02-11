// test_monster_ai.s — Runtime tests for monster_ai.s
//
// Tests: monster_ai_tick, wake check, movement, speed, FLAG_OCCUPIED,
//        confused movement.
//
// Results at $0400-$0409: $01 = pass, $00 = fail per test

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $0810 "Test Code"

.encoding "screencode_upper"

#import "../zeropage.s"
#import "../memory.s"
#import "../screen.s"
#import "../color.s"
#import "../config.s"
#import "../input.s"
#import "../rng.s"
#import "../math.s"
#import "../tables.s"
#import "../player.s"
#import "../ui_messages.s"
#import "../ui_status.s"
#import "../ui_character.s"
#import "../player_create.s"
#import "../sound.s"
#import "../dungeon_gen.s"
#import "../dungeon_features.s"
#import "../monster.s"
#import "../monster_ai.s"
#import "../dungeon_render.s"
#import "../dungeon_los.s"
#import "../player_move.s"
#import "../turn.s"

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test scratch
tai_save_x: .byte 0
tai_save_y: .byte 0
tai_ok:     .byte 0
tai_count:  .byte 0

test_start:
    // Bank out BASIC ROM (needed for $A000 area used by BFS)
    :BankOutBasic()

    // Initialize result area to $ff (untested)
    ldx #15
    lda #$ff
!clr:
    sta $0400,x
    dex
    bpl !clr-

    // Seed RNG deterministically
    lda #$42
    sta zp_rng_0
    lda #$13
    sta zp_rng_1
    lda #$7a
    sta zp_rng_2
    lda #$f1
    sta zp_rng_3

    // Set player dungeon level to 1
    lda #1
    sta zp_player_dlvl

    // Set light radius
    lda #1
    sta zp_light_radius

    // Generate a dungeon level for all tests
    lda #0
    sta level_entry_dir
    jsr level_generate

    // ==========================================
    // Test 1: monster_ai_tick with empty table — no crash
    // ==========================================
    jsr monster_init_table

    // Put player somewhere
    lda #20
    sta zp_player_x
    lda #20
    sta zp_player_y

    jsr monster_ai_tick

    // If we got here without crashing, it's a pass
    // Also check count is still 0
    lda zp_mon_count
    bne !t1_fail+
    lda #$01
    sta $0400
    jmp !t2+
!t1_fail:
    lda #$00
    sta $0400

    // ==========================================
    // Test 2: Immobile monster (speed=0) doesn't move
    // Type 6 (Shrieker mushroom) — speed=0
    // ==========================================
!t2:
    jsr monster_init_table

    // Place a floor tile at (30, 20) and spawn mushroom there
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #30
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    lda #30
    sta ms_spawn_x
    lda #20
    sta ms_spawn_y
    lda #6                      // Shrieker mushroom (speed=0)
    jsr monster_spawn_one

    // Save position
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    sta tai_save_x
    ldy #MX_Y
    lda (zp_ptr0),y
    sta tai_save_y

    // Put player nearby to potentially trigger wake
    lda #31
    sta zp_player_x
    lda #20
    sta zp_player_y

    // Run AI tick
    jsr monster_ai_tick

    // Check position unchanged
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp tai_save_x
    bne !t2_fail+
    ldy #MX_Y
    lda (zp_ptr0),y
    cmp tai_save_y
    bne !t2_fail+

    lda #$01
    sta $0401
    jmp !t3+
!t2_fail:
    lda #$00
    sta $0401

    // ==========================================
    // Test 3: Wake check — monster with sleep=0 within AAF range wakes
    // Type 9 (Jackal) — sleep=0, aaf=12
    // ==========================================
!t3:
    jsr monster_init_table

    // Place floor at (25, 20)
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #25
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    lda #25
    sta ms_spawn_x
    lda #20
    sta ms_spawn_y
    lda #9                      // Jackal (sleep=0, aaf=12)
    jsr monster_spawn_one

    // Place player within AAF range (distance=5)
    lda #30
    sta zp_player_x
    lda #20
    sta zp_player_y

    // Run AI tick
    jsr monster_ai_tick

    // Check MF_AWAKE is set
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_AWAKE
    bne !t3_pass+
    lda #$00
    sta $0402
    jmp !t4+
!t3_pass:
    lda #$01
    sta $0402

    // ==========================================
    // Test 4: Wake check — monster outside AAF range stays asleep
    // Type 9 (Jackal) — aaf=12
    // ==========================================
!t4:
    jsr monster_init_table

    // Place floor at (10, 10)
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    lda #10
    sta ms_spawn_x
    lda #10
    sta ms_spawn_y
    lda #9                      // Jackal (aaf=12)
    jsr monster_spawn_one

    // Place player far away (distance > 12)
    lda #40
    sta zp_player_x
    lda #40
    sta zp_player_y

    // Run AI tick
    jsr monster_ai_tick

    // Check MF_AWAKE is NOT set
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_AWAKE
    beq !t4_pass+
    lda #$00
    sta $0403
    jmp !t5+
!t4_pass:
    lda #$01
    sta $0403

    // ==========================================
    // Test 5: Awake monster moves toward player
    // Place monster, set awake, verify distance decreases
    // ==========================================
!t5:
    jsr monster_init_table

    // Create a clear corridor: floor tiles from (20,15) to (30,15)
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
!t5_fill:
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    iny
    cpy #31
    bne !t5_fill-

    // Spawn type 4 (Kobold, speed=1) at (20,15)
    lda #20
    sta ms_spawn_x
    lda #15
    sta ms_spawn_y
    lda #4
    jsr monster_spawn_one

    // Manually set MF_AWAKE
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y

    // Player at (30, 15) — distance=10
    lda #30
    sta zp_player_x
    lda #15
    sta zp_player_y

    // Run AI tick
    jsr monster_ai_tick

    // Check monster moved closer to player (x increased from 20)
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #21                     // Should have moved from 20 to 21
    bne !t5_fail+
    lda #$01
    sta $0404
    jmp !t6+
!t5_fail:
    lda #$00
    sta $0404

    // ==========================================
    // Test 6: Monster blocked by wall finds alternate path
    // Wall in diagonal, should try horizontal or vertical
    // ==========================================
!t6:
    jsr monster_init_table

    // Set up: monster at (20,15), player at (22,14)
    // Block diagonal (21,14) with a wall, leave (21,15) and (20,14) as floor

    // Floor at (20,15)
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    // Floor at (21,15)
    ldy #21
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    // Floor at (22,15)
    ldy #22
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    // Row 14: wall at (21,14), floor at (20,14), floor at (22,14)
    ldx #14
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    ldy #21
    lda #TILE_WALL_H | FLAG_LIT // Wall blocks diagonal
    sta (zp_ptr0),y
    ldy #22
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    // Spawn monster at (20,15)
    lda #20
    sta ms_spawn_x
    lda #15
    sta ms_spawn_y
    lda #4                      // Kobold
    jsr monster_spawn_one

    // Set awake
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y

    // Player at (22,14)
    lda #22
    sta zp_player_x
    lda #14
    sta zp_player_y

    // Run AI tick — diagonal (21,14) is wall, should try horizontal (21,15)
    jsr monster_ai_tick

    // Monster should be at (21,15) — moved horizontally
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #21
    bne !t6_fail+
    ldy #MX_Y
    lda (zp_ptr0),y
    cmp #15
    bne !t6_fail+

    lda #$01
    sta $0405
    jmp !t7+
!t6_fail:
    lda #$00
    sta $0405

    // ==========================================
    // Test 7: Monster doesn't step on player position
    // Monster adjacent to player — should NOT move onto player
    // ==========================================
!t7:
    jsr monster_init_table

    // Floor at (25,15) and (26,15)
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #25
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    ldy #26
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    // Spawn monster at (25,15)
    lda #25
    sta ms_spawn_x
    lda #15
    sta ms_spawn_y
    lda #4                      // Kobold
    jsr monster_spawn_one

    // Set awake
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y

    // Player at (26,15) — adjacent!
    lda #26
    sta zp_player_x
    lda #15
    sta zp_player_y

    // Run AI tick
    jsr monster_ai_tick

    // Monster should stay at (25,15) — can't step on player
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #25
    bne !t7_fail+
    ldy #MX_Y
    lda (zp_ptr0),y
    cmp #15
    bne !t7_fail+

    lda #$01
    sta $0406
    jmp !t8+
!t7_fail:
    lda #$00
    sta $0406

    // ==========================================
    // Test 8: Speed 2 monster moves twice per tick
    // Type 15 (Wild cat) — speed=2
    // ==========================================
!t8:
    jsr monster_init_table

    // Create floor corridor from (20,15) to (30,15)
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
!t8_fill:
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    iny
    cpy #31
    bne !t8_fill-

    // Spawn wild cat at (20,15)
    lda #20
    sta ms_spawn_x
    lda #15
    sta ms_spawn_y
    lda #15                     // Wild cat (speed=2)
    jsr monster_spawn_one

    // Set awake
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y

    // Player at (30,15) — distance=10
    lda #30
    sta zp_player_x
    lda #15
    sta zp_player_y

    // Run AI tick
    jsr monster_ai_tick

    // Monster should be at (22,15) — moved 2 tiles (speed=2)
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #22
    bne !t8_fail+

    lda #$01
    sta $0407
    jmp !t9+
!t8_fail:
    lda #$00
    sta $0407

    // ==========================================
    // Test 9: FLAG_OCCUPIED updated correctly on move
    // Old tile should have flag cleared, new tile should have it set
    // ==========================================
!t9:
    jsr monster_init_table

    // Floor at (20,20) and (21,20)
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    ldy #21
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    // Spawn Kobold at (20,20)
    lda #20
    sta ms_spawn_x
    lda #20
    sta ms_spawn_y
    lda #4
    jsr monster_spawn_one

    // Set awake
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y

    // Player at (30,20)
    lda #30
    sta zp_player_x
    lda #20
    sta zp_player_y

    // Run AI tick — monster should move from (20,20) to (21,20)
    jsr monster_ai_tick

    // Check old tile (20,20) — FLAG_OCCUPIED should be CLEAR
    ldx #20
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda (zp_ptr0),y
    and #FLAG_OCCUPIED
    bne !t9_fail+

    // Check new tile (21,20) — FLAG_OCCUPIED should be SET
    ldy #21
    lda (zp_ptr0),y
    and #FLAG_OCCUPIED
    beq !t9_fail+

    lda #$01
    sta $0408
    jmp !t10+
!t9_fail:
    lda #$00
    sta $0408

    // ==========================================
    // Test 10: Confused monster moves randomly
    // Run several times, check that position changes at least once
    // ==========================================
!t10:
    lda #0
    sta tai_ok                  // Track if any movement happened

    lda #5
    sta tai_count               // Try up to 5 iterations

!t10_retry:
    jsr monster_init_table

    // Create a 5x5 floor area around (25,25) for random movement
    ldx #23
!t10_row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #23
!t10_col:
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    iny
    cpy #28
    bne !t10_col-
    inx
    cpx #28
    bne !t10_row-

    // Spawn Kobold at (25,25)
    lda #25
    sta ms_spawn_x
    lda #25
    sta ms_spawn_y
    lda #4
    jsr monster_spawn_one

    // Set awake AND confused
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #MF_AWAKE | MF_CONFUSED
    sta (zp_ptr0),y

    // Player far away (won't affect direction)
    lda #5
    sta zp_player_x
    lda #5
    sta zp_player_y

    // Run AI tick
    jsr monster_ai_tick

    // Check if monster moved from (25,25)
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #25
    bne !t10_moved+
    ldy #MX_Y
    lda (zp_ptr0),y
    cmp #25
    beq !t10_nomove+

!t10_moved:
    lda #1
    sta tai_ok

!t10_nomove:
    dec tai_count
    bne !t10_retry-

    // After 5 tries, check if at least one moved
    lda tai_ok
    beq !t10_fail+
    lda #$01
    sta $0409
    jmp !tests_done+
!t10_fail:
    lda #$00
    sta $0409

!tests_done:
    brk
