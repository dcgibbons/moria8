// test_chest_loot.s — Focused runtime tests for step-13 chest loot fulfillment
// (docs/CHEST_DESIGN.md "Contents" + "Loot fulfillment handoff"). Exercises the
// resident chest_fulfill_loot handoff (no-op, stale-latch discard, fulfill) and
// the VMS drop decode + bounded placement in chest_generate_loot.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tc_results: .fill 10, $ff

.pc = $080E "Test Code"

.encoding "screencode_mixed"

test_bootstrap:
    // The overlay_load_no_kernal spy banks KERNAL out mid-test without RAM IRQ
    // vectors installed; mask interrupts first or a raster/CIA IRQ vectors
    // through uninitialized $FFFE/$FFFF and hangs the suite intermittently.
    sei
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
// This unit assembly normally exposes only the resident picker wrapper. The
// product chest-loot branch calls the same implementation inside GEN directly.
pick_item_type_overlay:
    jmp pick_item_type
tramp_roll_ego_type_modal:
    jmp tramp_roll_ego_type
#define C64_PRODUCT_OVERLAY_RUNTIME
#import "../../../../core/chest_loot.s"
#undef C64_PRODUCT_OVERLAY_RUNTIME

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
tcl_overlay_no_kernal_calls: .byte 0
tcl_runtime_resync_calls: .byte 0
tcl_modal_ego_calls: .byte 0
tcl_overlay_fail: .byte 0
tcl_rng_idx:     .byte 0
tcl_rng_seq:     .fill 32, 0

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
    lda tcl_overlay_fail
    bne !failed+
    clc                         // pretend the GEN overlay loaded
    rts
!failed:
    sec
    rts

overlay_load_no_kernal:
    inc tcl_overlay_no_kernal_calls
    jsr overlay_load
    bcs !done+
    lda #BANK_NO_KERNAL
    sta $01
!done:
    rts

test_runtime_resync:
    inc tcl_runtime_resync_calls
    lda #BANK_NO_BASIC
    sta $01
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

test_tramp_roll_ego_type_modal:
    inc tcl_modal_ego_calls
    lda #0
    rts

test_item_get_missile:
    lda #0                      // Bit 7 clear -> not ammo
    rts

test_monster_find_at:
    clc                         // No monsters in this suite: tile is always free
    rts

// fill_floor — Set the tiles around the chest to TILE_FLOOR so loot placement
// finds walkable tiles. Bounded to rows 24-30 / cols 9-15: the full map
// ($C000) overlaps this suite's Main code, so a whole-map fill would corrupt
// the running test. The chest's 5x5 drop box (rows 24-28) sits past the code.
fill_floor:
    ldx #24
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
    cpx #31
    bne !ff_row-
    rts

// test_reset — clear floor items, spies, latch; chest target tile (12,26).
test_reset:
    jsr player_init
    jsr item_init_floor
    jsr fill_floor
    lda #0
    sta tcl_overlay_calls
    sta tcl_overlay_no_kernal_calls
    sta tcl_runtime_resync_calls
    sta tcl_modal_ego_calls
    sta tcl_overlay_fail
    sta tcl_rng_idx
    sta zp_dirty_count
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
    lda #26
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
    :PatchJump(hal_platform_runtime_resync, test_runtime_resync)
    :PatchJump(rng_range, test_rng_range)
    :PatchJump(pick_item_type, test_pick_item_type)
    :PatchJump(roll_enchantment, test_roll_enchantment)
    :PatchJump(tramp_roll_ego_type_modal, test_tramp_roll_ego_type_modal)
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
    // 2 mixed drops, both forced object -> 2 items at (10,24) and (14,28)).
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
    lda tcl_overlay_no_kernal_calls
    cmp #1
    bne !t2_fail+
    lda tcl_runtime_resync_calls
    cmp #1
    bne !t2_fail+
    lda tcl_modal_ego_calls
    cmp #2
    bne !t2_fail+
    lda $01
    cmp #BANK_NO_BASIC
    bne !t2_fail+
    lda chest_loot_pending
    bne !t2_fail+
    // Drop 1 at (10,24) is the stub item id 5
    lda #10
    ldy #24
    jsr floor_item_find_at
    bcc !t2_fail+
    lda fi_item_id,x
    cmp #5
    bne !t2_fail+
    // Drop 2 at (14,28) is the stub item id 5
    lda #14
    ldy #28
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
    lda tcl_runtime_resync_calls
    cmp #1
    bne !t3_fail+
    lda tcl_modal_ego_calls
    bne !t3_fail+
    lda $01
    cmp #BANK_NO_BASIC
    bne !t3_fail+
    // No loot items beyond the chest (slots 1+ stay empty)
    lda fi_item_id + 1
    cmp #FI_EMPTY
    bne !t3_fail+
    lda #$01
    sta tc_results + 3
    jmp !t4+
