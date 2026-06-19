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

.const SFX_HIT    = 0
.const SFX_BUMP   = 1
.const SFX_PICKUP = 2
.const CF_UNDEAD  = $02
.const CF_EVIL    = $04
.const CF_ANIMAL  = $08
.const STORE_TOTAL_SLOTS = 96
.const MAX_CREATURES = 65
.label cmb_period = $00
cmb_type:   .byte 0
cmb_damage: .byte 0
eff_fear_timer: .byte 0
cr_mflags:  .fill 65, 0
current_tier: .byte 0
tier_loaded:  .byte 0
creature_name_buf: .fill 40, 0
recall_spells:     .fill MAX_CREATURES, 0
recall_kills:      .fill MAX_CREATURES, 0
recall_deaths:     .fill MAX_CREATURES, 0
si_item_id: .fill STORE_TOTAL_SLOTS, $ff
si_qty:     .fill STORE_TOTAL_SLOTS, 0
si_p1:      .fill STORE_TOTAL_SLOTS, 0
si_to_hit:  .fill STORE_TOTAL_SLOTS, 0
si_to_dam:  .fill STORE_TOTAL_SLOTS, 0
si_to_ac:   .fill STORE_TOTAL_SLOTS, 0
si_meta:    .fill STORE_TOTAL_SLOTS, 0
help_pages: .byte 0, 0
.const MX_CONFUSE = 9

hal_sound_play:
combat_append_decimal_16:
cmb_term_and_print:
tier_restore_after_overlay:
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
monster_get_ptr:
ui_help_display:
store_init_all:
store_restock_all:
store_enter:
    rts

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

player_death_check:
    rts

#import "../../../../core/zeropage.s"
#import "../memory.s"
#import "../screen.s"
#import "../../../../core/color.s"
#import "../config.s"
#import "../input.s"
#import "../../../../core/rng.s"
#import "../../../../core/math.s"
#import "../../../../core/tables.s"
#import "../../../../core/dungeon_data.s"
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
#import "../../../../core/huffman.s"
#import "../../../../core/dungeon_gen.s"
#import "../../../../core/dungeon_features.s"
#import "../../../../core/item.s"
#import "../../../../core/ego_items.s"
#import "../../../../core/player_items.s"
#import "../../../../core/spell_data.s"
#import "../../../../core/ui_inventory.s"
#import "../../../../core/ui_equipment.s"
#define C64_TEST_FULL_ITEMDESC_STUB
#import "../../../../core/ui_trampoline_stubs.s"

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

    jsr test_filtered_inventory_view
    jsr test_book_filtered_inventory_view
    jsr test_filtered_equipment_view
    jsr test_filtered_prompt_range
    jsr test_message_history_ring
    jsr test_message_more_resume
    jsr test_modal_restore_resets_message_state

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
    sta si_to_hit,x
    sta si_to_dam,x
    sta si_to_ac,x
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

test_filtered_inventory_view:
    jsr reset_shared_state

    lda #4
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0

    lda #17
    sta inv_item_id + 1
    lda #1
    sta inv_qty + 1

    lda #25
    sta inv_item_id + 4
    lda #1
    sta inv_qty + 4

    lda #ICAT_POTION
    sta piw_filter
    jsr ui_inv_display

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

    lda #$01
    bne !store+
!fail:
    lda #$00
!store:
    sta tc_results + 13
    rts

test_book_filtered_inventory_view:
    jsr reset_shared_state

    lda #47
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0

    lda #48
    sta inv_item_id + 1
    lda #1
    sta inv_qty + 1

    lda #55
    sta inv_item_id + 2
    lda #1
    sta inv_qty + 2

    lda #58
    sta inv_item_id + 3
    lda #1
    sta inv_qty + 3

    lda #PIW_FILTER_PRAYER_BOOK
    sta piw_filter
    jsr ui_inv_display

    lda #<expected_filtered_book_line_a
    sta zp_ptr0
    lda #>expected_filtered_book_line_a
    sta zp_ptr0_hi
    lda #2
    ldx #1
    jsr assert_screen_string
    bcc !fail+

    lda #<expected_filtered_book_line_b
    sta zp_ptr0
    lda #>expected_filtered_book_line_b
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
    sta tc_results + 14
    rts

test_filtered_equipment_view:
    jsr reset_shared_state

    lda #4
    sta inv_item_id + EQUIP_WEAPON
    lda #1
    sta inv_qty + EQUIP_WEAPON

    lda #14
    sta inv_item_id + EQUIP_LIGHT
    lda #1
    sta inv_qty + EQUIP_LIGHT

    jsr ui_equip_display

    lda #<expected_filtered_eq_weapon
    sta zp_ptr0
    lda #>expected_filtered_eq_weapon
    sta zp_ptr0_hi
    lda #2
    ldx #1
    jsr assert_screen_string
    bcc !fail+

    lda #<expected_filtered_eq_light
    sta zp_ptr0
    lda #>expected_filtered_eq_light
    sta zp_ptr0_hi
    lda #8
    ldx #1
    jsr assert_screen_string
    bcc !fail+

    lda #$01
    bne !store+
