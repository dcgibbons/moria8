#importonce
// item_tables.s — Hot item property tables, page-aware accessors, and
// cold ITEM.CAT wrappers (V2 361-item Base-255 paged catalog).

// Named item type constants
.const ITEM_FLASK_OIL = ITEM_SLOT_FLASK_OF_OIL
.const LANTERN_MAX_CHARGES = 250

.const IT_MISSILE_BASE  = ITEM_SLOT_SHORT_BOW          // Contiguous Page-0 ranged block (Short Bow..Iron Shot)
.const IT_LAUNCHER_END  = ITEM_SLOT_SLING + 1
.const IT_MISSILE_END   = ITEM_SLOT_IRON_SHOT + 1
.assert "Ranged launchers and ammo are contiguous on Page 0", ITEM_LONG_BOW == ITEM_SHORT_BOW + 1 && ITEM_COMPOSITE_BOW == ITEM_SHORT_BOW + 2 && ITEM_LIGHT_CROSSBOW == ITEM_SHORT_BOW + 3 && ITEM_HEAVY_CROSSBOW == ITEM_SHORT_BOW + 4 && ITEM_SLING == ITEM_SHORT_BOW + 5 && ITEM_ARROW == ITEM_SHORT_BOW + 6 && ITEM_BOLT == ITEM_SHORT_BOW + 7 && ITEM_ROCK == ITEM_SHORT_BOW + 8 && ITEM_IRON_SHOT == ITEM_SHORT_BOW + 9 && IT_MISSILE_END <= ITEM_PAGE_SIZE, true

// ============================================================
// Hot Catalog Arrays (generated in platforms/shared/item_catalog/item_hot_tables.s)
// Placed in AuxDataSegment on HAL_PLATFORM_AUX_PERSISTENT_DATA targets.
// ============================================================
#if HAL_PLATFORM_AUX_PERSISTENT_DATA
:AuxDataSegment()
#endif
#import "../platforms/shared/item_catalog/item_hot_tables.s"
#if HAL_PLATFORM_AUX_PERSISTENT_DATA
:ResidentItemsSegment()
#endif

// Shared item-name decode scratch buffer (48 bytes)
.const ITEM_NAME_DECODE_BUF_SIZE = 48
#if PLATFORM_SCRATCH_BUFS_IN_PAGE2 || PLATFORM_ITEM_NAME_BUF_LOW
.label item_name_decode_buf = PLATFORM_ITEM_NAME_DECODE_BUF_BASE
.assert "item_name_decode_buf size matches its page-2 home", ITEM_NAME_DECODE_BUF_SIZE, 48
#else
item_name_decode_buf: .fill ITEM_NAME_DECODE_BUF_SIZE, 0
#endif

// Cold 'ITM2' catalog reader (weight, dmg, cost, flags, missile, Huffman names)
#import "item_catalog.s"

// ============================================================
// Page-Aware Hot Lookups (NEVER invoke ITEM.CAT I/O)
// ============================================================

it_save_x: .byte 0
it_save_y: .byte 0
it_id_lo:  .byte 0
it_id_hi:  .byte 0

// item_get_category_inv_x — Set item_cur_page from inv_ego,x and return ICAT_*
// Input: X = inventory/equipment slot (0..TOTAL_INV_SLOTS-1)
// Output: A = ICAT_* (ICAT_NONE if slot is FI_EMPTY), item_cur_page updated.
// Preserves: X, Y
item_get_category_inv_x:
    lda inv_ego,x
    and #ITEM_PAGE_BIT
    sta item_cur_page
    lda inv_item_id,x
    cmp #FI_EMPTY
    bne item_get_category_a
    lda #ICAT_NONE
    rts

// item_get_category_floor_x — Set item_cur_page from fi_meta_hi,x and return ICAT_*
// Input: X = floor slot (0..MAX_FLOOR_ITEMS-1)
// Output: A = ICAT_* (ICAT_NONE if slot is FI_EMPTY), item_cur_page updated.
// Preserves: X, Y
item_get_category_floor_x:
    lda fi_meta_hi,x
    and #ITEM_PAGE_BIT
    sta item_cur_page
    lda fi_item_id,x
    cmp #FI_EMPTY
    bne item_get_category_a
    lda #ICAT_NONE
    rts

#import "floor_item_page.s"

// item_get_category_a — Read it_category for paged (item_cur_page, A)
// Input: A = slot_lo (0..254), item_cur_page ($00 or $40)
// Output: A = ICAT_* (N/Z set from A)
// Preserves: X, Y
item_get_category_a:
    sty it_save_y
    tay
    bit item_cur_page
    bvs !igc_p1+
#if HAL_PLATFORM_AUX_PERSISTENT_DATA
    :AuxReadY(it_category)
#else
    lda it_category,y
#endif
!igc_ret:
    pha
    ldy it_save_y
    pla
    rts
!igc_p1:
#if HAL_PLATFORM_AUX_PERSISTENT_DATA
    :AuxReadY(it_category + ITEM_PAGE_SIZE)
#else
    lda it_category + ITEM_PAGE_SIZE,y
#endif
    jmp !igc_ret-

