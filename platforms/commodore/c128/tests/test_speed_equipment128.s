#importonce
// test_speed_equipment128.s — Ring of Speed & Cloak slot equip/remove regression

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $0810 "Test Code"
test_start:
    sei
    lda #$3e
    sta $ff00
    jmp test_main
.assert "test_start stays below C128 BASIC ROM", test_start < $4000, true

#import "../../../../core/zeropage.s"
#import "../hal/entropy_consts.s"
#import "../../../../core/rng.s"
#import "../../../../core/math.s"
#import "../../../../core/tables.s"
#import "../../../../core/item_defs.s"

.const COL_WHITE = 1
.const COL_LGREY = 15
.const hal_layout_character_background_col = 0
.const HAL_PLATFORM_CHARACTER_BACKGROUND_RESYNC = 0

.macro MapRead_ptr0_y() {
    lda (zp_ptr0),y
}

map_row_lo: .fill 1, 0
map_row_hi: .fill 1, 0
map_row_ptr0_x:                     // as core/dungeon_data.s
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    rts

hal_screen_put_string:
screen_put_decimal:
    rts

inv_item_id: .fill TOTAL_INV_SLOTS, FI_EMPTY
inv_qty:     .fill TOTAL_INV_SLOTS, 0
inv_p1:      .fill TOTAL_INV_SLOTS, 0
inv_to_hit:  .fill TOTAL_INV_SLOTS, 0
inv_to_dam:  .fill TOTAL_INV_SLOTS, 0
inv_to_ac:   .fill TOTAL_INV_SLOTS, 0
inv_flags:   .fill TOTAL_INV_SLOTS, 0
inv_ego:     .fill TOTAL_INV_SLOTS, 0
fi_item_id:  .byte FI_EMPTY
fi_meta_hi:  .byte 0
si_meta_hi:  .byte 0

#import "../../../../core/item_tables.s"
#import "../../../../core/player.s"

tramp_ego_get_ac_bonus:
    lda #0
    rts

// Match the C128 product (hal/lifecycle_policy.s): the stat adjuster lives
// outside player_recalc_equipment.s on C128, so it must not be pulled in here.
#define HAL_PLATFORM_ADJUST_EQUIPMENT_STAT_EXTERNAL
#import "../../../../core/player_recalc_equipment.s"

test_main:
    sei
    cld
    ldx #$ff
    txs

    jsr player_init
    lda #RACE_HUMAN
    sta player_data + PL_RACE
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    lda #1
    sta player_data + PL_LEVEL
    ldx #STAT_COUNT - 1
    lda #10
!set_stats:
    sta player_data + PL_STR_BASE,x
    dex
    bpl !set_stats-
    jsr player_calc_stats

    // Equipping the ring must enable permanent speed.
    lda #ITEM_SLOT_RING_OF_SPEED
    sta inv_item_id + EQUIP_RING
    lda #ITEM_PAGE_RING_OF_SPEED
    sta inv_ego + EQUIP_RING
    jsr player_recalc_equipment
    lda player_pflags
    and #PFLAG_SPEED
    beq test_fail

    // Removing the ring through the same production recalculation must clear it.
    lda #FI_EMPTY
    sta inv_item_id + EQUIP_RING
    lda #0
    sta inv_ego + EQUIP_RING
    jsr player_recalc_equipment
    lda player_pflags
    and #PFLAG_SPEED
    bne test_fail

    // Equipping Cloak (base AC 1) [+2] of Speed in EQUIP_CLOAK (slot 32)
    // must apply both AC (1 + 2 = 3) and ego passive flags.
    lda #ITEM_SLOT_CLOAK
    sta inv_item_id + EQUIP_CLOAK
    lda #2
    sta inv_to_ac + EQUIP_CLOAK
    lda #(ITEM_PAGE_CLOAK | EGO_SPEED)
    sta inv_ego + EQUIP_CLOAK
    jsr player_recalc_equipment
    lda player_pflags
    and #PFLAG_SPEED
    beq test_fail
    lda zp_player_ac
    cmp #3
    bne test_fail

    // Removing the cloak must clear both AC and ego passive flags.
    lda #FI_EMPTY
    sta inv_item_id + EQUIP_CLOAK
    lda #0
    sta inv_to_ac + EQUIP_CLOAK
    sta inv_ego + EQUIP_CLOAK
    jsr player_recalc_equipment
    lda player_pflags
    and #PFLAG_SPEED
    bne test_fail
    lda zp_player_ac
    bne test_fail

test_pass:
    jmp test_pass

test_fail:
    jmp test_fail

// As core/ui_messages.s (not imported here): hal_screen_put_string with A/Y
// = pointer
screen_put_string_ay:
    sta zp_ptr0
    sty zp_ptr0_hi
    jmp hal_screen_put_string
