.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_exit_trampoline:
    ldx #19
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk

.pc = $0828 "Main"

.encoding "screencode_mixed"

cmb_buf_idx:     .byte 0
combat_msg_buf:  .fill 42, 0

reu_present:     .byte 0
reu_loading_row: .byte 0

reu_loading_hdr:
    .text "Loading:" ; .byte 0
reu_fn_t1: .text "MONSTER.DB.1" ; .byte 0
reu_fn_t2: .text "MONSTER.DB.2" ; .byte 0
reu_fn_t3: .text "MONSTER.DB.3" ; .byte 0
reu_fn_t4: .text "MONSTER.DB.4" ; .byte 0
reu_fn_tier_lo:
    .byte <reu_fn_t1, <reu_fn_t2, <reu_fn_t3, <reu_fn_t4
reu_fn_tier_hi:
    .byte >reu_fn_t1, >reu_fn_t2, >reu_fn_t3, >reu_fn_t4

df_target_x: .byte 0
df_target_y: .byte 0
.label cmb_period = $00
cmb_type:   .byte 0
cmb_damage: .byte 0
eff_fear_timer: .byte 0

reu_show_status:
reu_load_all_tiers:
reu_stash_overlays:
reu_fetch_tier:
reu_show_file:
overlay_invalidate:
find_random_floor:
combat_append_decimal_16:
cmb_term_and_print:
viewport_update:
render_viewport:
player_update_hunger_state:
eff_heal:
eff_detect_monsters:
eff_light_room:
eff_identify_prompt:
eff_identify_scroll_resident:
eff_teleport_self:
eff_remove_curse:
eff_aggravate:
eff_bolt:
eff_directional_monster:
    rts

current_overlay: .byte 0

combat_append_str:
    sta zp_ptr1
    sty zp_ptr1_hi
    ldx cmb_buf_idx
    ldy #0
!loop:
    lda (zp_ptr1),y
    beq !done+
    sta combat_msg_buf,x
    inx
    iny
    cpx #41
    bcc !loop-
!done:
    stx cmb_buf_idx
    rts

combat_append_char:
    ldx cmb_buf_idx
    sta combat_msg_buf,x
    inx
    stx cmb_buf_idx
    rts

combat_append_decimal:
    rts

magic_recalc_mana:
    rts

magic_check_new_spells:
    rts

#import "../../common/zeropage.s"
#import "../memory.s"
#import "../screen.s"
#import "../../common/color.s"
#import "../config.s"
#import "../input.s"
#import "../../common/rng.s"
#import "../../common/math.s"
#import "../../common/tables.s"
#import "../../common/dungeon_data.s"
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
#import "../../common/huffman.s"
#import "../../common/monster.s"
#import "../../common/tier_manager.s"
#import "../../common/item.s"
#import "../../common/ego_items.s"
#import "../../common/player_items.s"
#import "../../common/spell_data.s"
#import "../../common/ui_inventory.s"
#import "../../common/ui_equipment.s"
#import "../../common/ui_recall.s"
#import "../../common/recall.s"
#import "../../common/store_data.s"
#import "../../common/store.s"
#import "../../common/ui_store.s"
#import "../../common/ui_home.s"
#import "../../common/ui_home_text.s"
#import "../../common/ui_help_data.s"
#import "../../common/ui_help_page2_data.s"
#import "../../common/ui_help.s"
#define C64_TEST_FULL_ITEMDESC_STUB
#import "../../common/ui_trampoline_stubs.s"

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

recall_found_type: .byte 0

assign_special_room:
vault_seal_entrance:
spawn_special_room_monsters:
spawn_nest_gold:
find_special_room:
    rts

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

tc_results: .fill 20, $ff

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

    lda #<help_pages
    sta help_pages_src_lo
    lda #>help_pages
    sta help_pages_src_hi

    ldx #19
    lda #$ff
