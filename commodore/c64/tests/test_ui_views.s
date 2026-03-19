.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_exit_trampoline:
    ldx #6
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk

.pc = $0828 "Main"

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
#import "../../common/player_items.s"
#import "../../common/spell_data.s"
#import "../../common/projectile.s"
#import "../../common/spell_effects.s"
#import "../../common/player_magic.s"
#import "../../common/ui_inventory.s"
#import "../../common/ui_recall.s"
#import "../dungeon_render.s"
#import "../../common/dungeon_los.s"
#import "../../common/player_move.s"
#import "../../common/combat.s"
#import "../../common/monster_attack.s"
#import "../../common/turn.s"
#import "../../common/store_data.s"
#import "../../common/store.s"
#import "../../common/ui_store.s"
#import "../../common/ui_home.s"
#import "../../common/ui_help_data.s"
#import "../../common/ui_help.s"
#import "../../common/ui_trampoline_stubs.s"

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

recall_found_type: .byte 0

tramp_assign_special_room:     jmp assign_special_room
tramp_vault_seal_entrance:     jmp vault_seal_entrance
tramp_spawn_special_room_monsters: jmp spawn_special_room_monsters
tramp_spawn_nest_gold:         jmp spawn_nest_gold
tramp_find_special_room:       jmp find_special_room
tramp_roll_ego_type:           jmp roll_ego_type
tramp_ego_apply_damage:        jmp ego_apply_damage
tramp_ego_get_ac_bonus:        jmp ego_get_ac_bonus

tramp_ego_append_suffix:
    cmp #0
    beq !done+
    jsr ego_get_suffix_ptr
    ldx cmb_buf_idx
    ldy #0
!loop:
    lda (zp_ptr0),y
    beq !end+
    sta combat_msg_buf,x
    inx
    iny
    cpx #41
    bcs !end+
    jmp !loop-
!end:
    stx cmb_buf_idx
!done:
    rts

tramp_ego_put_suffix:
    cmp #0
    beq !done+
    jsr ego_get_suffix_ptr
    ldy #0
!loop:
    lda (zp_ptr0),y
    beq !done+
    sty teps_save_y
    jsr screen_put_char
    ldy teps_save_y
    iny
    jmp !loop-
!done:
    rts
teps_save_y: .byte 0

tc_results: .fill 7, $ff

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_start:
    sei
    cld
    ldx #$ff
    txs

    lda #<help_lines
    sta help_lines_src_lo
    lda #>help_lines
    sta help_lines_src_hi

    ldx #6
    lda #$ff
!clr_results:
    sta tc_results,x
    dex
    bpl !clr_results-

    jsr reset_shared_state

    jsr test_character_view
    jsr test_help_view
    jsr test_inventory_view
    jsr test_equipment_view
    jsr test_recall_view
    jsr test_store_view
    jsr test_home_view

    jmp test_exit_trampoline

reset_shared_state:
    lda #COL_LGREY
    sta zp_text_color
    jsr screen_clear

    lda #0
    sta zp_cursor_row
    sta zp_cursor_col
    sta zp_store_idx
    sta recall_found_type
    sta player_data + PL_LEVEL
    sta player_data + PL_HP_LO
    sta player_data + PL_HP_HI
    sta player_data + PL_MHP_LO
    sta player_data + PL_MHP_HI
    sta player_data + PL_MANA
    sta player_data + PL_MAX_MANA
    sta player_data + PL_GOLD_0
    sta player_data + PL_GOLD_1
    sta player_data + PL_XP_0
    sta player_data + PL_XP_1
    sta player_data + PL_SPELL_TYPE
    sta player_data + PL_SPELLS_KNOWN
    sta player_data + PL_SPELLS_KNOWN_HI
    sta player_data + PL_HUNGER
    sta player_data + PL_MAX_DLVL
    sta player_data + PL_SOCIAL_CLASS
    sta player_data + PL_FLAGS
    sta player_data + PL_RACE
    sta player_data + PL_CLASS
    sta player_data + PL_AC

    ldx #STAT_COUNT - 1
    lda #10
!clr_stats:
    sta player_data + PL_STR_CUR,x
    dex
    bpl !clr_stats-

    ldx #TOTAL_INV_SLOTS - 1
    lda #FI_EMPTY
!clr_inv_id:
    sta inv_item_id,x
    dex
    bpl !clr_inv_id-
    ldx #TOTAL_INV_SLOTS - 1
    lda #0
!clr_inv_rest:
    sta inv_qty,x
    sta inv_p1,x
    sta inv_flags,x
    sta inv_ego,x
    dex
    bpl !clr_inv_rest-

    ldx #STORE_TOTAL_SLOTS - 1
    lda #FI_EMPTY
!clr_store_id:
    sta si_item_id,x
    dex
    bpl !clr_store_id-
    ldx #STORE_TOTAL_SLOTS - 1
    lda #0
