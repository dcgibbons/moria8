// test_score.s — Runtime tests for score calculation, 24-bit math, and hiscore
//
// Tests: math_add_24 basic, math_add_24 carry, math_cmp_24 equal/lt/gt,
//        score_calculate, screen_put_decimal_24, screen_put_decimal_lz2,
//        screen_put_decimal_16, hiscore_insert empty/ordering/overflow,
//        screen_put_decimal_24 past 16 bits (65,547) and at 24 bits (16,777,215)
// NOTE: score_io.s is NOT imported — hiscore_table aliases CREATURE_BASE
//       ($C020) which overlaps test code. Local definitions redirect
//       hiscore_table to a safe buffer within the test body.
//
// Results at $0400-$040f: $01 = pass, $00 = fail per test (16 tests)

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
    ldx #15
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk

.pc = * "Test Body"

.segmentdef TestUnused [start=$E100, min=$E100, max=$FFF9]
.segmentdef TestUnusedUI [start=$E100, min=$E100, max=$FFF9]
.segmentdef TestCreateOverlay [start=$D000, min=$D000, max=$DFFF]
#import "../../../../core/zeropage.s"
#import "../memory.s"
#import "../../common/reu.s"
#import "../screen.s"
#import "../../../../core/color.s"
#import "../config.s"
#import "../input.s"
#import "../../../../core/rng.s"
#import "../../../../core/math.s"
#import "../../../../core/tables.s"
#import "../../../../core/item_defs.s"
#import "../../../../core/player.s"
#import "../../../../core/ui_messages.s"
.segment TestUnusedUI
#import "../../../../core/ui_status.s"
.segment Default
#import "../../../../core/ui_help_clear.s"
.segment TestUnusedUI
#import "../../../../core/ui_character.s"
#import "../../../../core/stat_display.s"
.segment Default
.segment TestCreateOverlay
player_create:
    brk
.segment Default
#import "../../../../core/sound.s"
#import "../../../../core/dungeon_data.s"
#import "dungeon_gen_stubs.s"
#import "../../../../core/huffman.s"
#import "../../../../core/dungeon_features.s"
#import "chest_summons_stubs.s"
#import "../../../../core/monster.s"
#import "../../../../core/tier_manager.s"
#import "../../common/overlay.s"
#import "../../../../core/monster_ai.s"
#import "../../../../core/recall.s"
.segment TestCreateOverlay
#import "../../../../core/monster_magic.s"
.segment Default
#define HAL_PLATFORM_ITEM_CAT_CUSTOM
#import "../../../../core/item.s"
hal_item_cat_read_byte:
    brk
#import "../../../../core/special_rooms.s"
#import "../../../../core/ego_items.s"
#import "../../../../core/special_rooms_stubs.s"
#import "../../../../core/player_items.s"
#import "../../../../core/spell_data.s"
.segment TestUnused
#import "../../../../core/projectile.s"
.segment Default
.segment TestCreateOverlay
#import "../../../../core/spell_effects.s"
.segment Default
#import "../../../../core/player_magic_state.s"
#import "../../../../core/player_magic_state_ops.s"
#import "../../../../core/player_magic.s"
#import "../../../../core/ui_inventory.s"
#import "../../../../core/ui_equipment.s"
.segment TestUnused
#import "../dungeon_render.s"
.segment Default
#import "../../../../core/dungeon_los.s"
#import "../../../../core/player_move.s"
.segment TestUnused
#import "../../../../core/combat.s"
#import "../../../../core/scene_mat_tile.s"
.segment Default
eff_fear_timer: .byte 0
monster_attack_player:
player_update_hunger_state:
    sec
    rts
// The production damage entries' shape (monster_attack.s): 8-bit, or 16-bit
// with the high byte in mad_dmg_hi (breath); acid breath's armour damage
// finds no armour here.
mad_dmg_hi: .byte 0
mon_atk_acid_armour:
    clc
    rts
mon_atk_apply_damage:
    lda #0
    sta mad_dmg_hi
mon_atk_apply_damage_16:
    lda zp_player_hp_lo
    sec
    sbc zp_combat_dmg
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda zp_player_hp_hi
    sbc mad_dmg_hi
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    bmi !mad_dead+
    ora zp_player_hp_lo
    beq !mad_dead+
    clc
    rts
!mad_dead:
    sec
    rts
player_death_check:
    lda zp_player_hp_hi
    bmi !pdc_dead+
    ora zp_player_hp_lo
    beq !pdc_dead+
    rts
