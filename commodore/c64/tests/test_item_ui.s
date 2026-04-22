// test_item_ui.s — Runtime tests for UI-heavy item selection flows
//
// Tests: filtered letters, identify '?', rechargeable overlay selection,
//        floor item slot 33, and drop '?' compaction behavior.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tc_results: .fill 8, $ff

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    :BankOutKernal()
    ldx #7
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    :BankInKernal()
    brk

.pc = $0840 "Main"

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
#import "../../common/ui_inventory.s"
#import "../../common/ui_equipment.s"
#import "../../common/ui_help.s"
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
#import "../dungeon_render.s"
#import "../../common/dungeon_los.s"
#import "../../common/player_move.s"
#import "../../common/combat.s"
#import "../../common/monster_attack.s"
#import "../../common/turn.s"
#import "../../common/ui_trampoline_stubs.s"

.segmentdef TestStoreOverlay [start=$d000, min=$d000, max=$ffff]
.segment TestStoreOverlay
#import "../../common/store_data.s"
#import "../../common/store.s"
#import "../../common/ui_store.s"
.segment Default

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

test_key_idx: .byte 0
test_key_script: .fill 8, 0

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

test_start:
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

    lda #4
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    lda #0
    sta inv_p1 + 0
    sta inv_flags + 0

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
    cmp #25
    bne !t1_fail+
    lda inv_item_id + 4
    cmp #FI_EMPTY
    bne !t1_fail+
    lda inv_item_id + 0
    cmp #4
    bne !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // Test 2: item_takeoff maps contiguous letters over equipped items
!t2:
    jsr item_init_inventory
    lda #0
    sta zp_msg_flags

    lda #4
    sta inv_item_id + EQUIP_WEAPON
    lda #1
    sta inv_qty + EQUIP_WEAPON
    lda #0
    sta inv_p1 + EQUIP_WEAPON
    sta inv_flags + EQUIP_WEAPON

    lda #14
    sta inv_item_id + EQUIP_LIGHT
    lda #1
    sta inv_qty + EQUIP_LIGHT
    lda #20
    sta inv_p1 + EQUIP_LIGHT
    lda #0
    sta inv_flags + EQUIP_LIGHT

    lda #2
    sta $c6
    lda #$42
    sta $0277
    lda #$20
    sta $0278

    jsr item_takeoff
    bcc !t2_fail+
    lda inv_item_id + EQUIP_WEAPON
    cmp #4
    bne !t2_fail+
    lda inv_item_id + EQUIP_LIGHT
    cmp #FI_EMPTY
    bne !t2_fail+
    lda inv_item_id + 0
    cmp #14
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
    sta zp_msg_flags

    lda #ITEM_FLASK_OIL
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    lda #20
    sta inv_p1 + 0
    lda #0
    sta inv_flags + 0

    lda #2
    sta inv_item_id + 4
    lda #1
    sta inv_qty + 4
    lda #0
    sta inv_p1 + 4
    sta inv_flags + 4

    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_wear
    bcc !t3_fail+
    lda inv_item_id + EQUIP_WEAPON
    cmp #2
    bne !t3_fail+
    lda inv_item_id + 4
    cmp #FI_EMPTY
    bne !t3_fail+
    lda inv_item_id + 0
    cmp #ITEM_FLASK_OIL
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
    sta id_known + 17

    lda #21
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    lda #17
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

    lda id_known + 17
    cmp #1
    bne !t4_fail+
    lda inv_item_id
    cmp #17
    bne !t4_fail+
    lda id_known + 21
    cmp #1
    bne !t4_fail+
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
    sta id_known + 17

    lda #21
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    lda #17
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

    lda id_known + 17
    bne !t5_fail+
    lda inv_item_id
    cmp #17
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

    lda #17
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    lda #0
    sta inv_p1 + 0
    sta inv_flags + 0

    lda #39
    sta inv_item_id + 1
    lda #1
    sta inv_qty + 1
    lda #5
    sta inv_p1 + 1
    lda #0
    sta inv_flags + 1

    lda #43
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
    cmp #43
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
    lda #2
    sta fi_add_id
    lda #1
    sta fi_add_qty
    lda #0
    sta fi_add_p1
    sta fi_add_flags
    sta fi_add_ego
    jsr floor_item_add
    bcc !t7_fail+
    inx
    jmp !t7_seed_loop-
!t7_seed_done:
    lda #10
    sta fi_add_x
    sta fi_add_y
    lda #2
    sta fi_add_id
    lda #1
    sta fi_add_qty
    lda #0
    sta fi_add_p1
    sta fi_add_flags
    sta fi_add_ego
    jsr floor_item_add
    bcc !t7_fail+

    lda #10
    ldy #10
    jsr floor_item_find_at
    bcc !t7_fail+
    lda fi_item_id,x
    cmp #2
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

    lda #4
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    lda #0
    sta inv_p1 + 0
    sta inv_flags + 0

    lda #6
    sta inv_item_id + 1
    lda #1
    sta inv_qty + 1
    lda #0
    sta inv_p1 + 1
    sta inv_flags + 1

    lda #17
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
    cmp #4
    bne !t8_fail+
    lda inv_item_id + 1
    cmp #17
    bne !t8_fail+
    lda inv_item_id + 2
    cmp #FI_EMPTY
    bne !t8_fail+

    lda #10
    ldy #10
    jsr floor_item_find_at
    bcc !t8_fail+
    lda fi_item_id,x
    cmp #6
    bne !t8_fail+
    lda #$01
    sta tc_results + 7
    jmp !tests_done+
!t8_fail:
    lda #$00
    sta tc_results + 7

!tests_done:
    jmp test_finish

item_ui_test_body_end:

.assert "Item UI test stays below MAP_BASE", item_ui_test_body_end <= MAP_BASE, true
