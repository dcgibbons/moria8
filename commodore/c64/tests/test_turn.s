// test_turn.s — Orchestration coverage for common/turn.s

.pc = $0801 "BASIC Stub"
:BasicUpstart2(bootstrap)

.pc = $080E "Bootstrap"

.encoding "screencode_mixed"

bootstrap:
    jmp test_start

.pc = $0830 "Test Code"

#import "../../common/zeropage.s"
#import "../../common/tables.s"
#import "../../common/item_defs.s"
#import "../../common/math.s"

.const FLAG_OCCUPIED       = $01
.const FLAG_VISITED        = $04
.const FLAG_LIT            = $08
.const PL_HP_LO            = 33
.const PL_HP_HI            = 34
.const PL_MHP_LO           = 35
.const PL_MHP_HI           = 36
.const PL_MANA             = 37
.const PL_CON_CUR          = 31
.const PL_DLEVEL           = 20
.const PL_LIGHT_RAD        = 55
.const PL_MAX_DLVL         = 56
.const PL_RESERVED         = 64
.const PL_SPELL_TYPE       = 60
eff_detect_timer:    .byte 0

.macro MapRead_ptr0_y() {
    lda (zp_ptr0),y
}

.macro MapWrite_ptr0_y() {
    sta (zp_ptr0),y
}

.const HSTR_EFF_POISON_END   = 40
.const HSTR_EFF_BLIND_END    = 41
.const HSTR_EFF_CONFUSE_END  = 42
.const HSTR_EFF_PARALYZE_END = 43
.const HSTR_EFF_FEAR_END     = 44
.const HSTR_TTL_DIM          = 45
.const HSTR_TTL_OUT          = 46
.const HSTR_RECALL_ARRIVE    = 47
.const HSTR_PID_WIELDING     = 178
.const HSTR_PID_BODY         = 179
.const HSTR_PID_ARM          = 180
.const HSTR_PID_HEAD         = 181
.const HSTR_PID_HANDS        = 182
.const HSTR_PID_FEET         = 183
.const HSTR_PID_LIGHT        = 184
.const HSTR_PID_RIGHT        = 185
.const HSTR_PID_PACK         = 186
.const DEATH_POISON  = $FE
.const DEATH_STARVE  = $FF
.const SFX_HUNGER_WARN  = $08
.const SFX_HUNGER_FAINT = $09

player_data:         .fill 80, 0
inv_item_id:         .fill TOTAL_INV_SLOTS, FI_EMPTY
inv_p1:              .fill TOTAL_INV_SLOTS, 0
inv_to_hit:          .fill TOTAL_INV_SLOTS, 0
inv_to_dam:          .fill TOTAL_INV_SLOTS, 0
inv_to_ac:           .fill TOTAL_INV_SLOTS, 0
inv_flags:           .fill TOTAL_INV_SLOTS, 0
inv_ego:             .fill TOTAL_INV_SLOTS, 0
level_entry_dir:     .byte 0
current_tier:        .byte 0
tier_loaded:         .byte 0
vis_room_revealed:   .byte 0
test_map_row:        .fill 80, FLAG_OCCUPIED
map_row_lo:          .fill 48, <test_map_row
map_row_hi:          .fill 48, >test_map_row

tc_results: .fill 23, $ff

test_seq_next: .byte 0
test_seq_effects: .byte 0
test_seq_hunger: .byte 0
test_seq_regen: .byte 0
test_seq_light: .byte 0
test_seq_pseudo: .byte 0
test_seq_status: .byte 0
test_store_restock_calls: .byte 0
test_status_dirty_calls: .byte 0
test_huff_calls: .byte 0
test_last_huff_id: .byte 0
test_msg_calls: .byte 0
test_last_msg_lo: .byte 0
test_last_msg_hi: .byte 0
test_level_generate_calls: .byte 0
test_monster_spawn_calls: .byte 0
test_item_spawn_calls: .byte 0
test_update_visibility_calls: .byte 0
test_screen_clear_calls: .byte 0
test_viewport_update_calls: .byte 0
test_render_viewport_calls: .byte 0
test_status_draw_calls: .byte 0
test_tier_transition_calls: .byte 0
test_tier_invalidate_calls: .byte 0
test_level_change_calls: .byte 0
test_inv_remove_calls: .byte 0
test_monster_ai_calls: .byte 0
test_monster_ai_return_a: .byte 0
test_monster_ai_return_c: .byte 0
test_player_death_calls: .byte 0
test_sound_calls: .byte 0
test_last_sound: .byte $ff
test_rng_result: .byte 0
test_last_rng_bound: .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