!pdc_dead:
    lda zp_game_flags
    ora #$01
    sta zp_game_flags
    rts
#import "../../../../core/store_data.s"
#import "../../../../core/store.s"
.segment TestUnused
#import "../../../../core/ui_store.s"
.segment Default
#import "../../../../core/ui_trampoline_stubs.s"
#import "../../../../core/runtime_ui_strings.s"
#import "../../common/compat/io_kernal_consts.s"

// Help rendering is not under test here. Keep a tiny stub so the score suite
// does not pull the full paged-help UI into its resident test image.
ui_help_display:
ui_help_show_paged:
    rts

// Test-local save/disk stubs. The score suite does not exercise persistence or
// disk UI, and importing the full save path needlessly bloats the resident body.
save_game:
load_game:
delete_savefile:
disk_prompt_save:
disk_prompt_game:
    rts

disk_mode:   .byte 0
save_device: .byte 8

// --- Test-local hiscore definitions (replaces score_io.s) ---
// score_io.s aliases hiscore_table to CREATURE_BASE ($C020) which
// overlaps the tail of test code. Park the buffer above MAP_BASE and below
// the $D000 overlay boundary so test-body growth cannot collide with it.
.const HISCORE_ENTRY_SIZE = 23
.const HISCORE_MAX_ENTRIES = 10
.const TEST_HISCORE_BUF = $CF00
.label hiscore_table = TEST_HISCORE_BUF
hiscore_count:  .byte 0
// Stub I/O functions (not under test)
hiscore_load:
hiscore_save:
    rts

#import "../../../../core/score.s"
#import "../../../../core/ui_recall.s"

recall_found_type: .byte 0

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test result buffer
tc_results: .fill 16, $ff
tc_count: .byte 0

test_start:
    // Initialize result area to $ff (untested)
    ldx #15
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
    // Test 8: screen_put_decimal_lz2 — verify leading-zero path
    // Value = 7, display at row 0, col 0
    // Should write "07" as screen codes $30,$37
    // ============================================================
    lda #$20
    ldx #39
!t8_clr:
    sta $0400,x
    dex
    bpl !t8_clr-

    lda #0
    sta zp_cursor_row
    sta zp_cursor_col
    lda #COL_WHITE
    sta zp_text_color

    lda #7
    jsr screen_put_decimal_lz2

    lda $0400
    cmp #$30
    bne !t8_fail+
    lda $0401
    cmp #$37
    bne !t8_fail+
    lda #$01
    jmp !t8_store+
!t8_fail:
    lda #$00
!t8_store:
    sta tc_results + 7

    // ============================================================
    // Test 9: screen_put_decimal_16 — verify shared 16-bit formatter
    // Value = 10005 ($2715), display at row 0, col 0
    // Should write "10005" as screen codes $31,$30,$30,$30,$35
    // ============================================================
    lda #$20
    ldx #39
!t9_clr:
    sta $0400,x
    dex
    bpl !t9_clr-

    lda #0
    sta zp_cursor_row
    sta zp_cursor_col
    lda #COL_WHITE
    sta zp_text_color

    lda #$15
    sta zp_temp0
    lda #$27
    sta zp_temp1
    jsr screen_put_decimal_16

    lda $0400
    cmp #$31
    bne !t9_fail+
    lda $0401
    cmp #$30
    bne !t9_fail+
    lda $0402
    cmp #$30
    bne !t9_fail+
    lda $0403
    cmp #$30
    bne !t9_fail+
    lda $0404
    cmp #$35
    bne !t9_fail+
    lda #$01
    jmp !t9_store+
!t9_fail:
    lda #$00
!t9_store:
    sta tc_results + 8

    // ============================================================
    // Test 10: hiscore_insert — into empty table
    // Should insert at index 0, count should be 1
    // hiscore_table now points to safe buffer (not CREATURE_BASE).
    // ============================================================
    lda #0
    sta hiscore_count
    tax
!t10_clr:
    sta hiscore_table,x
    inx
    cpx #HISCORE_MAX_ENTRIES * HISCORE_ENTRY_SIZE
    bne !t10_clr-

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
    bne !t10_fail+
    lda hiscore_count
    cmp #1
    bne !t10_fail+
    // Verify score in table
    lda hiscore_table + 16
    cmp #$E8
    bne !t10_fail+
    lda hiscore_table + 17
    cmp #$03
    bne !t10_fail+
    lda #$01
    jmp !t10_store+
!t10_fail:
    lda #$00
