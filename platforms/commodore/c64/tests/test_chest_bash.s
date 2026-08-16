// test_chest_bash.s — Focused runtime tests for step-11 chest Bash behavior
// (docs/CHEST_DESIGN.md "Bash (B <Dir>)"; VMS bash at moria.inc:3454).
// Exercises the production chest_bash_command: 1-in-10 destroy -> Ruined Chest
// (ID 134, p1/to_hit zeroed, even when opened), 1-in-10 lock break, the
// holds-firm fallback, and that bash never opens the chest nor disarms a trap.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tc_results: .fill 5, $ff

.pc = $080E "Test Code"

.encoding "screencode_mixed"

test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    :BankOutKernal()
    ldx #4
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
tcb_huff_count:  .byte 0   // huff_print_msg call count
tcb_huff_last:   .byte 0   // last HSTR_* id printed
tcb_huff_first:  .byte 0   // first HSTR_* id printed
tcb_rng_idx:     .byte 0   // rng sequence read index
tcb_rng_seq:     .fill 4, 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx tcb_huff_last
    lda tcb_huff_count
    bne !not_first+
    stx tcb_huff_first
!not_first:
    inc tcb_huff_count
    rts

test_rng_range:
    ldx tcb_rng_idx
    inc tcb_rng_idx
    lda tcb_rng_seq,x         // Load last so Z reflects the returned value
    rts

// test_reset — clear floor items and spies; chest target (12,18).
test_reset:
    jsr player_init
    jsr item_init_floor
    lda #0
    sta tcb_huff_count
    sta tcb_huff_last
    sta tcb_huff_first
    sta tcb_rng_idx
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
    :PatchJump(rng_range, test_rng_range)

    // Test 0: destroy roll succeeds (rng 0) on a locked+trapped chest -> Ruined
    // Chest (ID 134), p1/to_hit zeroed, destroy message, turn consumed.
    jsr test_reset
    lda #0
    sta tcb_rng_seq + 0
    lda #CHEST_P1_LOCKED | CHEST_P1_TRAP_STR
    ldx #5
    jsr test_setup_chest
    jsr chest_bash_command
    bcc !t0_fail+
    lda fi_item_id + 0
    cmp #134
    bne !t0_fail+
    lda fi_p1 + 0
    bne !t0_fail+
    lda fi_to_hit + 0
    bne !t0_fail+
    lda tcb_huff_first
    cmp #HSTR_CHEST_DESTROYED
    bne !t0_fail+
    lda #$01
    sta tc_results + 0
    jmp !t1+
!t0_fail:
    lda #$00
    sta tc_results + 0

    // Test 1: destroy roll fails (rng 5), chest locked, lock-break roll
    // succeeds (rng 0) -> lock cleared, "lock breaks open", chest intact.
!t1:
    jsr test_reset
    lda #5
    sta tcb_rng_seq + 0
    lda #0
    sta tcb_rng_seq + 1
    lda #CHEST_P1_LOCKED
    ldx #5
    jsr test_setup_chest
    jsr chest_bash_command
    bcc !t1_fail+
    lda fi_item_id + 0
    cmp #128
    bne !t1_fail+
    lda fi_p1 + 0
    and #CHEST_P1_LOCKED
    bne !t1_fail+
    lda tcb_huff_last
    cmp #HSTR_CHEST_LOCK_BREAKS
    bne !t1_fail+
    lda #$01
    sta tc_results + 1
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 1

    // Test 2: both rolls fail (rng 5,5) on a locked+trapped chest -> "holds
    // firm", lock and trap both intact (bash never disarms).
!t2:
    jsr test_reset
    lda #5
    sta tcb_rng_seq + 0
    sta tcb_rng_seq + 1
    lda #CHEST_P1_LOCKED | CHEST_P1_TRAP_STR
    ldx #5
    jsr test_setup_chest
    jsr chest_bash_command
    bcc !t2_fail+
    lda tcb_huff_last
    cmp #HSTR_CHEST_HOLDS_FIRM
    bne !t2_fail+
    lda fi_p1 + 0
    and #CHEST_P1_LOCKED
    beq !t2_fail+
    lda fi_p1 + 0
    and #CHEST_P1_TRAP_STR
    beq !t2_fail+
    lda #$01
    sta tc_results + 2
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 2

    // Test 3: destroy roll fails (rng 5) on an unlocked opened chest -> "holds
    // firm", OPENED preserved (bash never opens/changes state), one rng call.
!t3:
    jsr test_reset
    lda #5
    sta tcb_rng_seq + 0
    lda #CHEST_P1_OPENED
    ldx #5
    jsr test_setup_chest
    jsr chest_bash_command
    bcc !t3_fail+
    lda tcb_huff_last
    cmp #HSTR_CHEST_HOLDS_FIRM
    bne !t3_fail+
    lda fi_p1 + 0
    and #CHEST_P1_OPENED
    beq !t3_fail+
    lda fi_item_id + 0
    cmp #128
    bne !t3_fail+
    lda #$01
    sta tc_results + 3
    jmp !t4+
!t3_fail:
    lda #$00
    sta tc_results + 3

    // Test 4: destroy applies even to an already-opened chest (rng 0) ->
    // Ruined Chest, p1/to_hit zeroed.
!t4:
    jsr test_reset
    lda #0
    sta tcb_rng_seq + 0
    lda #CHEST_P1_OPENED
    ldx #5
    jsr test_setup_chest
    jsr chest_bash_command
    bcc !t4_fail+
    lda fi_item_id + 0
    cmp #134
    bne !t4_fail+
    lda fi_p1 + 0
    bne !t4_fail+
    lda fi_to_hit + 0
    bne !t4_fail+
    lda #$01
    sta tc_results + 4
    jmp !done+
!t4_fail:
    lda #$00
    sta tc_results + 4

!done:
    jmp test_finish
