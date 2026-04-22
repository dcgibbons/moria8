// test_genocide.s — Focused runtime test for shared genocide spell behavior
//
// Keeps glyph-based genocide coverage out of the large effects suite so the
// product death overlay can be exercised without pushing that harness around.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"

test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    lda tc_results
    sta $0400
    brk

.pc = $0830 "Main"

#import "../../common/zeropage.s"
#import "../memory.s"
#import "../../common/reu.s"
#import "../screen.s"
#import "../../common/color.s"
#import "../config.s"
#import "../input.s"
#import "../../common/rng.s"
#import "../../common/math.s"
#import "../../common/tables.s"
#import "../../common/item_defs.s"
#import "../../common/player.s"
#import "../../common/ui_messages.s"
#import "../../common/ui_status.s"
#import "../../common/ui_help_clear.s"
#import "../../common/ui_character.s"
#import "../../common/stat_display.s"
.segmentdef TestCreateOverlay [start=$D000]
.segment TestCreateOverlay
#import "../../common/background_data.s"
#import "../../common/player_create.s"
.segment Default
#import "../../common/input_contract.s"
#import "../../common/sound.s"
#import "../../common/dungeon_data.s"
#import "../../common/dungeon_gen.s"
#import "../../common/huffman.s"
#import "../../common/dungeon_features.s"
#import "../../common/monster.s"
#import "../../common/tier_manager.s"
#import "../../common/overlay.s"
#import "../../common/monster_ai.s"
#import "../../common/recall.s"
#import "../../common/monster_magic.s"
#import "../../common/item.s"
#import "../../common/special_rooms.s"
#import "../../common/ego_items.s"
#import "../../common/special_rooms_stubs.s"
#import "../../common/player_items.s"
#import "../../common/spell_data.s"
#import "../../common/projectile.s"
#import "../../common/spell_effects.s"
#import "../../common/player_magic_state.s"
#import "../../common/player_magic_state_ops.s"
#import "../../common/player_magic.s"
#import "../../common/player_magic_feedback.s"
#import "../../common/player_magic_execute_overlay.s"
#import "../../common/ui_inventory.s"
#import "../../common/ui_equipment.s"
#import "../dungeon_render.s"
#import "../../common/dungeon_los.s"
#import "../../common/player_move.s"
#import "../../common/combat.s"
#import "../../common/monster_attack.s"
#import "../../common/turn.s"

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
#import "../../common/ui_trampoline_stubs.s"

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

tc_results: .byte $ff
tpm_huff_calls: .byte 0
tpm_last_huff_id: .byte 0

recall_query_sc: .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx tpm_last_huff_id
    inc tpm_huff_calls
    rts

test_input_get_key_w:
    lda #$57
    rts

recall_key_to_screen_code:
    cmp #$41
    bcc !try_shifted+
    cmp #$5b
    bcs !try_shifted+
    sec
    sbc #$40
    sta recall_query_sc
    sec
    rts
!try_shifted:
    cmp #$c1
    bcc !invalid+
    cmp #$db
    bcs !invalid+
    and #$3f
    clc
    adc #$40
    sta recall_query_sc
    sec
    rts
!invalid:
    clc
    rts

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

test_start:
    :PatchJump(input_get_key, test_input_get_key_w)
    :PatchJump(huff_print_msg, test_huff_print_msg)

    jsr msg_init
    jsr sound_init
    jsr tv_setup_dark_room

    lda #23
    sta ms_spawn_x
    lda #12
    sta ms_spawn_y
    lda #2                      // 'W'
    jsr monster_spawn_one
    bcc !fail+

    lda #24
    sta ms_spawn_x
    lda #12
    sta ms_spawn_y
    lda #10                     // also 'W'
    jsr monster_spawn_one
    bcc !fail+

    lda #25
    sta ms_spawn_x
    lda #12
    sta ms_spawn_y
    lda #1                      // non-matching glyph
    jsr monster_spawn_one
    bcc !fail+

    lda #0
    sta vis_room_revealed
    sta tpm_huff_calls
    sta tpm_last_huff_id

    jsr eff_genocide

    lda tpm_huff_calls
    cmp #1
    bne !fail+
    lda tpm_last_huff_id
    cmp #HSTR_PM_TITLE_PRAY
    bne !fail+

    lda vis_room_revealed
    cmp #1
    bne !fail+

    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    bne !fail+

    ldx #1
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    bne !fail+

    ldx #2
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #1
    bne !fail+

    lda zp_mon_count
    cmp #1
    bne !fail+

    lda #$01
    sta tc_results
    jmp test_finish

!fail:
    lda #$00
    sta tc_results
    jmp test_finish