!t10_store:
    sta tc_results + 9

    // ============================================================
    // Test 11: hiscore_insert — ordering (higher score goes first)
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
    bne !t11_fail+
    lda hiscore_count
    cmp #2
    bne !t11_fail+
    // Verify: index 0 has score 2000
    lda hiscore_table + 16
    cmp #$D0
    bne !t11_fail+
    lda hiscore_table + 17
    cmp #$07
    bne !t11_fail+
    // Verify: index 1 has score 1000 (shifted down)
    lda hiscore_table + HISCORE_ENTRY_SIZE + 16
    cmp #$E8
    bne !t11_fail+
    lda hiscore_table + HISCORE_ENTRY_SIZE + 17
    cmp #$03
    bne !t11_fail+
    lda #$01
    jmp !t11_store+
!t11_fail:
    lda #$00
!t11_store:
    sta tc_results + 10

    // ============================================================
    // Test 12: hiscore_insert — full table overflow
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
    sta tc_results + 11

    // ============================================================
    // Test 12: hiscore_insert — winner sets the $80 class marker bit;
    // non-winner stores the plain class byte.
    // ============================================================
    lda #0
    sta hiscore_count
    tax
!t12_clr:
    sta hiscore_table,x
    inx
    cpx #HISCORE_MAX_ENTRIES * HISCORE_ENTRY_SIZE
    bne !t12_clr-

    lda #1
    sta player_data + PL_CLASS
    lda #$E8
    sta score_accum_0
    lda #$03
    sta score_accum_1
    lda #$00
    sta score_accum_2
    lda zp_game_flags
    ora #GAME_FLAG_WINNER
    sta zp_game_flags

    jsr hiscore_insert

    lda hiscore_table + 22
    cmp #$81                    // class 1 | $80 winner marker
    bne !t12_fail+

    // Non-winner: plain class byte
    lda #0
    sta hiscore_count
    tax
!t12_clr2:
    sta hiscore_table,x
    inx
    cpx #HISCORE_MAX_ENTRIES * HISCORE_ENTRY_SIZE
    bne !t12_clr2-
    lda zp_game_flags
    and #~GAME_FLAG_WINNER & $ff
    sta zp_game_flags
    jsr hiscore_insert
    lda hiscore_table + 22
    cmp #$01
    bne !t12_fail+
    lda #$01
    jmp !t12_store+
!t12_fail:
    lda #$00
!t12_store:
    sta tc_results + 12

    // ============================================================
    // Test 13: screen_put_decimal_24 past 16 bits: 65,547 ($01000B) as
    // "65547", not the low 16 bits' "11" (C128 Balrog queue, 2026-11-05)
    // ============================================================
    lda #$0b
    sta score_accum_0
    lda #$00
    sta score_accum_1
    lda #$01
    sta score_accum_2
    jsr t24_print
    lda #<t13_expect
    ldx #>t13_expect
    jsr t24_check
    lda #0
    rol
    sta tc_results + 13

    // ============================================================
    // Test 14: screen_put_decimal_24 at the 24-bit maximum: 16,777,215
    // ============================================================
    lda #$ff
    sta score_accum_0
    sta score_accum_1
    sta score_accum_2
    jsr t24_print
    lda #<t14_expect
    ldx #>t14_expect
    jsr t24_check
    lda #0
    rol
    sta tc_results + 14

    // ============================================================
    // Test 15: the death screen names the level of death, not the deepest
    // reached (VMS death.inc "Died on Level : dun_level"; Umoria's tomb):
    // clvl 40 Priests died on DL43 and DL50 under "Killed on dungeon level
    // 100" after a Balrog trip (C64 Balrog queue, 2026-11-13).
    // ============================================================
    .const t15_digits_at = 24       // "Killed on dungeon level " is 24 characters
    lda #43
    sta zp_player_dlvl
    lda #100
    sta player_data + PL_MAX_DLVL
    lda #0
    sta zp_game_flags
    jsr score_death_screen
    ldx #1
!t15_cmp:
    lda $0400 + 5 * 40 + SDS_INFO_COL + t15_digits_at,x
    cmp t15_expect,x
    bne !t15_fail+
    dex
    bpl !t15_cmp-
    lda $0400 + 5 * 40 + SDS_INFO_COL + t15_digits_at + 2
    cmp #$20                        // "43", not "100"
    bne !t15_fail+
    jsr test_recall_279_suite
    bcc !t15_fail+
    lda #$01
    .byte $2c
!t15_fail:
    lda #$00
    sta tc_results + 15

    jmp test_finish

