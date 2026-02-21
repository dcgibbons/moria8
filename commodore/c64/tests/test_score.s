// test_score.s — Runtime tests for score calculation, 24-bit math, and hiscore
//
// Tests: math_add_24 basic, math_add_24 carry, math_cmp_24 equal/lt/gt,
//        score_calculate, screen_put_decimal_24,
//        hiscore_insert empty/ordering/overflow
// NOTE: score_io.s is NOT imported — hiscore_table aliases CREATURE_BASE
//       ($C020) which overlaps test code. Local definitions redirect
//       hiscore_table to a safe buffer within the test body.
//
// Results at $0400-$0409: $01 = pass, $00 = fail per test (10 tests)

.pc = $0801 "BASIC Stub"
:BasicUpstart2(bootstrap)

.pc = $0810 "Test Code"

.encoding "screencode_mixed"

// Bootstrap — must be before imports so it's in RAM below $A000.
bootstrap:
    lda $01
    and #%11111110          // Clear bit 0 → bank out BASIC ROM
    sta $01
    jmp test_start

// test_finish — Copy results to $0400 and halt.
test_finish:
    ldx #9
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk

.pc = * "Test Body"

#import "../zeropage.s"
#import "../memory.s"
#import "../reu.s"
#import "../screen.s"
#import "../color.s"
#import "../config.s"
#import "../input.s"
#import "../rng.s"
#import "../math.s"
#import "../tables.s"
#import "../item_defs.s"
#import "../player.s"
#import "../ui_messages.s"
#import "../ui_status.s"
#import "../ui_help_clear.s"
#import "../ui_character.s"
#import "../stat_display.s"
#import "../player_create.s"
#import "../sound.s"
#import "../dungeon_data.s"
#import "../dungeon_gen.s"
#import "../huffman.s"
#import "../dungeon_features.s"
#import "../monster.s"
#import "../tier_manager.s"
#import "../overlay.s"
#import "../monster_ai.s"
#import "../recall.s"
#import "../monster_magic.s"
#import "../item.s"
#import "../special_rooms.s"
#import "../ego_items.s"
#import "../special_rooms_stubs.s"
#import "../player_items.s"
#import "../spell_data.s"
#import "../projectile.s"
#import "../spell_effects.s"
#import "../player_magic.s"
#import "../ui_inventory.s"
#import "../dungeon_render.s"
#import "../dungeon_los.s"
#import "../player_move.s"
#import "../combat.s"
#import "../monster_attack.s"
#import "../turn.s"
#import "../store_data.s"
#import "../store.s"
#import "../ui_store.s"
#import "../ui_help.s"
#import "../ui_trampoline_stubs.s"
#import "../save.s"
#import "../disk_swap.s"

// --- Test-local hiscore definitions (replaces score_io.s) ---
// score_io.s aliases hiscore_table to CREATURE_BASE ($C020) which
// overlaps the tail of test code. Define a safe buffer instead.
.const HISCORE_ENTRY_SIZE = 23
.const HISCORE_MAX_ENTRIES = 10
test_hiscore_buf: .fill HISCORE_MAX_ENTRIES * HISCORE_ENTRY_SIZE, 0
.label hiscore_table = test_hiscore_buf
hiscore_count:  .byte 0
// Stub I/O functions (not under test)
hiscore_load:
hiscore_save:
    rts

#import "../score.s"

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test result buffer
tc_results: .fill 12, $ff
tc_count: .byte 0

test_start:
    // Initialize result area to $ff (untested)
    ldx #11
    lda #$ff
!clr:
    sta tc_results,x
    dex
    bpl !clr-

    // ============================================================
    // Test 1: math_add_24 — basic addition (no carry)
    // $000100 + $000050 = $000150
    // ============================================================
    lda #$00
    sta score_accum_0
    lda #$01
    sta score_accum_1
    lda #$00
    sta score_accum_2

    lda #$50
    sta score_operand_0
    lda #$00
    sta score_operand_1
    lda #$00
    sta score_operand_2

    jsr math_add_24

    lda score_accum_0
    cmp #$50
    bne !t1_fail+
    lda score_accum_1
    cmp #$01
    bne !t1_fail+
    lda score_accum_2
    cmp #$00
    bne !t1_fail+
    lda #$01
    jmp !t1_store+
!t1_fail:
    lda #$00
!t1_store:
    sta tc_results + 0

    // ============================================================
    // Test 2: math_add_24 — carry propagation across all 3 bytes
    // $00FF80 + $000080 = $010000
    // ============================================================
    lda #$80
    sta score_accum_0
    lda #$FF
    sta score_accum_1
    lda #$00
    sta score_accum_2

    lda #$80
    sta score_operand_0
    lda #$00
    sta score_operand_1
    lda #$00
    sta score_operand_2

    jsr math_add_24

    lda score_accum_0
    cmp #$00
    bne !t2_fail+
    lda score_accum_1
    cmp #$00
    bne !t2_fail+
    lda score_accum_2
    cmp #$01
    bne !t2_fail+
    lda #$01
    jmp !t2_store+
