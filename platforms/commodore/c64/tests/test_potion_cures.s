// test_potion_cures.s — Cure-wounds and Healing potions through production
// item_quaff (the iq_dispatch table for #17/#25, the shared phase-3 path for
// #96/#100) and the production turn_tick_effects expiry that follows a cure.
//
// Oracle: VMS Moria 4.8 (pinned adce6c88) source/include/potions.inc quaff
// cases 13-16 (hp_player(damroll('2d7' / '4d7' / '6d7')), hp_player(1000))
// and 29-31 (cure_blindness, cure_confusion, cure_poison), selected by the
// potion flags in values.inc (Cure Light Wounds %X'10001000', Cure Serious
// %X'30002000', Cure Critical %X'70004000', Healing %X'70008000');
// spells.inc hp_player (no effect and no message at chp >= mhp; message by
// trunc(num/5)) and cure_* (a timer above 1 becomes 1, else unchanged);
// moria.inc status loop (a timer reaching 0 prints its message; the
// poisoned expiry turn does no damage). Umoria 5.7.15 (pinned 2a2a6b79)
// src/player_quaff.cpp and src/player_magic.cpp agree on every value tested.
//
// Results at $0400+: $01 = pass, $00 = fail per test.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tc_results: .fill 12, $ff      // Result buffer (copied to $0400 at the end)

.pc = $080E "Test Code"

.encoding "screencode_mixed"

// Bootstrap + exit trampoline must stay in "Test Code" so run_tests.sh
// breaks at the BRK below rather than at the end of the imported body.
test_bootstrap:
    :BankOutBasic()
    jmp test_start

// test_finish — Copy results to $0400 and halt.
test_finish:
    sei
    :BankOutBasic()
    :BankOutKernal()
    ldx #11
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    :BankInKernal()
    brk

.pc = $0840 "Main"

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
#import "../../../../core/ui_status.s"
#import "../../../../core/ui_help_clear.s"
#import "../../../../core/ui_character.s"
#import "../../../../core/stat_display.s"
.segmentdef TestCreateOverlay [start=$D000]
.segment TestCreateOverlay
#import "../../../../core/background_data.s"
#import "../../../../core/player_create.s"
.segment Default
#import "../../../../core/sound.s"
#import "../../../../core/dungeon_data.s"
#import "../../../../core/huffman.s"
#import "../../../../core/dungeon_features.s"
#import "../../../../core/monster.s"
#import "../../../../core/tier_manager.s"
#import "../../common/overlay.s"
#import "../../../../core/monster_ai.s"
#import "../../../../core/recall.s"
#import "../../../../core/monster_magic.s"
#import "../../../../core/item.s"
#import "../../../../core/special_rooms.s"
#import "../../../../core/ego_items.s"
#import "../../../../core/special_rooms_stubs.s"
#import "../../../../core/player_items.s"
#import "../../../../core/projectile.s"
#import "../../../../core/spell_effects.s"
#import "../../../../core/spell_data.s"
#import "../../../../core/player_move.s"
#import "../../../../core/turn.s"
#import "../dungeon_render.s"
#import "../../../../core/dungeon_los.s"
#import "../../../../core/combat.s"
#import "../../../../core/scene_mat_tile.s"
#import "../../../../core/monster_attack.s"
// Linker stub — special-room generation is not exercised by this suite.
random_floor_in_room:
    lda #10
    ldy #10
    rts
magic_recalc_mana:
magic_check_new_spells:
store_init_all:
store_restock_all:
store_enter:
ui_help_show_paged:
ui_help_display:
help_draw_line:
help_draw_hborder:
ui_inv_display:
ui_inv_select_display:
ui_equip_display:
    rts
#import "../../../../core/ui_trampoline_stubs.s"

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

// Message spy: effect messages go through huff_print_msg; the quaff prompt
// does not (piw_print_prompt_with_count), so these count effect messages.
tpm_huff_calls:   .byte 0
tpm_last_huff_id: .byte 0
test_huff_print_msg:
    stx tpm_last_huff_id
    inc tpm_huff_calls
    rts