!t3_fail:
    lda #$00
    sta tc_results + 3

    // Test 4: GEN load failure clears the latch without generating loot and
    // restores normal gameplay banking before returning.
!t4:
    jsr test_reset
    jsr place_chest_at_latch
    lda #1
    sta chest_loot_pending
    sta tcl_overlay_fail
    lda #$0f
    sta chest_loot_flags
    jsr chest_fulfill_loot
    lda tcl_overlay_no_kernal_calls
    cmp #1
    bne !t4_fail+
    lda tcl_runtime_resync_calls
    cmp #1
    bne !t4_fail+
    lda tcl_rng_idx
    bne !t4_fail+
    lda chest_loot_pending
    bne !t4_fail+
    lda fi_item_id + 1
    cmp #FI_EMPTY
    bne !t4_fail+
    lda $01
    cmp #BANK_NO_BASIC
    bne !t4_fail+
    lda #$01
    sta tc_results + 4
    jmp !t5+
!t4_fail:
    lda #$00
    sta tc_results + 4

    // Test 5: one successful object drop latches the action-owned redraw
    // request for the enclosing command's turn_post_action.
!t5:
    jsr test_reset
    jsr place_chest_at_latch
    lda #1
    sta chest_loot_pending
    lda #$0f
    sta chest_loot_flags
    // rng seq: 60% roll=10 succeeds; 90% roll=95 fails; type=10(obj), x=0, y=0.
    lda #10
    sta tcl_rng_seq + 0
    lda #95
    sta tcl_rng_seq + 1
    lda #10
    sta tcl_rng_seq + 2
    lda #0
    sta tcl_rng_seq + 3
    sta tcl_rng_seq + 4
    jsr chest_fulfill_loot
    lda chest_loot_pending
    bne !t5_fail+
    lda zp_dirty_count
    cmp #1
    bne !t5_fail+
    lda #$01
    sta tc_results + 5
    jmp !t6+
!t5_fail:
    lda #$00
    sta tc_results + 5

    // Test 6: one successful gold drop also latches the redraw request.
!t6:
    jsr test_reset
    jsr place_chest_at_latch
    lda #1
    sta chest_loot_pending
    lda #$0f
    sta chest_loot_flags
    // rng seq: 60% roll=10 succeeds; 90% roll=95 fails; type=60(gold), x=0, y=0.
    lda #10
    sta tcl_rng_seq + 0
    lda #95
    sta tcl_rng_seq + 1
    lda #60
    sta tcl_rng_seq + 2
    lda #0
    sta tcl_rng_seq + 3
    sta tcl_rng_seq + 4
    jsr chest_fulfill_loot
    lda chest_loot_pending
    bne !t6_fail+
    lda zp_dirty_count
    cmp #1
    bne !t6_fail+
    lda #$01
    sta tc_results + 6
    jmp !t7+
!t6_fail:
    lda #$00
    sta tc_results + 6

    // Test 7: low-edge chest at (1,1) with zero RNG offsets wraps the 5x5
    // candidate to ($ff,$ff). The bounds check must reject every attempt
    // before any row-table or map access: drop discarded, latch cleared, no
    // redraw latched, exactly 1 + 10*2 RNG draws consumed.
