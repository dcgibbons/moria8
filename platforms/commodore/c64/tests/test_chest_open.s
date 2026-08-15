// test_chest_open.s — Focused runtime tests for step-9 chest Open behavior
// (docs/CHEST_DESIGN.md "Open (o <Dir>)"). Exercises the production
// chest_open_command through its real routine: lock pick (skill-based
// threshold), XP award, confused lockout, trap-on-open (STR / explosion /
// summon), opened state, and re-open turn consumption.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tc_results: .fill 8, $ff

.pc = $080E "Test Code"

.encoding "screencode_mixed"

test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    :BankOutKernal()
    ldx #7
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
tco_trap_spy:    .byte 0   // trap_apply_damage call count
tco_huff_count:  .byte 0   // huff_print_msg call count
tco_huff_last:   .byte 0   // last HSTR_* id printed
tco_skill_spy:   .byte 0   // chest_disarm_skill call count
tco_skill:       .byte 0   // controlled effective skill value
tco_rng_next:    .byte 0   // controlled rng_range result

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx tco_huff_last
    inc tco_huff_count
    rts

test_trap_apply_damage:
    inc tco_trap_spy
    rts

test_rng_range:
    lda tco_rng_next
    rts

test_chest_disarm_skill:
    inc tco_skill_spy
    lda tco_skill
    rts

// test_reset — clear floor items, spies, player XP/effects; chest target (12,18).
test_reset:
    jsr player_init
    jsr item_init_floor
    lda #0
    sta tco_trap_spy
    sta tco_huff_count
    sta tco_huff_last
    sta tco_skill_spy
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

    // Test 0: unlocked, untrapped chest opens, sets OPENED, consumes the turn,
    // fires no trap, awards no XP.
    jsr test_reset
    lda #0
    ldx #5
    jsr test_setup_chest
    jsr chest_open_command
    bcc !t0_fail+
    lda fi_p1 + 0
    and #CHEST_P1_OPENED
    beq !t0_fail+
    lda tco_trap_spy
    bne !t0_fail+
    lda player_data + PL_XP_0
    bne !t0_fail+
    lda #$01
    sta tc_results + 0
    jmp !t1+
!t0_fail:
    lda #$00
    sta tc_results + 0

    // Test 1: locked chest, successful pick (skill 50 vs difficulty 10 ->
    // threshold capped at 100, rng 99) clears the lock, awards source_level XP,
    // then opens (no traps) and sets OPENED.
!t1:
    jsr test_reset
    lda #50
    sta tco_skill
    lda #99
    sta tco_rng_next
    lda #CHEST_P1_LOCKED
    ldx #5
    jsr test_setup_chest
    jsr chest_open_command
    bcc !t1_fail+
    lda fi_p1 + 0
    and #CHEST_P1_LOCKED
    bne !t1_fail+
    lda fi_p1 + 0
    and #CHEST_P1_OPENED
    beq !t1_fail+
    lda player_data + PL_XP_0
    cmp #5
    bne !t1_fail+
    lda #$01
    sta tc_results + 1
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 1

    // Test 2: locked chest, failed pick (skill 50 vs source_level 127 ->
    // difficulty 254, threshold 0, rng 0) keeps the lock, awards no XP, sets no
    // OPENED, consumes the turn.
!t2:
    jsr test_reset
    lda #50
    sta tco_skill
    lda #0
    sta tco_rng_next
    lda #CHEST_P1_LOCKED
    ldx #127
    jsr test_setup_chest
    jsr chest_open_command
    bcc !t2_fail+
    lda fi_p1 + 0
    and #CHEST_P1_LOCKED
    beq !t2_fail+
    lda fi_p1 + 0
    and #CHEST_P1_OPENED
    bne !t2_fail+
    lda player_data + PL_XP_0
    bne !t2_fail+
    lda #$01
    sta tc_results + 2
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 2

    // Test 3: confused player cannot pick a lock — message, lock intact, no
    // skill roll consumed, turn consumed.
!t3:
    jsr test_reset
    lda #1
    sta zp_eff_confuse
    lda #CHEST_P1_LOCKED
    ldx #5
    jsr test_setup_chest
    jsr chest_open_command
    bcc !t3_fail+
    lda fi_p1 + 0
    and #CHEST_P1_LOCKED
    beq !t3_fail+
    lda fi_p1 + 0
    and #CHEST_P1_OPENED
    bne !t3_fail+
    lda tco_skill_spy
    bne !t3_fail+
    lda tco_huff_last
    cmp #HSTR_CHEST_PICK_CONFUSED
    bne !t3_fail+
    lda #$01
    sta tc_results + 3
    jmp !t4+
!t3_fail:
    lda #$00
    sta tc_results + 3

    // Test 4: unlocked chest with an armed lose-STR trap fires on open — trap
    // damage applied once, STR decremented 10->9, trap identified (bit 6) and
    // disarmed (bit 1 cleared), OPENED set.
!t4:
    jsr test_reset
    lda #CHEST_P1_TRAP_STR
    ldx #5
    jsr test_setup_chest
    jsr chest_open_command
    bcc !t4_fail+
    lda fi_p1 + 0
    and #CHEST_P1_OPENED
    beq !t4_fail+
    lda fi_p1 + 0
    and #CHEST_P1_TRAP_STR
    bne !t4_fail+
    lda fi_p1 + 0
    and #CHEST_P1_TRAP_FOUND
    beq !t4_fail+
    lda tco_trap_spy
    cmp #1
    bne !t4_fail+
    lda player_data + PL_STR_CUR
    cmp #9
    bne !t4_fail+
    lda #$01
    sta tc_results + 4
    jmp !t5+
!t4_fail:
    lda #$00
    sta tc_results + 4

    // Test 5: explosion trap destroys the chest (slot emptied), suppresses the
    // OPENED state, still applies damage and consumes the turn.
!t5:
    jsr test_reset
    lda #CHEST_P1_TRAP_EXPL
    ldx #5
    jsr test_setup_chest
    jsr chest_open_command
    bcc !t5_fail+
    lda fi_item_id + 0
    cmp #FI_EMPTY
    bne !t5_fail+
    lda tco_trap_spy
    cmp #1
    bne !t5_fail+
    lda #$01
    sta tc_results + 5
    jmp !t6+
!t5_fail:
    lda #$00
    sta tc_results + 5

    // Test 6: summoning trap stages three deferred spawn attempts in the
    // resident latch, applies no direct damage, and the chest opens.
!t6:
    jsr test_reset
    lda #CHEST_P1_TRAP_SUMMON
    ldx #5
    jsr test_setup_chest
    jsr chest_open_command
    bcc !t6_fail+
    lda chest_pending_summons
    cmp #3
    bne !t6_fail+
    lda tco_trap_spy
    bne !t6_fail+
    lda fi_p1 + 0
    and #CHEST_P1_OPENED
    beq !t6_fail+
    lda #$01
    sta tc_results + 6
    jmp !t7+
!t6_fail:
    lda #$00
    sta tc_results + 6

    // Test 7: re-opening an already-opened chest consumes a turn, fires no trap,
    // and leaves OPENED set.
!t7:
    jsr test_reset
    lda #CHEST_P1_OPENED
    ldx #5
    jsr test_setup_chest
    jsr chest_open_command
    bcc !t7_fail+
    lda fi_p1 + 0
    and #CHEST_P1_OPENED
    beq !t7_fail+
    lda tco_trap_spy
    bne !t7_fail+
    lda #$01
    sta tc_results + 7
    jmp !done+
!t7_fail:
    lda #$00
    sta tc_results + 7

!done:
    jmp test_finish