monster_ai_tick:
    inc test_monster_ai_calls
    lda test_monster_ai_return_c
    beq !clear+
    lda test_monster_ai_return_a
    sec
    rts
!clear:
    lda test_monster_ai_return_a
    clc
    rts

map_get_tile:
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    txa
    tay
    :MapRead_ptr0_y()
    rts

status_mark_dirty:
    inc test_status_dirty_calls
    lda test_seq_next
    sta test_seq_status
    inc test_seq_next
    rts

tramp_store_restock_all:
    inc test_store_restock_calls
    rts

tier_check_transition:
    inc test_tier_transition_calls
    rts

tier_invalidate_state:
    inc test_tier_invalidate_calls
    lda #0
    sta current_tier
    sta tier_loaded
    rts

level_change_generate_current:
    inc test_level_change_calls
    inc test_tier_transition_calls
    inc test_level_generate_calls
    inc test_monster_spawn_calls
    inc test_item_spawn_calls
    inc test_update_visibility_calls
    inc test_screen_clear_calls
    inc test_viewport_update_calls
    inc test_render_viewport_calls
    inc test_status_draw_calls
    lda #$ff
    sta zp_run_dir
    rts

level_generate:
    inc test_level_generate_calls
    rts

monster_spawn_level:
    inc test_monster_spawn_calls
    rts

item_spawn_level:
    inc test_item_spawn_calls
    rts

update_visibility:
    inc test_update_visibility_calls
    rts

screen_clear:
    inc test_screen_clear_calls
    rts

viewport_update:
    inc test_viewport_update_calls
    rts

render_viewport:
    inc test_render_viewport_calls
    rts

status_draw:
    inc test_status_draw_calls
    rts

huff_print_msg:
    inc test_huff_calls
    stx test_last_huff_id
    rts

msg_print:
    inc test_msg_calls
    lda zp_ptr0
    sta test_last_msg_lo
    lda zp_ptr0_hi
    sta test_last_msg_hi
    rts

player_death_check:
    inc test_player_death_calls
    rts

sound_play:
    inc test_sound_calls
    sta test_last_sound
    rts

rng_range:
    sta test_last_rng_bound
    lda test_rng_result
    rts

inv_remove_item:
    inc test_inv_remove_calls
    lda #FI_EMPTY
    sta inv_item_id,x
    lda #0
    sta inv_p1,x
    rts

#import "../../common/turn.s"

install_turn_patches:
    :PatchJump(turn_tick_effects, test_turn_tick_effects)
    :PatchJump(turn_tick_hunger, test_turn_tick_hunger)
    :PatchJump(turn_tick_regen, test_turn_tick_regen)
    :PatchJump(turn_tick_light, test_turn_tick_light)
    :PatchJump(turn_tick_pseudo_id, test_turn_tick_pseudo_id)
    rts

restore_turn_routines:
    lda #$20
    sta turn_tick_effects
    sta turn_tick_hunger
    sta turn_tick_regen
    sta turn_tick_light
    sta turn_tick_pseudo_id
    rts