!clr_results:
    sta tc_results,x
    dex
    bpl !clr_results-

    jsr reset_shared_state

    jsr test_character_view
    jsr test_help_view
    jsr test_inventory_view
    jsr test_inventory_invalid_ego_view
    jsr test_inventory_select_view
    jsr test_inventory_identify_select_view
    jsr test_equipment_view
    jsr test_recall_view
    jsr test_store_view
    jsr test_ui_help_clear_forces_status_redraw
    jsr test_home_view
    jsr test_status_redraw_shrinks_numbers
    jsr test_screen_clear_forces_status_redraw
    jsr test_status_search_indicator_row21
    jsr test_inventory_identify_select_view_six_items
    jsr test_screen_put_string_clamps_to_row
    jsr test_equipment_select_view

    jmp test_exit_trampoline

reset_shared_state:
    lda #COL_LGREY
    sta zp_text_color
    jsr screen_clear

    lda #0
    sta help_page_idx
    sta test_key_idx
    sta test_key_len
    sta piw_visible_count
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
    lda #$ff
    sta piw_filter

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
    sta si_meta,x
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

    lda #<help_title_str
    sta zp_ptr0
    lda #>help_title_str
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

    lda #<uh_next_key_str
    sta zp_ptr0
    lda #>uh_next_key_str
    sta zp_ptr0_hi
    lda #24
    ldx #3
    jsr assert_screen_string
    bcc !fail+

    lda #1
    sta help_page_idx
    jsr ui_help_display

    lda #<expected_help_more_keys
    sta zp_ptr0
    lda #>expected_help_more_keys
    sta zp_ptr0_hi
    lda #1
    ldx #2
    jsr assert_screen_string
    bcc !fail+

    lda #<expected_help_notes
    sta zp_ptr0
    lda #>expected_help_notes
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
    ldx #5
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

    lda #4
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    lda #EGO_SLAY_EVIL
    sta inv_ego + 0
    lda #IF_SENSED
    sta inv_flags + 0

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

test_inventory_invalid_ego_view:
    jsr reset_shared_state

    lda #4
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    lda #$40
    sta inv_ego + 0

    jsr ui_inv_display

    lda #<expected_inventory_plain_line
    sta zp_ptr0
    lda #>expected_inventory_plain_line
    sta zp_ptr0_hi
    lda #2
    ldx #1
    jsr assert_screen_string
    bcc !fail+

    lda #2
    sta zp_cursor_row
    lda #14
    sta zp_cursor_col
    jsr screen_set_cursor
    ldy #0
    lda (zp_screen_lo),y
    cmp #$20
    bne !fail+

    lda #$01
    bne !store+
!fail:
    lda #$00
!store:
    sta tc_results + 3
    rts

test_inventory_select_view:
    jsr reset_shared_state

    lda #4
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    lda #17
    sta inv_item_id + 1
    lda #1
    sta inv_qty + 1
    lda #$ff
    sta piw_filter

    jsr ui_inv_select_display

    lda #<expected_filtered_inv_line_a
    sta zp_ptr0
    lda #>expected_filtered_inv_line_a
    sta zp_ptr0_hi
    lda #2
    ldx #1
    jsr assert_screen_string
    bcc !fail+

    lda #<expected_filtered_inv_line_b
    sta zp_ptr0
    lda #>expected_filtered_inv_line_b
    sta zp_ptr0_hi
    lda #3
    ldx #1
    jsr assert_screen_string
    bcc !fail+

    lda #<uinv_select_str
    sta zp_ptr0
    lda #>uinv_select_str
    sta zp_ptr0_hi
    lda #24
    ldx #14
    jsr assert_screen_string
    bcc !fail+

    lda #$01
    bne !store+
!fail:
    lda #$00
!store:
    sta tc_results + 4
    rts

test_inventory_identify_select_view:
    jsr reset_shared_state

    lda #4
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    lda #$fd
    sta piw_filter

    jsr ui_inv_select_display

    lda #<uinv_identify_footer_str
    sta zp_ptr0
    lda #>uinv_identify_footer_str
    sta zp_ptr0_hi
    lda #24
    ldx #7
    jsr assert_screen_string
    bcc !fail+

    lda #$01
    bne !store+
