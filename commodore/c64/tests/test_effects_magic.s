// test_effects_magic.s — Runtime tests for player-magic-heavy effect paths

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tc_results: .fill 52, $ff
tpm_msg_buf:  .fill 42, 0
tpm_expected_identify_csw:
    .text "This is a Cure Serious Wounds potion." ; .byte 0

.pc = $080E "Test Code"

.encoding "screencode_mixed"

test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    :BankOutKernal()
    ldx #51
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    :BankInKernal()
    brk

.pc = $0840 "Main"

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
#import "../../common/projectile.s"
#import "../../common/spell_effects.s"
#import "../../common/spell_data.s"
#import "../../common/player_magic_state.s"
#import "../../common/player_magic_state_ops.s"
#import "../../common/player_magic.s"
#import "../../common/player_magic_feedback.s"
#import "../dungeon_render.s"
#import "../../common/dungeon_los.s"
#import "../../common/player_move.s"
#import "../../common/combat.s"
#import "../../common/monster_attack.s"
#import "../../common/turn.s"
#import "../../common/item_actions_overlay.s"
#import "../../common/ui_trampoline_stubs.s"

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

tpm_spell_exec_calls: .byte 0
tpm_huff_calls:   .byte 0
tpm_last_huff_id: .byte 0
tpm_cast_loop_ctr: .byte 0
tpm_key_idx: .byte 0
tpm_msg_seen: .byte 0
tpm_key_script:
    .byte $3f, $1b
tpm_key_script_stop:
    .byte $3f, $03

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_input_get_key_qmark_then_esc:
    ldx tpm_key_idx
    lda tpm_key_script,x
    inc tpm_key_idx
    rts

test_input_get_key_qmark_then_stop:
    ldx tpm_key_idx
    lda tpm_key_script_stop,x
    inc tpm_key_idx
    rts

test_input_get_modal_spell_a:
test_input_get_key_a:
    lda #$41
    rts

test_input_get_key_b:
    lda #$42
    rts

test_input_get_modal_spell_esc:
    lda #$1b
    rts

test_tramp_spell_execute_selected:
    inc tpm_spell_exec_calls
    rts

test_huff_print_msg:
    stx tpm_last_huff_id
    inc tpm_huff_calls
    rts

test_msg_print_capture:
    :BankOutKernal()
    ldy #0
!copy:
    lda (zp_ptr0),y
    sta tpm_msg_buf,y
    cmp #0
    beq !done+
    iny
    cpy #42
    bcc !copy-
!done:
    :BankInKernal()
    lda #1
    sta tpm_msg_seen
    rts

test_cmb_term_and_print_capture:
    :BankOutKernal()
    ldx cmb_buf_idx
    lda #0
    sta combat_msg_buf,x
    ldx #0
!copy:
    lda combat_msg_buf,x
    sta tpm_msg_buf,x
    cmp #0
    beq !done+
    inx
    cpx #42
    bcc !copy-
!done:
    :BankInKernal()
    lda #1
    sta tpm_msg_seen
    rts

test_pm_select_book:
    lda #0
    sta pm_book_idx
    lda #<book_mask_0
    sta pm_book_mask_lo
    lda #>book_mask_0
    sta pm_book_mask_hi
    sec
    rts

test_pm_pick_visible_spell:
    lda #0
    sta pm_spell_idx
    sec
    rts

test_pm_pick_visible_spell_b:
    lda #1
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell:
    sec
    rts

test_calc_spell_failure_success:
    clc
    rts

test_calc_spell_failure_fail:
    sec
    rts

test_start:
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
    sta zp_eff_poison
    sta zp_eff_blind
    sta zp_eff_confuse
    sta zp_eff_paralyze
    sta zp_eff_regen
    sta zp_game_flags

!t15:
    lda #8
    sta $c6
    lda #$20
    sta $0277
    sta $0278
    sta $0279
    sta $027a
    sta $027b
    sta $027c
    sta $027d
    sta $027e

    lda #0
    sta zp_game_flags

    lda #SPELL_MAGE
    sta pm_spell_type
    lda #<mage_spell_fail
    sta pm_fail_tbl_lo
    lda #>mage_spell_fail
    sta pm_fail_tbl_hi
    lda #<mage_spell_level
    sta pm_lvl_tbl_lo
    lda #>mage_spell_level
    sta pm_lvl_tbl_hi
    lda #0
    sta pm_spell_idx

    lda #10
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_INT_CUR

    lda #HUNGER_FAINT
    sta zp_hunger_state

    jsr calc_spell_failure

    lda pm_fail_work
    cmp #25
    bcc !t15_fail+
    lda #$01
    sta tc_results + 14
    jmp !t16+
