// test_item_ui.s — Runtime tests for UI-heavy item selection flows
//
// Tests: filtered letters, identify '?', rechargeable overlay selection,
//        floor item slot 33, and drop '?' compaction behavior.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tc_results: .fill 16, $ff

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    :BankOutKernal()
    ldx #15
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    :BankInKernal()
    brk

.pc = $0840 "Main"

.encoding "screencode_mixed"

.segmentdef TestCreateOverlay [start=$D000, min=$D000, max=$DFFF]
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
.segment Default
#import "../../../../core/6502/ui_status.s"
.segment Default
#import "../../../../core/6502/ui_help_clear.s"
#import "../../../../core/6502/ui_character.s"
combat_compute_level_threshold:
    rts
ccl_adj_0: .byte 0
ccl_adj_1: .byte 0
ccl_adj_2: .byte 0
.segment TestCreateOverlay
#import "../../../../core/6502/stat_display.s"
.segment Default
.segment TestCreateOverlay
player_create:
    brk
.segment Default
#import "../../../../core/6502/ui_inventory.s"
#import "../../../../core/6502/ui_equipment.s"
#import "../../../../core/6502/ui_help.s"
#import "../../../../core/6502/sound.s"
#import "../../../../core/6502/dungeon_data.s"
#import "dungeon_gen_stubs.s"
#import "../../../../core/6502/huffman.s"
#define DISARM_COMMAND_EXTERNAL
#define DISARM_HELPERS_EXTERNAL
#import "../../../../core/6502/dungeon_features.s"
#import "chest_summons_stubs.s"
#undef DISARM_HELPERS_EXTERNAL
#undef DISARM_COMMAND_EXTERNAL
#import "../../../../core/6502/monster.s"
#import "../../../../core/6502/tier_manager.s"
#import "../../common/overlay.s"
.segment TestCreateOverlay
#import "../../../../core/6502/monster_ai.s"
.segment Default
#import "../../../../core/6502/recall.s"
.segment TestCreateOverlay
#import "../../../../core/6502/monster_magic.s"
.segment Default
#define HAL_PLATFORM_ITEM_CAT_CUSTOM
#import "../../../../core/6502/item.s"
#import "item_cat_resident_helper.s"
.segment Default
#import "../../../../core/6502/special_rooms.s"
.segment Default
#import "../../../../core/6502/ego_items.s"
#import "../../../../core/6502/special_rooms_stubs.s"
#import "../../../../core/6502/player_items.s"
#import "../../../../core/6502/spell_data.s"
.segment TestCreateOverlay
#import "../../../../core/6502/projectile.s"
.segment Default
#define SPELL_EFFECTS_INCLUDE_IDENTIFY
#import "../../../../core/6502/spell_effects.s"
.segment TestCreateOverlay
#import "../../../../core/6502/scene_mat_tile.s"
.segment Default
#undef SPELL_EFFECTS_INCLUDE_IDENTIFY
#import "../../../../core/6502/player_magic_state.s"
#import "../../../../core/6502/player_magic_state_ops.s"
#import "../../../../core/6502/player_magic.s"
#define C64_TEST_FULL_ITEMDESC_STUB
#import "../../../../core/6502/ui_trampoline_stubs.s"

// Store modules are never executed here; item_cat_data takes the $E100 window
// (item_cat_kernal_helper.s), so only the store inventory arrays that
// ui_trampoline_stubs.s references are linked (data, parked).
.segment Default
#import "../../../../core/6502/store_data_defs.s"
#import "../../../../core/6502/store_inventory_data.s"
.segment Default

.segmentdef TestPromptData [start=$bd00, min=$bd00, max=$bfff]

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

test_key_idx: .byte 0
test_key_script: .fill 8, 0
captured_prompt_row0: .fill 40, 0
cmb_buf_idx: .byte 0
cmb_damage: .byte 0
cmb_type: .byte 0
cmb_slot: .byte 0
combat_msg_buf: .fill 42, 0
walkable_table: .fill 16, 0
eff_fear_timer: .byte 0
render_single_tile:
    rts