reset_state:
    lda #0
    sta test_seq_next
    sta test_seq_effects
    sta test_seq_hunger
    sta test_seq_regen
    sta test_seq_light
    sta test_seq_pseudo
    sta test_seq_status
    sta test_store_restock_calls
    sta test_status_dirty_calls
    sta test_huff_calls
    sta test_last_huff_id
    sta test_msg_calls
    sta test_last_msg_lo
    sta test_last_msg_hi
    sta test_level_generate_calls
    sta test_monster_spawn_calls
    sta test_item_spawn_calls
    sta test_update_visibility_calls
    sta test_screen_clear_calls
    sta test_viewport_update_calls
    sta test_render_viewport_calls
    sta test_status_draw_calls
    sta test_tier_transition_calls
    sta test_tier_invalidate_calls
    sta test_level_change_calls
    sta test_inv_remove_calls
    sta test_monster_ai_calls
    sta test_monster_ai_return_a
    sta test_monster_ai_return_c
    sta test_player_death_calls
    sta test_sound_calls
    sta test_rng_result
    sta test_last_rng_bound
    sta zp_turn_lo
    sta zp_turn_hi
    sta turn_scene_dirty
    sta turn_action_redraw_pending
    sta zp_eff_poison
    sta zp_eff_blind
    sta zp_eff_confuse
    sta zp_eff_paralyze
    sta eff_fear_timer
    sta eff_resist_cold_timer
    sta zp_eff_speed
    sta zp_eff_protect
    sta zp_eff_invis
    sta zp_eff_infra
    sta zp_eff_resist
    sta zp_eff_bless
    sta zp_eff_hero
    sta zp_eff_regen
    sta zp_eff_word_recall
    sta zp_player_mp
    sta player_data + PL_MANA
    sta zp_player_dlvl
    sta player_data + PL_DLEVEL
    sta player_data + PL_MAX_DLVL
    sta level_entry_dir
    sta current_tier
    sta zp_player_x
    sta zp_player_y
    sta vis_room_revealed
    sta light_tick_counter
    sta zp_death_source
    lda #$ff
    sta test_last_sound
    lda #$ff
    sta zp_run_dir
    ldx #TOTAL_INV_SLOTS - 1
!clr_inv:
    lda #FI_EMPTY
    sta inv_item_id,x
    lda #0
    sta inv_p1,x
    sta inv_flags,x
    sta inv_ego,x
    dex
    bpl !clr_inv-
    lda #FLAG_OCCUPIED
    ldx #79
!clr_map:
    sta test_map_row,x
    dex
    bpl !clr_map-
    rts

test_turn_tick_effects:
    lda test_seq_next
    sta test_seq_effects
    inc test_seq_next
    rts

test_turn_tick_hunger:
    lda test_seq_next
    sta test_seq_hunger
    inc test_seq_next
    rts

test_turn_tick_regen:
    lda test_seq_next
    sta test_seq_regen
    inc test_seq_next
    rts

test_turn_tick_light:
    lda test_seq_next
    sta test_seq_light
    inc test_seq_next
    rts

test_turn_tick_pseudo_id:
    lda test_seq_next
    sta test_seq_pseudo
    inc test_seq_next
    rts

test_start:
    sei
    cld
    ldx #$ff
    txs

    ldx #22
    lda #$ff
!init_results:
    sta tc_results,x
    dex
    bpl !init_results-

    // Test 2: poisoned regen suppression leaves HP/counter unchanged.
    jsr reset_state
    lda #1
    sta zp_eff_poison
    lda #5
    sta zp_regen_counter
    lda #8
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #12
    sta zp_player_mhp_lo
    jsr turn_tick_regen
    lda zp_regen_counter
    cmp #5
    bne !t2_fail+
    lda zp_player_hp_lo
    cmp #8
    bne !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp !t2_done+
!t2_fail:
    lda #$00
    sta tc_results + 1
!t2_done:

    // Test 3: starvation damages HP and sets death source.
    jsr reset_state
    lda #0
    sta zp_player_food
    sta zp_player_food_hi
    lda #5
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    jsr turn_tick_hunger
    lda zp_player_hp_lo
    cmp #4
    bne !t3_fail+
    lda zp_death_source
    cmp #DEATH_STARVE
    bne !t3_fail+
    lda zp_hunger_state
    cmp #HUNGER_FAINT
    bne !t3_fail+
    lda test_player_death_calls
    cmp #1
    bne !t3_fail+
    lda #$01
    sta tc_results + 2
    jmp !t3_done+
!t3_fail:
    lda #$00
    sta tc_results + 2
!t3_done:

    // Test 4: light warning/depletion path emits messages and clears slot.
    jsr reset_state
    ldx #EQUIP_LIGHT
    lda #13
    sta inv_item_id,x
    lda #3
    sta inv_p1,x
    lda #1
    sta light_tick_counter
    lda #1
    sta zp_light_radius
    sta player_data + PL_LIGHT_RAD
    jsr turn_tick_light
    lda inv_p1 + EQUIP_LIGHT
    cmp #2
    bne !t4_fail+
    lda test_last_huff_id
    cmp #HSTR_TTL_DIM
    bne !t4_fail+
    lda #1
    sta light_tick_counter
    jsr turn_tick_light
    lda inv_p1 + EQUIP_LIGHT
    cmp #1
    bne !t4_fail+
    lda #1
    sta light_tick_counter
    jsr turn_tick_light
    lda inv_item_id + EQUIP_LIGHT
    cmp #FI_EMPTY
    bne !t4_fail+
    lda zp_light_radius
    bne !t4_fail+
    lda test_inv_remove_calls
    cmp #1
    bne !t4_fail+
    lda test_last_huff_id
    cmp #HSTR_TTL_OUT
    bne !t4_fail+
    lda #$01
    sta tc_results + 3
    jmp !t4_done+