!t15_fail:
    lda #$00
    sta tc_results + 14

!t16:
    lda #0
    sta pm_spell_idx
    lda #10
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_INT_CUR

    lda #HUNGER_FULL
    sta zp_hunger_state

    jsr calc_spell_failure

    lda pm_fail_work
    cmp #5
    bne !t16_fail+
    lda #$01
    sta tc_results + 15
    jmp !t17+
!t16_fail:
    lda #$00
    sta tc_results + 15

!t17:
    lda #$07
    sta player_data + PL_SPELLS_KNOWN
    lda #$01
    sta player_data + PL_SPELLS_KNOWN_HI

    jsr count_spells_known

    cmp #4
    bne !t17_fail+
    lda #$01
    sta tc_results + 16
    jmp !t18+
!t17_fail:
    lda #$00
    sta tc_results + 16

!t18:
    lda #5
    sta zp_eff_blind

    jsr item_read_scroll

    bcs !t18_fail+
    lda #$01
    sta tc_results + 17
    jmp !t19+
!t18_fail:
    lda #$00
    sta tc_results + 17

!t19:
    lda #0
    sta zp_game_flags
    sta zp_eff_blind
    sta zp_eff_confuse

    lda #SPELL_MAGE
    sta pm_spell_type
    sta player_data + PL_SPELL_TYPE
    lda #0
    sta pm_spell_idx

    lda #<mage_spell_mana
    sta pm_mana_tbl_lo
    lda #>mage_spell_mana
    sta pm_mana_tbl_hi
    lda #<mage_spell_level
    sta pm_lvl_tbl_lo
    lda #>mage_spell_level
    sta pm_lvl_tbl_hi
    lda #<mage_spell_fail
    sta pm_fail_tbl_lo
    lda #>mage_spell_fail
    sta pm_fail_tbl_hi
    lda #<mage_spell_name_lo
    sta pm_name_lo_lo
    lda #>mage_spell_name_lo
    sta pm_name_lo_hi
    lda #<mage_spell_name_hi
    sta pm_name_hi_lo
    lda #>mage_spell_name_hi
    sta pm_name_hi_hi

    lda #50
    sta zp_player_mp
    sta player_data + PL_MANA
    lda #50
    sta zp_player_mmp
    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #10
    sta zp_eff_confuse
    lda #18
    sta player_data + PL_INT_CUR

    lda #200
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI

    jsr pm_validate_selected_spell
    bcc !t19_fail+
    jsr pm_consume_mana

    lda zp_player_mp
    cmp #50
    bcs !t19_fail+
    lda #$01
    sta tc_results + 18
    jmp !t33+
!t19_fail:
    lda #$00
    sta tc_results + 18

!t33:
    jsr player_init
    lda #CLASS_MAGE
    sta player_data + PL_CLASS
    lda #SPELL_MAGE
    sta player_data + PL_SPELL_TYPE
    lda #SPELL_MAGE
    sta pm_spell_type
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL

    lda #<book_mask_0
    sta pm_book_mask_lo
    lda #>book_mask_0
    sta pm_book_mask_hi

    lda #0
    sta player_data + PL_SPELLS_LEARNT_0
    sta player_data + PL_SPELLS_LEARNT_1
    sta player_data + PL_SPELLS_LEARNT_2
    sta player_data + PL_SPELLS_LEARNT_3

    jsr pm_setup_active_tables
    jsr pm_build_learnable_list_from_book

    lda pm_spell_count
    cmp #7
    bne !t33_fail+
    lda pm_spell_list + 0
    cmp #0
    bne !t33_fail+
    lda pm_spell_list + 6
    cmp #6
    bne !t33_fail+
    lda #$01
    sta tc_results + 32
    jmp !t34+
!t33_fail:
    lda #$00
    sta tc_results + 32

