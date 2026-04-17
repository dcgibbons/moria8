// test_directional_effects.s — Focused runtime tests for shared directional
// targeting and adjacent sleep helpers. Keeps these checks out of the large
// effects suite so it stays below its scratch-buffer boundary.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"

test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    ldx #3
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk

.pc = $0830 "Main"

.encoding "screencode_mixed"

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

tc_results: .fill 4, $ff
tde_huff_calls: .byte 0
tde_last_huff_id: .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_input_wait_release:
    rts

test_huff_print_msg:
    stx tde_last_huff_id
    inc tde_huff_calls
    rts

test_get_direction_target_east:
    lda zp_player_x
    clc
    adc #1
    sta df_target_x
    lda zp_player_y
    sta df_target_y
    sec
    rts

test_start:
    :PatchJump(input_wait_release, test_input_wait_release)
    :PatchJump(huff_print_msg, test_huff_print_msg)

    lda #$42
    sta zp_rng_0
    lda #$13
    sta zp_rng_1
    lda #$7a
    sta zp_rng_2
    lda #$f1
    sta zp_rng_3

    jsr msg_init
    jsr sound_init

    lda #8
    sta $c6
    ldx #7
    lda #$20
!seed_keys:
    sta $0277,x
    dex
    bpl !seed_keys-

    lda #0
    sta zp_eff_blind
    sta vis_room_revealed
    lda #1
    sta zp_player_dlvl
    sta zp_light_radius
    sta player_data + PL_LIGHT_RAD

    // Test 1: directional monster effects trace
    // to the first monster in the chosen line,
    // not just the adjacent tile.
    jsr tv_setup_dark_room
    :PatchJump(get_direction_target, test_get_direction_target_east)

    lda #25
    sta ms_spawn_x
    lda #12
    sta ms_spawn_y
    lda #1
    jsr monster_spawn_one
    bcc !t1_fail+

    jsr eff_directional_monster
    bcc !t1_fail+

    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // Test 2: adjacent sleep effects clear the
    // awake flag and set a live sleep counter.
!t2:
    jsr tv_setup_dark_room

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
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #MF_AWAKE | MF_PROVOKED
    sta (zp_ptr0),y
    ldy #MX_SLEEP_CUR
    lda #0
    sta (zp_ptr0),y

    jsr eff_sleep_adjacent

    lda #23
    ldy #12
    jsr monster_find_at
    bcc !t2_fail+
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_AWAKE
    bne !t2_fail+
    ldy #MX_SLEEP_CUR
    lda (zp_ptr0),y
    cmp #20
    bne !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1
    jmp !t3+

    // Test 3: bolt hit messages must target the
    // actual monster slot they hit, not stale cmb_slot state.
!t3:
    jsr tv_setup_dark_room
    :PatchJump(get_direction_target, test_get_direction_target_east)

    lda #0
    sta cmb_slot

    lda #5
    sta ms_spawn_x
    lda #5
    sta ms_spawn_y
    lda #1
    jsr monster_spawn_one
    bcc !t3_fail+

    lda #25
    sta ms_spawn_x
    lda #12
    sta ms_spawn_y
    lda #1
    jsr monster_spawn_one
    bcc !t3_fail+

    lda #25
    ldy #12
    jsr monster_find_at
    bcc !t3_fail+
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda #20
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y

    lda #2
    ldx #6
    ldy #1
    jsr eff_bolt

    lda cmb_slot
    cmp #1
    bne !t3_fail+
    lda #$01
    sta tc_results + 2
    jmp !t4+
!t3_fail:
    lda #$00
    sta tc_results + 2
    jmp !t4+

    // Test 4: a clean bolt miss stays silent
    // instead of printing "Your spell fizzles out."
!t4:
    jsr tv_setup_dark_room
    :PatchJump(get_direction_target, test_get_direction_target_east)

    lda #0
    sta tde_huff_calls
    sta tde_last_huff_id

    lda #2
    ldx #6
    ldy #1
    jsr eff_bolt

    lda tde_huff_calls
    beq !t4_pass+
    lda tde_last_huff_id
    cmp #HSTR_EB_FIZZLE
    beq !t4_fail+
!t4_pass:
    lda #$01
    sta tc_results + 3
    jmp test_finish
!t4_fail:
    lda #$00
    sta tc_results + 3
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
