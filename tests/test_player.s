// test_player.s — Runtime tests for player.s and tables.s
//
// Tests stat calculation, HP calculation, and data table integrity.
// No interactive input required — sets player data directly.
//
// Results at $0400: $01 = pass per test

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $0810 "Test Code"

#import "../zeropage.s"
#import "../memory.s"
#import "../screen.s"
#import "../color.s"
#import "../input.s"
#import "../rng.s"
#import "../math.s"
#import "../tables.s"
#import "../player.s"

test_start:
    // Init results
    ldx #15
    lda #$ff
!clr:
    sta $0400,x
    dex
    bpl !clr-

    // ==========================================
    // Test 1: player_init zeroes the struct
    // ==========================================
    // Write garbage first
    lda #$aa
    ldx #PL_STRUCT_SIZE - 1
!fill:
    sta player_data,x
    dex
    bpl !fill-

    jsr player_init

    // Check a few fields
    lda player_data + PL_LEVEL
    bne !t1_fail+
    lda player_data + PL_STR_BASE
    bne !t1_fail+
    lda player_data + PL_HP_LO
    bne !t1_fail+
    lda #$01
    sta $0400
    jmp !t1_done+
!t1_fail:
    lda #$00
    sta $0400
!t1_done:

    // ==========================================
    // Test 2: Human Warrior stat calc (no modifiers)
    // Set base stats to 10, race=Human, class=Warrior
    // Human: 0,0,0,0,0,0. Warrior: +5,-2,-2,+2,+2,-1
    // Expected: 15,8,8,12,12,9
    // ==========================================
    jsr player_init
    lda #RACE_HUMAN
    sta player_data + PL_RACE
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    lda #1
    sta player_data + PL_LEVEL

    // Set all base stats to 10
    ldx #5
    lda #10
!set10:
    sta player_data + PL_STR_BASE,x
    dex
    bpl !set10-

    jsr player_calc_stats

    // Check: STR should be 10+0+5 = 15
    lda player_data + PL_STR_CUR
    cmp #15
    bne !t2_fail+
    // INT should be 10+0-2 = 8
    lda player_data + PL_INT_CUR
    cmp #8
    bne !t2_fail+
    // DEX should be 10+0+2 = 12
    lda player_data + PL_DEX_CUR
    cmp #12
    bne !t2_fail+
    // CON should be 10+0+2 = 12
    lda player_data + PL_CON_CUR
    cmp #12
    bne !t2_fail+
    lda #$01
    sta $0401
    jmp !t2_done+
!t2_fail:
    lda #$00
    sta $0401
!t2_done:

    // ==========================================
    // Test 3: Dwarf Priest stat calc
    // Base 10 for all. Dwarf: +2,-3,+1,-2,+2,-3
    // Priest: -3,-3,+3,-1,0,+2
    // Expected: 10+2-3=9, 10-3-3=4→clamped 4, 10+1+3=14,
    //           10-2-1=7, 10+2+0=12, 10-3+2=9
    // ==========================================
    jsr player_init
    lda #RACE_DWARF
    sta player_data + PL_RACE
    lda #CLASS_PRIEST
    sta player_data + PL_CLASS
    lda #1
    sta player_data + PL_LEVEL

    ldx #5
    lda #10
!set10b:
    sta player_data + PL_STR_BASE,x
    dex
    bpl !set10b-

    jsr player_calc_stats

    // STR: 10+2-3 = 9
    lda player_data + PL_STR_CUR
    cmp #9
    bne !t3_fail+
    // INT: 10-3-3 = 4
    lda player_data + PL_INT_CUR
    cmp #4
    bne !t3_fail+
    // WIS: 10+1+3 = 14
    lda player_data + PL_WIS_CUR
    cmp #14
    bne !t3_fail+
    // DEX: 10-2-1 = 7
    lda player_data + PL_DEX_CUR
    cmp #7
    bne !t3_fail+
    lda #$01
    sta $0402
    jmp !t3_done+
!t3_fail:
    lda #$00
    sta $0402
!t3_done:

    // ==========================================
    // Test 4: Stat clamping (low end)
    // Half-Troll Mage: STR base 3 → 3+4-5=2→clamp 3
    // ==========================================
    jsr player_init
    lda #RACE_HALF_TROLL
    sta player_data + PL_RACE
    lda #CLASS_MAGE
    sta player_data + PL_CLASS
    lda #1
    sta player_data + PL_LEVEL

    lda #3
    ldx #5