!t34:
    :PatchJump(huff_print_msg, test_huff_print_msg)

    jsr player_init
    lda #CLASS_MAGE
    sta player_data + PL_CLASS
    lda #SPELL_MAGE
    sta player_data + PL_SPELL_TYPE
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_INT_CUR
    lda #20
    sta zp_player_mp
    sta player_data + PL_MANA
    sta zp_player_mmp
    sta player_data + PL_MAX_MANA
    lda #1
    sta player_data + PL_SPELLS_LEARNT_0
    lda #0
    sta player_data + PL_SPELLS_LEARNT_1
    sta player_data + PL_SPELLS_LEARNT_2
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3
    lda #0
    sta pm_spell_idx
    lda #1
    sta pm_spell_count

    lda #16
    sta tpm_cast_loop_ctr
!t34_cast_loop:
    lda #1
    sta pm_cost_tmp
    jsr pm_consume_mana
    jsr pm_mark_worked
    dec tpm_cast_loop_ctr
    lda tpm_cast_loop_ctr
    bne !t34_cast_loop-

    lda zp_player_mp
    cmp #4
    bne !t34_fail+
    lda player_data + PL_MANA
    cmp #4
    bne !t34_fail+
    lda pm_spell_idx
    cmp #0
    bne !t34_fail+
    lda pm_spell_count
    cmp #1
    bne !t34_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$01
    cmp #$01
    bne !t34_fail+
    lda #$01
    sta tc_results + 33
    jmp !t35+
!t34_fail:
    lda #$00
    sta tc_results + 33

!t35:
    jsr player_init
    lda #CLASS_ROGUE
    sta player_data + PL_CLASS
    lda #SPELL_MAGE
    sta player_data + PL_SPELL_TYPE
    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #0
    sta inv_item_id + 0
    sta tpm_huff_calls
    sta tpm_last_huff_id
    jsr player_cast_spell
    bcs !t35_fail+
    lda tpm_huff_calls
    beq !t35_fail+
    lda tpm_last_huff_id
    cmp #HSTR_PM_NO_EXP
    bne !t35_fail+
    lda #$01
    sta tc_results + 34
    jmp !t36+
!t35_fail:
    lda #$00
    sta tc_results + 34

!t36:
    jsr player_init
    lda #CLASS_RANGER
    sta player_data + PL_CLASS
    lda #SPELL_MAGE
    sta player_data + PL_SPELL_TYPE
    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #0
    sta inv_item_id + 0
    sta tpm_huff_calls
    sta tpm_last_huff_id
    jsr player_cast_spell
    bcs !t36_fail+
    lda tpm_huff_calls
    beq !t36_fail+
    lda tpm_last_huff_id
    cmp #HSTR_PM_NO_EXP
    bne !t36_fail+
    lda #$01
    sta tc_results + 35
    jmp !t37+
!t36_fail:
    lda #$00
    sta tc_results + 35

!t37:
    :PatchJump(input_get_key, test_input_get_key_a)
    :PatchJump(input_get_modal_dismiss_key, test_input_get_modal_spell_a)
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(test_spell_execute_selected, test_tramp_spell_execute_selected)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_pick_visible_spell, test_pm_pick_visible_spell)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)

    jsr player_init
    lda #CLASS_MAGE
    sta player_data + PL_CLASS
    lda #SPELL_MAGE
    sta player_data + PL_SPELL_TYPE
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_INT_CUR
    lda #20
    sta zp_player_mp
    sta player_data + PL_MANA
    sta zp_player_mmp
    sta player_data + PL_MAX_MANA
    lda #1
    sta player_data + PL_SPELLS_LEARNT_0
    lda #0
    sta player_data + PL_SPELLS_LEARNT_1
    sta player_data + PL_SPELLS_LEARNT_2
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3
    sta tpm_spell_exec_calls
    sta tpm_huff_calls
    sta tpm_last_huff_id
    lda #8
    sta tpm_cast_loop_ctr
!t37_cast_loop:
    jsr player_cast_spell
    bcc !t37_fail+
    dec tpm_cast_loop_ctr
    bne !t37_cast_loop-

    lda tpm_spell_exec_calls
    cmp #8
    bne !t37_fail+
    lda zp_player_mp
    cmp #12
    bne !t37_fail+
    lda player_data + PL_MANA
    cmp #12
    bne !t37_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$01
    cmp #$01
    bne !t37_fail+
    lda #$01
    sta tc_results + 36
    jmp !t38+
!t37_fail:
    lda #$00
    sta tc_results + 36