light_room_x: .byte 0
vis_room_revealed: .byte 0
projectile_msg_suffix: .byte 0
cmb_the_str: .text "the " ; .byte 0
cmb_period: .text "." ; .byte 0

combat_append_str:
mon_atk_build_effect_msg:
combat_append_char:
combat_append_decimal:
combat_append_decimal_16:
cmb_term_and_print:
player_death_check:
monster_attack_player:
mon_atk_apply_damage:
mon_atk_apply_damage_16:
mon_atk_acid_armour:
viewport_update:
render_viewport:
player_update_hunger_state:
combat_apply_damage_16:
combat_kill_message:
combat_msg_monster_in_way:
combat_print_winner_message:
player_disarm_get_effective_chance:
combat_award_xp:
combat_check_levelup:
combat_check_leveldown:
combat_note_kill:
    rts
mad_dmg_hi: .byte 0               // the 16-bit damage entry's high byte (monster_attack.s)

player_get_infra_range:
    lda #0
    rts

tile_is_walkable:
    sec
    rts

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_input_get_key_script:
    ldx test_key_idx
    lda test_key_script,x
    beq !default+
    inx
    stx test_key_idx
    rts
!default:
    lda #$20
    rts

test_input_wait_release:
    rts

capture_prompt_row0:
    ldx #0
!capture_loop:
    lda $0400,x
    sta captured_prompt_row0,x
    inx
    cpx #40
    bcc !capture_loop-
    rts

test_input_get_key_capture_space:
    jsr capture_prompt_row0
    lda #$20
    rts

assert_captured_prompt_row0:
    ldy #0
!assert_loop:
    lda (zp_ptr0),y
    beq !assert_ok+
    cmp captured_prompt_row0,y
    bne !assert_fail+
    iny
    cpy #40
    bcc !assert_loop-
!assert_fail:
    clc
    rts
!assert_ok:
    sec
    rts

test_build_recharge_cache:
    ldy #0
    ldx #0
!tbrc_scan:
    cpx #MAX_INV_SLOTS
    bcs !tbrc_done+
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !tbrc_next+
    tay
    lda it_category,y
    cmp #ICAT_WAND
    beq !tbrc_store+
    cmp #ICAT_STAFF
    bne !tbrc_next+
!tbrc_store:
    txa
    ldy piw_visible_count
    sta piw_visible_slots,y
    iny
    sty piw_visible_count
!tbrc_next:
    inx
    jmp !tbrc_scan-
!tbrc_done:
    lda piw_visible_count
    rts

test_pick_recharge_item:
    lda #0
    sta piw_visible_count
    jsr test_build_recharge_cache
    bne !tpri_have_choices+
    lda #$ff
    clc
    rts
!tpri_have_choices:
    jsr input_prepare_followup_key
    jsr input_get_key
    cmp #$3f
    bne !tpri_not_inv+
    lda #$ff
    jsr show_inv_and_select
    cmp #$03
    beq !tpri_cancel+
    cmp #$20
    beq !tpri_cancel+
    sec
    sbc #$41
    bcc !tpri_cancel+
    cmp #MAX_INV_SLOTS
    bcs !tpri_cancel+
    tax
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !tpri_cancel+
    tay
    lda it_category,y
    cmp #ICAT_WAND
    beq !tpri_ok+
    cmp #ICAT_STAFF
    beq !tpri_ok+
    lda #0
    clc
    rts
!tpri_not_inv:
    cmp #$03
    beq !tpri_cancel+
    cmp #$20
    beq !tpri_cancel+
    jsr piw_pick_filtered_inv_key
    bcs !tpri_ok+
!tpri_cancel:
    lda #0
    clc
    rts
!tpri_ok:
    lda inv_item_id,x
    sec
    rts

test_asset_load_fails:
    sec
    rts