!set3:
    sta player_data + PL_STR_BASE,x
    dex
    bpl !set3-

    jsr player_calc_stats

    // STR: 3+4-5=2 → clamped to 3
    lda player_data + PL_STR_CUR
    cmp #3
    bne !t4_fail+
    lda #$01
    sta $0403
    jmp !t4_done+
!t4_fail:
    lda #$00
    sta $0403
!t4_done:

    // ==========================================
    // Test 5: 18/xx stats (high end)
    // Half-Troll Warrior: STR base 18, race +4, class +5
    // With increment_stat, each +1 above 18 uses random steps
    // Result must be in 18/xx range (19-118)
    // ==========================================
    jsr player_init
    lda #RACE_HALF_TROLL
    sta player_data + PL_RACE
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    lda #1
    sta player_data + PL_LEVEL

    lda #18
    ldx #5
!set18:
    sta player_data + PL_STR_BASE,x
    dex
    bpl !set18-

    jsr player_calc_stats

    // STR must be >= 19 (entered 18/xx range)
    lda player_data + PL_STR_CUR
    cmp #19
    bcc !t5_fail+
    // STR must be <= 118 (capped at 18/100)
    cmp #119
    bcs !t5_fail+
    lda #$01
    sta $0404
    jmp !t5_done+
!t5_fail:
    lda #$00
    sta $0404
!t5_done:

    // ==========================================
    // Test 6: HP calculation — Warrior level 1
    // Warrior HD=9, CON=12 → CON bonus=0
    // Max HP = 9 (hit die only at level 1)
    // ==========================================
    jsr player_init
    lda #RACE_HUMAN
    sta player_data + PL_RACE
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    lda #1
    sta player_data + PL_LEVEL
    lda #12
    sta player_data + PL_CON_CUR

    jsr player_calc_hp

    lda player_data + PL_MHP_LO
    cmp #9
    bne !t6_fail+
    lda player_data + PL_MHP_HI
    cmp #0
    bne !t6_fail+
    lda #$01
    sta $0405
    jmp !t6_done+
!t6_fail:
    lda #$00
    sta $0405
!t6_done:

    // ==========================================
    // Test 7: HP calculation — Warrior level 5
    // HD=9, CON=12→bonus=0. HP = 9 + 4*(9/2+0) = 9+4*4 = 25
    // ==========================================
    lda #5
    sta player_data + PL_LEVEL

    jsr player_calc_hp

    lda player_data + PL_MHP_LO
    cmp #25
    bne !t7_fail+
    lda #$01
    sta $0406
    jmp !t7_done+
!t7_fail:
    lda #$00
    sta $0406
!t7_done:

    // ==========================================
    // Test 8: Race class restriction — Dwarf can be Warrior
    // ==========================================
    ldx #RACE_DWARF
    lda race_class_flags,x
    and #(1 << CLASS_WARRIOR)
    beq !t8_fail+
    lda #$01
    sta $0407
    jmp !t8_done+
!t8_fail:
    lda #$00
    sta $0407
!t8_done:

    // ==========================================
    // Test 9: Race class restriction — Dwarf cannot be Mage
    // ==========================================
    ldx #RACE_DWARF
    lda race_class_flags,x
    and #(1 << CLASS_MAGE)
    bne !t9_fail+
    lda #$01
    sta $0408
    jmp !t9_done+
!t9_fail:
    lda #$00
    sta $0408
!t9_done:

    // ==========================================
    // Test 10: ZP sync round-trip
    // ==========================================
    jsr player_init
    lda #42
    sta player_data + PL_MAP_X
    lda #7
    sta player_data + PL_MAP_Y
    lda #99
    sta player_data + PL_HP_LO

    jsr player_sync_to_zp

    // Verify ZP
    lda zp_player_x
    cmp #42
    bne !t10_fail+
    lda zp_player_y
    cmp #7
    bne !t10_fail+
    lda zp_player_hp_lo
    cmp #99
    bne !t10_fail+

    // Modify ZP and sync back
    lda #50
    sta zp_player_x
    jsr player_sync_from_zp
    lda player_data + PL_MAP_X
    cmp #50
    bne !t10_fail+

    lda #$01
    sta $0409
    jmp !t10_done+
!t10_fail:
    lda #$00
    sta $0409
!t10_done:

    brk
