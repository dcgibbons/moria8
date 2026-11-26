// test_ball_effects.s — Focused runtime tests for shared ball-style spells
//
// Keeps `eff_ball` coverage out of the large effects suite so the suite stays
// below the C64 scratch-buffer boundary.

#define C64_TEST_NAME_STREAMS_A000

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"

test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    ldx #1
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk

.pc = $0830 "Main"

#define COMPILE_EMBEDDED_DUNGEON_TEST_ROSTER

.segmentdef TestUnused [start=$E100, min=$E100, max=$FFF9]
.segmentdef TestCreateOverlay [start=$D000, min=$D000, max=$DFFF]
.segmentdef TestNameStreams [start=$E100, min=$E100, max=$FFF9]
#import "../../../../core/6502/zeropage.s"
#import "../memory.s"
#import "../../common/reu.s"
#import "../screen.s"
#import "../../../../core/6502/color.s"
#import "../config.s"
#import "../input.s"
#import "../../../../core/6502/rng.s"
#import "../../../../core/6502/math.s"
#import "../../../../core/6502/tables.s"
#import "../../../../core/6502/item_defs.s"
#import "../../../../core/6502/player.s"
#import "../../../../core/6502/ui_messages.s"
.segment TestUnused
#import "../../../../core/6502/ui_status.s"
.segment Default
#import "../../../../core/6502/ui_help_clear.s"
#import "../../../../core/6502/stat_display.s"
.segment TestCreateOverlay
player_create:
    brk
.segment Default
#import "../../../../core/6502/input_contract.s"
#import "../../../../core/6502/sound.s"
#import "../../../../core/6502/dungeon_data.s"
#import "../../../../core/6502/dungeon_gen.s"
#import "../../../../core/6502/huffman.s"
#import "../../../../core/6502/dungeon_features.s"
#import "chest_summons_stubs.s"
#import "../../../../core/6502/monster.s"
#import "../../../../core/6502/tier_manager.s"
#import "../../common/overlay.s"
.segment TestCreateOverlay
#import "../../../../core/6502/monster_ai.s"
.segment Default
#import "../../../../core/6502/recall.s"
.segment TestUnused
monster_can_cast:
monster_pick_spell:
    brk
.segment Default
#define HAL_PLATFORM_ITEM_CAT_CUSTOM
#import "../../../../core/6502/item.s"
hal_item_cat_read_byte:
    brk
.segment TestCreateOverlay
#import "../../../../core/6502/special_rooms.s"
.segment Default
#import "../../../../core/6502/ego_items.s"
#import "../../../../core/6502/special_rooms_stubs.s"
.segment TestUnused
#import "../../../../core/6502/player_items.s"
.segment Default
#import "../../../../core/6502/spell_data.s"
#import "../../../../core/6502/projectile.s"
#import "../../../../core/6502/spell_effects.s"
#import "../../../../core/6502/player_magic_state.s"
#import "../../../../core/6502/player_magic_state_ops.s"
#import "../../../../core/6502/player_magic.s"
#import "../../../../core/6502/player_magic_ball.s"
#import "../dungeon_render.s"
#import "../../../../core/6502/dungeon_los.s"
#import "../../../../core/6502/player_move.s"
#import "../../../../core/6502/combat.s"
#import "../../../../core/6502/scene_mat_tile.s"
.segment TestUnused
#import "../../../../core/6502/monster_attack.s"
.segment TestCreateOverlay
#import "../../../../core/6502/turn.s"
.segment Default

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
    rts
#import "../../../../core/6502/ui_trampoline_stubs.s"

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

tc_results:       .fill 2, $ff
tlk_flash_calls:  .byte 0
tlk_first_flash_row: .byte 0
tlk_first_flash_col: .byte 0
tlk_flash_row:    .byte 0
tlk_flash_col:    .byte 0
tbf_hp_before:    .byte 0
tbf_kill_calls:   .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_get_direction_target_east:
    lda zp_player_x
    clc
    adc #1
    sta df_target_x
    lda zp_player_y
    sta df_target_y
    sec
    rts