test_start:
    // No disk here: a tier restore's load fails at once instead of a real
    // KERNAL LOAD from the empty drive, which hung VICE's serial bus in some
    // code layouts (as test_effects_magic does).
    lda #$4c                    // jmp test_asset_load_fails
    sta hal_asset_load_prg_header
    lda #<test_asset_load_fails
    sta hal_asset_load_prg_header + 1
    lda #>test_asset_load_fails
    sta hal_asset_load_prg_header + 2
    ldx #7
    lda #$ff
!clr:
    sta tc_results,x
    dex
    bpl !clr-

    lda #$42
    sta zp_rng_0
    lda #$13
    sta zp_rng_1
    lda #$7a
    sta zp_rng_2
    lda #$f1
    sta zp_rng_3

    lda #1
    sta zp_player_dlvl
    sta zp_light_radius

    jsr msg_init

    lda #200
    sta zp_player_hp_lo
    sta zp_player_mhp_lo
    lda #0
    sta zp_player_hp_hi
    sta zp_player_mhp_hi

    lda #12
    sta player_data + PL_STR_CUR
    sta player_data + PL_DEX_CUR
    sta player_data + PL_CON_CUR
    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL

    lda #1
    sta $c6
    lda #$20
    sta $0277

    // Test 1: item_quaff maps filtered letters over sparse slots
    jsr item_init_inventory

    lda #0
    sta zp_msg_flags

    lda #50
    sta zp_player_hp_lo
    lda #0
    sta zp_player_hp_hi
    lda #200
    sta zp_player_mhp_lo
    lda #0
    sta zp_player_mhp_hi

    lda #ITEM_SLOT_LONG_SWORD
    sta inv_item_id + 0
    .if (ITEM_PAGE_LONG_SWORD != 0) {
        lda #ITEM_PAGE_LONG_SWORD
        sta inv_ego + 0
    }
    lda #1
    sta inv_qty + 0
    lda #0
    sta inv_p1 + 0
    sta inv_flags + 0

    lda #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS
    sta inv_item_id + 1
    lda #1
    sta inv_qty + 1
    lda #0
    sta inv_p1 + 1
    sta inv_flags + 1

    lda #ITEM_SLOT_POTION_OF_CURE_SERIOUS_WOUNDS
    sta inv_item_id + 4
    lda #1
    sta inv_qty + 4
    lda #0
    sta inv_p1 + 4
    sta inv_flags + 4

    lda #1
    sta $c6
    lda #$41
    sta $0277

    jsr item_quaff
    bcc !t1_fail+
    lda inv_item_id + 1
    cmp #FI_EMPTY
    bne !t1_fail+
    lda inv_item_id + 3
    cmp #ITEM_SLOT_POTION_OF_CURE_SERIOUS_WOUNDS
    bne !t1_fail+
    lda inv_item_id + 4
    cmp #FI_EMPTY
    bne !t1_fail+
    lda inv_item_id + 0
    cmp #ITEM_SLOT_LONG_SWORD
    bne !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // Test 2: item_takeoff '?' overlay accepts equipment-list selection
!t2:
    jsr item_init_inventory
    :PatchJump(input_get_key, test_input_get_key_script)
    :PatchJump(input_wait_release, test_input_wait_release)
    lda #0
    sta test_key_idx
    sta zp_msg_flags

    lda #ITEM_SLOT_LONG_SWORD
    sta inv_item_id + EQUIP_WEAPON
    .if (ITEM_PAGE_LONG_SWORD != 0) {
        lda #ITEM_PAGE_LONG_SWORD
        sta inv_ego + EQUIP_WEAPON
    }
    lda #1
    sta inv_qty + EQUIP_WEAPON
    lda #0
    sta inv_p1 + EQUIP_WEAPON
    sta inv_flags + EQUIP_WEAPON

    lda #ITEM_SLOT_BRASS_LANTERN
    sta inv_item_id + EQUIP_LIGHT
    lda #1
    sta inv_qty + EQUIP_LIGHT
    lda #20
    sta inv_p1 + EQUIP_LIGHT
    lda #0
    sta inv_flags + EQUIP_LIGHT

    lda #$3f
    sta test_key_script + 0
    lda #$42
    sta test_key_script + 1
    lda #0
    sta test_key_script + 2

    jsr item_takeoff
    bcc !t2_fail+
    lda inv_item_id + EQUIP_WEAPON
    cmp #ITEM_SLOT_LONG_SWORD
    bne !t2_fail+
    lda inv_item_id + EQUIP_LIGHT
    cmp #FI_EMPTY
    bne !t2_fail+
    lda inv_item_id + 0
    cmp #ITEM_SLOT_BRASS_LANTERN
    bne !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // Test 3: item_wear hides Flask of Oil from wearable selection