!clr_store_rest:
    sta si_qty,x
    sta si_p1,x
    sta si_flags,x
    sta si_ego,x
    dex
    bpl !clr_store_rest-

    ldx #159
    lda #0
!clr_bg:
    sta player_background,x
    dex
    bpl !clr_bg-

    ldx #39
!clr_name_buf:
    sta creature_name_buf,x
    dex
    bpl !clr_name_buf-

    ldx #MAX_CREATURES - 1
!clr_recall:
    sta recall_spells,x
    sta recall_kills,x
    sta recall_deaths,x
    dex
    bpl !clr_recall-
    rts

test_character_view:
    jsr reset_shared_state

    lda #7
    sta player_data + PL_LEVEL
    lda #12
    sta player_data + PL_HP_LO
    sta player_data + PL_MHP_LO
    lda #3
    sta player_data + PL_MANA
    lda #4
    sta player_data + PL_MAX_MANA
    lda #50
    sta player_data + PL_GOLD_0
    lda #9
    sta player_data + PL_XP_0
    lda #18
    sta player_data + PL_STR_CUR
    lda #17
    sta player_data + PL_STR_CUR + 1
    lda #16
    sta player_data + PL_STR_CUR + 2
    lda #15
    sta player_data + PL_STR_CUR + 3
    lda #14
    sta player_data + PL_STR_CUR + 4
    lda #13
    sta player_data + PL_STR_CUR + 5
    lda #1
    sta player_data + PL_FLAGS
    lda #42
    sta player_data + PL_SOCIAL_CLASS

    lda #<test_player_name
    sta zp_ptr0
    lda #>test_player_name
    sta zp_ptr0_hi
    lda #<(player_data + PL_NAME)
    sta zp_ptr1
    lda #>(player_data + PL_NAME)
    sta zp_ptr1_hi
    jsr copy_string_zp

    jsr ui_char_display

    lda #<char_title_str
    sta zp_ptr0
    lda #>char_title_str
    sta zp_ptr0_hi
    lda #0
    ldx #12
    jsr assert_screen_string
    bcc !fail+

    lda #<test_player_name
    sta zp_ptr0
    lda #>test_player_name
    sta zp_ptr0_hi
    lda #2
    ldx #7
    jsr assert_screen_string
    bcc !fail+

    lda #<press_key_str
    sta zp_ptr0
    lda #>press_key_str
    sta zp_ptr0_hi
    lda #18
    ldx #10
    jsr assert_screen_string
    bcc !fail+

    lda #$01
    bne !store+
!fail:
    lda #$00
!store:
    sta tc_results + 0
    rts

test_help_view:
    jsr reset_shared_state
    jsr ui_help_display

    lda #<uh_title_str
    sta zp_ptr0
    lda #>uh_title_str
    sta zp_ptr0_hi
    lda #0
    ldx #11
    jsr assert_screen_string
    bcc !fail+

    lda #<expected_help_movement
    sta zp_ptr0
    lda #>expected_help_movement
    sta zp_ptr0_hi
    lda #1
    ldx #2
    jsr assert_screen_string
    bcc !fail+

    lda #<expected_help_actions
    sta zp_ptr0
    lda #>expected_help_actions
    sta zp_ptr0_hi
    lda #1
    ldx #20
    jsr assert_screen_string
    bcc !fail+

    lda #<uh_press_key_str
    sta zp_ptr0
    lda #>uh_press_key_str
    sta zp_ptr0_hi
    lda #24
    ldx #13
    jsr assert_screen_string
    bcc !fail+

    lda #$01
    bne !store+
!fail:
    lda #$00
!store:
    sta tc_results + 1
    rts

test_inventory_view:
    jsr reset_shared_state

    lda #15
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0

    jsr ui_inv_display

    lda #<uinv_title_str
    sta zp_ptr0
    lda #>uinv_title_str
    sta zp_ptr0_hi
    lda #0
    ldx #15
    jsr assert_screen_string
    bcc !fail+

    lda #<expected_inventory_line
    sta zp_ptr0
    lda #>expected_inventory_line
    sta zp_ptr0_hi
    lda #2
    ldx #1
    jsr assert_screen_string
    bcc !fail+

    lda #<press_key_str
    sta zp_ptr0
    lda #>press_key_str
    sta zp_ptr0_hi
    lda #24
    ldx #12
    jsr assert_screen_string
    bcc !fail+

    lda #$01
    bne !store+
!fail:
    lda #$00
!store:
    sta tc_results + 2
    rts

test_equipment_view:
    jsr reset_shared_state

    lda #2
    sta inv_item_id + EQUIP_WEAPON
    lda #1
    sta inv_qty + EQUIP_WEAPON

    jsr ui_equip_display

    lda #<ueq_title_str
    sta zp_ptr0
    lda #>ueq_title_str
    sta zp_ptr0_hi
    lda #0
    ldx #15
    jsr assert_screen_string
    bcc !fail+

    lda #<expected_equip_line
    sta zp_ptr0
    lda #>expected_equip_line
    sta zp_ptr0_hi
    lda #2
    ldx #1
    jsr assert_screen_string
    bcc !fail+

    lda #$01
    bne !store+