// Scratch
tq_item:      .byte 0
tq_lo:        .byte 0
tq_hi:        .byte 0
tq_loop:      .byte 0
tq_ok:        .byte 0
tq_outside:   .byte 0
tq_carry:     .byte 0

// tq_timers — A = poison, X = blind, Y = confuse timers; other timers 0.
tq_timers:
    sta tq_t_poison
    stx tq_t_blind
    sty tq_t_confuse
    lda #0
    ldx #zp_eff_word_recall - zp_eff_poison
!clr:
    sta zp_eff_poison,x
    dex
    bpl !clr-
    sta eff_fear_timer
    sta eff_invuln_timer
    sta eff_detect_timer
    lda tq_t_poison
    sta zp_eff_poison
    lda tq_t_blind
    sta zp_eff_blind
    lda tq_t_confuse
    sta zp_eff_confuse
    rts
tq_t_poison:  .byte 0
tq_t_blind:   .byte 0
tq_t_confuse: .byte 0

// tq_set_hp — HP = A (lo) / X (hi), max HP = tq_lo (lo) / tq_hi (hi)
tq_set_hp:
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    stx zp_player_hp_hi
    stx player_data + PL_HP_HI
    lda tq_lo
    sta zp_player_mhp_lo
    sta player_data + PL_MHP_LO
    lda tq_hi
    sta zp_player_mhp_hi
    sta player_data + PL_MHP_HI
    rts

// tq_quaff — Quaff potion type A from slot 0 through production item_quaff.
// Output: tq_carry = 1 when a turn was consumed. Message spy reset first.
tq_quaff:
    sta tq_item
    jsr item_init_inventory
    lda tq_item
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags
    sta zp_msg_flags
    sta tpm_huff_calls
    lda #$ff
    sta tpm_last_huff_id
    lda #2
    sta $c6
    lda #$41                    // 'A' = slot 0
    sta $0277
    lda #$20
    sta $0278
    jsr item_quaff
    lda #0
    rol
    sta tq_carry
    rts

// tq_range — Quaff potion type A 100 times from HP 1 / max HP 255 and check
// each heal against [tq_lo, tq_hi]. Output: tq_ok = 1 when every heal is in
// range and a turn was consumed; tq_outside = heals outside [4, 11] (the
// pre-fix Cure Light Wounds range, rng(8) + 4).
tq_range:
    sta tq_item
    lda tq_lo
    sta tq_r_lo
    lda tq_hi
    sta tq_r_hi
    lda #255                    // max HP 255 for every quaff
    sta tq_lo
    lda #0
    sta tq_hi
    lda #1
    sta tq_ok
    lda #0
    sta tq_outside
    lda #100
    sta tq_loop
!loop:
    lda #0
    tax
    tay
    jsr tq_timers
    lda #1
    ldx #0
    jsr tq_set_hp
    lda tq_item
    jsr tq_quaff
    lda tq_carry
    beq !bad+
    lda zp_player_hp_hi
    bne !bad+
    lda zp_player_hp_lo
    sec
    sbc #1                      // heal = HP - 1
    cmp tq_r_lo
    bcc !bad+
    cmp tq_r_hi
    beq !in+
    bcs !bad+
!in:
    cmp #4
    bcc !outside+
    cmp #12
    bcc !next+
!outside:
    inc tq_outside
    jmp !next+
!bad:
    lda #0
    sta tq_ok
!next:
    dec tq_loop
    bne !loop-
    rts
tq_r_lo: .byte 0
tq_r_hi: .byte 0

// tq_hp_in — carry set when 8-bit HP (hi 0) is in [tq_lo, tq_hi]
tq_hp_in:
    lda zp_player_hp_hi
    bne !no+
    lda zp_player_hp_lo
    cmp tq_lo
    bcc !no+
    cmp tq_hi
    beq !yes+
    bcs !no+
