// test_balrog_victory.s — Focused runtime tests for the Balrog win condition
// (docs/BACKLOG.md "Add Balrog victory and retirement flow"). Pins
// combat_note_kill (type + level-100 guard, once-only pending latch), the
// eff_kill_monster choke point shared by spell/earthquake/dispel kills, and
// the once-only winner message.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tc_results: .fill 6, $ff

.pc = $080E "Test Code"

.encoding "screencode_mixed"

test_bootstrap:
    sei
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    :BankOutKernal()
    ldx #5
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
tbv_msg_count:  .byte 0   // msg_print call count
tbv_levelups:   .byte 0   // combat_check_levelup call count

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_msg_print:
    inc tbv_msg_count
    rts

test_check_levelup:
    inc tbv_levelups
    rts

// test_reset — clear winner state, spies, monster table; cr_level[Balrog]=100.
test_reset:
    jsr player_init
    jsr monster_init_table
    lda zp_game_flags
    and #~GAME_FLAG_WINNER & $ff
    sta zp_game_flags
    lda #0
    sta cmb_winner_pending
    sta tbv_msg_count
    sta tbv_levelups
    lda #100
    sta cr_level + CREATURE_BALROG
    rts

// Redirect map row 20 to scratch so monster_remove's FLAG_OCCUPIED clear never
// touches the real map ($C000 overlaps this suite's code).
tbv_map_row: .fill MAP_COLS, 0

test_map_redirect:
    lda #<tbv_map_row
    sta map_row_lo + 20
    lda #>tbv_map_row
    sta map_row_hi + 20
    rts

test_start:
    :PatchJump(msg_print, test_msg_print)
    :PatchJump(combat_check_levelup, test_check_levelup)

    // Test 0: non-Balrog kill -> no winner flag, carry clear, no pending.
    jsr test_reset
    lda #4                      // Ordinary creature
    sta cmb_type
    jsr combat_note_kill
    bcs !t0_fail+
    lda zp_game_flags
    and #GAME_FLAG_WINNER
    bne !t0_fail+
    lda cmb_winner_pending
    bne !t0_fail+
    lda #$01
    sta tc_results + 0
    jmp !t1+
!t0_fail:
    lda #$00
    sta tc_results + 0

    // Test 1: Balrog kill (level 100 guard passes) -> winner flag set, pending
    // latched, carry set.
!t1:
    jsr test_reset
    lda #CREATURE_BALROG
    sta cmb_type
    jsr combat_note_kill
    bcc !t1_fail+
    lda zp_game_flags
    and #GAME_FLAG_WINNER
    beq !t1_fail+
    lda cmb_winner_pending
    cmp #1
    bne !t1_fail+
    lda #$01
    sta tc_results + 1
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 1

    // Test 2: winner flag already set -> once-only: no pending, carry clear.
!t2:
    jsr test_reset
    lda zp_game_flags
    ora #GAME_FLAG_WINNER
    sta zp_game_flags
    lda #CREATURE_BALROG
    sta cmb_type
    jsr combat_note_kill
    bcs !t2_fail+
    lda cmb_winner_pending
    bne !t2_fail+
    lda zp_game_flags
    and #GAME_FLAG_WINNER
    beq !t2_fail+
    lda #$01
    sta tc_results + 2
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 2

    // Test 3: Balrog type but cr_level != 100 -> guard rejects, no flag.
!t3:
    jsr test_reset
    lda #50
    sta cr_level + CREATURE_BALROG
    lda #CREATURE_BALROG
    sta cmb_type
    jsr combat_note_kill
    bcs !t3_fail+
    lda zp_game_flags
    and #GAME_FLAG_WINNER
    bne !t3_fail+
    lda #$01
    sta tc_results + 3
    jmp !t4+
!t3_fail:
    lda #$00
    sta tc_results + 3

    // Test 4: eff_kill_monster on a live Balrog slot (the spell/earthquake/
    // dispel kill choke point) -> winner flag set, slot emptied, count drops.
!t4:
    jsr test_reset
    jsr test_map_redirect
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #CREATURE_BALROG
    sta (zp_ptr0),y
    ldy #MX_X
    lda #10
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #20
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #0
    sta (zp_ptr0),y
    lda #1
    sta zp_mon_count
    ldx #0
    jsr eff_kill_monster
    lda zp_game_flags
    and #GAME_FLAG_WINNER
    beq !t4_fail+
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    bne !t4_fail+
    lda zp_mon_count
    bne !t4_fail+
    lda #$01
    sta tc_results + 4
    jmp !t5+
!t4_fail:
    lda #$00
    sta tc_results + 4

    // Test 5: winner message prints exactly once: pending=1 -> one msg_print
    // and pending cleared; a second call prints nothing.
!t5:
    jsr test_reset
    lda #1
    sta cmb_winner_pending
    jsr combat_print_winner_message
    lda tbv_msg_count
    cmp #1
    bne !t5_fail+
    lda cmb_winner_pending
    bne !t5_fail+
    jsr combat_print_winner_message
    lda tbv_msg_count
    cmp #1
    bne !t5_fail+
    lda #$01
    sta tc_results + 5
    jmp !done+
!t5_fail:
    lda #$00
    sta tc_results + 5

!done:
    jmp test_finish