!fail:
    lda #$00
!store:
    sta tc_results + 3
    rts

test_recall_view:
    jsr reset_shared_state

    lda #<test_creature_name
    sta zp_ptr0
    lda #>test_creature_name
    sta zp_ptr0_hi
    lda #<creature_name_buf
    sta zp_ptr1
    lda #>creature_name_buf
    sta zp_ptr1_hi
    jsr copy_string_zp

    lda #0
    sta recall_found_type
    sta cr_color
    lda #$0b                    // 'K'
    sta cr_display
    lda #7
    sta cr_level
    lda #12
    sta cr_ac
    lda #1
    sta cr_hd_num
    lda #8
    sta cr_hd_sides
    lda #1
    sta recall_spells
    lda #3
    sta recall_kills

    jsr ui_recall_display

    lda #<rcl_s_title
    sta zp_ptr0
    lda #>rcl_s_title
    sta zp_ptr0_hi
    lda #0
    ldx #13
    jsr assert_screen_string
    bcc !fail+

    lda #<test_creature_name
    sta zp_ptr0
    lda #>test_creature_name
    sta zp_ptr0_hi
    lda #2
    ldx #6
    jsr assert_screen_string
    bcc !fail+

    lda #<expected_recall_lv
    sta zp_ptr0
    lda #>expected_recall_lv
    sta zp_ptr0_hi
    lda #4
    ldx #2
    jsr assert_screen_string
    bcc !fail+

    lda #$01
    bne !store+
!fail:
    lda #$00
!store:
    sta tc_results + 4
    rts

test_store_view:
    jsr reset_shared_state

    lda #0
    sta zp_store_idx
    lda #15
    sta si_item_id + 0
    lda #1
    sta si_qty + 0

    jsr store_draw_screen

    lda #<sn_general
    sta zp_ptr0
    lda #>sn_general
    sta zp_ptr0_hi
    lda #0
    ldx #1
    jsr assert_screen_string
    bcc !fail+

    lda #<so_0
    sta zp_ptr0
    lda #>so_0
    sta zp_ptr0_hi
    lda #1
    ldx #2
    jsr assert_screen_string
    bcc !fail+

    lda #<expected_inventory_line
    sta zp_ptr0
    lda #>expected_inventory_line
    sta zp_ptr0_hi
    lda #3
    ldx #1
    jsr assert_screen_string
    bcc !fail+

    lda #$01
    bne !store+
!fail:
    lda #$00
!store:
    sta tc_results + 5
    rts

test_home_view:
    jsr reset_shared_state
    jsr screen_clear

    :PatchJump(input_get_key, test_input_get_key)
    :PatchJump(ui_help_clear_all, test_ui_help_clear_all)

    lda #STORE_HOME
    sta zp_store_idx
    lda #2
    sta si_item_id + 84
    lda #1
    sta si_qty + 84

    jsr home_enter

    lda #<sn_home
    sta zp_ptr0
    lda #>sn_home
    sta zp_ptr0_hi
    lda #0
    ldx #1
    jsr assert_screen_string
    bcc !fail+

    lda #<expected_home_line
    sta zp_ptr0
    lda #>expected_home_line
    sta zp_ptr0_hi
    lda #3
    ldx #1
    jsr assert_screen_string
    bcc !fail+

    lda #<hm_menu_str
    sta zp_ptr0
    lda #>hm_menu_str
    sta zp_ptr0_hi
    lda #18
    ldx #1
    jsr assert_screen_string
    bcc !fail+

    lda #$01
    bne !store+
!fail:
    lda #$00
!store:
    sta tc_results + 6
    rts

assert_screen_string:
    sta zp_cursor_row
    stx zp_cursor_col
    jsr screen_set_cursor
    ldy #0
!loop:
    lda (zp_ptr0),y
    beq !ok+
    sta zp_temp0
    lda (zp_screen_lo),y
    cmp zp_temp0
    bne !bad+
    iny
    cpy #40
    bcc !loop-
!bad:
    clc
    rts
!ok:
    sec
    rts

copy_string_zp:
    ldy #0
!loop:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    beq !done+
    iny
    cpy #40
    bcc !loop-
!done:
    rts

test_input_get_key:
    lda #$51
    rts

test_ui_help_clear_all:
    rts

test_player_name:
    .text "TESTER" ; .byte 0
test_creature_name:
    .text "KOBOLD" ; .byte 0
expected_help_movement:
    .text "Movement" ; .byte 0
expected_help_actions:
    .text "Actions" ; .byte 0
expected_inventory_line:
    .byte $01
    .text ") Ration of Food" ; .byte 0
expected_equip_line:
    .text "Weapon: Dagger" ; .byte 0
expected_recall_lv:
    .text "LV 1" ; .byte 0
expected_home_line:
    .byte $01
    .text ") Dagger" ; .byte 0
