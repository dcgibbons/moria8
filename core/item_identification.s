#importonce
// item_identification.s — Item ID state, 174-flavour shuffles, and lookup helpers

// ============================================================
// Item Identification System (V2 361-item Base-255 paged catalog)
// ============================================================

#if HAL_PLATFORM_ITEM_TABLES_SPLIT_RESIDENT
:ResidentItemsSegment()
#endif

// Shuffle tables: map class-local flavour index -> appearance description index.
// 46 potions, 49 scrolls, 30 rings, 24 wands, 25 staves (174 total).
// Set at new game and by save load; PLATFORM_SHUFFLES_EXTERNAL places them
// in platform-designated RAM.
#if PLATFORM_SHUFFLES_EXTERNAL
.label potion_shuffle = PLATFORM_SHUFFLE_BASE
.label scroll_shuffle = potion_shuffle + FLAVOUR_POTION_COUNT
.label ring_shuffle   = scroll_shuffle + FLAVOUR_SCROLL_COUNT
.label wand_shuffle   = ring_shuffle   + FLAVOUR_RING_COUNT
.label staff_shuffle  = wand_shuffle   + FLAVOUR_WAND_COUNT
#else
potion_shuffle: .fill FLAVOUR_POTION_COUNT, 0
scroll_shuffle: .fill FLAVOUR_SCROLL_COUNT, 0
ring_shuffle:   .fill FLAVOUR_RING_COUNT,   0
wand_shuffle:   .fill FLAVOUR_WAND_COUNT,   0
staff_shuffle:  .fill FLAVOUR_STAFF_COUNT,  0
#endif
.assert "The shuffle tables are contiguous in class order", (staff_shuffle + FLAVOUR_STAFF_COUNT) - potion_shuffle, FLAVOUR_COUNT

.const FLAVOUR_POTION_BASE = 0
.const FLAVOUR_SCROLL_BASE = FLAVOUR_POTION_BASE + FLAVOUR_POTION_COUNT
.const FLAVOUR_RING_BASE   = FLAVOUR_SCROLL_BASE + FLAVOUR_SCROLL_COUNT
.const FLAVOUR_WAND_BASE   = FLAVOUR_RING_BASE   + FLAVOUR_RING_COUNT
.const FLAVOUR_STAFF_BASE  = FLAVOUR_WAND_BASE   + FLAVOUR_WAND_COUNT
.assert "Global flavour base sum matches FLAVOUR_COUNT", FLAVOUR_STAFF_BASE + FLAVOUR_STAFF_COUNT, FLAVOUR_COUNT

// iuk_flavour_x — Global flavour index (0..173) of unknown paged item (item_cur_page, X).
// Output: Carry clear and X = global flavour index for randomized potion/scroll/
//         ring/wand/staff; Carry set for fixed classes, books, or fixed-flavour
//         items (it_unknown_idx == $FF, e.g. Water, Apple Juice, Slime Mold Juice).
// Sets item_display_id and item_display_page. Preserves item_cur_page. Clobbers: A, X, Y.
iuk_flavour_x:
    stx item_display_id
    lda item_cur_page
    sta item_display_page
    txa
    jsr item_get_category_a
    cmp #ICAT_POTION
    bcc !iuf_none+
    cmp #ICAT_STAFF + 1
    bcs !iuf_none+
    tay
    lda iuf_class_base - ICAT_POTION,y
    cmp #$ff                        // ICAT_BOOK has no shuffled flavour (do NOT use bmi: staff base >= $80)
    beq !iuf_none+
    sta iuf_base
    txa
    jsr item_get_unknown_idx_a
    cmp #$ff                        // Fixed-flavour potions (Water/Apple Juice/Slime Mold Juice) keep real name & color
    beq !iuf_none+
    clc
    adc iuf_base
    tax
    lda potion_shuffle,x            // Shuffled class-local appearance index
    clc
    adc iuf_base
    tax
    clc
    rts
!iuf_none:
    sec
    rts

iuf_class_base:
    .byte FLAVOUR_POTION_BASE
    .byte FLAVOUR_SCROLL_BASE
    .byte FLAVOUR_RING_BASE
    .byte $ff
    .byte FLAVOUR_WAND_BASE
    .byte FLAVOUR_STAFF_BASE
iuf_base:          .byte 0
item_display_id:   .byte 0
item_display_page: .byte 0
.assert "ICAT ids iuf_class_base assumes", ICAT_STAFF - ICAT_POTION, 5
.assert "ICAT_BOOK sits between rings and wands", ICAT_BOOK - ICAT_POTION, 3