!fail:
    lda #$00
!store:
    sta tc_results + 15
    rts

test_filtered_prompt_range:
    jsr reset_shared_state
    jsr msg_init

    lda #2
    ldx #HSTR_PIQ_QUAFF_PROMPT
    jsr piw_print_prompt_with_count

    lda #<expected_quaff_prompt_ab
    sta zp_ptr0
    lda #>expected_quaff_prompt_ab
    sta zp_ptr0_hi
    lda #0
    ldx #0
    jsr assert_screen_string
    bcc !fail+

    lda #$01
    bne !store+
!fail:
    lda #$00
!store:
    sta tc_results + 16
    rts

test_message_history_ring:
    jsr reset_shared_state
    jsr msg_init

    lda #<hist_msg_a
    sta zp_ptr0
    lda #>hist_msg_a
    sta zp_ptr0_hi
    jsr msg_save_history

    lda #<hist_msg_b
    sta zp_ptr0
    lda #>hist_msg_b
    sta zp_ptr0_hi
    jsr msg_save_history

    lda #<hist_msg_c
    sta zp_ptr0
    lda #>hist_msg_c
    sta zp_ptr0_hi
    jsr msg_save_history

    lda #<hist_msg_d
    sta zp_ptr0
    lda #>hist_msg_d
    sta zp_ptr0_hi
    jsr msg_save_history

    lda #<hist_msg_e
    sta zp_ptr0
    lda #>hist_msg_e
    sta zp_ptr0_hi
    jsr msg_save_history

    lda #<hist_msg_f
    sta zp_ptr0
    lda #>hist_msg_f
    sta zp_ptr0_hi
    jsr msg_save_history

    lda #<hist_msg_g
    sta zp_ptr0
    lda #>hist_msg_g
    sta zp_ptr0_hi
    jsr msg_save_history

    lda #<hist_msg_h
    sta zp_ptr0
    lda #>hist_msg_h
    sta zp_ptr0_hi
    jsr msg_save_history

    lda #<hist_msg_i
    sta zp_ptr0
    lda #>hist_msg_i
    sta zp_ptr0_hi
    jsr msg_save_history

    lda msg_hist_idx
    cmp #1
    bne !fail+

    lda msg_history
    cmp #'I'
    bne !fail+
    lda msg_history + 1
    bne !fail+

    lda msg_history + MSG_HIST_LEN
    cmp #'B'
    bne !fail+
    lda msg_history + (MSG_HIST_LEN * 7)
    cmp #'H'
    bne !fail+

    lda #$01
    bne !store+
!fail:
    lda #$00
!store:
    sta tc_results + 17
    rts

test_message_more_resume:
    jsr reset_shared_state
    jsr msg_init

    :PatchJump(input_get_key, test_input_get_key)

    lda #$20
    sta test_key_script
    lda #0
    sta test_key_idx
    lda #1
    sta test_key_len

    lda #<hist_msg_one
    sta zp_ptr0
    lda #>hist_msg_one
    sta zp_ptr0_hi
    jsr msg_print

    lda #<hist_msg_two
    sta zp_ptr0
    lda #>hist_msg_two
    sta zp_ptr0_hi
    jsr msg_print

    lda #<hist_msg_three
    sta zp_ptr0
    lda #>hist_msg_three
    sta zp_ptr0_hi
    jsr msg_print

    lda zp_msg_flags
    cmp #MSG_PENDING
    bne !fail+

    lda #<expected_more_resume_row0
    sta zp_ptr0
    lda #>expected_more_resume_row0
    sta zp_ptr0_hi
    lda #0
    ldx #0
    jsr assert_screen_string
    bcc !fail+

    lda $0400 + (40 * 1)
    cmp #$20
    bne !fail+

    lda msg_hist_idx
    cmp #3
    bne !fail+

    lda msg_history + (MSG_HIST_LEN * 2)
    cmp #'T'
    bne !fail+

    lda #$01
    bne !store+
!fail:
    lda #$00
!store:
    sta tc_results + 18
    rts

test_modal_restore_resets_message_state:
    jsr reset_shared_state

    lda #0
    sta zp_player_dlvl
    sta current_tier
    sta tier_loaded

    lda #MSG_PENDING | MSG_FULL
    sta zp_msg_flags
    lda #23
    sta msg_row1_col

    jsr ui_view_restore_modal_overlay

    lda zp_msg_flags
    bne !fail+
    lda msg_row1_col
    bne !fail+

    lda #$01
    bne !store+
!fail:
    lda #$00
!store:
    sta tc_results + 19
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
    .byte $51, $15, $01, $06, $06, $20, $17, $08, $09, $03, $08, $20
    .byte $10, $0f, $14, $09, $0f, $0e, $20, $28, $01, $2d, $02, $29, $3f, $00
expected_equip_line:
    .byte $01
    .text ") Weapon: Long Sword (Slay Evil) (mag" ; .byte 0
expected_recall_lv:
    .text "LV 1" ; .byte 0
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

ui_views_part2_end:
.assert "UI views part 2 stays below MAP_BASE", ui_views_part2_end <= MAP_BASE, true