!yes:
    sec
    rts
!no:
    clc
    rts

test_start:
    :PatchJump(input_wait_release, store_enter)

    // Seed RNG deterministically
    lda #$42
    sta zp_rng_0
    lda #$13
    sta zp_rng_1
    lda #$7a
    sta zp_rng_2
    lda #$f1
    sta zp_rng_3

    jsr msg_init
    jsr hal_sound_init
    lda #0
    sta zp_game_flags
    sta player_data + PL_SPELL_TYPE  // no mana regen in turn_tick_effects
    lda #10
    sta player_data + PL_CON_CUR
    sta zp_player_con
    :PatchJump(huff_print_msg, test_huff_print_msg)

    // ==========================================
    // Test 1: Cure Light Wounds (#17) heals 2d7 and cures blindness only
    // (VMS cases 13 + 29). HP 50/200; poison, blind, confuse all 40.
    // ==========================================
    lda #40
    ldx #40
    ldy #40
    jsr tq_timers
    lda #200
    sta tq_lo
    lda #0
    sta tq_hi
    lda #50
    ldx #0
    jsr tq_set_hp
    lda #17
    jsr tq_quaff
    lda #$00
    sta tc_results + 0
    lda tq_carry
    beq !t1_done+
    lda inv_item_id
    cmp #FI_EMPTY
    bne !t1_done+
    lda zp_eff_blind
    cmp #1
    bne !t1_done+
    lda zp_eff_confuse
    cmp #40
    bne !t1_done+
    lda zp_eff_poison
    cmp #40
    bne !t1_done+
    lda #52                     // 50 + 2d7 = [52, 64]
    sta tq_lo
    lda #64
    sta tq_hi
    jsr tq_hp_in
    bcc !t1_done+
    lda player_data + PL_HP_LO
    cmp zp_player_hp_lo
    bne !t1_done+
    lda #$01
    sta tc_results + 0
!t1_done:

    // ==========================================
    // Test 2: Cure Serious Wounds (#25) heals 4d7 and cures blindness and
    // confusion, not poison (VMS cases 14 + 29 + 30).
    // ==========================================
    lda #40
    ldx #40
    ldy #40
    jsr tq_timers
    lda #200
    sta tq_lo
    lda #0
    sta tq_hi
    lda #50
    ldx #0
    jsr tq_set_hp
    lda #25
    jsr tq_quaff
    lda #$00
    sta tc_results + 1
    lda tq_carry
    beq !t2_done+
    lda zp_eff_blind
    cmp #1
    bne !t2_done+
    lda zp_eff_confuse
    cmp #1
    bne !t2_done+
    lda zp_eff_poison
    cmp #40
    bne !t2_done+
    lda #54                     // 50 + 4d7 = [54, 78]
    sta tq_lo
    lda #78
    sta tq_hi
    jsr tq_hp_in
    bcc !t2_done+
    lda #$01
    sta tc_results + 1
!t2_done:

    // ==========================================
    // Test 3: Cure Critical Wounds (#100, phase-3 path) heals 6d7 and cures
    // blindness, confusion and poison (VMS cases 15 + 29 + 30 + 31).
    // ==========================================
    lda #40
    ldx #40
    ldy #40
    jsr tq_timers
    lda #200
    sta tq_lo
    lda #0
    sta tq_hi
    lda #50
    ldx #0
    jsr tq_set_hp
    lda #ITEM_TYPE_POT_CURE_CRITICAL
    jsr tq_quaff
    lda #$00
    sta tc_results + 2
    lda tq_carry
    beq !t3_done+
    lda zp_eff_blind
    cmp #1
    bne !t3_done+
    lda zp_eff_confuse
    cmp #1
    bne !t3_done+
    lda zp_eff_poison
    cmp #1
    bne !t3_done+
    lda #56                     // 50 + 6d7 = [56, 92]
    sta tq_lo
    lda #92
    sta tq_hi
    jsr tq_hp_in
    bcc !t3_done+
    lda #$01
    sta tc_results + 2
