// test_timed_buffs.s — Haste and Protection from Evil durations through the
// production handlers: item_quaff (Potion of Speed, #18), item_read_scroll
// (Protect from Evil, #38), eff_haste_self, eff_staff_speed and
// eff_protect_from_evil (spell overlay, shared with the Staff of Speed).
//
// Oracle: VMS Moria 4.8 (pinned adce6c88) source/include/potions.inc case 23
// (fast := fast + randint(25) + 15), magic.inc case 28 (fast := fast +
// randint(20) + py.misc.lev), staffs.inc case 17 (fast := fast + randint(30)
// + 15), scrolls.inc case 28 and prayer.inc case 21 -> spells.inc
// protect_evil (protevil := protevil + randint(25) + 3*py.misc.lev).
// Umoria 5.7.15 (pinned 2a2a6b79) player_quaff.cpp, mage_spells.cpp,
// staves.cpp and player_magic.cpp playerProtectEvil agree. Upstream keeps
// fast and slow as separate unbounded counters; Moria8 has one signed byte
// (> 0 haste, < 0 slow), so haste stacks to +127 and adds onto a slow timer.
//
// Results at $0400+: $01 = pass, $00 = fail per test.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tc_results: .fill 10, $ff

.pc = $080E "Test Code"

.encoding "screencode_mixed"

test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    :BankOutKernal()
    ldx #9
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    :BankInKernal()
    brk

.pc = $0840 "Main"

#define COMPILE_EMBEDDED_DUNGEON_TEST_ROSTER

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
#import "../../../../core/input_contract.s"
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
#import "../../../../core/spell_data.s"
#import "../../../../core/projectile.s"
#import "../../../../core/spell_effects.s"
#import "../../../../core/spell_effects_overlay.s"
#import "../../../../core/player_magic_state.s"
#import "../../../../core/player_magic_state_ops.s"
#import "../../../../core/player_magic.s"
#import "../../../../core/player_magic_feedback.s"
#import "../../../../core/player_magic_slow_runtime.s"
#import "../../../../core/player_magic_execute_overlay.s"
viewport_update:
render_viewport:
render_single_tile:
render_local_area:
    rts
#import "../../../../core/dungeon_los.s"
#import "../../../../core/player_move.s"
#import "../../../../core/combat.s"
#import "../../../../core/scene_mat_tile.s"
#import "../../../../core/turn_render_state.s"
eff_fear_timer: .byte 0
monster_attack_player:
player_update_hunger_state:
    sec
    rts
mon_atk_apply_damage:
    clc
    rts
player_death_check:
    rts
store_init_all:
store_restock_all:
store_enter:
fill_map_rock:
random_floor_in_room:
ui_help_show_paged:
ui_help_display:
help_draw_line:
help_draw_hborder:
ui_inv_display:
ui_inv_select_display:
ui_equip_display:
    rts
#import "../../../../core/ui_trampoline_stubs.s"

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

recall_query_sc: .byte 0
// Linker stub — the spell overlay's genocide prompt is not exercised here.
recall_key_to_screen_code:
    clc
    rts

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

// Message spy: effect messages print through huff_print_msg.
ttb_huff_calls: .byte 0
test_huff_print_msg:
    inc ttb_huff_calls
    rts

test_input_get_key_a:
    lda #$41                    // 'A': the item in slot 0
    rts

// Scratch
ttb_item:  .byte 0
ttb_loop:  .byte 0
ttb_ok:    .byte 0
ttb_lo:    .byte 0
ttb_hi:    .byte 0
ttb_start: .byte 0
ttb_top:   .byte 0              // Values seen at ttb_hi
ttb_value: .byte 0

// ttb_give — Slot 0 holds one item of type ttb_item
ttb_give:
    jsr item_init_inventory
    lda ttb_item
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags
    sta zp_msg_flags
    sta zp_eff_blind
    rts

// ttb_run — Call routine (ttb_call) 100 times, each from timer value
// ttb_start; A = the timer's zero-page address. Each result must be in
// [ttb_lo, ttb_hi] (unsigned); ttb_top counts results equal to ttb_hi.
// Output: ttb_ok = 1 when every result is in range.
ttb_run:
    sta ttb_timer_lda + 1
    sta ttb_timer_sta + 1
    lda #1
    sta ttb_ok
    lda #0
    sta ttb_top
    lda #100
    sta ttb_loop
!run_loop:
    lda ttb_start
ttb_timer_sta:
    sta zp_eff_speed            // Operand patched: the timer under test
    jsr ttb_give
ttb_call:
    jsr $0000                   // Operand patched: the routine under test
ttb_timer_lda:
    lda zp_eff_speed            // Operand patched
    sta ttb_value
    cmp ttb_lo
    bcc !run_bad+
    cmp ttb_hi
    bcc !run_next+
    bne !run_bad+
    inc ttb_top
    bne !run_next+              // Always
!run_bad:
    lda #0
    sta ttb_ok
!run_next:
    dec ttb_loop
    bne !run_loop-
    rts

.macro TtbCall(routine) {
    lda #<routine
    sta ttb_call + 1
    lda #>routine
    sta ttb_call + 2
}

// ttb_quaff / ttb_read — the production item command on slot 0
ttb_quaff:
    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278
    jmp item_quaff
ttb_read:
    jmp item_read_scroll