!t3:
    jsr item_init_inventory
    lda #0
    sta test_key_idx
    sta zp_msg_flags

    lda #ITEM_SLOT_FLASK_OF_OIL
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    lda #20
    sta inv_p1 + 0
    lda #0
    sta inv_flags + 0

    lda #ITEM_SLOT_DAGGER
    sta inv_item_id + 4
    .if (ITEM_PAGE_DAGGER != 0) {
        lda #ITEM_PAGE_DAGGER
        sta inv_ego + 4
    }
    lda #1
    sta inv_qty + 4
    lda #0
    sta inv_p1 + 4
    sta inv_flags + 4

    lda #$41
    sta test_key_script + 0
    lda #0
    sta test_key_script + 1

    jsr item_wear
    bcc !t3_fail+
    lda inv_item_id + EQUIP_WEAPON
    cmp #ITEM_SLOT_DAGGER
    bne !t3_fail+
    lda inv_item_id + 4
    cmp #FI_EMPTY
    bne !t3_fail+
    lda inv_item_id + 0
    cmp #ITEM_SLOT_FLASK_OF_OIL
    bne !t3_fail+
    lda #$01
    sta tc_results + 2
    jmp !t4+
!t3_fail:
    lda #$00
    sta tc_results + 2

    // Test 4: identify prompt supports '?'
!t4:
    jsr item_init_inventory
    :PatchJump(input_get_key, test_input_get_key_script)
    :PatchJump(input_wait_release, test_input_wait_release)
    lda #0
    sta test_key_idx
    sta zp_msg_flags
    ldx #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS
    jsr id_known_clear

    lda #ITEM_SLOT_SCROLL_OF_IDENTIFY
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    lda #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS
    sta inv_item_id + 1
    lda #1
    sta inv_qty + 1
    lda #0
    sta inv_p1 + 1
    sta inv_flags + 1

    lda #$41
    sta test_key_script + 0
    lda #$3f
    sta test_key_script + 1
    lda #$41
    sta test_key_script + 2
    lda #0
    sta test_key_script + 3

    jsr item_read_scroll

    ldx #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS
    jsr id_known_test
    beq !t4_fail+
    lda inv_item_id
    cmp #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS
    bne !t4_fail+
    ldx #ITEM_SLOT_SCROLL_OF_IDENTIFY
    jsr id_known_test
    beq !t4_fail+
    lda #$01
    sta tc_results + 3
    jmp !t5+
!t4_fail:
    lda #$00
    sta tc_results + 3

    // Test 5: identify '?' dismiss key does not get reused
!t5:
    jsr item_init_inventory
    lda #0
    sta test_key_idx
    sta zp_msg_flags
    ldx #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS
    jsr id_known_clear

    lda #ITEM_SLOT_SCROLL_OF_IDENTIFY
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    lda #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS
    sta inv_item_id + 1
    lda #1
    sta inv_qty + 1
    lda #0
    sta inv_p1 + 1
    sta inv_flags + 1

    lda #$41
    sta test_key_script + 0
    lda #$3f
    sta test_key_script + 1
    lda #$20
    sta test_key_script + 2
    lda #0
    sta test_key_script + 3

    jsr item_read_scroll

    ldx #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS
    jsr id_known_test
    bne !t5_fail+
    lda inv_item_id
    cmp #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS
    bne !t5_fail+
    lda #$01
    sta tc_results + 4
    jmp !t6+