!t4_fail:
    lda #$00
    sta tc_results + 3
!t4_done:

    // Test 5: recall from dungeon returns to town and runs orchestration tail.
    jsr reset_state
    lda #1
    sta zp_eff_word_recall
    lda #5
    sta zp_player_dlvl
    sta player_data + PL_DLEVEL
    lda #7
    sta player_data + PL_MAX_DLVL
    lda #9
    sta zp_player_x
    lda #4
    sta zp_player_y
    lda #2
    sta zp_run_dir
    jsr turn_tick_effects
    lda zp_player_dlvl
    bne !t5_fail+
    lda level_entry_dir
    cmp #1
    bne !t5_fail+
    lda test_store_restock_calls
    cmp #1
    bne !t5_fail+
    lda test_tier_transition_calls
    cmp #1
    bne !t5_fail+
    lda test_tier_invalidate_calls
    cmp #1
    bne !t5_fail+
    lda test_level_change_calls
    cmp #1
    bne !t5_fail+
    lda test_level_generate_calls
    cmp #1
    bne !t5_fail+
    lda test_monster_spawn_calls
    cmp #1
    bne !t5_fail+
    lda test_item_spawn_calls
    cmp #1
    bne !t5_fail+
    lda test_update_visibility_calls
    cmp #1
    bne !t5_fail+
    lda test_screen_clear_calls
    cmp #1
    bne !t5_fail+
    lda test_viewport_update_calls
    cmp #1
    bne !t5_fail+
    lda test_render_viewport_calls
    cmp #1
    bne !t5_fail+
    lda test_status_draw_calls
    cmp #1
    bne !t5_fail+
    lda zp_run_dir
    cmp #$ff
    bne !t5_fail+
    lda test_last_huff_id
    cmp #HSTR_RECALL_ARRIVE
    bne !t5_fail+
    lda test_map_row + 9
    and #FLAG_OCCUPIED
    bne !t5_fail+
    lda #$01
    sta tc_results + 4
    jmp !t5_done+
!t5_fail:
    lda #$00
    sta tc_results + 4
!t5_done:

    // Test 6: recall from town descends to max depth without town restock.
    jsr reset_state
    lda #1
    sta zp_eff_word_recall
    lda #0
    sta zp_player_dlvl
    lda #9
    sta player_data + PL_MAX_DLVL
    jsr turn_tick_effects
    lda zp_player_dlvl
    cmp #9
    bne !t6_fail+
    lda level_entry_dir
    bne !t6_fail+
    lda test_store_restock_calls
    bne !t6_fail+
    lda test_tier_invalidate_calls
    cmp #1
    bne !t6_fail+
    lda test_level_change_calls
    cmp #1
    bne !t6_fail+
    lda test_tier_transition_calls
    cmp #1
    bne !t6_fail+
    lda #$01
    sta tc_results + 5
    jmp !t6_done+
!t6_fail:
    lda #$00
    sta tc_results + 5
!t6_done:

    // Test 7: recall in town with no max depth fizzles cleanly.
    jsr reset_state
    lda #1
    sta zp_eff_word_recall
    lda #0
    sta zp_player_dlvl
    sta player_data + PL_MAX_DLVL
    jsr turn_tick_effects
    lda zp_player_dlvl
    bne !t7_fail+
    lda test_level_generate_calls
    bne !t7_fail+
    lda test_tier_invalidate_calls
    bne !t7_fail+
    lda test_level_change_calls
    bne !t7_fail+
    lda test_tier_transition_calls
    bne !t7_fail+
    lda test_last_huff_id
    bne !t7_fail+
    lda test_map_row
    and #FLAG_OCCUPIED
    beq !t7_fail+
    lda #$01
    sta tc_results + 6
    jmp !t7_done+
!t7_fail:
    lda #$00
    sta tc_results + 6
