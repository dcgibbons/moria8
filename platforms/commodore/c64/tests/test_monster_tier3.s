// test_monster_tier3.s — The shipped tier3 creature rows
//
// Data-only checks of platforms/commodore/c64/creature_data/tier3.s, generated
// by tools/parse_creatures.py. tier3.s and tier4.s cannot share one assembly
// (both define TIER_COUNT), and test_monster_attack.s holds the tier4 rows,
// so the creatures found only in tier3 are checked here.
//
// Results at $0400-$0403: $01 = pass, $00 = fail per test

.pc = $0801 "BASIC Stub"
:BasicUpstart2(bootstrap)

.pc = $0810 "Test Code"

.encoding "screencode_mixed"

bootstrap:
    lda $01
    and #%11111110          // Clear bit 0 -> bank out BASIC ROM
    sta $01
    jmp test_start

// test_finish — Copy results to $0400 and halt.
test_finish:
    ldx #3
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk

.pc = * "Test Body"

// core/monster.s values (this suite links no code)
.const T3_ATK_NORMAL     = 1
.const T3_CF_ATTACK_ONLY = $01
.const T3_CR_MAX_HP      = $80

.const T3_VIOLET_MOLD = 13      // tier3.s index map: [152] DL15 Violet Mold
.const T3_UMBER_HULK  = 14      // [153] DL16 Umber Hulk
.const T3_TROLL       = 17      // [160] DL17 Troll
.const T3_QUYLTHULG   = 25      // [174] DL20 Quylthulg

tc_results: .fill 4, $ff
tc_rec:     .word 0

test_start:
    // Test 1: Umber Hulk, VMS values.inc:2428 '3 7 0d0|1 1 1d6|1 1 1d6|1 2
    // 2d6' (Umoria data_creatures.cpp:299 identical): its biggest blows,
    // 1d6 and the 2d6 bite, not the 0d0 confusing gaze (was CONFUSE 0d0,
    // NORMAL 1d6; tools/parse_creatures.py select_attack_slots)
    ldx #T3_UMBER_HULK
    lda #<tc_hulk_row
    ldy #>tc_hulk_row
    jsr t3_row_check
    sta tc_results + 0

    // Test 2: Troll, values.inc:2442 '1 1 1d4|1 1 1d4|1 2 1d6' (Umoria :306
    // identical): a claw and its 1d6 bite (was 1d4, 1d4)
    ldx #T3_TROLL
    lda #<tc_troll_row
    ldy #>tc_troll_row
    jsr t3_row_check
    sta tc_results + 1

    // Test 3: no tier3 creature has a spell chance without a spell; the
    // Violet Mold (values.inc:2426 spells %X'00010009': drain mana only, not
    // in Moria8) has chance 0 (was 11)
    ldx #tier3_cr_spell_flags - tier3_cr_spell_chance - 1   // TIER_COUNT - 1
!t3_loop:
    lda tier3_cr_spell_chance,x
    beq !t3_next+
    lda tier3_cr_spell_flags,x
    beq !t3_fail+
!t3_next:
    dex
    bpl !t3_loop-
    lda tier3_cr_spell_chance + T3_VIOLET_MOLD
    bne !t3_fail+
    lda #$01
    .byte $2c
!t3_fail:
    lda #$00
    sta tc_results + 2

    // Test 4: the Quylthulg (Umoria data_creatures.cpp:320: CMOVE
    // $00010004 CM_ONLY_MAGIC, cdefense $5000 with CD_MAX_HP, no attacks)
    // never moves and spawns with its full 4d8
    ldx #T3_QUYLTHULG
    lda tier3_cr_mflags,x
    and #T3_CF_ATTACK_ONLY
    beq !t4_fail+
    lda tier3_cr_speed,x
    and #T3_CR_MAX_HP
    beq !t4_fail+
    lda tier3_cr_atk0_type,x
    bne !t4_fail+
    lda #$01
    .byte $2c
!t4_fail:
    lda #$00
    sta tc_results + 3

    jmp test_finish

// t3_row_check — A = $01 when tier3 creature X has the six attack bytes
// (atk0 type/dice/sides, atk1 type/dice/sides) and then the zero-terminated
// name at A/Y (lo/hi), else $00.
t3_row_check:
    sta tc_rec
    sty tc_rec + 1
    lda tc_rec
    sta t3_rec_read + 1
    lda tc_rec + 1
    sta t3_rec_read + 2
    lda tier3_cr_atk0_type,x
    sta tc_atks + 0
    lda tier3_cr_atk0_dice,x
    sta tc_atks + 1
    lda tier3_cr_atk0_sides,x
    sta tc_atks + 2
    lda tier3_cr_atk1_type,x
    sta tc_atks + 3
    lda tier3_cr_atk1_dice,x
    sta tc_atks + 4
    lda tier3_cr_atk1_sides,x
    sta tc_atks + 5
    lda tier3_cr_name_lo,x
    sta t3_name_read + 1
    lda tier3_cr_name_hi,x
    sta t3_name_read + 2
    ldy #0
!trc_atk:
    jsr t3_rec_read
    cmp tc_atks,y
    bne !trc_fail+
    iny
    cpy #6
    bne !trc_atk-
    ldx #0
!trc_name:
    jsr t3_rec_read
    sta tc_ch
    jsr t3_name_read
    cmp tc_ch
    bne !trc_fail+
    iny
    inx
    cmp #0
    bne !trc_name-
    lda #$01
    rts
!trc_fail:
    lda #$00
    rts

// Self-modified readers: A = record byte Y / name byte X.
t3_rec_read:
    lda $ffff,y
    rts
t3_name_read:
    lda $ffff,x
    rts

tc_atks: .fill 6, 0
tc_ch:   .byte 0

// atk0 type/dice/sides, atk1 type/dice/sides, then the name
tc_hulk_row:  .byte T3_ATK_NORMAL, 1, 6, T3_ATK_NORMAL, 2, 6
              .text "Umber Hulk" ; .byte 0
tc_troll_row: .byte T3_ATK_NORMAL, 1, 4, T3_ATK_NORMAL, 1, 6
              .text "Troll" ; .byte 0

#import "../creature_data/tier3.s"

test_end:
.assert "Tier3 data test stays below BASIC ROM", test_end <= $a000, true