!t2_fail:
    lda #$00
!t2_store:
    sta tc_results + 1

    // ============================================================
    // Test 3: math_cmp_24 — equal
    // $012345 == $012345
    // ============================================================
    lda #$45
    sta score_accum_0
    lda #$23
    sta score_accum_1
    lda #$01
    sta score_accum_2

    lda #$45
    sta score_operand_0
    lda #$23
    sta score_operand_1
    lda #$01
    sta score_operand_2

    jsr math_cmp_24
    bne !t3_fail+               // Z flag should be set (equal)
    bcc !t3_fail+               // C flag should be set (>=)
    lda #$01
    jmp !t3_store+
!t3_fail:
    lda #$00
!t3_store:
    sta tc_results + 2

    // ============================================================
    // Test 4: math_cmp_24 — less than
    // $000100 < $010000
    // ============================================================
    lda #$00
    sta score_accum_0
    lda #$01
    sta score_accum_1
    lda #$00
    sta score_accum_2

    lda #$00
    sta score_operand_0
    lda #$00
    sta score_operand_1
    lda #$01
    sta score_operand_2

    jsr math_cmp_24
    bcs !t4_fail+               // C clear means accum < operand
    lda #$01
    jmp !t4_store+
!t4_fail:
    lda #$00
!t4_store:
    sta tc_results + 3

    // ============================================================
    // Test 5: math_cmp_24 — greater than
    // $010000 > $000100
    // ============================================================
    lda #$00
    sta score_accum_0
    lda #$00
    sta score_accum_1
    lda #$01
    sta score_accum_2

    lda #$00
    sta score_operand_0
    lda #$01
    sta score_operand_1
    lda #$00
    sta score_operand_2

    jsr math_cmp_24
    bcc !t5_fail+               // C set means accum >= operand
    beq !t5_fail+               // Z clear means not equal (strict >)
    lda #$01
    jmp !t5_store+
!t5_fail:
    lda #$00
!t5_store:
    sta tc_results + 4

    // ============================================================
    // Test 6: score_calculate — known XP + gold + depth → expected
    // XP = $000064 (100), gold = $0000C8 (200), max_depth = 8
    // depth bonus = 8 * 50 = 400 = $0190
    // total = 100 + 200 + 400 = 700 = $0002BC
    // ============================================================
    // Clear player data
    lda #0
    ldx #PL_STRUCT_SIZE - 1
!t6_clr:
    sta player_data,x
    dex
    bpl !t6_clr-

    // Set XP = 100 ($000064)
    lda #$64
    sta player_data + PL_XP_0
    lda #$00
    sta player_data + PL_XP_1
    sta player_data + PL_XP_2

    // Set gold = 200 ($0000C8)
    lda #$C8
    sta player_data + PL_GOLD_0
    lda #$00
    sta player_data + PL_GOLD_1
    sta player_data + PL_GOLD_2

    // Set max depth = 8
    lda #8
    sta player_data + PL_MAX_DLVL

    jsr score_calculate

    // Expected: 700 = $0002BC
    lda score_accum_0
    cmp #$BC
    bne !t6_fail+
    lda score_accum_1
    cmp #$02
    bne !t6_fail+
    lda score_accum_2
    cmp #$00
    bne !t6_fail+
    lda #$01
    jmp !t6_store+
!t6_fail:
    lda #$00
!t6_store:
    sta tc_results + 5

    // ============================================================
    // Test 7: screen_put_decimal_24 — verify screen RAM output
    // Value = 12345 ($003039), display at row 0, col 0
    // Should write "12345" as screen codes $31,$32,$33,$34,$35
    // (Runs before hiscore tests for logical grouping)
    // ============================================================
    // Clear screen area
    lda #$20
    ldx #39
!t7_clr:
    sta $0400,x
    dex
    bpl !t7_clr-

    lda #0
    sta zp_cursor_row
    sta zp_cursor_col
    lda #COL_WHITE
    sta zp_text_color

    lda #$39                    // lo byte of 12345
    sta score_accum_0
    lda #$30                    // mid byte of 12345
    sta score_accum_1
    lda #$00
    sta score_accum_2

    jsr screen_put_decimal_24

    // Verify screen RAM at $0400: '1','2','3','4','5'
    lda $0400
    cmp #$31                    // '1'
    bne !t7_fail+
    lda $0401
    cmp #$32                    // '2'
    bne !t7_fail+
    lda $0402
    cmp #$33                    // '3'
    bne !t7_fail+
    lda $0403
    cmp #$34                    // '4'
    bne !t7_fail+
    lda $0404
    cmp #$35                    // '5'
    bne !t7_fail+
    lda #$01
    jmp !t7_store+
