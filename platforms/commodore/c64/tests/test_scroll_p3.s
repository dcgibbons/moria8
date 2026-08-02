// test_scroll_p3.s — Runtime tests for Phase 3 scroll effects
//
// Tests: dispatch routing, object detection reveal, mass genocide LOS filter,
// teleport level depth change.
//
// Results at $0400-$0407: $01 = pass, $00 = fail per test

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_exit_trampoline:
    ldx #7
!tc_copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !tc_copy-
    brk

.pc = $0828 "Main"

.encoding "screencode_mixed"

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
#import "../../../../core/ui_help.s"
#import "../../../../core/ui_trampoline_stubs.s"
#import "../../../../core/stat_display.s"
.segmentdef TestCreateOverlay [start=$D000]
.segment TestCreateOverlay
#import "../../../../core/background_data.s"
#import "../../../../core/player_create.s"
.segment Default
#import "../../../../core/sound.s"
#import "../../../../core/dungeon_data.s"
#import "dungeon_gen_stubs.s"
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
#import "../../../../core/player_magic_state.s"
#import "../../../../core/player_magic_state_ops.s"
#import "../../../../core/player_magic.s"
#import "../../../../core/ui_inventory.s"
#import "../../../../core/ui_equipment.s"
#import "../../../../core/dungeon_los.s"
#import "../../../../core/los_trace.s"
#import "../../../../core/player_move.s"
#import "../../../../core/combat.s"
#import "../../../../core/scene_mat_tile.s"
#import "../../../../core/monster_attack.s"
#import "../../../../core/turn.s"
#import "../../../../core/store_data.s"
#import "../../../../core/store.s"
#import "../../../../core/ui_store.s"

// Stubs for spell-overlay-only handlers the scroll dispatch calls.
spy_last: .byte 0
eff_recharge_item:
    sta spy_last
    rts
eff_glyph_of_warding:
    lda #ITEM_TYPE_SCR_RUNE_PROTECTION
    sta spy_last
    rts
eff_genocide:
    lda #ITEM_TYPE_SCR_GENOCIDE
    sta spy_last
    rts
eff_destroy_area:
    lda #ITEM_TYPE_SCR_DESTRUCTION
    sta spy_last
    rts
eff_reveal_floorplan:
    lda #ITEM_TYPE_SCR_MAGIC_MAPPING
    sta spy_last
    rts
pmx_print_inline:
    rts

// Strings referenced by imported modules
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test result buffer
tc_results: .fill 8, $ff
tc_loop_ctr: .byte 0
t7_slot_a: .byte 0
t7_slot_b: .byte 0

#define SCROLL_P3_EXISTING_OWNER
#define SCROLL_P3_NEW_OWNER
#define SCROLL_P3_ROUTER_ENABLED
#import "../../../../core/scroll_effects_p3.s"
#undef SCROLL_P3_NEW_OWNER
#undef SCROLL_P3_EXISTING_OWNER

test_start:
    ldx #7
    lda #$ff
!clr:
    sta tc_results,x
    dex
    bpl !clr-

    // Seed RNG deterministically
    lda #$42
    sta zp_rng_0
    lda #$13
    sta zp_rng_1
    lda #$7a
    sta zp_rng_2
    lda #$05
    sta zp_rng_3

    // ==========================================
    // Test 1: Recharging scroll routes to eff_recharge_item with A=50
    // ==========================================
    lda #0
    sta spy_last
    lda #ITEM_TYPE_SCR_RECHARGING
    jsr irs_dispatch_p3_overlay
    lda spy_last
    cmp #50
    bne !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // ==========================================
    // Test 2: Rune of Protection routes to eff_glyph_of_warding
    // ==========================================
!t2:
    lda #0
    sta spy_last
    lda #ITEM_TYPE_SCR_RUNE_PROTECTION
    jsr irs_dispatch_p3_overlay
    lda spy_last
    cmp #ITEM_TYPE_SCR_RUNE_PROTECTION
    bne !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // ==========================================
    // Test 3: Genocide routes to eff_genocide
    // ==========================================
!t3:
    lda #0
    sta spy_last
    lda #ITEM_TYPE_SCR_GENOCIDE
    jsr irs_dispatch_p3_overlay
    lda spy_last
    cmp #ITEM_TYPE_SCR_GENOCIDE
    bne !t3_fail+
    lda #$01
    sta tc_results + 2
    jmp !t4+
!t3_fail:
    lda #$00
    sta tc_results + 2

    // ==========================================
    // Test 4: *Destruction* routes to eff_destroy_area
    // ==========================================
!t4:
    lda #0
    sta spy_last
    lda #ITEM_TYPE_SCR_DESTRUCTION
    jsr irs_dispatch_p3_overlay
    lda spy_last
    cmp #ITEM_TYPE_SCR_DESTRUCTION
    bne !t4_fail+
    lda #$01
    sta tc_results + 3
    jmp !t5+
