// test_chest_loot.s — Focused runtime tests for step-13 chest loot fulfillment
// (docs/CHEST_DESIGN.md "Contents" + "Loot fulfillment handoff"). Exercises the
// resident chest_fulfill_loot handoff (no-op, stale-latch discard, fulfill) and
// the VMS drop decode + bounded placement in chest_generate_loot.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tc_results: .fill 4, $ff

.pc = $080E "Test Code"

.encoding "screencode_mixed"

test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    :BankOutKernal()
    ldx #3
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
tcl_overlay_calls: .byte 0  // overlay_load call count
tcl_rng_idx:     .byte 0
tcl_rng_seq:     .fill 12, 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_overlay_load:
    inc tcl_overlay_calls
    clc                         // pretend the GEN overlay loaded
    rts

test_rng_range:
    ldx tcl_rng_idx
    inc tcl_rng_idx
    lda tcl_rng_seq,x
    rts

test_pick_item_type:
    lda #5                      // Fixed loot item ID (Mace)
    rts

test_roll_enchantment:
    lda #0
    rts

test_tramp_roll_ego_type:
    lda #0
    rts

test_item_get_missile:
    lda #0                      // Bit 7 clear -> not ammo
    rts

test_monster_find_at:
    clc                         // No monsters in this suite: tile is always free
    rts

// fill_floor — Set the tiles around the chest to TILE_FLOOR so loot placement
// finds walkable tiles. Bounded to rows 15-21 / cols 9-15: the full map
// ($C000) overlaps this suite's Main code (ends $C402), so a whole-map fill
// would corrupt the running test. The chest's 5x5 drop box (rows 16-20) sits
// safely past the code.
fill_floor:
    ldx #15
!ff_row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #9
!ff_col:
    lda #TILE_FLOOR
    sta (zp_ptr0),y
    iny
    cpy #16
    bne !ff_col-
    inx
    cpx #22
    bne !ff_row-
    rts

// test_reset — clear floor items, spies, latch; chest target tile (12,18).
test_reset:
    jsr player_init
    jsr item_init_floor
    jsr fill_floor
    lda #0
    sta tcl_overlay_calls
    sta tcl_rng_idx
    sta chest_loot_pending
    sta chest_loot_x
    sta chest_loot_y
    sta chest_loot_flags
    sta chest_pending_summons
    lda #3
    sta zp_player_dlvl
    lda #12
    sta df_target_x
    sta chest_loot_x
    lda #18
    sta df_target_y
    sta chest_loot_y
    rts

// place_chest_at_latch — put a Small Wooden Chest (id 128) in floor slot 0 at
// the latch position so the stale-latch guard finds it.
place_chest_at_latch:
    lda #128
    sta fi_item_id + 0
    lda chest_loot_x
    sta fi_x + 0
    lda chest_loot_y
    sta fi_y + 0
    lda #CHEST_P1_OPENED
    sta fi_p1 + 0
    rts

test_start:
    :PatchJump(overlay_load, test_overlay_load)
    :PatchJump(rng_range, test_rng_range)
    :PatchJump(pick_item_type, test_pick_item_type)
    :PatchJump(roll_enchantment, test_roll_enchantment)
    :PatchJump(tramp_roll_ego_type, test_tramp_roll_ego_type)
    :PatchJump(item_get_missile, test_item_get_missile)
    :PatchJump(monster_find_at, test_monster_find_at)

    // Test 0: no pending latch -> no-op (no GEN load, no loot, latch stays 0).
    jsr test_reset
    jsr chest_fulfill_loot
    lda tcl_overlay_calls
    bne !t0_fail+
    lda chest_loot_pending
    bne !t0_fail+
    lda fi_item_id + 0
    cmp #FI_EMPTY
    bne !t0_fail+
    lda #$01
    sta tc_results + 0
    jmp !t1+
!t0_fail:
    lda #$00
    sta tc_results + 0

    // Test 1: stale latch (pending but no chest at the position) -> discarded:
    // latch cleared, no GEN load, no loot placed.
!t1:
    jsr test_reset
    lda #1
    sta chest_loot_pending
    lda #$0f
    sta chest_loot_flags
    jsr chest_fulfill_loot
    lda tcl_overlay_calls
    bne !t1_fail+
    lda chest_loot_pending
    bne !t1_fail+
    lda fi_item_id + 0
    cmp #FI_EMPTY
    bne !t1_fail+
    lda #$01
    sta tc_results + 1
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 1

    // Test 2: valid opened chest with pending contents -> GEN loaded once,
    // latch cleared, drops placed (small wooden $0F: 60%+90% both succeed ->
    // 2 mixed drops, both forced object -> 2 items at (10,16) and (14,20)).
!t2:
    jsr test_reset
    jsr place_chest_at_latch
    lda #1
    sta chest_loot_pending
    lda #$0f
    sta chest_loot_flags
    // rng seq: 60% roll=10, 90% roll=10, type1=10(obj), x1=0,y1=0,
    //          type2=10(obj), x2=4,y2=4
    lda #10
    sta tcl_rng_seq + 0
    sta tcl_rng_seq + 1
    sta tcl_rng_seq + 2
    lda #0
    sta tcl_rng_seq + 3
    sta tcl_rng_seq + 4
    lda #10
    sta tcl_rng_seq + 5
    lda #4
    sta tcl_rng_seq + 6
    sta tcl_rng_seq + 7
    jsr chest_fulfill_loot
    lda tcl_overlay_calls
    cmp #1
    bne !t2_fail+
    lda chest_loot_pending
    bne !t2_fail+
    // Drop 1 at (10,16) is the stub item id 5
    lda #10
    ldy #16
    jsr floor_item_find_at
    bcc !t2_fail+
    lda fi_item_id,x
    cmp #5
    bne !t2_fail+
    // Drop 2 at (14,20) is the stub item id 5
    lda #14
    ldy #20
    jsr floor_item_find_at
    bcc !t2_fail+
    lda fi_item_id,x
    cmp #5
    bne !t2_fail+
    lda #$01
    sta tc_results + 2
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 2

    // Test 3: 60%/90% both fail -> zero drops, no items placed (latch cleared).
!t3:
    jsr test_reset
    jsr place_chest_at_latch
    lda #1
    sta chest_loot_pending
    lda #$0f
    sta chest_loot_flags
    // rng seq: 60% roll=90 (>=60 fails), 90% roll=95 (>=90 fails)
    lda #90
    sta tcl_rng_seq + 0
    lda #95
    sta tcl_rng_seq + 1
    jsr chest_fulfill_loot
    lda chest_loot_pending
    bne !t3_fail+
    // No loot items beyond the chest (slots 1+ stay empty)
    lda fi_item_id + 1
    cmp #FI_EMPTY
    bne !t3_fail+
    lda #$01
    sta tc_results + 3
    jmp !done+
!t3_fail:
    lda #$00
    sta tc_results + 3

!done:
    jmp test_finish