!t7_fail:
    lda #$00
!t7_store:
    sta tc_results + 6

    // ============================================================
    // Test 8: hiscore_insert — into empty table
    // Should insert at index 0, count should be 1
    // hiscore_table now points to safe buffer (not CREATURE_BASE).
    // ============================================================
    lda #0
    sta hiscore_count
    tax
!t8_clr:
    sta hiscore_table,x
    inx
    cpx #HISCORE_MAX_ENTRIES * HISCORE_ENTRY_SIZE
    bne !t8_clr-

    // Set player name
    lda #$14                    // 'T' screencode
    sta player_data + PL_NAME
    lda #$05                    // 'E' screencode
    sta player_data + PL_NAME + 1
    lda #$13                    // 'S' screencode
    sta player_data + PL_NAME + 2
    lda #$14                    // 'T' screencode
    sta player_data + PL_NAME + 3
    lda #0
    sta player_data + PL_NAME + 4

    lda #5
    sta player_data + PL_LEVEL
    lda #3
    sta player_data + PL_MAX_DLVL
    lda #0
    sta player_data + PL_RACE
    lda #1
    sta player_data + PL_CLASS

    // Set score = 1000 = $0003E8
    lda #$E8
    sta score_accum_0
    lda #$03
    sta score_accum_1
    lda #$00
    sta score_accum_2

    jsr hiscore_insert

    // Check result
    lda score_new_rank
    cmp #0
    bne !t8_fail+
    lda hiscore_count
    cmp #1
    bne !t8_fail+
    // Verify score in table
    lda hiscore_table + 16
    cmp #$E8
    bne !t8_fail+
    lda hiscore_table + 17
    cmp #$03
    bne !t8_fail+
    lda #$01
    jmp !t8_store+
!t8_fail:
    lda #$00
!t8_store:
    sta tc_results + 7

    // ============================================================
    // Test 9: hiscore_insert — ordering (higher score goes first)
    // Table has score 1000, insert score 2000 → should be at index 0
    // ============================================================
    // Table already has 1 entry (score 1000 at index 0) from test 8

    // Set score = 2000 = $0007D0
    lda #$D0
    sta score_accum_0
    lda #$07
    sta score_accum_1
    lda #$00
    sta score_accum_2

    jsr hiscore_insert

    // New entry should be at index 0 (higher score)
    lda score_new_rank
    cmp #0
    bne !t9_fail+
    lda hiscore_count
    cmp #2
    bne !t9_fail+
    // Verify: index 0 has score 2000
    lda hiscore_table + 16
    cmp #$D0
    bne !t9_fail+
    lda hiscore_table + 17
    cmp #$07
    bne !t9_fail+
    // Verify: index 1 has score 1000 (shifted down)
    lda hiscore_table + HISCORE_ENTRY_SIZE + 16
    cmp #$E8
    bne !t9_fail+
    lda hiscore_table + HISCORE_ENTRY_SIZE + 17
    cmp #$03
    bne !t9_fail+
    lda #$01
    jmp !t9_store+
!t9_fail:
    lda #$00
!t9_store:
    sta tc_results + 8

    // ============================================================
    // Test 10: hiscore_insert — full table overflow
    // Fill table with 10 entries of score 500, insert score 100
    // Should return $FF (didn't qualify)
    // ============================================================
    lda #HISCORE_MAX_ENTRIES
    sta hiscore_count

    // Fill all entries with score 500 = $01F4
    ldx #0
    ldy #0
!t10_fill:
    cpx #HISCORE_MAX_ENTRIES
    bcs !t10_fill_done+
    txa
    pha                         // Save X
    ldx #HISCORE_ENTRY_SIZE
    jsr math_multiply           // zp_math_a = offset
    lda zp_math_a
    tay                         // Y = offset
    lda #$F4
    sta hiscore_table + 16,y
    lda #$01
    sta hiscore_table + 17,y
    lda #$00
    sta hiscore_table + 18,y
    pla
    tax                         // Restore X
    inx
    jmp !t10_fill-
!t10_fill_done:

    // Try to insert score 100 = $000064
    lda #$64
    sta score_accum_0
    lda #$00
    sta score_accum_1
    lda #$00
    sta score_accum_2

    jsr hiscore_insert

    lda score_new_rank
    cmp #$ff                    // Should not qualify
    beq !t10_pass+
    lda #$00
    jmp !t10_store+
!t10_pass:
    lda #$01
!t10_store:
    sta tc_results + 9

    jmp test_finish
