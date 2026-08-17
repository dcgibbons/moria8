// test_chest_disarm.s — Focused runtime tests for step-10 chest Disarm behavior
// (docs/CHEST_DESIGN.md "Disarm (D <Dir>)"). Exercises the production
// chest_disarm_command: unfound-vs-not-trapped gating, the VMS chest threshold
// (skill - source_level - 1), trap-bit clearing with lock preserved, XP award,
// ordinary failure, and bad-fail trap firing that leaves the trap armed.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tc_results: .fill 7, $ff

.pc = $080E "Test Code"

.encoding "screencode_mixed"

test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    :BankOutKernal()
    ldx #6
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
#import "../../../../core/dungeon_gen.s"
#import "../../../../core/huffman.s"
#define CHEST_ROUTING_ENABLED
#import "../../../../core/dungeon_features.s"
.macro ChestSearchSegment() {
}
.macro ChestSearchRestoreSegment() {
}
#import "../../../../core/chest_search.s"
#import "../../../../core/monster.s"
#import "../../../../core/tier_manager.s"
#import "../../common/overlay.s"
#import "../../../../core/monster_ai.s"
#import "../../../../core/recall.s"
#import "../../../../core/monster_magic.s"
#import "../../../../core/item.s"
#import "../../../../core/item_tables.s"
#import "../../../../core/special_rooms.s"
#import "../../../../core/ego_items.s"
#import "../../../../core/special_rooms_stubs.s"
#import "../../../../core/player_items.s"
#import "../../../../core/projectile.s"
#import "../../../../core/spell_effects.s"
#import "../../../../core/spell_effects_overlay.s"
#import "../../../../core/spell_data.s"
#import "../../../../core/player_magic_state.s"
#import "../../../../core/player_magic_state_ops.s"
#import "../../../../core/player_magic.s"
#import "../../../../core/player_magic_feedback.s"
#import "../dungeon_render.s"
#import "../../../../core/dungeon_los.s"
#import "../../../../core/player_move.s"
#import "../../../../core/combat.s"
#import "../../../../core/scene_mat_tile.s"
#import "../../../../core/monster_attack.s"
#import "../../../../core/turn.s"
#import "../../../../core/item_actions_overlay.s"
#import "../../../../core/ui_trampoline_stubs.s"
.macro ChestSummonsSegment() {
}
.macro ChestSummonsRestoreSegment() {
}
#import "../../../../core/chest_summons.s"
#import "../../../../core/chest.s"
.macro ChestLootSegment() {
}
.macro ChestLootRestoreSegment() {
}
#import "../../../../core/chest_loot.s"

store_init_all:
    rts

store_restock_all:
    rts

store_enter:
    rts

ui_help_show_paged:
ui_help_display:
help_draw_line:
help_draw_hborder:
ui_inv_display:
ui_inv_select_display:
ui_equip_display:
    rts

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// ---- Test spies / controlled stubs ----------------------------------------
tcd_trap_spy:    .byte 0   // trap_apply_damage call count
tcd_huff_count:  .byte 0   // huff_print_msg call count
tcd_huff_last:   .byte 0   // last HSTR_* id printed
tcd_huff_first:  .byte 0   // first HSTR_* id printed
tcd_skill_spy:   .byte 0   // chest_disarm_skill call count
tcd_skill:       .byte 0   // controlled effective skill value
tcd_rng_idx:     .byte 0   // rng sequence read index
tcd_rng_seq:     .fill 4, 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx tcd_huff_last
    lda tcd_huff_count
    bne !not_first+
    stx tcd_huff_first
!not_first:
    inc tcd_huff_count
    rts

test_trap_apply_damage:
    inc tcd_trap_spy
    rts

test_rng_range:
    ldx tcd_rng_idx
    lda tcd_rng_seq,x
    inc tcd_rng_idx
    ldx #$ff                    // Clobber X like the real rng_range (guards the
    rts                         // chest_search_reveal slot-preservation fix)

test_chest_disarm_skill:
    inc tcd_skill_spy
    lda tcd_skill
    rts