!t5_fail:
    lda #$00
    sta tc_results + 4

    // Test 6: rechargeable-item prompt supports '?'
!t6:
    jsr item_init_inventory
    lda #0
    sta test_key_idx
    sta zp_msg_flags

    lda #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    lda #0
    sta inv_p1 + 0
    sta inv_flags + 0

    lda #ITEM_SLOT_WAND_OF_LIGHT
    sta inv_item_id + 1
    lda #1
    sta inv_qty + 1
    lda #5
    sta inv_p1 + 1
    lda #0
    sta inv_flags + 1

    lda #ITEM_SLOT_STAFF_OF_LIGHT
    sta inv_item_id + 3
    lda #1
    sta inv_qty + 3
    lda #7
    sta inv_p1 + 3
    lda #0
    sta inv_flags + 3

    lda #$3f
    sta test_key_script + 0
    lda #$44
    sta test_key_script + 1
    lda #0
    sta test_key_script + 2

    jsr test_pick_recharge_item
    bcc !t6_fail+
    cpx #3
    bne !t6_fail+
    cmp #ITEM_SLOT_STAFF_OF_LIGHT
    bne !t6_fail+
    lda #$01
    sta tc_results + 5
    jmp !t7+
!t6_fail:
    lda #$00
    sta tc_results + 5

    // Test 7: floor item #33 can still be added
!t7:
    jsr item_init_floor
    ldx #0
!t7_seed_loop:
    cpx #32
    bcs !t7_seed_done+
    txa
    clc
    adc #1
    sta fi_add_x
    lda #1
    sta fi_add_y
    lda #ITEM_SLOT_DAGGER
    sta fi_add_id
    lda #1
    sta fi_add_qty
    lda #0
    sta fi_add_p1
    sta fi_add_flags
    .if (ITEM_PAGE_DAGGER != 0) {
        lda #ITEM_PAGE_DAGGER
    }
    sta fi_add_ego
    jsr floor_item_add
    bcc !t7_fail+
    inx
    jmp !t7_seed_loop-
!t7_seed_done:
    lda #10
    sta fi_add_x
    sta fi_add_y
    lda #ITEM_SLOT_DAGGER
    sta fi_add_id
    lda #1
    sta fi_add_qty
    lda #0
    sta fi_add_p1
    sta fi_add_flags
    .if (ITEM_PAGE_DAGGER != 0) {
        lda #ITEM_PAGE_DAGGER
    }
    sta fi_add_ego
    jsr floor_item_add
    bcc !t7_fail+

    lda #10
    ldy #10
    jsr floor_item_find_at
    bcc !t7_fail+
    lda fi_item_id,x
    cmp #ITEM_SLOT_DAGGER
    bne !t7_fail+
    lda zp_item_count
    cmp #33
    bne !t7_fail+
    lda #$01
    sta tc_results + 6
    jmp !t8+
!t7_fail:
    lda #$00
    sta tc_results + 6

    // Test 8: item_drop '?' overlay follows compact letters
