#importonce
// test_item_desc128.s — C128 VDC coverage for real item descriptions

#import "../../common/zeropage.s"
#import "../screen_vdc.s"
#import "../../common/color.s"
#import "../../common/rng.s"
#import "../../common/math.s"
#import "../../common/item_defs.s"
.const HD_DECODE_BUF_SIZE = 64
hd_decode_buf: .fill HD_DECODE_BUF_SIZE, 0

.const ICAT_NONE     = 0
.const ICAT_GOLD     = 1
.const ICAT_WEAPON   = 2
.const ICAT_ARMOR    = 3
.const ICAT_SHIELD   = 4
.const ICAT_HELM     = 5
.const ICAT_GLOVES   = 6
.const ICAT_BOOTS    = 7
.const ICAT_LIGHT    = 8
.const ICAT_FOOD     = 9
.const ICAT_POTION   = 10
.const ICAT_SCROLL   = 11
.const ICAT_RING     = 12
.const ICAT_BOOK     = 13
.const ICAT_WAND     = 14
.const ICAT_STAFF    = 15

#import "../../common/item_tables.s"
#import "../../common/item_identification.s"

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $5000 "Test Code"

banked_ego_put_suffix:
    rts

put_tool_ego_prefix:
    rts

inv_item_id: .fill TOTAL_INV_SLOTS, 0
inv_p1:      .fill TOTAL_INV_SLOTS, 0
inv_to_hit:  .fill TOTAL_INV_SLOTS, 0
inv_to_dam:  .fill TOTAL_INV_SLOTS, 0
inv_to_ac:   .fill TOTAL_INV_SLOTS, 0
inv_flags:   .fill TOTAL_INV_SLOTS, 0
inv_ego:     .fill TOTAL_INV_SLOTS, 0

si_item_id: .byte 0
si_p1:      .byte 0
si_to_hit:  .byte 0
si_to_dam:  .byte 0
si_to_ac:   .byte 0
si_meta:    .byte 0
fi_add_flags: .byte 0
fi_add_ego:   .byte 0

#import "../../common/item_desc_banked.s"

test_start:
    sei
    cld
    ldx #$ff
    txs

    lda #COL_WHITE
    sta zp_text_color
    jsr screen_clear

    // Test 1: identified weapon prints split to-hit/to-dam suffix.
    jsr test_prepare_row0
    lda #2
    sta itemdesc_item_id
    lda #0
    sta itemdesc_p1
    sta itemdesc_to_ac
    sta itemdesc_ego
    lda #2
    sta itemdesc_to_hit
    lda #$fd
    sta itemdesc_to_dam
    lda #IF_IDENTIFIED
    sta itemdesc_flags
    jsr itemdesc_put_staged

    lda #<expected_weapon_vdc
    sta zp_ptr0
    lda #>expected_weapon_vdc
    sta zp_ptr0_hi
    lda #0
    jsr assert_row0_from_col
    bcs !weapon_ok+
    jmp test_fail
!weapon_ok:

    // Test 2: identified armor prints base AC and to-AC with bracket glyphs.
    jsr test_prepare_row0
    lda #7
    sta itemdesc_item_id
    lda #0
    sta itemdesc_p1
    sta itemdesc_to_hit
    sta itemdesc_to_dam
    sta itemdesc_ego
    lda #1
    sta itemdesc_to_ac
    lda #IF_IDENTIFIED
    sta itemdesc_flags
    jsr itemdesc_put_staged

    lda #<expected_armor_suffix_vdc
    sta zp_ptr0
    lda #>expected_armor_suffix_vdc
    sta zp_ptr0_hi
    lda #14
    jsr assert_row0_from_col
    bcs !armor_ok+
    jmp test_fail
!armor_ok:

    // Test 3: sensed-only items show magik but no stat suffix leakage.
    jsr test_prepare_row0
    lda #2
    sta itemdesc_item_id
    lda #0
    sta itemdesc_p1
    sta itemdesc_to_ac
    sta itemdesc_ego
    lda #5
    sta itemdesc_to_hit
    sta itemdesc_to_dam
    lda #IF_SENSED
    sta itemdesc_flags
    jsr itemdesc_put_staged

    lda #<expected_sensed_vdc
    sta zp_ptr0
    lda #>expected_sensed_vdc
    sta zp_ptr0_hi
    lda #0
    jsr assert_row0_from_col
    bcs !sensed_prefix_ok+
    jmp test_fail