// test_reset — clear floor items, spies, player XP/effects; chest target (12,18).
test_reset:
    jsr player_init
    jsr item_init_floor
    lda #0
    sta tcd_trap_spy
    sta tcd_huff_count
    sta tcd_huff_last
    sta tcd_huff_first
    sta tcd_skill_spy
    sta tcd_rng_idx
    sta zp_eff_confuse
    sta zp_eff_blind
    sta zp_eff_poison
    sta zp_eff_paralyze
    sta chest_pending_summons
    sta player_data + PL_XP_0
    sta player_data + PL_XP_1
    sta player_data + PL_XP_2
    lda #10
    sta player_data + PL_STR_CUR
    sta zp_player_str
    lda #12
    sta df_target_x
    lda #18
    sta df_target_y
    rts

// test_setup_chest — place a Small Wooden Chest (id 128) in floor slot 0 at the
// df_target tile. Input: A = p1 flags, X = to_hit (source_level).
test_setup_chest:
    pha
    txa
    pha
    jsr item_init_floor
    lda #128
    sta fi_item_id + 0
    lda df_target_x
    sta fi_x + 0
    lda df_target_y
    sta fi_y + 0
    pla
    sta fi_to_hit + 0
    pla
    sta fi_p1 + 0
    rts

test_start:
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(trap_apply_damage, test_trap_apply_damage)
    :PatchJump(rng_range, test_rng_range)
    :PatchJump(chest_disarm_skill, test_chest_disarm_skill)

    // Test 0: untrapped chest -> "The chest was not trapped.", no turn, no
    // skill roll, no state change.
    jsr test_reset
    lda #0
    ldx #5
    jsr test_setup_chest
    jsr chest_disarm_command
    bcs !t0_fail+
    lda tcd_huff_last
    cmp #HSTR_CHEST_DISARM_NOT_TRAPPED
    bne !t0_fail+
    lda tcd_skill_spy
    bne !t0_fail+
    lda tcd_trap_spy
    bne !t0_fail+
    lda #$01
    sta tc_results + 0
    jmp !t1+
!t0_fail:
    lda #$00
    sta tc_results + 0

    // Test 1: armed but unfound trap -> "I don't see a trap...", no turn, trap
    // stays armed and unfound, no skill roll.
!t1:
    jsr test_reset
    lda #CHEST_P1_TRAP_STR
    ldx #5
    jsr test_setup_chest
    jsr chest_disarm_command
    bcs !t1_fail+
    lda tcd_huff_last
    cmp #HSTR_CHEST_DISARM_UNFOUND
    bne !t1_fail+
    lda tcd_skill_spy
    bne !t1_fail+
    lda fi_p1 + 0
    and #CHEST_P1_TRAP_STR
    beq !t1_fail+
    lda fi_p1 + 0
    and #CHEST_P1_TRAP_FOUND
    bne !t1_fail+
    lda #$01
    sta tc_results + 1
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 1

    // Test 2: armed + found, successful disarm (skill 50, source_level 5 ->
    // threshold 44, rng 10 < 44) clears the trap, awards source_level XP,
    // prints disarmed, consumes the turn.
!t2:
    jsr test_reset
    lda #50
    sta tcd_skill
    lda #10
    sta tcd_rng_seq + 0
    lda #CHEST_P1_TRAP_STR | CHEST_P1_TRAP_FOUND
    ldx #5
    jsr test_setup_chest
    jsr chest_disarm_command
    bcc !t2_fail+
    lda fi_p1 + 0
    and #CHEST_P1_TRAP_STR
    bne !t2_fail+
    lda player_data + PL_XP_0
    cmp #5
    bne !t2_fail+
    lda tcd_huff_last
    cmp #HSTR_CHEST_DISARMED
    bne !t2_fail+
    lda #$01
    sta tc_results + 2
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 2

    // Test 3: successful disarm of a locked chest clears the trap but preserves
    // the lock.