!t8:
    jsr item_init_floor
    jsr item_init_inventory
    :PatchJump(input_get_key, test_input_get_key_script)
    :PatchJump(input_wait_release, test_input_wait_release)
    lda #0
    sta test_key_idx
    sta zp_msg_flags

    lda #10
    sta zp_player_x
    sta zp_player_y

    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda #TILE_FLOOR | FLAG_LIT | FLAG_VISITED
    sta (zp_ptr0),y

    lda #ITEM_SLOT_LONG_SWORD
    sta inv_item_id + 0
    .if (ITEM_PAGE_LONG_SWORD != 0) {
        lda #ITEM_PAGE_LONG_SWORD
        sta inv_ego + 0
    }
    lda #1
    sta inv_qty + 0
    lda #0
    sta inv_p1 + 0
    sta inv_flags + 0

    lda #ITEM_SLOT_ROBE
    sta inv_item_id + 1
    lda #1
    sta inv_qty + 1
    lda #0
    sta inv_p1 + 1
    sta inv_flags + 1

    lda #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS
    sta inv_item_id + 2
    lda #1
    sta inv_qty + 2
    lda #0
    sta inv_p1 + 2
    sta inv_flags + 2

    lda #$3f
    sta test_key_script + 0
    lda #$42
    sta test_key_script + 1
    lda #0
    sta test_key_script + 2

    jsr item_drop
    bcc !t8_fail+
    lda inv_item_id + 0
    cmp #ITEM_SLOT_LONG_SWORD
    bne !t8_fail+
    lda inv_item_id + 1
    cmp #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS
    bne !t8_fail+
    lda inv_item_id + 2
    cmp #FI_EMPTY
    bne !t8_fail+

    lda #10
    ldy #10
    jsr floor_item_find_at
    bcc !t8_fail+
    lda fi_item_id,x
    cmp #ITEM_SLOT_ROBE
    bne !t8_fail+
    lda #$01
    sta tc_results + 7
    jmp !t9+
!t8_fail:
    lda #$00
    sta tc_results + 7

    // Test 9: direct drop prompt patch uses C64 screen-code range letters
!t9:
    lda #0
    sta zp_msg_flags
    lda #22
    ldx #HSTR_IDR_PROMPT
    jsr piw_print_prompt_with_count

    lda #<expected_drop_prompt_av
    sta zp_ptr0
    lda #>expected_drop_prompt_av
    sta zp_ptr0_hi
    ldy #0
!t9_cmp:
    lda (zp_ptr0),y
    beq !t9_pass+
    cmp $0400,y
    bne !t9_fail+
    iny
    cpy #40
    bcc !t9_cmp-
!t9_fail:
    lda #$00
    sta tc_results + 8
    jmp !t10+
!t9_pass:
    lda #$01
    sta tc_results + 8

    // Test 10: item_wear prompt row renders contiguous screen-code letters
!t10:
    jsr item_init_inventory
    :PatchJump(input_get_key, test_input_get_key_capture_space)
    :PatchJump(input_wait_release, test_input_wait_release)
    lda #0
    sta zp_msg_flags

    lda #ITEM_SLOT_DAGGER
    sta inv_item_id + 0
    .if (ITEM_PAGE_DAGGER != 0) {
        lda #ITEM_PAGE_DAGGER
        sta inv_ego + 0
    }
    lda #1
    sta inv_qty + 0
    lda #0
    sta inv_p1 + 0
    sta inv_flags + 0

    lda #ITEM_SLOT_LEATHER_ARMOR
    sta inv_item_id + 1
    lda #1
    sta inv_qty + 1
    lda #0
    sta inv_p1 + 1
    sta inv_flags + 1

    lda #ITEM_SLOT_SMALL_SHIELD
    sta inv_item_id + 2
    .if (ITEM_PAGE_SMALL_SHIELD != 0) {
        lda #ITEM_PAGE_SMALL_SHIELD
        sta inv_ego + 2
    }
    lda #1
    sta inv_qty + 2
    lda #0
    sta inv_p1 + 2
    sta inv_flags + 2

    jsr item_wear

    lda #<expected_wear_prompt_ac
    sta zp_ptr0
    lda #>expected_wear_prompt_ac
    sta zp_ptr0_hi
    jsr assert_captured_prompt_row0
    bcc !t10_fail+
    lda #$01
    sta tc_results + 9
    jmp !t11+
!t10_fail:
    lda #$00
    sta tc_results + 9

    // Test 11: item_takeoff prompt row renders contiguous screen-code letters