t15_expect: .byte $34, $33          // "43" as screen codes

// ============================================================
// Phase 5 279-species Monster Recall UI suite (ui_recall_display):
//   R1: 4 attacks (atk0..atk3) with packed verb bits + 40-col Row 7 wrap
//   R2: 0-dice status/theft tags (GLD/ITM/PAR/CHG/DIS/SHR) vs 0d0 ATK_NORMAL
//   R3: Extended spell_flags2 ($1f vs CM2_*) and MS_HOLD ($80) spell recall
//   R4: Hurt vulnerabilities, Traits (INVIS/PHASE/NO-SLP/UNDEAD/EVIL), K:/D:
// ============================================================
tc_recall_sub: .fill 4, $ff

trcl_reset_slot0:
    lda #0
    sta recall_found_type
    sta cr_mflags
    sta cr_atk0_type
    sta cr_atk0_dice
    sta cr_atk0_sides
    sta cr_atk1_type
    sta cr_atk1_dice
    sta cr_atk1_sides
    sta cr_atk2_type
    sta cr_atk2_dice
    sta cr_atk2_sides
    sta cr_atk3_type
    sta cr_atk3_dice
    sta cr_atk3_sides
    sta cr_spell_chance
    sta cr_spell_flags
    sta cr_spell_flags2
    sta cr_cdefense
    sta recall_kills
    sta recall_deaths
    sta recall_attacks
    sta recall_spells
    lda #COL_RED
    sta cr_color
    lda #$42                        // 'B'
    sta cr_display
    lda #50
    sta cr_level
    lda #80
    sta cr_ac
    lda #30
    sta cr_hd_num
    lda #10
    sta cr_hd_sides
    ldx #0
!nm:
    lda trcl_name,x
    sta creature_name_buf,x
    beq !nm_done+
    inx
    bne !nm-
!nm_done:
    rts

// trcl_assert_at — Input: A = row, X = col, zp_ptr0 = expected C-string.
// Returns C=1 on match, C=0 on mismatch.
trcl_assert_at:
    tay
    clc
    txa
    adc screen_row_lo,y
    sta zp_ptr1
    lda screen_row_hi,y
    adc #0
    sta zp_ptr1_hi
    ldy #0
!cmp_loop:
    lda (zp_ptr0),y
    beq !match+
    cmp (zp_ptr1),y
    bne !mismatch+
    iny
    bne !cmp_loop-
!match:
    sec
    rts
!mismatch:
    clc
    rts

test_recall_279_suite:
    // --- R1: 4 attacks + packed verb bits + 40-col wrap to Row 7 Col 7 ---
    jsr trcl_reset_slot0
    lda #ATK_FIRE | $80
    sta cr_atk0_type
    lda #3
    sta cr_atk0_dice
    lda #12 | $30
    sta cr_atk0_sides

    lda #ATK_LOSE_STR | $80
    sta cr_atk1_type
    lda #2
    sta cr_atk1_dice
    lda #6 | $50
    sta cr_atk1_sides

    lda #ATK_ACID
    sta cr_atk2_type
    lda #1
    sta cr_atk2_dice
    lda #10 | $90
    sta cr_atk2_sides

    lda #ATK_LIGHT | $80
    sta cr_atk3_type
    lda #4
    sta cr_atk3_dice
    lda #8 | $f0
    sta cr_atk3_sides

    jsr ui_recall_display

    lda #<trcl_exp_r1_row6
    sta zp_ptr0
    lda #>trcl_exp_r1_row6
    sta zp_ptr0_hi
    lda #6
    ldx #7
    jsr trcl_assert_at
    bcc !r1_fail+

    lda #<trcl_exp_r1_row7
    sta zp_ptr0
    lda #>trcl_exp_r1_row7
    sta zp_ptr0_hi
    lda #7
    ldx #7
    jsr trcl_assert_at
    bcc !r1_fail+
    lda #1
    sta tc_recall_sub + 0
    bne !r2_start+
!r1_fail:
    lda #0
    sta tc_recall_sub + 0
    clc
    rts