!t7_done:

    // Test 8: mana regen ticks every other turn for casters.
    jsr reset_state
    lda #1
    sta player_data + PL_SPELL_TYPE
    lda #2
    sta zp_player_mmp
    lda #0
    sta zp_player_mp
    sta zp_turn_lo
    jsr turn_tick_effects
    lda zp_player_mp
    cmp #1
    bne !t8_fail+
    lda #$01
    sta tc_results + 7
    jmp !t9+
!t8_fail:
    lda #$00
    sta tc_results + 7

!t9:
    // Test 9: poison damage clamps at 0 instead of wrapping to $FFFF.
    jsr reset_state
    lda #2
    sta zp_eff_poison
    lda #0
    sta zp_player_hp_lo
    sta zp_player_hp_hi
    sta player_data + PL_HP_LO
    sta player_data + PL_HP_HI
    jsr turn_tick_effects
    lda zp_player_hp_lo
    bne !t9_fail+
    lda zp_player_hp_hi
    bne !t9_fail+
    lda player_data + PL_HP_LO
    bne !t9_fail+
    lda player_data + PL_HP_HI
    bne !t9_fail+
    lda zp_death_source
    cmp #DEATH_POISON
    bne !t9_fail+
    lda test_player_death_calls
    cmp #1
    bne !t9_fail+
    lda #$01
    sta tc_results + 8
    jmp !t10+
!t9_fail:
    lda #$00
    sta tc_results + 8

!t10:
    // Test 10: starvation damage clamps at 0 instead of wrapping to $FFFF.
    jsr reset_state
    lda #0
    sta zp_player_food
    sta zp_player_food_hi
    sta zp_player_hp_lo
    sta zp_player_hp_hi
    sta player_data + PL_HP_LO
    sta player_data + PL_HP_HI
    jsr turn_tick_hunger
    lda zp_player_hp_lo
    bne !t10_fail+
    lda zp_player_hp_hi
    bne !t10_fail+
    lda player_data + PL_HP_LO
    bne !t10_fail+
    lda player_data + PL_HP_HI
    bne !t10_fail+
    lda zp_death_source
    cmp #DEATH_STARVE
    bne !t10_fail+
    lda test_player_death_calls
    cmp #1
    bne !t10_fail+
    lda #$01
    sta tc_results + 9
    jmp t17_test
!t10_fail:
    lda #$00
    sta tc_results + 9
    jmp t17_test

t17_test:
    // Test 17: bless/prayer expiry prints the dedicated expiry message.
    jsr reset_state
    lda #1
    sta zp_eff_bless
    jsr turn_tick_effects
    lda zp_eff_bless
    bne !t17_fail+
    lda test_msg_calls
    cmp #1
    bne !t17_fail+
    lda test_last_msg_lo
    cmp #<turn_prayer_off_msg
    bne !t17_fail+
    lda test_last_msg_hi
    cmp #>turn_prayer_off_msg
    bne !t17_fail+
    lda #$01
    sta tc_results + 16
    jmp t18_test
!t17_fail:
    lda #$00
    sta tc_results + 16
    jmp t18_test

t18_test:
    // Test 18: umoria outer pseudo-ID chance uses level-based bound on 16-turn cadence.
    jsr reset_state
    lda #1
    sta zp_player_lvl
    lda #$0f
    sta zp_turn_lo
    lda #5
    sta inv_item_id + 1
    lda #1
    sta inv_p1 + 1
    lda #1
    sta test_rng_result
    jsr turn_tick_pseudo_id
    lda inv_flags + 1
    and #IF_SENSED
    bne !t18_fail+
    lda test_last_rng_bound
    cmp #135
    bne !t18_fail+
    lda test_msg_calls
    cmp #0
    bne !t18_fail+
    lda #$01
    sta tc_results + 17
    jmp t19_test
!t18_fail:
    lda #$00
    sta tc_results + 17
    jmp t19_test

t19_test:
    // Test 19: equipped positive gear uses the exact umoria-style wording.
    jsr reset_state
    lda #40
    sta zp_player_lvl
    lda #$0f
    sta zp_turn_lo
    lda #5
    sta inv_item_id + EQUIP_WEAPON
    lda #1
    sta inv_p1 + EQUIP_WEAPON
    lda #0
    sta test_rng_result
    jsr turn_tick_pseudo_id
    lda inv_flags + EQUIP_WEAPON
    and #IF_SENSED
    beq !t19_fail+
    lda test_huff_calls
    cmp #1
    bne !t19_fail+
    lda test_last_huff_id
    cmp #HSTR_PID_WIELDING
    bne !t19_fail+
    lda test_msg_calls
    bne !t19_fail+
    lda #$01
    sta tc_results + 18
    jmp t20_test