!t11:
    jsr item_init_inventory
    lda #0
    sta zp_msg_flags

    lda #ITEM_SLOT_LONG_SWORD
    sta inv_item_id + EQUIP_WEAPON
    .if (ITEM_PAGE_LONG_SWORD != 0) {
        lda #ITEM_PAGE_LONG_SWORD
        sta inv_ego + EQUIP_WEAPON
    }
    lda #1
    sta inv_qty + EQUIP_WEAPON
    lda #0
    sta inv_p1 + EQUIP_WEAPON
    sta inv_flags + EQUIP_WEAPON

    lda #ITEM_SLOT_SMALL_SHIELD
    sta inv_item_id + EQUIP_SHIELD
    .if (ITEM_PAGE_SMALL_SHIELD != 0) {
        lda #ITEM_PAGE_SMALL_SHIELD
        sta inv_ego + EQUIP_SHIELD
    }
    lda #1
    sta inv_qty + EQUIP_SHIELD
    lda #0
    sta inv_p1 + EQUIP_SHIELD
    sta inv_flags + EQUIP_SHIELD

    lda #ITEM_SLOT_BRASS_LANTERN
    sta inv_item_id + EQUIP_LIGHT
    lda #1
    sta inv_qty + EQUIP_LIGHT
    lda #20
    sta inv_p1 + EQUIP_LIGHT
    lda #0
    sta inv_flags + EQUIP_LIGHT

    jsr item_takeoff

    lda #<expected_takeoff_prompt_ac
    sta zp_ptr0
    lda #>expected_takeoff_prompt_ac
    sta zp_ptr0_hi
    jsr assert_captured_prompt_row0
    bcc !t11_fail+
    lda #$01
    sta tc_results + 10
    jmp !t12+
!t11_fail:
    lda #$00
    sta tc_results + 10

    // Test 12: item_drop prompt row renders contiguous screen-code letters
!t12:
    jsr item_init_inventory
    lda #0
    sta zp_msg_flags

    lda #ITEM_SLOT_LONG_SWORD
    sta inv_item_id + 0
    .if (ITEM_PAGE_LONG_SWORD != 0) {
        lda #ITEM_PAGE_LONG_SWORD
        sta inv_ego + 0
    }
    lda #1
    sta inv_qty + 0
    lda #0
    sta inv_p1 + 0
    sta inv_flags + 0

    lda #ITEM_SLOT_ROBE
    sta inv_item_id + 1
    lda #1
    sta inv_qty + 1
    lda #0
    sta inv_p1 + 1
    sta inv_flags + 1

    lda #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS
    sta inv_item_id + 2
    lda #1
    sta inv_qty + 2
    lda #0
    sta inv_p1 + 2
    sta inv_flags + 2

    jsr item_drop

    lda #<expected_drop_prompt_ac
    sta zp_ptr0
    lda #>expected_drop_prompt_ac
    sta zp_ptr0_hi
    jsr assert_captured_prompt_row0
    bcc !t12_fail+
    lda #$01
    sta tc_results + 11
    jmp !t13+
!t12_fail:
    lda #$00
    sta tc_results + 11

    // Test 13: mage book prompt row renders contiguous screen-code letters
!t13:
    jsr item_init_inventory
    lda #0
    sta zp_msg_flags
    sta pm_mode
    lda #SPELL_MAGE
    sta pm_spell_type

    lda #ITEM_SLOT_SPELLBOOK_BEGINNERS_MAGICK
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    lda #0
    sta inv_p1 + 0
    sta inv_flags + 0

    lda #ITEM_SLOT_SPELLBOOK_MAGICK_I
    sta inv_item_id + 1
    lda #1
    sta inv_qty + 1
    lda #0
    sta inv_p1 + 1
    sta inv_flags + 1

    lda #ITEM_SLOT_SPELLBOOK_MAGICK_II
    sta inv_item_id + 2
    lda #1
    sta inv_qty + 2
    lda #0
    sta inv_p1 + 2
    sta inv_flags + 2

    jsr pm_select_book

    lda #<expected_spell_book_prompt_ac
    sta zp_ptr0
    lda #>expected_spell_book_prompt_ac
    sta zp_ptr0_hi
    jsr assert_captured_prompt_row0
    bcc !t13_fail+
    lda #$01
    sta tc_results + 12
    jmp !t14+