!r2_start:
    // --- R2: 0-dice status/theft attacks vs 0d0 ATK_NORMAL suppression ---
    jsr trcl_reset_slot0
    lda #ATK_STEAL_GOLD | $80
    sta cr_atk0_type
    lda #$40                        // 0 sides + packed verb nibble 4
    sta cr_atk0_sides
    lda #ATK_STEAL_ITEM
    sta cr_atk1_type
    lda #ATK_PARALYZE | $80
    sta cr_atk2_type
    lda #$20
    sta cr_atk2_sides
    lda #ATK_EAT_CHARGES
    sta cr_atk3_type
    jsr ui_recall_display

    lda #<trcl_exp_r2_status4
    sta zp_ptr0
    lda #>trcl_exp_r2_status4
    sta zp_ptr0_hi
    lda #6
    ldx #7
    jsr trcl_assert_at
    bcc !r2_fail+

    // Slot 0 = 0d0 ATK_NORMAL (suppressed), Slots 1..2 = 0d0 DIS + SHR
    jsr trcl_reset_slot0
    lda #ATK_NORMAL | $80
    sta cr_atk0_type
    lda #$30
    sta cr_atk0_sides
    lda #ATK_DISENCHANT
    sta cr_atk1_type
    lda #ATK_AGGRAVATE
    sta cr_atk2_type
    jsr ui_recall_display

    lda #<trcl_exp_r2_dis_shr
    sta zp_ptr0
    lda #>trcl_exp_r2_dis_shr
    sta zp_ptr0_hi
    lda #6
    ldx #7
    jsr trcl_assert_at
    bcc !r2_fail+

    // Only 0d0 ATK_NORMAL across slots -> "None"
    jsr trcl_reset_slot0
    lda #ATK_NORMAL | $80
    sta cr_atk0_type
    sta cr_atk2_type
    lda #$50
    sta cr_atk0_sides
    sta cr_atk2_sides
    jsr ui_recall_display

    lda #<trcl_exp_none
    sta zp_ptr0
    lda #>trcl_exp_none
    sta zp_ptr0_hi
    lda #6
    ldx #7
    jsr trcl_assert_at
    bcc !r2_fail+
    lda #1
    sta tc_recall_sub + 1
    bne !r3_start+
!r2_fail:
    lda #0
    sta tc_recall_sub + 1
    clc
    rts

!r3_start:
    // --- R3: Extended caster recall (cr_spell_flags2 & $1f, MS_HOLD $80) ---
    jsr trcl_reset_slot0
    lda #MSF2_BLINK
    sta cr_spell_flags2
    lda #4
    sta cr_spell_chance
    jsr ui_recall_display

    lda #<trcl_exp_spl_yes
    sta zp_ptr0
    lda #>trcl_exp_spl_yes
    sta zp_ptr0_hi
    lda #8
    ldx #2
    jsr trcl_assert_at
    bcc !r3_fail+

    // Movement-only CM2_* bits in cr_spell_flags2 ($E0) must NOT show Spl: Yes
    jsr trcl_reset_slot0
    lda #CM2_PHASE | CM2_EATS_OTHER | CM2_PICKS_UP
    sta cr_spell_flags2
    lda #4
    sta cr_spell_chance
    jsr ui_recall_display

    lda #<trcl_exp_spl_none
    sta zp_ptr0
    lda #>trcl_exp_spl_none
    sta zp_ptr0_hi
    lda #8
    ldx #2
    jsr trcl_assert_at
    bcc !r3_fail+

    // MS_HOLD ($80) with non-zero frequency -> Spl: Yes; with freq 0 -> Spl: None
    jsr trcl_reset_slot0
    lda #MS_HOLD | 6
    sta cr_spell_chance
    jsr ui_recall_display

    lda #<trcl_exp_spl_yes
    sta zp_ptr0
    lda #>trcl_exp_spl_yes
    sta zp_ptr0_hi
    lda #8
    ldx #2
    jsr trcl_assert_at
    bcc !r3_fail+

    jsr trcl_reset_slot0
    lda #MS_HOLD
    sta cr_spell_chance
    jsr ui_recall_display

    lda #<trcl_exp_spl_none
    sta zp_ptr0
    lda #>trcl_exp_spl_none
    sta zp_ptr0_hi
    lda #8
    ldx #2
    jsr trcl_assert_at
    bcc !r3_fail+
    lda #1
    sta tc_recall_sub + 2
    bne !r4_start+
!r3_fail:
    lda #0
    sta tc_recall_sub + 2
    clc
    rts