!t4_fail:
    lda #$00
    sta tc_results + 3

    // ==========================================
    // Test 5: Magic Mapping routes to eff_reveal_floorplan
    // ==========================================
!t5:
    lda #0
    sta spy_last
    lda #ITEM_TYPE_SCR_MAGIC_MAPPING
    jsr irs_dispatch_p3_overlay
    lda spy_last
    cmp #ITEM_TYPE_SCR_MAGIC_MAPPING
    bne !t5_fail+
    lda #$01
    sta tc_results + 4
    jmp !t6+
!t5_fail:
    lda #$00
    sta tc_results + 4

    // ==========================================
    // Test 6: Object Detection marks the floor item's tile visited
    // ==========================================
!t6:
    jsr item_init_floor

    // Place a floor item at (12, 8) on the map (row 8)
    ldx #8
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #12
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    // Give the item a floor slot pointing at that tile
    lda #2
    sta fi_item_id
    lda #12
    sta fi_x
    lda #8
    sta fi_y

    // Clear the tile's visited flag first
    ldx #8
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #12
    lda (zp_ptr0),y
    and #~FLAG_VISITED & $ff
    sta (zp_ptr0),y

    lda #ITEM_TYPE_SCR_OBJECT_DETECT
    jsr irs_dispatch_p3_overlay

    // Tile should now be visited
    ldx #8
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #12
    lda (zp_ptr0),y
    and #FLAG_VISITED
    beq !t6_fail+
    lda #$01
    sta tc_results + 5
    jmp !t7+
!t6_fail:
    lda #$00
    sta tc_results + 5

    // ==========================================
    // Test 7: Mass Genocide removes LOS monsters, keeps blocked ones
    // ==========================================
!t7:
    jsr item_init_floor

    // Player at (10, 10)
    lda #10
    sta zp_player_x
    sta zp_player_y

    // Monster A at (12, 10): same row, clear LOS
    // Monster B at (12, 12): wall between at (11... no — put it far behind a wall column
    // Simple approach: A adjacent in the open, B behind a granite column at x=11
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #8
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    ldy #9
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    ldy #10
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    ldy #11
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y
    ldy #12
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    // Wall row at y=11 (x=8..16) blocks LOS from player (10,10) to monster B (12,12)
    ldx #11
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #7
!t7_wall:
    iny
    lda #TILE_WALL_V
    sta (zp_ptr0),y
    cpy #16
    bcc !t7_wall-

    // Monster B's tile stays floor behind the wall
    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #12
    lda #TILE_FLOOR | FLAG_LIT
    sta (zp_ptr0),y

    // Spawn monster A at (12, 10), open LOS to player (10, 10)
    lda #12
    sta ms_spawn_x
    lda #10
    sta ms_spawn_y
    lda #1
    jsr monster_spawn_one
    stx t7_slot_a

    // Spawn monster B at (12, 12), LOS blocked by the wall row at y=11
    lda #12
    sta ms_spawn_x
    lda #12
    sta ms_spawn_y
    lda #1
    jsr monster_spawn_one
    stx t7_slot_b

    lda #ITEM_TYPE_SCR_MASS_GENOCIDE
    jsr irs_dispatch_p3_overlay

    // Slot A (LOS) should be removed; slot B (blocked) should remain
    ldx t7_slot_a
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    bne !t7_fail+
    ldx t7_slot_b
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !t7_fail+

    lda #$01
    sta tc_results + 6
    jmp !t8+
!t7_fail:
    lda #$00
    sta tc_results + 6

    // ==========================================
    // Test 8: Teleport Level changes dlvl by ±1 and clamps at 1
    // ==========================================
!t8:
    lda #5
    sta zp_player_dlvl
    lda #ITEM_TYPE_SCR_TELEPORT_LEVEL
    jsr irs_dispatch_p3_overlay
    lda zp_player_dlvl
    cmp #4
    beq !t8_ok+
    cmp #6
    beq !t8_ok+
    jmp !t8_fail+
!t8_ok:
    lda player_data + PL_DLEVEL
    cmp zp_player_dlvl
    bne !t8_fail+
    // From dlvl 1, teleport must clamp to >= 1
    lda #1
    sta zp_player_dlvl
    lda #ITEM_TYPE_SCR_TELEPORT_LEVEL
    jsr irs_dispatch_p3_overlay
    lda zp_player_dlvl
    cmp #1
    bcc !t8_fail+
    lda #$01
    sta tc_results + 7
    jmp !tests_done+
!t8_fail:
    lda #$00
    sta tc_results + 7

!tests_done:
    jmp test_exit_trampoline

// dungeon_render.s lives in TestCreateOverlay ($D000+) so the test body stays
// below MAP_BASE; it must come after dungeon_data.s defines MAP_COLS.
.segment TestCreateOverlay
#import "../dungeon_render.s"
.segment Default
