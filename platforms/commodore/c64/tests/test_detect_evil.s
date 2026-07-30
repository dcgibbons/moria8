// test_detect_evil.s — Focused runtime tests for the Detect Evil prayer row

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tc_results: .fill 4, $ff

.pc = $080E "Test Code"

.encoding "screencode_mixed"

test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    :BankOutKernal()
    ldx #3
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
#import "../../../../core/projectile.s"
#import "../../../../core/spell_effects.s"
#import "../../../../core/spell_data.s"
#import "../../../../core/player_magic_state.s"
#import "../../../../core/player_magic_state_ops.s"
#import "../../../../core/player_magic.s"
#define PMX_DETECT_EFFECTS_EXTERNAL
#import "../../../../core/player_magic_detect.s"
#undef PMX_DETECT_EFFECTS_EXTERNAL
#import "../dungeon_render.s"
#import "../../../../core/dungeon_los.s"
#import "../../../../core/player_move.s"
#import "../../../../core/combat.s"
#import "../../../../core/scene_mat_tile.s"
#import "../../../../core/monster_attack.s"
#import "../../../../core/turn.s"
#import "../../../../core/ui_trampoline_stubs.s"

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

tde_spell_exec_calls: .byte 0
tde_huff_calls: .byte 0
tde_last_huff_id: .byte 0
tde_msg_calls: .byte 0
tde_last_msg_lo: .byte 0
tde_last_msg_hi: .byte 0
tde_last_spell_idx: .byte $ff

test_mon_table:
    .fill MAX_MONSTERS * MONSTER_ENTRY_SIZE, 0

test_mon_ptr_lo:
    .fill MAX_MONSTERS, <(test_mon_table + i * MONSTER_ENTRY_SIZE)
test_mon_ptr_hi:
    .fill MAX_MONSTERS, >(test_mon_table + i * MONSTER_ENTRY_SIZE)

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx tde_last_huff_id
    inc tde_huff_calls
    rts

test_msg_print_capture:
    inc tde_msg_calls
    lda zp_ptr0
    sta tde_last_msg_lo
    lda zp_ptr0_hi
    sta tde_last_msg_hi
    rts

test_monster_get_ptr:
    lda test_mon_ptr_lo,x
    sta zp_ptr0
    lda test_mon_ptr_hi,x
    sta zp_ptr0_hi
    rts

test_tramp_detect_evil_execute:
    inc tde_spell_exec_calls
    lda pm_spell_idx
    sta tde_last_spell_idx
    jsr pmx_detect_evil_msg
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

test_pm_prompt_visible_spell_choice:
    lda #0
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell:
    lda #1
    sta pm_cost_tmp
    sec
    rts

test_calc_spell_failure_success:
    clc
    rts

test_calc_spell_failure_fail:
    sec
    rts

test_clear_monsters:
    ldx #MAX_MONSTERS * MONSTER_ENTRY_SIZE - 1
    lda #0
!clear_loop:
    sta test_mon_table,x
    dex
    bpl !clear_loop-

    ldx #0
    lda #EMPTY_SLOT
!empty_loop:
    sta test_mon_table + MX_TYPE,x
    txa
    clc
    adc #MONSTER_ENTRY_SIZE
    tax
    cpx #MAX_MONSTERS * MONSTER_ENTRY_SIZE
    bcc !empty_loop-

    ldx #64
    lda #0
!clear_flags:
    sta cr_mflags,x
    dex
    bpl !clear_flags-
    rts

test_reset_detect_evil_prayer_state:
    jsr player_init
    lda #0
    sta tde_spell_exec_calls
    sta tde_huff_calls
    sta tde_last_huff_id
    sta tde_msg_calls
    sta tde_last_msg_lo
    sta tde_last_msg_hi
    sta eff_detect_timer
    sta eff_detect_evil_mode
    sta vis_room_revealed
    lda #$ff
    sta tde_last_spell_idx

    lda #CLASS_PRIEST
    sta player_data + PL_CLASS
    lda #SPELL_PRIEST
    sta pm_spell_type
    sta player_data + PL_SPELL_TYPE
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_WIS_CUR
    lda #20
    sta zp_player_mp
    sta player_data + PL_MANA
    sta zp_player_mmp
    sta player_data + PL_MAX_MANA

    lda #$01
    sta player_data + PL_SPELLS_LEARNT_0
    lda #0
    sta player_data + PL_SPELLS_LEARNT_1
    sta player_data + PL_SPELLS_LEARNT_2
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3
    rts

test_start:
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(msg_print, test_msg_print_capture)
    :PatchJump(test_spell_execute_selected, test_tramp_detect_evil_execute)
    :PatchJump(monster_get_ptr, test_monster_get_ptr)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)

    // Test 1: Detect Evil with no evil monsters reports none, leaves detect
    // timer state clear, spends mana, and marks the prayer worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_clear_monsters
    jsr test_reset_detect_evil_prayer_state
    lda #0
    sta test_mon_table + MX_TYPE
    jsr player_pray
    bcc !t1_fail+
    lda tde_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda tde_last_spell_idx
    cmp #0
    bne !t1_fail+
    lda tde_msg_calls
    cmp #1
    bne !t1_fail+
    lda tde_last_msg_lo
    cmp #<pmx_msg_no_evil
    bne !t1_fail+
    lda tde_last_msg_hi
    cmp #>pmx_msg_no_evil
    bne !t1_fail+
    lda tde_huff_calls
    bne !t1_fail+
    lda eff_detect_timer
    bne !t1_fail+
    lda vis_room_revealed
    bne !t1_fail+
    lda zp_player_mp
    cmp #19
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #19
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$01
    beq !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // Test 2: Detect Evil with an evil monster in the current panel reports
    // presence of evil and marks that monster for the one-shot reveal without
    // permanently revealing the terrain.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_clear_monsters
    jsr test_reset_detect_evil_prayer_state
    lda #1
    sta test_mon_table + MX_TYPE
    lda #20
    sta test_mon_table + MX_X
    lda #12
    sta test_mon_table + MX_Y
    lda #CF_EVIL
    sta cr_mflags + 1
    lda #0
    sta zp_view_x
    sta zp_view_y
    jsr player_pray
    bcs !t2_cast_ok+
    jmp !t2_fail+