!r4_start:
    // --- R4: Hurt vulnerabilities + Traits + shifted K:/D: row 14 ---
    jsr trcl_reset_slot0
    lda #$ff                        // All 6 CD_* hurts + CD_NO_SLEEP + CD_INVISIBLE
    sta cr_cdefense
    lda #CM2_PHASE
    sta cr_spell_flags2
    lda #CF_UNDEAD | CF_EVIL
    sta cr_mflags
    lda #9
    sta recall_kills
    lda #2
    sta recall_deaths
    jsr ui_recall_display

    lda #<trcl_exp_hurt_all
    sta zp_ptr0
    lda #>trcl_exp_hurt_all
    sta zp_ptr0_hi
    lda #10
    ldx #2
    jsr trcl_assert_at
    bcc !r4_fail+

    lda #<trcl_exp_traits_all
    sta zp_ptr0
    lda #>trcl_exp_traits_all
    sta zp_ptr0_hi
    lda #12
    ldx #2
    jsr trcl_assert_at
    bcc !r4_fail+

    lda #<trcl_exp_kills
    sta zp_ptr0
    lda #>trcl_exp_kills
    sta zp_ptr0_hi
    lda #14
    ldx #2
    jsr trcl_assert_at
    bcc !r4_fail+

    lda #<trcl_exp_deaths
    sta zp_ptr0
    lda #>trcl_exp_deaths
    sta zp_ptr0_hi
    lda #14
    ldx #16
    jsr trcl_assert_at
    bcc !r4_fail+

    // Empty cdefense / mflags / phase -> Hurt: None & Traits: None
    jsr trcl_reset_slot0
    jsr ui_recall_display

    lda #<trcl_exp_hurt_none
    sta zp_ptr0
    lda #>trcl_exp_hurt_none
    sta zp_ptr0_hi
    lda #10
    ldx #2
    jsr trcl_assert_at
    bcc !r4_fail+

    lda #<trcl_exp_traits_none
    sta zp_ptr0
    lda #>trcl_exp_traits_none
    sta zp_ptr0_hi
    lda #12
    ldx #2
    jsr trcl_assert_at
    bcc !r4_fail+

    lda #1
    sta tc_recall_sub + 3
    sec
    rts
!r4_fail:
    lda #0
    sta tc_recall_sub + 3
    clc
    rts

trcl_name:           .text "BALROG" ; .byte 0
trcl_exp_r1_row6:    .text "FIR 3D12  STR 2D6  ACD 1D10 " ; .byte 0
trcl_exp_r1_row7:    .text "LTG 4D8 " ; .byte 0
trcl_exp_r2_status4: .text "GLD  ITM  PAR  CHG " ; .byte 0
trcl_exp_r2_dis_shr: .text "DIS  SHR " ; .byte 0
trcl_exp_none:       .text "None " ; .byte 0
trcl_exp_spl_yes:    .text "Spl: Yes " ; .byte 0
trcl_exp_spl_none:   .text "Spl: None " ; .byte 0
trcl_exp_hurt_all:   .text "Hurt: FIR CLD ACD PSN LIT STN " ; .byte 0
trcl_exp_hurt_none:  .text "Hurt: None " ; .byte 0
trcl_exp_traits_all: .text "Traits: INVIS PHASE NO-SLP UNDEAD EVIL" ; .byte 0
trcl_exp_traits_none:.text "Traits: None " ; .byte 0
trcl_exp_kills:      .text "K: 9 " ; .byte 0
trcl_exp_deaths:     .text "D: 2 " ; .byte 0

// Clear row 0 and print score_accum_0-2 at row 0, col 0.
t24_print:
    lda #$20
    ldx #39
!clr:
    sta $0400,x
    dex
    bpl !clr-
    lda #0
    sta zp_cursor_row
    sta zp_cursor_col
    lda #COL_WHITE
    sta zp_text_color
    jmp screen_put_decimal_24

// Compare $0400.. with the zero-terminated text at A/X (lo/hi), then a space
// after it; C set on a match.
t24_check:
    sta zp_ptr0
    stx zp_ptr0_hi
    ldy #0
!loop:
    lda (zp_ptr0),y
    beq !end+
    cmp $0400,y
    bne !bad+
    iny
    bne !loop-
!end:
    lda $0400,y
    cmp #$20
    bne !bad+
    sec
    rts
!bad:
    clc
    rts

t13_expect: .text "65547" ; .byte 0
t14_expect: .text "16777215" ; .byte 0

test_body_end:
.assert "Score test body stays below hiscore buffer", test_body_end <= TEST_HISCORE_BUF, true
.assert "Score test body stays below overlay boundary", test_body_end < $d000, true
.assert "Hiscore test buffer stays below overlay boundary", TEST_HISCORE_BUF + (HISCORE_ENTRY_SIZE * HISCORE_MAX_ENTRIES) <= $d000, true