!t7:
    jsr test_reset
    lda #1
    sta chest_loot_x
    sta chest_loot_y
    jsr place_chest_at_latch
    lda #1
    sta chest_loot_pending
    lda #$04                    // bit2 only: 60% one drop, type resolves object
    sta chest_loot_flags
    lda #10
    sta tcl_rng_seq + 0         // 60% roll succeeds; offsets stay 0
    jsr chest_fulfill_loot
    lda chest_loot_pending
    beq !t7_a+
    lda #$f1
    jmp !t7_fail+
!t7_a:
    lda zp_dirty_count
    beq !t7_b+
    lda #$f2
    jmp !t7_fail+
!t7_b:
    lda tcl_rng_idx
    cmp #21
    beq !t7_c+
    jmp !t7_fail+
!t7_c:
    lda fi_item_id + 1
    cmp #FI_EMPTY
    beq !t7_d+
    lda #$f4
    jmp !t7_fail+
!t7_d:
    lda #$01
    sta tc_results + 7
    jmp !t8+
!t7_fail:
    sta tc_results + 7

    // Test 8: high-edge chest at (MAP_COLS-2, MAP_ROWS-2) with maximum RNG
    // offsets lands candidates at (MAP_COLS, MAP_ROWS). Same rejection
    // contract as test 7.
!t8:
    jsr test_reset
    lda #MAP_COLS - 2
    sta chest_loot_x
    lda #MAP_ROWS - 2
    sta chest_loot_y
    jsr place_chest_at_latch
    lda #1
    sta chest_loot_pending
    lda #$04
    sta chest_loot_flags
    lda #10
    sta tcl_rng_seq + 0         // 60% roll succeeds
    lda #4
    ldx #20
!t8_seq:
    sta tcl_rng_seq,x           // offsets 1..20 -> 4 (candidate = MAP_COLS/ROWS)
    dex
    bne !t8_seq-
    jsr chest_fulfill_loot
    lda chest_loot_pending
    beq !t8_a+
    lda #$f1
    jmp !t8_fail+
!t8_a:
    lda zp_dirty_count
    beq !t8_b+
    lda #$f2
    jmp !t8_fail+
!t8_b:
    lda tcl_rng_idx
    cmp #21
    beq !t8_c+
    jmp !t8_fail+
!t8_c:
    lda fi_item_id + 1
    cmp #FI_EMPTY
    beq !t8_d+
    lda #$f4
    jmp !t8_fail+
!t8_d:
    lda #$01
    sta tc_results + 8
    jmp !t9+
!t8_fail:
    sta tc_results + 8

    // Test 9: town-level (dlvl=0) gold drop must not hang. Without the depth
    // clamp, rng_range_word(0) rejects every 16-bit draw and the suite times
    // out. With the clamp (dlvl treated as 1), qty = rng_range_word(10) + 5.
!t9:
    jsr test_reset
    jsr place_chest_at_latch
    lda #0
    sta zp_player_dlvl        // Town depth
    lda #1
    sta chest_loot_pending
    lda #$06                  // bit2 (60% one drop) + type 2 (gold only)
    sta chest_loot_flags
    // rng seq: 60% roll=10 succeeds; offsets x=0, y=0; gold id roll=0
    lda #10
    sta tcl_rng_seq + 0
    lda #0
    sta tcl_rng_seq + 1
    sta tcl_rng_seq + 2
    sta tcl_rng_seq + 3
    jsr chest_fulfill_loot
    lda chest_loot_pending
    bne !t9_fail+
    lda #10
    ldy #24
    jsr floor_item_find_at
    bcc !t9_fail+
    lda fi_item_id,x
    cmp #2                    // gold IDs are 0/1
    bcs !t9_fail+
    lda fi_qty,x
    cmp #5
    bcc !t9_fail+
    cmp #15
    bcs !t9_fail+
    lda #$01
    sta tc_results + 9
    jmp !done+
!t9_fail:
    lda #$00
    sta tc_results + 9

!done:
    jmp test_finish

test_body_end:
.assert "Chest loot test stays below its first map write", test_body_end <= MAP_BASE + 24 * MAP_COLS + 9, true