!t2_cast_ok:
    jmp !t2_checks+
!t2_fail_jmp:
    jmp !t2_fail+
!t2_checks:
    lda tde_spell_exec_calls
    cmp #1
    bne !t2_fail_jmp-
    lda tde_last_spell_idx
    cmp #0
    bne !t2_fail_jmp-
    lda tde_msg_calls
    cmp #1
    bne !t2_fail_jmp-
    lda tde_last_msg_lo
    cmp #<pmx_msg_evil_on
    bne !t2_fail_jmp-
    lda tde_last_msg_hi
    cmp #>pmx_msg_evil_on
    bne !t2_fail_jmp-
    lda test_mon_table + MX_FLAGS
    and #MF_DETECTED
    beq !t2_fail_jmp-
    lda eff_detect_timer
    bne !t2_fail_jmp-
    lda eff_detect_evil_mode
    cmp #1
    bne !t2_fail_jmp-
    jsr detect_evil_clear_reveal
    lda eff_detect_evil_mode
    bne !t2_fail+
    lda test_mon_table + MX_FLAGS
    and #MF_DETECTED
    bne !t2_fail+
    lda vis_room_revealed
    cmp #1
    beq !t2_reveal_ok+
    jmp !t2_fail+
!t2_reveal_ok:
    ldx #12
    lda map_row_lo,x
    sta zp_ptr1
    lda map_row_hi,x
    sta zp_ptr1_hi
    ldy #20
    :MapRead_ptr1_y()
    and #(FLAG_VISITED | FLAG_LIT)
    bne !t2_fail+
    lda zp_player_mp
    cmp #19
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #19
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$01
    beq !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // Test 3: Detect Evil preserves active Detect Monsters. Its one-shot
    // reveal clears after redraw, then timed detect owns MF_DETECTED again.
!t3:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_clear_monsters
    jsr test_reset_detect_evil_prayer_state
    lda #1
    sta test_mon_table + MX_TYPE
    lda #10
    sta test_mon_table + MX_X
    sta test_mon_table + MX_Y
    lda #MF_DETECTED
    sta test_mon_table + MX_FLAGS
    lda #2
    sta test_mon_table + MONSTER_ENTRY_SIZE + MX_TYPE
    lda #11
    sta test_mon_table + MONSTER_ENTRY_SIZE + MX_X
    sta test_mon_table + MONSTER_ENTRY_SIZE + MX_Y
    lda #MF_DETECTED
    sta test_mon_table + MONSTER_ENTRY_SIZE + MX_FLAGS
    lda #CF_EVIL
    sta cr_mflags + 2
    lda #DETECT_TIMER_TURNS
    sta eff_detect_timer
    lda #0
    sta zp_view_x
    sta zp_view_y
    jsr player_pray
    bcc tde_t3_fail
    lda eff_detect_timer
    cmp #DETECT_TIMER_TURNS
    bne tde_t3_fail
    lda eff_detect_evil_mode
    cmp #1
    bne tde_t3_fail
    jsr detect_evil_clear_reveal
    lda eff_detect_timer
    cmp #DETECT_TIMER_TURNS
    bne tde_t3_fail
    lda eff_detect_evil_mode
    bne tde_t3_fail
    lda test_mon_table + MX_FLAGS
    and #MF_DETECTED
    beq tde_t3_fail
    lda test_mon_table + MONSTER_ENTRY_SIZE + MX_FLAGS
    and #MF_DETECTED
    beq tde_t3_fail
    lda #$01
    sta tc_results + 2
    jmp !t4+
tde_t3_fail:
    lda #$00
    sta tc_results + 2

    // Test 4: cast failure spends mana, prints HSTR_PM_FAIL, does not execute,
    // and leaves Detect Evil unworked.
!t4:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_clear_monsters
    jsr test_reset_detect_evil_prayer_state
    lda #1
    sta test_mon_table + MX_TYPE
    lda #CF_EVIL
    sta cr_mflags + 1
    jsr player_pray
    bcc !t4_fail+
    lda tde_huff_calls
    cmp #1
    bne !t4_fail+
    lda tde_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t4_fail+
    lda tde_spell_exec_calls
    bne !t4_fail+
    lda tde_msg_calls
    bne !t4_fail+
    lda eff_detect_timer
    bne !t4_fail+
    lda eff_detect_evil_mode
    bne !t4_fail+
    lda vis_room_revealed
    bne !t4_fail+
    lda zp_player_mp
    cmp #19
    bne !t4_fail+
    lda player_data + PL_MANA
    cmp #19
    bne !t4_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$01
    bne !t4_fail+
    lda #$01
    sta tc_results + 3
    jmp test_finish
!t4_fail:
    lda #$00
    sta tc_results + 3
    jmp test_finish
