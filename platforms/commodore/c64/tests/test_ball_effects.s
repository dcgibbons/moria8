// test_ball_effects.s — Focused runtime tests for shared ball-style spells
//
// Keeps `eff_ball` coverage out of the large effects suite so the suite stays
// below the C64 scratch-buffer boundary.

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
#import "../../../../core/dungeon_gen.s"
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
#import "../../../../core/player_magic_ball.s"
#import "../../../../core/ui_inventory.s"
#import "../../../../core/ui_equipment.s"
#import "../dungeon_render.s"
#import "../../../../core/dungeon_los.s"
#import "../../../../core/player_move.s"
#import "../../../../core/combat.s"
#import "../../../../core/monster_attack.s"
#import "../../../../core/turn.s"

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
#import "../../../../core/ui_trampoline_stubs.s"

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