!fail:
    lda #$00
!store:
    sta tc_results + 5
    rts

test_equipment_view:
    jsr reset_shared_state

    lda #4
    sta inv_item_id + EQUIP_WEAPON
    lda #1
    sta inv_qty + EQUIP_WEAPON
    lda #EGO_SLAY_EVIL
    sta inv_ego + EQUIP_WEAPON
    lda #IF_SENSED
    sta inv_flags + EQUIP_WEAPON

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
    sta tc_results + 6
    rts

test_equipment_select_view:
    jsr reset_shared_state

    lda #4
    sta inv_item_id + EQUIP_WEAPON
    lda #1
    sta inv_qty + EQUIP_WEAPON

    jsr ui_equip_select_display

    lda #<ueq_select_str
    sta zp_ptr0
    lda #>ueq_select_str
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
    sta tc_results + 15
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
    sta cr_atk0_type
    lda #2
    sta cr_atk0_dice
    lda #6
    sta cr_atk0_sides
    lda #0
    sta cr_atk1_type
    sta cr_atk1_dice
    sta cr_atk1_sides
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

    lda #<expected_recall_hp
    sta zp_ptr0
    lda #>expected_recall_hp
    sta zp_ptr0_hi
    lda #4
    ldx #21
    jsr assert_screen_string
    bcc !fail+

    lda #<expected_recall_atk
    sta zp_ptr0
    lda #>expected_recall_atk
    sta zp_ptr0_hi
    lda #6
    ldx #7
    jsr assert_screen_string
    bcc !fail+

    // Zero-damage placeholder attacks should be suppressed.
    jsr reset_shared_state
    lda #0
    sta recall_found_type
    lda #1
    sta cr_atk0_type
    sta cr_atk1_type
    lda #0
    sta cr_atk0_dice
    sta cr_atk0_sides
    sta cr_atk1_dice
    sta cr_atk1_sides
    jsr ui_recall_display

    lda #<rcl_s_none
    sta zp_ptr0
    lda #>rcl_s_none
    sta zp_ptr0_hi
    lda #6
    ldx #7
    jsr assert_screen_string
    bcc !fail+

    lda #$01
    bne !store+
!fail:
    lda #$00
!store:
    sta tc_results + 7
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

    lda #<expected_store_line
    sta zp_ptr0
    lda #>expected_store_line
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
    sta tc_results + 8
    rts

test_ui_help_clear_forces_status_redraw:
    jsr reset_shared_state

    lda #0
    sta status_cache_valid
    sta zp_player_hp_hi
    sta zp_player_mhp_hi
    sta player_data + PL_HP_HI
    sta player_data + PL_MHP_HI
    sta zp_player_mp
    sta zp_player_mmp
    sta zp_player_ac
    sta zp_hunger_state
    lda #1
    sta zp_player_dlvl

    lda #21
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #34
    sta zp_player_mhp_lo
    sta player_data + PL_MHP_LO
    jsr status_draw

    jsr ui_help_clear_all
    jsr status_draw

    lda #<expected_status_hp_after_modal_clear
    sta zp_ptr0
    lda #>expected_status_hp_after_modal_clear
    sta zp_ptr0_hi
    lda #23
    ldx #0
    jsr assert_screen_string
    bcc !fail+

    lda #$01
    bne !store+
!fail:
    lda #$00
!store:
    sta tc_results + 9
    rts

test_home_view:
    jsr reset_shared_state
    jsr screen_clear

    :PatchJump(ui_help_clear_all, test_ui_help_clear_all)

    lda #1
    sta $c6
    lda #$51
    sta $0277

    lda #STORE_HOME
    sta zp_store_idx
    lda #2
    sta si_item_id + 84
    lda #1
    sta si_qty + 84

    jsr home_enter
    :PatchJump(ui_help_clear_all, ui_clear_full_screen_safe)

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
    sta tc_results + 10
    rts