!sensed_prefix_ok:
    lda #14
    jsr read_row0_col
    cmp #SC_SPACE
    beq !sensed_ok+
    jmp test_fail
!sensed_ok:

    // Test 4: known scrolls use Umoria-style category names.
    jsr test_prepare_row0
    lda #1
    sta id_known + 21
    lda #21
    sta itemdesc_item_id
    lda #0
    sta itemdesc_p1
    sta itemdesc_to_hit
    sta itemdesc_to_dam
    sta itemdesc_to_ac
    sta itemdesc_ego
    sta itemdesc_flags
    jsr itemdesc_put_staged

    lda #<expected_identify_scroll_vdc
    sta zp_ptr0
    lda #>expected_identify_scroll_vdc
    sta zp_ptr0_hi
    lda #0
    jsr assert_row0_from_col
    bcs !scroll_ok+
    jmp test_fail
!scroll_ok:

    // Test 5: known prayer books include the book category text.
    jsr test_prepare_row0
    lda #48
    sta itemdesc_item_id
    lda #0
    sta itemdesc_p1
    sta itemdesc_to_hit
    sta itemdesc_to_dam
    sta itemdesc_to_ac
    sta itemdesc_ego
    sta itemdesc_flags
    jsr itemdesc_put_staged

    lda #<expected_prayer_book_vdc
    sta zp_ptr0
    lda #>expected_prayer_book_vdc
    sta zp_ptr0_hi
    lda #0
    jsr assert_row0_from_col
    bcs !book_ok+
    jmp test_fail
!book_ok:

    jmp test_pass

test_prepare_row0:
    jsr screen_clear
    lda #0
    sta zp_cursor_row
    sta zp_cursor_col
    rts

// Input: A = row 0 column, zp_ptr0 = expected VDC bytes, 0-terminated.
assert_row0_from_col:
    sta assert_col
    lda #0
    sta zp_cursor_row
    lda assert_col
    sta zp_cursor_col
    jsr screen_set_cursor
    lda zp_screen_hi
    ldy zp_screen_lo
    jsr vdc_set_update_addr
    ldy #0
!loop:
    lda (zp_ptr0),y
    beq !ok+
    sta assert_expected
    sty assert_idx
    ldx #31
    jsr vdc_read_reg
    ldy assert_idx
    cmp assert_expected
    bne !fail+
    iny
    cpy #80
    bcc !loop-
!fail:
    clc
    rts
!ok:
    sec
    rts

read_row0_col:
    sta zp_cursor_col
    lda #0
    sta zp_cursor_row
    jsr screen_set_cursor
    lda zp_screen_hi
    ldy zp_screen_lo
    jsr vdc_set_update_addr
    ldx #31
    jmp vdc_read_reg

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass

// Expected VDC Set 1 bytes. Lowercase letters are $01-$1a.
expected_weapon_vdc:
    .byte $44, $01, $07, $07, $05, $12, $20, $28, $2b, $32, $2c, $2d, $33, $29, 0
expected_armor_suffix_vdc:
    .byte $1b, $34, $2c, $2b, $31, $1d, 0
expected_sensed_vdc:
    .byte $44, $01, $07, $07, $05, $12, $20, $28, $0d, $01, $07, $09, $0b, $29, 0
expected_identify_scroll_vdc:
    .byte $53, $03, $12, $0f, $0c, $0c, $20, $0f, $06, $20, $49, $04, $05, $0e, $14, $09, $06, $19, 0
expected_prayer_book_vdc:
    .byte $48, $0f, $0c, $19, $20, $42, $0f, $0f, $0b, $20, $0f, $06, $20, $50, $12, $01, $19, $05, $12, $13, $20, $42, $05, $07, $09, $0e, $0e, $05, $12, $13, $20, $48, $01, $0e, $04, $02, $0f, $0f, $0b, 0

assert_col: .byte 0
assert_idx: .byte 0
assert_expected: .byte 0
inv_qty: .fill TOTAL_INV_SLOTS, 0