test_screen_flash_at:
    lda tlk_flash_calls
    bne !tsfa_not_first+
    stx tlk_first_flash_row
    sty tlk_first_flash_col
!tsfa_not_first:
    stx tlk_flash_row
    sty tlk_flash_col
    inc tlk_flash_calls
    rts

test_combat_kill_message:
    inc tbf_kill_calls
    jsr monster_remove
    inc zp_dirty_count
    rts

// Dropped ui_* imports to stay under the map-overlap boundary.
ui_char_display:
ui_inv_display:
ui_inv_select_display:
ui_equip_display:
    rts
count_spells_known:
    rts

test_start:
    jsr msg_init
    jsr hal_sound_init
    jsr tv_setup_dark_room
    :PatchJump(get_direction_target, test_get_direction_target_east)
    :PatchJump(screen_flash_at, test_screen_flash_at)

    lda #0
    sta tlk_flash_calls
    sta tlk_first_flash_row
    sta tlk_first_flash_col

    lda #23
    sta ms_spawn_x
    lda #12
    sta ms_spawn_y
    lda #10
    jsr monster_spawn_one
    bcc !fail+

    lda #23
    ldy #12
    jsr monster_find_at
    bcc !fail+
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda #8
    sta (zp_ptr0),y
    iny
    lda #0
    sta (zp_ptr0),y
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    sta tbf_hp_before

    lda #1
    jsr eff_ball

    lda tlk_flash_calls
    cmp #2
    bcc !fail+
    lda tlk_first_flash_row
    cmp #11
    bne !fail+
    lda tlk_first_flash_col
    cmp #21
    bne !fail+

    lda #23
    ldy #12
    jsr monster_find_at
    bcc !pass+
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp tbf_hp_before
    bcs !fail+
!pass:
    lda #$01
    sta tc_results
    jmp !t2+
!fail:
    lda #$00
    sta tc_results

    // ==========================================
    // Test 2: lethal ball damage prints the
    // standard slain message.
    // ==========================================
!t2:
    jsr tv_setup_dark_room
    :PatchJump(get_direction_target, test_get_direction_target_east)
    :PatchJump(combat_kill_message, test_combat_kill_message)

    lda #0
    sta tbf_kill_calls

    lda #23
    sta ms_spawn_x
    lda #12
    sta ms_spawn_y
    lda #1
    jsr monster_spawn_one
    bcc !t2_fail+

    lda #23
    ldy #12
    jsr monster_find_at
    bcc !t2_fail+

    lda #255
    jsr eff_ball

    lda tbf_kill_calls
    cmp #1
    bne !t2_fail+
    lda #23
    ldy #12
    jsr monster_find_at
    bcs !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp test_finish
!t2_fail:
    lda #$00
    sta tc_results + 1
    jmp test_finish


tv_setup_dark_room:
    jsr fill_map_rock
    jsr item_init_floor
    jsr monster_init_table
    lda #0
    sta vis_room_revealed
    lda #$ff
    sta vis_cached_room_idx
    lda #0
    sta room_count

    lda #1
    sta room_count
    lda #20
    sta room_x
    sta dg_room_x
    lda #10
    sta room_y
    sta dg_room_y
    lda #10
    sta room_w
    sta dg_room_w
    lda #6
    sta room_h
    sta dg_room_h
    lda #0
    sta room_lit
    jsr draw_dungeon_room
    jsr darken_rooms

    lda #22
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda #12
    sta zp_player_y
    sta player_data + PL_MAP_Y
    lda #1
    sta zp_player_dlvl
    lda #0
    sta zp_eff_blind
    lda #1
    sta zp_light_radius
    sta player_data + PL_LIGHT_RAD
    lda #COL_BLACK
    sta zp_text_color
    jsr screen_clear
    jsr update_visibility
    jsr viewport_update
    jsr render_viewport
    rts