test_status_redraw_shrinks_numbers:
    jsr reset_shared_state

    lda #0
    sta status_cache_valid
    sta zp_player_hp_hi
    sta zp_player_mhp_hi
    sta player_data + PL_HP_HI
    sta player_data + PL_MHP_HI
    sta zp_player_mp
    sta zp_player_mmp
    sta zp_player_ac
    sta zp_hunger_state
    lda #1
    sta zp_player_dlvl

    lda #211
    sta zp_player_hp_lo
    sta zp_player_mhp_lo
    sta player_data + PL_HP_LO
    sta player_data + PL_MHP_LO
    jsr status_draw

    lda #5
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #21
    sta zp_player_mhp_lo
    sta player_data + PL_MHP_LO
    jsr status_draw

    lda #<expected_status_hp_shrunk
    sta zp_ptr0
    lda #>expected_status_hp_shrunk
    sta zp_ptr0_hi
    lda #23
    ldx #0
    jsr assert_screen_string
    bcc !fail+

    lda #$01
    bne !store+
!fail:
    lda #$00
!store:
    sta tc_results + 11
    rts

test_screen_clear_forces_status_redraw:
    jsr reset_shared_state

    lda #0
    sta status_cache_valid
    sta zp_player_hp_hi
    sta zp_player_mhp_hi
    sta player_data + PL_HP_HI
    sta player_data + PL_MHP_HI
    sta zp_player_mp
    sta zp_player_mmp
    sta zp_player_ac
    sta zp_hunger_state
    lda #1
    sta zp_player_dlvl

    lda #21
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #34
    sta zp_player_mhp_lo
    sta player_data + PL_MHP_LO
    jsr status_draw

    jsr screen_clear
    jsr status_draw

    lda #<expected_status_hp_after_clear
    sta zp_ptr0
    lda #>expected_status_hp_after_clear
    sta zp_ptr0_hi
    lda #23
    ldx #0
    jsr assert_screen_string
    bcc !fail+

    lda #$01
    bne !store+
!fail:
    lda #$00
!store:
    sta tc_results + 12
    rts

test_status_search_indicator_row21:
    jsr reset_shared_state

    lda #0
    sta player_data + PL_NAME
    sta status_cache_valid
    sta player_data + PL_FLAGS
    sta zp_player_hp_hi
    sta zp_player_mhp_hi
    sta player_data + PL_HP_HI
    sta player_data + PL_MHP_HI
    sta zp_player_mp
    sta zp_player_mmp
    sta zp_player_ac
    sta zp_hunger_state
    lda #1
    sta zp_player_lvl
    sta zp_player_dlvl
    lda #21
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #34
    sta zp_player_mhp_lo
    sta player_data + PL_MHP_LO
    jsr status_draw

    lda player_data + PL_FLAGS
    ora #PLF_SEARCHING
    sta player_data + PL_FLAGS
    lda zp_ui_dirty
    ora #$01
    sta zp_ui_dirty
    sei
    jsr status_draw
    cli

    lda #<expected_status_search
    sta zp_ptr0
    lda #>expected_status_search
    sta zp_ptr0_hi
    lda #21
    ldx #19
    sei
    jsr assert_screen_string
    bcc !string_fail+

    cli

    lda #$01
    bne !store+
!string_fail:
    cli
    lda #$02
!store:
    sta tc_results + 16
    rts

test_inventory_identify_select_view_six_items:
    jsr reset_shared_state

    lda #$fd
    sta piw_filter
    ldx #0
!fill_loop:
    lda #4
    sta inv_item_id,x
    lda #1
    sta inv_qty,x
    inx
    cpx #6
    bcc !fill_loop-

    jsr ui_inv_select_display

    lda #<expected_identify_prompt_af
    sta zp_ptr0
    lda #>expected_identify_prompt_af
    sta zp_ptr0_hi
    lda #24
    ldx #7
    jsr assert_screen_string
    bcc !fail+

    lda #$01
    bne !store+
!fail:
    lda #$00
!store:
    sta tc_results + 13
    rts