!t19_fail:
    lda #$00
    sta tc_results + 18
    jmp t20_test

t20_test:
    // Test 20: carried positive gear uses the pack wording and sensing path.
    jsr reset_state
    lda #1
    sta zp_player_lvl
    lda #$0f
    sta zp_turn_lo
    lda #5
    sta inv_item_id + 1
    lda #2
    sta inv_p1 + 1
    lda #0
    sta test_rng_result
    jsr turn_tick_pseudo_id
    lda inv_flags + 1
    and #IF_SENSED
    beq !t20_fail+
    lda test_huff_calls
    cmp #1
    bne !t20_fail+
    lda test_last_huff_id
    cmp #HSTR_PID_PACK
    bne !t20_fail+
    lda test_msg_calls
    bne !t20_fail+
    lda #$01
    sta tc_results + 19
    jmp t21_test
!t20_fail:
    lda #$00
    sta tc_results + 19
    jmp t21_test

t21_test:
    // Test 21: equipped light source fuel does not pseudo-sense as magic.
    jsr reset_state
    lda #1
    sta zp_player_lvl
    lda #$0f
    sta zp_turn_lo
    lda #13
    sta inv_item_id + EQUIP_LIGHT
    lda #10
    sta inv_p1 + EQUIP_LIGHT
    lda #0
    sta test_rng_result
    jsr turn_tick_pseudo_id
    lda inv_flags + EQUIP_LIGHT
    and #IF_SENSED
    bne !t21_fail+
    lda test_huff_calls
    cmp #0
    bne !t21_fail+
    lda #$01
    sta tc_results + 20
    jmp !t12+
!t21_fail:
    lda #$00
    sta tc_results + 20
    jmp !t12+

!t1_seq:
    jsr install_turn_patches

    // Test 1: turn_post_action sequencing + counter + restock + dirty flag.
    jsr reset_state
    lda #$ff
    sta zp_turn_lo
    lda #3
    sta zp_turn_hi
    jsr turn_post_action
    lda test_seq_effects
    cmp #0
    bne !t1_fail+
    lda test_seq_hunger
    cmp #1
    bne !t1_fail+
    lda test_seq_regen
    cmp #2
    bne !t1_fail+
    lda test_seq_light
    cmp #3
    bne !t1_fail+
    lda test_seq_pseudo
    cmp #4
    bne !t1_fail+
    lda test_monster_ai_calls
    cmp #1
    bne !t1_fail+
    lda test_seq_status
    cmp #5
    bne !t1_fail+
    lda zp_turn_lo
    bne !t1_fail+
    lda zp_turn_hi
    cmp #4
    bne !t1_fail+
    lda test_store_restock_calls
    cmp #1
    bne !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t11+
!t1_fail:
    lda #$00
    sta tc_results + 0
    jmp test_finish

!t11:
    // Test 11: pending redraw promotes to scene-dirty once, then clears.
    jsr reset_state
    lda #1
    sta turn_action_redraw_pending
    jsr turn_post_action
    lda turn_scene_dirty
    cmp #1
    bne !t11_fail+
    lda turn_action_redraw_pending
    bne !t11_fail+
    jsr turn_post_action
    lda turn_scene_dirty
    bne !t11_fail+
    lda turn_action_redraw_pending
    bne !t11_fail+
    lda #$01
    sta tc_results + 10
    jmp !t16+
!t11_fail:
    lda #$00
    sta tc_results + 10
    jmp !t16+

!t16:
    // Test 16: monster AI explicit dirty reports still promote turn_scene_dirty.
    jsr reset_state
    lda #1
    sta test_monster_ai_return_a
    lda #0
    sta test_monster_ai_return_c
    jsr turn_post_action
    lda test_monster_ai_calls
    cmp #1
    bne !t16_fail+
    lda turn_scene_dirty
    cmp #1
    bne !t16_fail+
    lda zp_dirty_count
    bne !t16_fail+
    lda #$01
    sta tc_results + 15
    jmp !t22+
!t16_fail:
    lda #$00
    sta tc_results + 15
    jmp !t22+