!t3:
    jsr test_reset
    lda #50
    sta tcd_skill
    lda #10
    sta tcd_rng_seq + 0
    lda #CHEST_P1_LOCKED | CHEST_P1_TRAP_STR | CHEST_P1_TRAP_FOUND
    ldx #5
    jsr test_setup_chest
    jsr chest_disarm_command
    bcc !t3_fail+
    lda fi_p1 + 0
    and #CHEST_P1_TRAP_STR
    bne !t3_fail+
    lda fi_p1 + 0
    and #CHEST_P1_LOCKED
    beq !t3_fail+
    lda #$01
    sta tc_results + 3
    jmp !t4+
!t3_fail:
    lda #$00
    sta tc_results + 3

    // Test 4: ordinary failure (skill 50, threshold 44, rng 50 fails; bad-fail
    // roll rng 50 >= 5 is safe) leaves the trap armed, prints failed, consumes
    // the turn, fires nothing.
!t4:
    jsr test_reset
    lda #50
    sta tcd_skill
    lda #50
    sta tcd_rng_seq + 0
    sta tcd_rng_seq + 1
    lda #CHEST_P1_TRAP_STR | CHEST_P1_TRAP_FOUND
    ldx #5
    jsr test_setup_chest
    jsr chest_disarm_command
    bcc !t4_fail+
    lda tcd_huff_last
    cmp #HSTR_CHEST_DISARM_FAIL
    bne !t4_fail+
    lda fi_p1 + 0
    and #CHEST_P1_TRAP_STR
    beq !t4_fail+
    lda tcd_trap_spy
    bne !t4_fail+
    lda player_data + PL_XP_0
    bne !t4_fail+
    lda #$01
    sta tc_results + 4
    jmp !t5+
!t4_fail:
    lda #$00
    sta tc_results + 4

    // Test 5: bad failure (skill 3 < 6 forces the bad-fail branch; threshold 0
    // fails) fires the trap once, decrements STR, sets the found bit, and
    // leaves the trap armed (upstream keeps flags on a bad fail).
!t5:
    jsr test_reset
    lda #3
    sta tcd_skill
    lda #0
    sta tcd_rng_seq + 0
    lda #CHEST_P1_TRAP_STR | CHEST_P1_TRAP_FOUND
    ldx #5
    jsr test_setup_chest
    jsr chest_disarm_command
    bcc !t5_fail+
    lda tcd_huff_first
    cmp #HSTR_CHEST_DISARM_SET_OFF
    bne !t5_fail+
    lda tcd_trap_spy
    cmp #1
    bne !t5_fail+
    lda player_data + PL_STR_CUR
    cmp #9
    bne !t5_fail+
    lda fi_p1 + 0
    and #CHEST_P1_TRAP_STR
    beq !t5_fail+
    lda fi_p1 + 0
    and #CHEST_P1_TRAP_FOUND
    beq !t5_fail+
    lda #$01
    sta tc_results + 5
    jmp !t6+
!t5_fail:
    lda #$00
    sta tc_results + 5

    // Test 6: search reveals the trap (sets found), then disarm must take the
    // found path — not "I don't see a trap" (regression: search/disarm found-bit).
!t6:
    jsr test_reset
    lda #CHEST_P1_TRAP_STR
    ldx #5
    jsr test_setup_chest
    lda #100
    sta df_search_chance
    jsr chest_search_reveal          // should mark the trap found
    lda fi_p1 + 0
    and #CHEST_P1_TRAP_FOUND
    beq !t6_fail+
    lda #50
    sta tcd_skill
    lda #0                           // search roll and disarm threshold roll both succeed
    sta tcd_rng_seq + 0
    sta tcd_rng_seq + 1
    sta tcd_rng_seq + 2
    jsr chest_disarm_command
    bcc !t6_fail+
    lda tcd_huff_first
    cmp #HSTR_CHEST_DISARM_UNFOUND   // must NOT be "I don't see a trap..."
    beq !t6_fail+
    lda fi_p1 + 0
    and #CHEST_P1_TRAP_STR
    bne !t6_fail+
    lda #$01
    sta tc_results + 6
    jmp !done+
!t6_fail:
    lda #$00
    sta tc_results + 6

!done:
    jmp test_finish