test_screen_put_string_clamps_to_row:
    jsr reset_shared_state

    lda #<long_row_string
    sta zp_ptr0
    lda #>long_row_string
    sta zp_ptr0_hi
    lda #2
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    jsr screen_put_string
    lda zp_cursor_col
    cmp #40
    bne !fail+

    lda #2
    sta zp_cursor_row
    lda #39
    sta zp_cursor_col
    jsr screen_set_cursor
    ldy #0
    lda (zp_screen_lo),y
    cmp #$39
    bne !fail+

    lda #3
    sta zp_cursor_row
    lda #0
    sta zp_cursor_col
    jsr screen_set_cursor
    ldy #0
    lda (zp_screen_lo),y
    cmp #$20
    bne !fail+

    lda #$01
    bne !store+
!fail:
    lda #$00
!store:
    sta tc_results + 14
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

hist_msg_a: .text "A" ; .byte 0
hist_msg_b: .text "B" ; .byte 0
hist_msg_c: .text "C" ; .byte 0
hist_msg_d: .text "D" ; .byte 0
hist_msg_e: .text "E" ; .byte 0
hist_msg_f: .text "F" ; .byte 0
hist_msg_g: .text "G" ; .byte 0
hist_msg_h: .text "H" ; .byte 0
hist_msg_i: .text "I" ; .byte 0
hist_msg_one: .text "ONE" ; .byte 0
hist_msg_two: .text "TWO" ; .byte 0
hist_msg_three: .text "THREE" ; .byte 0
expected_more_resume_row0: .text "THREE" ; .byte 0
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
    ldx test_key_idx
    cpx test_key_len
    bcs !default+
    lda test_key_script,x
    inx
    stx test_key_idx
    rts
!default:
    lda #$51
    rts

test_key_script: .fill 4, 0
test_key_len:    .byte 0
test_key_idx:    .byte 0

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
expected_help_more_keys:
    .text "More Keys" ; .byte 0
expected_help_notes:
    .text "Notes" ; .byte 0
expected_inventory_line:
    .byte $01
    .text ") Long Sword (Slay Evil) (magik)" ; .byte 0
expected_inventory_plain_line:
    .byte $01
    .text ") Long Sword" ; .byte 0
expected_filtered_inv_line_a:
    .byte $01
    .text ") " ; .byte 0
expected_filtered_inv_line_b:
    .byte $02
    .text ") " ; .byte 0
expected_filtered_book_line_a:
    .byte $01
    .text ") Holy Book of Prayers Beginners Handb" ; .byte 0
expected_filtered_book_line_b:
    .byte $02
    .text ") Holy Book of Prayers Words of Wisdom" ; .byte 0
expected_store_line:
    .byte $01
    .text ") Ration of Food" ; .byte 0
expected_filtered_eq_weapon:
    .byte $01
    .text ") Weapon: " ; .byte 0
expected_filtered_eq_light:
    .byte $02
    .text ") Light: " ; .byte 0
expected_quaff_prompt_ab:
    .text "Quaff which potion (a-b)?" ; .byte 0
expected_identify_prompt_af:
    .text "Identify which item (a-" ; .byte $06 ; .text ")?" ; .byte 0
expected_equip_line:
    .byte $01
    .text ") Weapon: Long Sword (Slay Evil) (mag" ; .byte 0
expected_recall_lv:
    .text "LV 7" ; .byte 0
expected_recall_hp:
    .byte $31, $44, $38, 0
expected_recall_atk:
    .byte $48, $49, $54, $20, $32, $44, $36, 0
expected_home_line:
    .byte $01
    .text ") Dagger" ; .byte 0
expected_status_hp_shrunk:
    .text "HP:5/21   " ; .byte 0
expected_status_hp_after_clear:
    .text "HP:21/34" ; .byte 0
expected_status_hp_after_modal_clear:
    .text "HP:21/34" ; .byte 0
expected_status_search:
    .text "Search*" ; .byte 0
long_row_string:
    .text "1234567890123456789012345678901234567890" ; .byte 0

ui_views_part1_end:
.assert "UI views part 1 stays below MAP_BASE", ui_views_part1_end <= MAP_BASE, true