!t38:
    :PatchJump(huff_print_msg, test_huff_print_msg)
    jsr player_init
    lda #CLASS_MAGE
    sta player_data + PL_CLASS
    lda #SPELL_MAGE
    sta player_data + PL_SPELL_TYPE
    lda #0
    sta tpm_huff_calls
    sta tpm_last_huff_id
    jsr player_pray
    bcs !t38_fail+
    lda tpm_huff_calls
    beq !t38_fail+
    lda tpm_last_huff_id
    cmp #HSTR_PM_NO_PRAY
    bne !t38_fail+
    lda #$01
    sta tc_results + 37
    jmp !t39+
!t38_fail:
    lda #$00
    sta tc_results + 37

!t39:
    :PatchJump(huff_print_msg, test_huff_print_msg)
    jsr player_init
    lda #CLASS_PRIEST
    sta player_data + PL_CLASS
    lda #SPELL_PRIEST
    sta player_data + PL_SPELL_TYPE
    lda #0
    sta tpm_huff_calls
    sta tpm_last_huff_id
    jsr player_cast_spell
    bcs !t39_fail+
    lda tpm_huff_calls
    beq !t39_fail+
    lda tpm_last_huff_id
    cmp #HSTR_PM_NO_CAST
    bne !t39_fail+
    lda #$01
    sta tc_results + 38
    jmp !t40+
!t39_fail:
    lda #$00
    sta tc_results + 38

!t40:
    lda #0
    sta pm_mode
    lda #SPELL_MAGE
    sta pm_spell_type
    jsr pm_book_prompt_huff_id
    cpx #HSTR_PM_BOOK_CAST
    bne !t40_fail+

    lda #0
    sta pm_mode
    lda #SPELL_PRIEST
    sta pm_spell_type
    jsr pm_book_prompt_huff_id
    cpx #HSTR_PM_BOOK_PRAY
    bne !t40_fail+

    lda #1
    sta pm_mode
    lda #SPELL_PRIEST
    sta pm_spell_type
    jsr pm_book_prompt_huff_id
    cpx #HSTR_IGS_PROMPT
    bne !t40_fail+

    lda #$01
    sta tc_results + 39
    jmp !t42+
!t40_fail:
    lda #$00
    sta tc_results + 39
    jmp !t42+

!t42:
    :PatchJump(huff_print_msg, test_huff_print_msg)

    lda #0
    sta tpm_huff_calls
    sta tpm_last_huff_id
    sta tpm_msg_seen

    lda #10
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda #20
    sta zp_player_mhp_lo
    lda #0
    sta zp_player_mhp_hi

    lda #4
    jsr pmx_heal_and_report

    lda zp_player_hp_lo
    cmp #14
    bne !t42_fail+
    lda tpm_huff_calls
    cmp #1
    bne !t42_fail+
    lda tpm_last_huff_id
    cmp #HSTR_PIQ_LITTLE_BETTER
    bne !t42_fail+
    lda #$01
    sta tc_results + 41
    jmp !t43+
!t42_fail:
    lda #$00
    sta tc_results + 41

!t43:
    lda #0
    sta tpm_huff_calls
    sta tpm_last_huff_id
    sta tpm_msg_seen

    lda #10
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda #40
    sta zp_player_mhp_lo
    lda #0
    sta zp_player_mhp_hi

    lda #10
    jsr pmx_heal_and_report

    lda zp_player_hp_lo
    cmp #20
    bne !t43_fail+
    lda tpm_huff_calls
    cmp #1
    bne !t43_fail+
    lda tpm_last_huff_id
    cmp #HSTR_EFF_POISON_END
    bne !t43_fail+
    lda #$01
    sta tc_results + 42
    jmp !t44+
!t43_fail:
    lda #$00
    sta tc_results + 42

!t44:
    lda #0
    sta tpm_huff_calls
    sta tpm_last_huff_id
    sta tpm_msg_seen

    lda #10
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda #40
    sta zp_player_mhp_lo
    lda #0
    sta zp_player_mhp_hi

    lda #20
    jsr pmx_heal_and_report

    lda zp_player_hp_lo
    cmp #30
    bne !t44_fail+
    lda tpm_huff_calls
    cmp #1
    bne !t44_fail+
    lda tpm_last_huff_id
    cmp #HSTR_PIQ_MUCH_BETTER
    bne !t44_fail+
    lda #$01
    sta tc_results + 43
    jmp !t45+
!t44_fail:
    lda #$00
    sta tc_results + 43