test_start:
    :PatchJump(input_wait_release, store_enter)
    :PatchJump(input_get_key, test_input_get_key_a)

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
    :PatchJump(huff_print_msg, test_huff_print_msg)

    // ==========================================
    // Test 1: Potion of Speed (#18) from no haste: randint(25) + 15 =
    // 16-40 over 100 quaffs (VMS potions.inc case 23; before: 10-29).
    // ==========================================
    lda #18
    sta ttb_item
    lda #0
    sta ttb_start
    lda #16
    sta ttb_lo
    lda #40
    sta ttb_hi
    :TtbCall(ttb_quaff)
    lda #zp_eff_speed
    jsr ttb_run
    lda ttb_ok
    sta tc_results + 0

    // ==========================================
    // Test 2: stacking haste stops at +127. From 120 every quaff leaves
    // 127; before the fix 120 + 10-29 crossed into the slow half.
    // ==========================================
    lda #120
    sta ttb_start
    lda #127
    sta ttb_lo
    sta ttb_hi
    lda #zp_eff_speed
    jsr ttb_run
    lda ttb_ok
    sta tc_results + 1

    // ==========================================
    // Test 3: haste while slowed (timer -20) adds onto it: -20 + 16-40 =
    // -4..20, i.e. $fc-$ff or 0-20; before the fix the unsigned carry
    // capped it at 255 (slow 1).
    // ==========================================
    lda #$ec                    // -20
    sta ttb_start
    lda #1
    sta ttb_ok
    lda #60
    sta ttb_loop
!t3_loop:
    lda ttb_start
    sta zp_eff_speed
    jsr ttb_give
    jsr ttb_quaff
    lda zp_eff_speed
    bmi !t3_neg+
    cmp #21
    bcc !t3_next+
    bcs !t3_bad+
!t3_neg:
    cmp #$fc
    bcs !t3_next+
!t3_bad:
    lda #0
    sta ttb_ok
!t3_next:
    dec ttb_loop
    bne !t3_loop-
    lda ttb_ok
    sta tc_results + 2

    // ==========================================
    // Test 4: Haste Self at level 5: randint(20) + 5 = 6-25 (VMS magic.inc
    // case 28), and 25 is reached in 100 casts (before: rng_range(20) + 5
    // = 5-24).
    // ==========================================
    lda #5
    sta zp_player_lvl
    lda #0
    sta ttb_start
    lda #6
    sta ttb_lo
    lda #25
    sta ttb_hi
    :TtbCall(eff_haste_self)
    lda #zp_eff_speed
    jsr ttb_run
    lda ttb_ok
    beq !t4_store+
    lda ttb_top
    beq !t4_store+
    lda #$01
!t4_store:
    sta tc_results + 3

    // ==========================================
    // Test 5: Haste Self at level 40 from 100: 141-160 stops at 127
    // (before: the signed timer turned negative, i.e. slow).
    // ==========================================
    lda #40
    sta zp_player_lvl
    lda #100
    sta ttb_start
    lda #127
    sta ttb_lo
    sta ttb_hi
    lda #zp_eff_speed
    jsr ttb_run
    lda ttb_ok
    sta tc_results + 4

    // ==========================================
    // Test 6: Staff of Speed (production eff_staff_speed, the staff's
    // dispatch target) at level 1: randint(30) + 15 = 16-45 (VMS staffs.inc
    // case 17; before: Haste Self's rng_range(20) + lev = 1-20).
    // ==========================================
    lda #1
    sta zp_player_lvl
    lda #0
    sta ttb_start
    lda #16
    sta ttb_lo
    lda #45
    sta ttb_hi
    :TtbCall(eff_staff_speed)
    lda #zp_eff_speed
    jsr ttb_run
    lda ttb_ok
    sta tc_results + 5

    // ==========================================
    // Test 7: Scroll of Protect from Evil (#38) at level 20: randint(25) +
    // 60 = 61-85 (VMS scrolls.inc case 28 -> spells.inc protect_evil),
    // through item_read_scroll (before: rng_range(25) + 25 = 25-49).
    // ==========================================
    lda #20
    sta zp_player_lvl
    lda #38
    sta ttb_item
    lda #0
    sta ttb_start
    lda #61
    sta ttb_lo
    lda #85
    sta ttb_hi
    :TtbCall(ttb_read)
    lda #zp_eff_protect
    jsr ttb_run
    lda ttb_ok
    sta tc_results + 6

    // ==========================================
    // Test 8: the scroll adds onto an active timer and saturates at 255
    // (from 200: 261-285 -> 255).
    // ==========================================
    lda #200
    sta ttb_start
    lda #255
    sta ttb_lo
    sta ttb_hi
    lda #zp_eff_protect
    jsr ttb_run
    lda ttb_ok
    sta tc_results + 7

    // ==========================================
    // Test 9: the Protection from Evil prayer (production
    // eff_protect_from_evil) at level 20: 61-85 (VMS prayer.inc
    // case 21 -> protect_evil; before: 25-49).
    // ==========================================
    lda #0
    sta ttb_start
    lda #61
    sta ttb_lo
    lda #85
    sta ttb_hi
    :TtbCall(eff_protect_from_evil)
    lda #zp_eff_protect
    jsr ttb_run
    lda ttb_ok
    sta tc_results + 8

    // ==========================================
    // Test 10: the prayer saturates at 255 (from 200)
    // ==========================================
    lda #200
    sta ttb_start
    lda #255
    sta ttb_lo
    sta ttb_hi
    lda #zp_eff_protect
    jsr ttb_run
    lda ttb_ok
    sta tc_results + 9

    jmp test_finish

timed_buffs_test_end:
.assert "Timed buffs test stays below MAP_BASE", timed_buffs_test_end <= MAP_BASE, true