!t3_done:

    // ==========================================
    // Test 4: Healing (#96) heals exactly 1000 below a 1100 max (VMS case
    // 16, hp_player(1000)), prints "You feel very good." once (trunc(1000/5)
    // >= 7) and cures all three.
    // ==========================================
    lda #40
    ldx #40
    ldy #40
    jsr tq_timers
    lda #<1100
    sta tq_lo
    lda #>1100
    sta tq_hi
    lda #1
    ldx #0
    jsr tq_set_hp
    lda #ITEM_TYPE_POT_HEALING
    jsr tq_quaff
    lda #$00
    sta tc_results + 3
    lda tq_carry
    beq !t4_done+
    lda zp_player_hp_lo
    cmp #<1001
    bne !t4_done+
    lda zp_player_hp_hi
    cmp #>1001
    bne !t4_done+
    lda player_data + PL_HP_LO
    cmp #<1001
    bne !t4_done+
    lda player_data + PL_HP_HI
    cmp #>1001
    bne !t4_done+
    lda tpm_huff_calls
    cmp #1
    bne !t4_done+
    lda tpm_last_huff_id
    cmp #HSTR_PIQ_VERY_GOOD
    bne !t4_done+
    lda zp_eff_blind
    cmp #1
    bne !t4_done+
    lda zp_eff_confuse
    cmp #1
    bne !t4_done+
    lda zp_eff_poison
    cmp #1
    bne !t4_done+
    lda #$01
    sta tc_results + 3
!t4_done:

    // ==========================================
    // Test 5: Healing caps at max HP (100/600 -> 600) and cure_* leaves a
    // timer of 0 or 1 alone (VMS "if (blind > 1)"): poison 0, blind 1,
    // confuse 2 -> 0, 1, 1.
    // ==========================================
    lda #0
    ldx #1
    ldy #2
    jsr tq_timers
    lda #<600
    sta tq_lo
    lda #>600
    sta tq_hi
    lda #100
    ldx #0
    jsr tq_set_hp
    lda #ITEM_TYPE_POT_HEALING
    jsr tq_quaff
    lda #$00
    sta tc_results + 4
    lda zp_player_hp_lo
    cmp #<600
    bne !t5_done+
    lda zp_player_hp_hi
    cmp #>600
    bne !t5_done+
    lda zp_eff_poison
    bne !t5_done+
    lda zp_eff_blind
    cmp #1
    bne !t5_done+
    lda zp_eff_confuse
    cmp #1
    bne !t5_done+
    lda #$01
    sta tc_results + 4
!t5_done:

    // ==========================================
    // Test 6: at full HP, hp_player does nothing and prints nothing, but the
    // cures still apply (separate flag bits, VMS cases 29-31).
    // ==========================================
    lda #40
    ldx #40
    ldy #40
    jsr tq_timers
    lda #<300
    sta tq_lo
    lda #>300
    sta tq_hi
    lda #<300
    ldx #>300
    jsr tq_set_hp
    lda #ITEM_TYPE_POT_CURE_CRITICAL
    jsr tq_quaff
    lda #$00
    sta tc_results + 5
    lda tq_carry
    beq !t6_done+
    lda zp_player_hp_lo
    cmp #<300
    bne !t6_done+
    lda zp_player_hp_hi
    cmp #>300
    bne !t6_done+
    lda tpm_huff_calls
    bne !t6_done+
    lda zp_eff_blind
    cmp #1
    bne !t6_done+
    lda zp_eff_confuse
    cmp #1
    bne !t6_done+
    lda zp_eff_poison
    cmp #1
    bne !t6_done+
    lda #$01
    sta tc_results + 5