!t45:
    lda #0
    sta tpm_huff_calls
    sta tpm_last_huff_id
    sta tpm_msg_seen

    lda #5
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda #40
    sta zp_player_mhp_lo
    lda #0
    sta zp_player_mhp_hi

    lda #200
    jsr pmx_heal_and_report

    lda zp_player_hp_lo
    cmp #40
    bne !t45_fail+
    lda tpm_huff_calls
    cmp #1
    bne !t45_fail+
    lda tpm_last_huff_id
    cmp #HSTR_PIQ_VERY_GOOD
    bne !t45_fail+
    lda #$01
    sta tc_results + 44
    jmp !t46+
!t45_fail:
    lda #$00
    sta tc_results + 44

!t46:
    lda #0
    sta tpm_huff_calls
    sta tpm_last_huff_id
    sta tpm_msg_seen

    lda #20
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda #20
    sta zp_player_mhp_lo
    lda #0
    sta zp_player_mhp_hi

    lda #4
    jsr pmx_heal_and_report

    lda zp_player_hp_lo
    cmp #20
    bne !t46_fail+
    lda tpm_huff_calls
    bne !t46_fail+
    lda tpm_msg_seen
    bne !t46_fail+
    lda #$01
    sta tc_results + 45
    jmp !t47+
!t46_fail:
    lda #$00
    sta tc_results + 45

!t47:
    :PatchJump(input_get_key, test_input_get_key_qmark_then_esc)
    :PatchJump(input_get_modal_dismiss_key, test_input_get_modal_spell_esc)
    lda #0
    sta tpm_key_idx

    lda #SPELL_MAGE
    sta pm_spell_type
    lda #0
    sta pm_mode
    lda #1
    sta pm_spell_count
    lda #0
    sta pm_spell_list
    lda #$ff
    sta pm_spell_idx

    jsr pm_prompt_visible_spell_choice
    bcs !t47_fail+
    lda pm_spell_idx
    cmp #$ff
    bne !t47_fail+
    lda #$01
    sta tc_results + 46
    jmp !t48+
!t47_fail:
    lda #$00
    sta tc_results + 46

!t48:
    :PatchJump(input_get_key, test_input_get_key_qmark_then_stop)
    :PatchJump(input_get_modal_dismiss_key, test_input_get_modal_spell_esc)
    lda #0
    sta tpm_key_idx

    lda #SPELL_MAGE
    sta pm_spell_type
    lda #0
    sta pm_mode
    lda #1
    sta pm_spell_count
    lda #0
    sta pm_spell_list
    lda #$ff
    sta pm_spell_idx

    jsr pm_prompt_visible_spell_choice
    bcs !t48_fail+
    lda pm_spell_idx
    cmp #$ff
    bne !t48_fail+
    lda #$01
    sta tc_results + 47
    jmp !t49+
!t48_fail:
    lda #$00
    sta tc_results + 47

!t49:
    :PatchJump(input_get_key, test_input_get_key_a)
    :PatchJump(cmb_term_and_print, test_cmb_term_and_print_capture)
    jsr item_init_inventory

    lda #0
    sta tpm_msg_seen
    sta id_known + 25

    lda #25
    sta inv_item_id + 1
    lda #1
    sta inv_qty + 1
    lda #0
    sta inv_p1 + 1
    sta inv_flags + 1
    sta inv_ego + 1

    jsr eff_identify_prompt

    lda id_known + 25
    cmp #1
    bne !t49_fail+
    lda inv_flags + 1
    and #IF_IDENTIFIED
    beq !t49_fail+
    lda tpm_msg_seen
    cmp #1
    bne !t49_fail+

    lda #<tpm_expected_identify_csw
    sta zp_ptr0
    lda #>tpm_expected_identify_csw
    sta zp_ptr0_hi
    lda #<tpm_msg_buf
    sta zp_ptr1
    lda #>tpm_msg_buf
    sta zp_ptr1_hi
    :BankOutKernal()
    ldy #0
!t48_cmp:
    lda (zp_ptr0),y
    cmp (zp_ptr1),y
    bne !t49_fail+
    cmp #0
    beq !t49_pass+
    iny
    cpy #42
    bcc !t48_cmp-
    bcs !t49_fail+
!t49_pass:
    :BankInKernal()
    lda #$01
    sta tc_results + 48
    jmp !t50+