// item_get_color_a — Read default display color (high nibble of it_color_ac)
// Input: A = slot_lo (0..254), item_cur_page ($00 or $40)
// Output: A = color (0..15)
// Preserves: X, Y
item_get_color_a:
    sty it_save_y
    tay
    jsr it_read_color_ac_y
    lsr
    lsr
    lsr
    lsr
    ldy it_save_y
    rts

// item_get_unknown_idx_a — Read it_unknown_idx for paged (item_cur_page, A)
// Input: A = slot_lo (0..254), item_cur_page ($00 or $40)
// Output: A = class-local flavour index, or $FF if fixed
// Preserves: X, Y
item_get_unknown_idx_a:
    sty it_save_y
    tay
    bit item_cur_page
    bvs !igui_p1+
#if HAL_PLATFORM_AUX_PERSISTENT_DATA
    :AuxReadY(it_unknown_idx)
#else
    lda it_unknown_idx,y
#endif
!igui_ret:
    pha
    ldy it_save_y
    pla
    rts
!igui_p1:
#if HAL_PLATFORM_AUX_PERSISTENT_DATA
    :AuxReadY(it_unknown_idx + ITEM_PAGE_SIZE)
#else
    lda it_unknown_idx + ITEM_PAGE_SIZE,y
#endif
    jmp !igui_ret-

// item_get_flavour_color_x — Read flavour_colors[X]
// Input: X = global flavour index (0..FLAVOUR_COUNT-1)
// Output: A = color
// Preserves: X, Y
item_get_flavour_color_x:
    sty it_save_y
    txa
    tay
#if HAL_PLATFORM_AUX_PERSISTENT_DATA
    :AuxReadY(flavour_colors)
#else
    lda flavour_colors,y
#endif
    pha
    ldy it_save_y
    pla
    rts

// it_read_color_ac_y — Internal: read it_color_ac for paged (item_cur_page, Y).
// Preserves: X, Y
it_read_color_ac_y:
    bit item_cur_page
    bvs !irca_p1+
#if HAL_PLATFORM_AUX_PERSISTENT_DATA
    :AuxReadY(it_color_ac)
#else
    lda it_color_ac,y
#endif
    rts
!irca_p1:
#if HAL_PLATFORM_AUX_PERSISTENT_DATA
    :AuxReadY(it_color_ac + ITEM_PAGE_SIZE)
#else
    lda it_color_ac + ITEM_PAGE_SIZE,y
#endif
    rts

// item_get_base_ac — Get base armor class for paged item type (item_cur_page, Y)
// Input: Y = slot_lo (0..254), item_cur_page ($00 or $40)
// Output: A = base AC (0..28)
// Preserves: X, Y
item_get_base_ac:
    jsr it_read_color_ac_y
    and #$0f
    cmp #15
    bne !igba_done+
    // Compute 9-bit logical ID = Y + (page_bit ? 255 : 0) into (A=lo, it_id_hi=hi)
    stx it_save_x
    sty it_save_y
    lda #0
    sta it_id_hi
    tya
    bit item_cur_page
    bvc !igba_scan_prep+
    clc
    adc #ITEM_PAGE_SIZE
    bcc !igba_scan_prep+
    inc it_id_hi
!igba_scan_prep:
    sta it_id_lo
    ldy #IT_AC_EXTRA_COUNT - 1
!igba_loop:
#if HAL_PLATFORM_AUX_PERSISTENT_DATA
    :AuxReadY(it_ac_extra_id_lo)
#else
    lda it_ac_extra_id_lo,y
#endif
    cmp it_id_lo
    beq !igba_match_hi+
!igba_next:
    dey
    bpl !igba_loop-
    lda #15
    ldx it_save_x
    ldy it_save_y
!igba_done:
    rts
!igba_match_hi:
#if HAL_PLATFORM_AUX_PERSISTENT_DATA
    :AuxReadY(it_ac_extra_id_hi)
#else
    lda it_ac_extra_id_hi,y
#endif
    cmp it_id_hi
    bne !igba_next-
#if HAL_PLATFORM_AUX_PERSISTENT_DATA
    :AuxReadY(it_ac_extra_val)
#else
    lda it_ac_extra_val,y
#endif
    ldx it_save_x
    ldy it_save_y
    rts

// Display glyph by category (0..20). Digging tools are category 0.
// Exceptions (ranged launchers/ammo, Flask of Oil) are handled in item_get_display_char.
it_display_by_cat:
    .byte $5c   // 0: digging — '\'
    .byte $24   // 1: gold — '$'
    .byte $2f   // 2: weapon — '/'
    .byte $5b   // 3: armor — '['
    .byte $29   // 4: shield — ')'
    .byte $5d   // 5: helm — ']'
    .byte $5d   // 6: gloves — ']'
    .byte $5d   // 7: boots — ']'
    .byte $2a   // 8: light — '*'
    .byte $2c   // 9: food — ','
    .byte $21   // 10: potion — '!'
    .byte $3f   // 11: scroll — '?'
    .byte $3d   // 12: ring — '='
    .byte $3f   // 13: book — '?'
    .byte $2d   // 14: wand — '-'
    .byte $2f   // 15: staff — '/'
    .byte $22   // 16: amulet — '"'
    .byte $26   // 17: chest — '&'
    .byte $5c   // 18: spike — '\'
    .byte $28   // 19: cloak — '('
    .byte $5c   // 20: junk — '\'