#if PLATFORM_PRODUCT_OVERLAY_RUNTIME
:ItemInitIdentSegment()
#endif
// ============================================================
// item_init_identification — Reset id_known_bits and 174-flavour shuffle tables
// Called once at new game start.
// Clobbers: A, X, Y
// ============================================================
item_init_identification:
    ldx #ID_KNOWN_BYTES - 1
    lda #0
!iid_clear:
    sta id_known_bits,x
    dex
    bpl !iid_clear-

#if ITEM_REFRESH_KNOWN_EXTERNAL && !ITEM_REFRESH_KNOWN_CO_LOCATED
    jsr tramp_item_refresh_fixed_known
#else
    jsr item_refresh_fixed_known
#endif

    ldx #4                          // 5 flavour classes (staff..potion)
!iid_cls_loop:
    stx iid_cls_idx
    lda #<potion_shuffle
    clc
    adc !iid_cls_off+,x
    sta zp_ptr0
    lda #>potion_shuffle
    adc #0
    sta zp_ptr0_hi

    ldy !iid_cls_cnt+,x
    dey
!iid_init_seq:
    tya
    sta (zp_ptr0),y
    dey
    bpl !iid_init_seq-

    lda !iid_cls_cnt+,x
    tax
    dex
    jsr iid_shuffle_ptr

    ldx iid_cls_idx
    dex
    bpl !iid_cls_loop-
    rts

!iid_cls_off:
    .byte FLAVOUR_POTION_BASE, FLAVOUR_SCROLL_BASE, FLAVOUR_RING_BASE, FLAVOUR_WAND_BASE, FLAVOUR_STAFF_BASE
!iid_cls_cnt:
    .byte FLAVOUR_POTION_COUNT, FLAVOUR_SCROLL_COUNT, FLAVOUR_RING_COUNT, FLAVOUR_WAND_COUNT, FLAVOUR_STAFF_COUNT

// Fisher-Yates shuffle on (zp_ptr0)[0..X]
iid_shuffle_ptr:
!iid_shuffle_loop:
    txa
    clc
    adc #1
    stx iid_save_x
    jsr rng_range
    sta iid_rand_y
    ldy iid_save_x
    lda (zp_ptr0),y
    pha
    ldy iid_rand_y
    lda (zp_ptr0),y
    ldy iid_save_x
    sta (zp_ptr0),y
    pla
    ldy iid_rand_y
    sta (zp_ptr0),y
    ldx iid_save_x
    dex
    bne !iid_shuffle_loop-
    rts

iid_cls_idx: .byte 0
iid_save_x:  .byte 0
iid_rand_y:  .byte 0

#if PLATFORM_PRODUCT_OVERLAY_RUNTIME
:ItemInitIdentRestoreSegment()
#endif

#if !ITEM_REFRESH_KNOWN_EXTERNAL
#import "item_refresh_known_cold.s"
#endif

// ============================================================
// item_get_name_ptr — Decode known or shuffled unid name for (item_cur_page, A)
// Input: A = slot_lo (0..254), item_cur_page ($00 or $40)
// Output: zp_ptr0/zp_ptr0_hi = null-terminated decoded name in item_name_decode_buf
// Clobbers: A, X, Y
// ============================================================
item_get_name_ptr:
    tax
    lda item_cur_page
    sta item_display_page
    stx item_display_id
    jsr id_known_test
    bne !ignp_known+

    jsr iuk_flavour_x
    bcs !ignp_fallback+
    txa
    jmp item_cat_decode_flavour

!ignp_fallback:
    lda item_display_page
    sta item_cur_page
    ldx item_display_id
!ignp_known:
    txa
    jmp item_cat_decode_item

// ============================================================
// item_get_floor_color — Get display color for paged item (item_cur_page, A)
// Input: A = slot_lo (0..254), item_cur_page ($00 or $40)
// Output: A = color byte (0..15)
// Clobbers: A, X, Y
// ============================================================
item_get_floor_color:
    tax
    lda item_cur_page
    sta item_display_page
    stx item_display_id
    jsr id_known_test
    bne !igfc_known+

    jsr iuk_flavour_x
    bcs !igfc_fallback+
    jmp item_get_flavour_color_x

!igfc_fallback:
    lda item_display_page
    sta item_cur_page
    lda item_display_id
    jmp item_get_color_a

!igfc_known:
    txa
    jmp item_get_color_a
