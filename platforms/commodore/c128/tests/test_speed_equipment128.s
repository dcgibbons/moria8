#importonce
// test_speed_equipment128.s — Ring of Speed equip/remove regression

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $0810 "Test Code"

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

hal_screen_put_string:
screen_put_decimal:
    rts

#import "../../../../core/player.s"

inv_item_id: .fill TOTAL_INV_SLOTS, FI_EMPTY
inv_p1:      .fill TOTAL_INV_SLOTS, 0
inv_to_hit:  .fill TOTAL_INV_SLOTS, 0
inv_to_dam:  .fill TOTAL_INV_SLOTS, 0
inv_to_ac:   .fill TOTAL_INV_SLOTS, 0
inv_ego:     .fill TOTAL_INV_SLOTS, 0
it_color_ac: .fill ITEM_TYPE_COUNT, 0

item_get_base_ac:
    lda it_color_ac,y
    and #$0f
    rts

tramp_ego_get_ac_bonus:
    lda #0
    rts

#import "../../../../core/player_recalc_equipment.s"

test_start:
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

    // Equipping the ring must enable permanent speed.
    lda #ITEM_TYPE_RING_SPEED
    sta inv_item_id + EQUIP_RING
    jsr player_recalc_equipment
    lda player_pflags
    and #PFLAG_SPEED
    beq test_fail

    // Removing the ring through the same production recalculation must clear it.
    lda #FI_EMPTY
    sta inv_item_id + EQUIP_RING
    jsr player_recalc_equipment
    lda player_pflags
    and #PFLAG_SPEED
    bne test_fail

test_pass:
    jmp test_pass

test_fail:
    jmp test_fail