// item_get_display_char — Get floor display glyph for paged item (item_cur_page, X)
// NEVER invokes cold ITEM.CAT I/O.
// Input: X = slot_lo (0..254), item_cur_page ($00 or $40)
// Output: A = display glyph (screen code)
// Preserves: X, Y
item_get_display_char:
    bit item_cur_page
    bvs !igd_cat+
    cpx #IT_MISSILE_BASE
    bcc !igd_not_ranged+
    cpx #IT_MISSILE_END
    bcs !igd_not_ranged+
    cpx #ITEM_SLOT_ARROW
    bcc !igd_bow+
    lda #$1b                    // '{' ammo
    rts
!igd_bow:
    lda #$1c                    // '}' launcher
    rts
!igd_not_ranged:
    .assert "Flask of Oil lives on Page 0", ITEM_PAGE_FLASK_OF_OIL, 0
    cpx #ITEM_FLASK_OIL
    bne !igd_cat+
    lda #$21                    // '!' flask
    rts
!igd_cat:
    sty idc_save_y
    txa
    jsr item_get_category_a     // preserves X, Y
    tay
    lda it_display_by_cat,y
    ldy idc_save_y
    rts
idc_save_y: .byte 0

// ============================================================
// Cold ITEM.CAT Attribute Wrappers (keep out of combat/turn/render hot loops)
// ============================================================

// item_get_missile — Get missile type for paged item (item_cur_page, X)
// Non-weapons short-circuit immediately from hot it_category without ITEM.CAT I/O.
// Input: X = slot_lo (0..254), item_cur_page
// Output: A = missile value (0 if not ranged; N/Z reflect A)
// Preserves: X, Y
item_get_missile:
#if HAL_PLATFORM_ITEM_PICKUP_CACHE
    bit item_cur_page
    bvs !igm_zero+
    cpx #IT_MISSILE_BASE
    bcc !igm_zero+
    cpx #IT_MISSILE_END
    bcs !igm_zero+
    lda igm_vals - IT_MISSILE_BASE,x
    rts
!igm_zero:
    lda #0
    rts
igm_vals: .byte 1, 1, 1, 2, 2, 3, $81, $82, $83, $83
igm_vals_end:
.assert "igm_vals matches unified IT_MISSILE span", (igm_vals_end - igm_vals == 10) && (IT_MISSILE_END - IT_MISSILE_BASE == 10), true
#else
    txa
    jsr item_get_category_a     // preserves X, Y
    cmp #ICAT_WEAPON
    beq !igm_query+
    lda #0
    rts
!igm_query:
    sty it_save_y
    txa
    jsr item_cat_select_id
    jsr item_cat_get_missile_type
    ldy it_save_y
    ora #0
    rts
#endif

// item_get_weight_x — Load 16-bit weight for paged item (item_cur_page, X)
// Output: icat_weight_lo/hi loaded, A = icat_weight_lo
// Preserves: X, Y
item_get_weight_x:
#if HAL_PLATFORM_ITEM_PICKUP_CACHE
    jmp item_pickup_cache_get_weight_x
#else
    sty it_save_y
    txa
    jsr item_cat_select_id
    jsr item_cat_get_weight
    ldy it_save_y
    lda icat_weight_lo
    rts
#endif

// item_get_dmg_packed_x — Load packed (dice<<4)|sides for paged item (item_cur_page, X)
// Output: A = (dice<<4)|sides, icat_dmg_dice & icat_dmg_sides also set
// Preserves: X, Y
item_get_dmg_packed_x:
    sty it_save_y
    txa
    jsr item_cat_select_id
    jsr item_cat_get_dmg_packed
    ldy it_save_y
    ora #0
    rts

// item_get_cost_x — Load 16-bit cost for paged item (item_cur_page, X)
// Output: icat_cost_lo/hi loaded, A = icat_cost_lo
// Preserves: X, Y
item_get_cost_x:
    sty it_save_y
    txa
    jsr item_cat_select_id
    jsr item_cat_get_cost
    ldy it_save_y
    lda icat_cost_lo
    rts

// item_unpack_id_ay — Convert 9-bit logical item ID (Y=hi, A=lo) in 0..360
// into (item_cur_page = $00/$40, A = slot_lo in 0..254).
// Preserves: X
item_unpack_id_ay:
    cpy #0
    bne !iui_hi+
    cmp #ITEM_PAGE_SIZE
    bcs !iui_p0_top+
    sty item_cur_page           // Y = 0
    rts
!iui_p0_top:
    sec
    sbc #ITEM_PAGE_SIZE
    ldy #ITEM_PAGE_BIT
    sty item_cur_page
    rts
!iui_hi:
    clc
    adc #1                      // 256 + lo - 255 = lo + 1
    ldy #ITEM_PAGE_BIT
    sty item_cur_page
    rts