!t49_fail:
    :BankInKernal()
    lda #$00
    sta tc_results + 48

!t50:
    :PatchJump(input_get_key, test_input_get_key_b)
    jsr item_init_inventory

    lda #0
    sta id_known + 17
    sta id_known + 25

    lda #17
    sta inv_item_id + 1
    lda #1
    sta inv_qty + 1
    lda #0
    sta inv_p1 + 1
    sta inv_flags + 1

    lda #25
    sta inv_item_id + 4
    lda #1
    sta inv_qty + 4
    lda #0
    sta inv_p1 + 4
    sta inv_flags + 4

    jsr eff_identify_prompt

    lda id_known + 17
    bne !t50_fail+
    lda id_known + 25
    cmp #1
    bne !t50_fail+
    lda inv_flags + 4
    and #IF_IDENTIFIED
    beq !t50_fail+
    lda #$01
    sta tc_results + 49
    jmp !t51+
!t50_fail:
    lda #$00
    sta tc_results + 49

!t51:
    :PatchJump(input_get_key, test_input_get_key_a)
    :PatchJump(input_get_modal_dismiss_key, test_input_get_modal_spell_a)
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(test_spell_execute_selected, test_tramp_spell_execute_selected)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_pick_visible_spell, test_pm_pick_visible_spell)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)

    jsr player_init
    lda #CLASS_MAGE
    sta player_data + PL_CLASS
    lda #SPELL_MAGE
    sta player_data + PL_SPELL_TYPE
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_INT_CUR
    lda #20
    sta zp_player_mp
    sta player_data + PL_MANA
    sta zp_player_mmp
    sta player_data + PL_MAX_MANA
    lda #1
    sta player_data + PL_SPELLS_LEARNT_0
    lda #0
    sta player_data + PL_SPELLS_LEARNT_1
    sta player_data + PL_SPELLS_LEARNT_2
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3
    sta tpm_spell_exec_calls
    sta tpm_huff_calls
    sta tpm_last_huff_id

    jsr player_cast_spell
    bcc !t51_fail+
    lda tpm_spell_exec_calls
    bne !t51_fail+
    lda tpm_huff_calls
    cmp #1
    bne !t51_fail+
    lda tpm_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t51_fail+
    lda zp_player_mp
    cmp #19
    bne !t51_fail+
    lda player_data + PL_MANA
    cmp #19
    bne !t51_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$01
    bne !t51_fail+
    lda #$01
    sta tc_results + 50
    jmp !t52+
!t51_fail:
    lda #$00
    sta tc_results + 50

!t52:
    :PatchJump(input_get_key, test_input_get_key_b)
    :PatchJump(input_get_modal_dismiss_key, test_input_get_modal_spell_a)
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(test_spell_execute_selected, test_tramp_spell_execute_selected)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_pick_visible_spell, test_pm_pick_visible_spell_b)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)

    jsr player_init
    lda #CLASS_MAGE
    sta player_data + PL_CLASS
    lda #SPELL_MAGE
    sta player_data + PL_SPELL_TYPE
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_INT_CUR
    lda #20
    sta zp_player_mp
    sta player_data + PL_MANA
    sta zp_player_mmp
    sta player_data + PL_MAX_MANA
    lda #$02
    sta player_data + PL_SPELLS_LEARNT_0
    lda #0
    sta player_data + PL_SPELLS_LEARNT_1
    sta player_data + PL_SPELLS_LEARNT_2
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3
    sta tpm_spell_exec_calls
    sta tpm_huff_calls
    sta tpm_last_huff_id

    jsr player_cast_spell
    bcc !t52_fail+
    lda tpm_spell_exec_calls
    bne !t52_fail+
    lda tpm_huff_calls
    cmp #1
    bne !t52_fail+
    lda tpm_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t52_fail+
    lda zp_player_mp
    cmp #19
    bne !t52_fail+
    lda player_data + PL_MANA
    cmp #19
    bne !t52_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$02
    bne !t52_fail+
    lda #$01
    sta tc_results + 51
    jmp !tests_done+
!t52_fail:
    lda #$00
    sta tc_results + 51

!tests_done:
    jmp test_finish

effects_magic_test_body_end:

.assert "Effects magic test stays below MAP_BASE", effects_magic_test_body_end <= MAP_BASE, true
.assert "Effects magic result buffer stays under KERNAL ROM", tc_results + 52 <= $10000, true