!t6_done:

    // ==========================================
    // Tests 7-9: heal ranges over 100 quaffs each: 2d7 = [2, 14], 4d7 =
    // [4, 28], 6d7 = [6, 42]. Test 7 also needs a heal outside [4, 11]
    // (pre-fix rng(8) + 4); 2d7 lands in [4, 11] with p = 40/49, so 100 in a
    // row is p < 2e-9 (and the seeded RNG is deterministic). Test 8's upper
    // bound 28 rejects the pre-fix 5d8 + 5 = [10, 45].
    // ==========================================
    lda #2
    sta tq_lo
    lda #14
    sta tq_hi
    lda #17
    jsr tq_range
    lda #$00
    sta tc_results + 6
    lda tq_ok
    beq !t7_done+
    lda tq_outside
    beq !t7_done+
    lda #$01
    sta tc_results + 6
!t7_done:

    lda #4
    sta tq_lo
    lda #28
    sta tq_hi
    lda #25
    jsr tq_range
    lda tq_ok
    sta tc_results + 7

    lda #6
    sta tq_lo
    lda #42
    sta tq_hi
    lda #ITEM_TYPE_POT_CURE_CRITICAL
    jsr tq_range
    lda tq_ok
    sta tc_results + 8

    // ==========================================
    // Tests 10-12: the cured timer ends on the production effect tick that
    // follows (turn_post_action runs turn_tick_effects): blindness ends with
    // "You can see again." and a viewport redraw request; confusion with
    // "You feel less confused."; poison with "You feel better." and no
    // damage on the expiry turn (VMS moria.inc; TRN-010).
    // ==========================================
    lda #0
    ldx #40
    ldy #0
    jsr tq_timers
    lda #200
    sta tq_lo
    lda #0
    sta tq_hi
    lda #50
    ldx #0
    jsr tq_set_hp
    lda #17
    jsr tq_quaff
    lda #0
    sta vis_room_revealed
    sta tpm_huff_calls
    jsr turn_tick_effects
    lda #$00
    sta tc_results + 9
    lda zp_eff_blind
    bne !t10_done+
    lda vis_room_revealed
    beq !t10_done+
    lda tpm_huff_calls
    cmp #1
    bne !t10_done+
    lda tpm_last_huff_id
    cmp #HSTR_EFF_BLIND_END
    bne !t10_done+
    lda #$01
    sta tc_results + 9
!t10_done:

    lda #0
    ldx #0
    ldy #40
    jsr tq_timers
    lda #50
    ldx #0
    jsr tq_set_hp
    lda #25
    jsr tq_quaff
    lda #0
    sta tpm_huff_calls
    jsr turn_tick_effects
    lda #$00
    sta tc_results + 10
    lda zp_eff_confuse
    bne !t11_done+
    lda tpm_huff_calls
    cmp #1
    bne !t11_done+
    lda tpm_last_huff_id
    cmp #HSTR_EFF_CONFUSE_END
    bne !t11_done+
    lda #$01
    sta tc_results + 10
!t11_done:

    lda #40
    ldx #0
    ldy #0
    jsr tq_timers
    lda #20                     // full HP: no heal, so HP stays 20
    sta tq_lo
    lda #0
    sta tq_hi
    lda #20
    ldx #0
    jsr tq_set_hp
    lda #ITEM_TYPE_POT_CURE_CRITICAL
    jsr tq_quaff
    lda #0
    sta tpm_huff_calls
    jsr turn_tick_effects
    lda #$00
    sta tc_results + 11
    lda zp_eff_poison
    bne !t12_done+
    lda zp_player_hp_hi
    bne !t12_done+
    lda zp_player_hp_lo
    cmp #20
    bne !t12_done+
    lda tpm_huff_calls
    cmp #1
    bne !t12_done+
    lda tpm_last_huff_id
    cmp #HSTR_EFF_POISON_END
    bne !t12_done+
    lda #$01
    sta tc_results + 11
!t12_done:

    jmp test_finish

potion_cures_test_body_end:
.assert "Potion cures test stays below MAP_BASE", potion_cures_test_body_end <= MAP_BASE, true