!t13_fail:
    lda #$00
    sta tc_results + 12

    // Test 14: prayer book prompt row renders contiguous screen-code letters
!t14:
    jsr item_init_inventory
    lda #0
    sta zp_msg_flags
    sta pm_mode
    lda #SPELL_PRIEST
    sta pm_spell_type

    lda #ITEM_SLOT_HOLY_BOOK_OF_PRAYERS_BEGINNERS_HANDBOOK
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    lda #0
    sta inv_p1 + 0
    sta inv_flags + 0

    lda #ITEM_SLOT_HOLY_BOOK_OF_PRAYERS_WORDS_OF_WISDOM
    sta inv_item_id + 1
    lda #1
    sta inv_qty + 1
    lda #0
    sta inv_p1 + 1
    sta inv_flags + 1

    lda #ITEM_SLOT_HOLY_BOOK_OF_PRAYERS_CHANTS_AND_BLESSINGS
    sta inv_item_id + 2
    lda #1
    sta inv_qty + 2
    lda #0
    sta inv_p1 + 2
    sta inv_flags + 2

    jsr pm_select_book

    lda #<expected_prayer_book_prompt_ac
    sta zp_ptr0
    lda #>expected_prayer_book_prompt_ac
    sta zp_ptr0_hi
    jsr assert_captured_prompt_row0
    bcc !t14_fail+
    lda #$01
    sta tc_results + 13
    jmp !t15+
!t14_fail:
    lda #$00
    sta tc_results + 13

    // Test 15: cast footer prompt row renders contiguous screen-code letters
!t15:
    lda #0
    sta zp_msg_flags
    lda #SPELL_MAGE
    sta pm_spell_type
    lda #3
    sta pm_spell_count

    jsr pm_prompt_visible_spell_choice

    lda #<expected_cast_prompt_ac
    sta zp_ptr0
    lda #>expected_cast_prompt_ac
    sta zp_ptr0_hi
    jsr assert_captured_prompt_row0
    bcc !t15_fail+
    lda #$01
    sta tc_results + 14
    jmp !t16+
!t15_fail:
    lda #$00
    sta tc_results + 14

    // Test 16: pray footer prompt row renders contiguous screen-code letters
!t16:
    lda #0
    sta zp_msg_flags
    lda #SPELL_PRIEST
    sta pm_spell_type
    lda #3
    sta pm_spell_count

    jsr pm_prompt_visible_spell_choice

    lda #<expected_pray_prompt_ac
    sta zp_ptr0
    lda #>expected_pray_prompt_ac
    sta zp_ptr0_hi
    jsr assert_captured_prompt_row0
    bcc !t16_fail+
    lda #$01
    sta tc_results + 15
    jmp !tests_done+
!t16_fail:
    lda #$00
    sta tc_results + 15

!tests_done:
    jmp test_finish

.segment TestPromptData
expected_drop_prompt_av:
    .text "Drop which item (a-v)?" ; .byte 0
expected_wear_prompt_ac:
    .text "Wear which item (a-c)?" ; .byte 0
expected_takeoff_prompt_ac:
    .text "Take off which item (a-c)?" ; .byte 0
expected_drop_prompt_ac:
    .text "Drop which item (a-c)?" ; .byte 0
expected_spell_book_prompt_ac:
    .text "Spell book (a-c)?" ; .byte 0
expected_prayer_book_prompt_ac:
    .text "Prayer book (a-c)?" ; .byte 0
expected_cast_prompt_ac:
    .text "Cast which? (a-c" ; .byte 0
expected_pray_prompt_ac:
    .text "Pray which? (a-c" ; .byte 0

.segment Default
item_ui_test_body_end:

.assert "Item UI test stays below MAP_BASE", item_ui_test_body_end <= MAP_BASE, true