!t22:
    // Test 22: carry-only monster movement still promotes redraw in lit rooms.
    jsr reset_state
    lda #10
    sta zp_player_x
    lda #0
    sta zp_player_y
    lda #(FLAG_VISITED | FLAG_LIT)
    sta test_map_row + 10
    lda #1
    sta test_monster_ai_return_c
    lda #0
    sta test_monster_ai_return_a
    jsr turn_post_action
    lda turn_scene_dirty
    cmp #1
    bne !t22_fail+
    lda #$01
    sta tc_results + 21
    jmp !t23+
!t22_fail:
    lda #$00
    sta tc_results + 21
    jmp !t23+

!t23:
    // Test 23: the carry-only promotion does not fire on unlit tiles.
    jsr reset_state
    lda #10
    sta zp_player_x
    lda #0
    sta zp_player_y
    lda #0
    sta test_map_row + 10
    lda #1
    sta test_monster_ai_return_c
    lda #0
    sta test_monster_ai_return_a
    jsr turn_post_action
    lda turn_scene_dirty
    bne !t23_fail+
    lda #$01
    sta tc_results + 22
    jmp test_finish
!t23_fail:
    lda #$00
    sta tc_results + 22
    jmp test_finish

!t12:
    // Test 12: entering HUNGRY plays the mild hunger alert once.
    jsr reset_state
    lda #HUNGER_FULL
    sta zp_hunger_state
    lda #149
    sta zp_player_food
    lda #0
    sta zp_player_food_hi
    jsr turn_tick_hunger
    lda zp_hunger_state
    cmp #HUNGER_HUNGRY
    bne !t12_fail+
    lda test_sound_calls
    cmp #1
    bne !t12_fail+
    lda test_last_sound
    cmp #SFX_HUNGER_WARN
    bne !t12_fail+
    lda #$01
    sta tc_results + 11
    jmp !t13+
!t12_fail:
    lda #$00
    sta tc_results + 11

!t13:
    // Test 13: entering WEAK plays the mild hunger alert once.
    jsr reset_state
    lda #HUNGER_HUNGRY
    sta zp_hunger_state
    lda #49
    sta zp_player_food
    lda #0
    sta zp_player_food_hi
    jsr turn_tick_hunger
    lda zp_hunger_state
    cmp #HUNGER_WEAK
    bne !t13_fail+
    lda test_sound_calls
    cmp #1
    bne !t13_fail+
    lda test_last_sound
    cmp #SFX_HUNGER_WARN
    bne !t13_fail+
    lda #$01
    sta tc_results + 12
    jmp !t14+
!t13_fail:
    lda #$00
    sta tc_results + 12
    jmp !t14+

!t14:
    // Test 14: entering FAINT plays the severe hunger alert once.
    jsr reset_state
    lda #HUNGER_WEAK
    sta zp_hunger_state
    lda #9
    sta zp_player_food
    lda #0
    sta zp_player_food_hi
    jsr turn_tick_hunger
    lda zp_hunger_state
    cmp #HUNGER_FAINT
    bne !t14_fail+
    lda test_sound_calls
    cmp #1
    bne !t14_fail+
    lda test_last_sound
    cmp #SFX_HUNGER_FAINT
    bne !t14_fail+
    lda #$01
    sta tc_results + 13
    jmp !t15+
!t14_fail:
    lda #$00
    sta tc_results + 13
    jmp !t15+

!t15:
    // Test 15: steady faint and recovery recompute do not replay alerts.
    jsr reset_state
    lda #HUNGER_FAINT
    sta zp_hunger_state
    lda #9
    sta zp_player_food
    lda #0
    sta zp_player_food_hi
    jsr turn_tick_hunger
    lda zp_hunger_state
    cmp #HUNGER_FAINT
    bne !t15_fail+
    lda test_sound_calls
    bne !t15_fail+

    lda #HUNGER_WEAK
    sta zp_hunger_state
    lda #200
    sta zp_player_food
    jsr player_update_hunger_state
    lda zp_hunger_state
    cmp #HUNGER_FULL
    bne !t15_fail+
    lda test_sound_calls
    bne !t15_fail+
    lda test_last_sound
    cmp #$ff
    bne !t15_fail+
    lda #$01
    sta tc_results + 14
    jmp !t1_seq-
!t15_fail:
    lda #$00
    sta tc_results + 14
    jmp !t1_seq-

test_finish:
    ldx #22
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk
